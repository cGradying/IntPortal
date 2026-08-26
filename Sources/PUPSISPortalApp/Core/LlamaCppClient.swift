import Foundation

/// The app's one and only local-model transport — chat/tools, plain
/// completion (note drafting, summaries, quiz explanations), embeddings, and
/// model downloads, all through `llama-server`'s OpenAI-compatible API.
/// Used to be RAG-only, sitting alongside a separate Ollama client for
/// everything else; that split is gone — see `ModelCatalog` and
/// `LlamaServerManager`'s two roles (`.chat`/`.embed`).
///
/// **Localhost only, deliberately** — same promise every local-model client
/// in this app makes: the endpoint is a constant, not a setting.
///
/// No `model` field in any request body: llama-server serves exactly one
/// model per process, so which model answers is `LlamaServerManager`'s job
/// (which GGUF a role's process was launched with), not a per-request
/// parameter. Every method still *accepts* a `model` argument, defaulted to
/// `""` and otherwise ignored — kept only so call sites built against the
/// old Ollama shape (`generate(model: preferences.aiModel, ...)`) didn't all
/// need editing just to drop it.
struct LlamaCppClient {
    /// The `.chat`-role server — assistant chat/tools, RAG answering, quiz
    /// generation/explanation, note-editor AI help.
    static let endpoint = URL(string: "http://127.0.0.1:8080/v1/chat/completions")!
    /// The `.embed`-role server — note search embeddings only.
    static let embedEndpoint = URL(string: "http://127.0.0.1:8081/v1/embeddings")!

    /// The house style for note drafting. Kept here rather than in the view so
    /// it's one string to tune, and so the request builder is testable whole.
    static let instruction = """
    You are helping a student expand their own study notes. Continue or clarify \
    the material below in Markdown. Reply with the note text only — no preamble, \
    no explanation of what you did, no code fences around the whole answer.
    """

    enum ClientError: LocalizedError {
        case offline
        case http(Int)
        case empty

        var errorDescription: String? {
            switch self {
            case .offline:
                "Couldn't reach the local model server. Start it with Settings ▸ AI, or `brew install llama.cpp` if that's not installed yet."
            case .http(let code):
                "The local model server returned HTTP \(code)."
            case .empty:
                "The local model server returned an empty response."
            }
        }
    }

    struct ChatMessage: Equatable {
        enum Role: String { case system, user, assistant, tool }
        let role: Role
        let content: String
    }

    private let send: (Data) async throws -> (Data, Int)
    private let sendEmbed: (Data) async throws -> (Data, Int)

    init(
        send: ((Data) async throws -> (Data, Int))? = nil,
        sendEmbed: ((Data) async throws -> (Data, Int))? = nil
    ) {
        self.send = send ?? { try await Self.post($0, to: Self.endpoint) }
        self.sendEmbed = sendEmbed ?? { try await Self.post($0, to: Self.embedEndpoint) }
    }

    private static func post(_ body: Data, to url: URL) async throws -> (Data, Int) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        // A cold local model can genuinely take a while on the first request.
        request.timeoutInterval = 180
        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        return (data, code)
    }

    // MARK: Plain completion — note drafting, /summary, /create, quiz explanations

    /// Deliberately no JSON schema and no tool menu in the prompt — a plain
    /// "here's context, answer/continue" completion. `model` is accepted and
    /// ignored, see the type's own doc comment.
    func generate(model: String = "", selection: String, instruction: String = Self.instruction) async throws -> String {
        let body = try Self.requestBody(selection: selection, instruction: instruction)
        let (data, code): (Data, Int)
        do {
            (data, code) = try await send(body)
        } catch {
            throw ClientError.offline
        }
        guard (200..<300).contains(code) else { throw ClientError.http(code) }
        return try Self.parseContent(data)
    }

    static func requestBody(selection: String, instruction: String = Self.instruction) throws -> Data {
        let payload: [String: Any] = [
            "messages": [
                ["role": "system", "content": instruction],
                ["role": "user", "content": selection],
            ],
            "temperature": 0.2,
            "max_tokens": 800,
        ]
        return try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
    }

    // MARK: Structured chat — assistant tool loop, quiz card generation

    /// One structured turn: `messages` is the whole conversation so far;
    /// `schema` constrains the reply via `response_format`. Returns the raw
    /// JSON string plus the model's reasoning (empty when `think` is `.off`
    /// or the model returned none) — llama-server carries reasoning in its
    /// own `message.reasoning_content` field, confirmed live, never mixed
    /// into `content`, so no `<think>`-tag stripping is needed anywhere.
    func chat(
        model: String = "", messages: [ChatMessage], schema: [String: Any],
        numPredict: Int? = nil, think: AssistantThinking = .off, temperature: Double = 0.2
    ) async throws -> (content: String, thinking: String) {
        let body = try Self.chatRequestBody(messages: messages, schema: schema, numPredict: numPredict, think: think, temperature: temperature)
        let (data, code): (Data, Int)
        do {
            (data, code) = try await send(body)
        } catch {
            throw ClientError.offline
        }
        guard (200..<300).contains(code) else { throw ClientError.http(code) }
        return try Self.parseChatContent(data)
    }

    /// `think`'s `reasoning_effort` values, confirmed live against
    /// `granite4.2:3b`'s successor here (Qwen3-1.7B): `"none"` genuinely
    /// disables reasoning (fast, no `reasoning_content` at all), `"low"`/
    /// `"medium"`/`"high"` scale the pass. This is the *real* API field —
    /// unlike Ollama, there was no guessing between two shapes here.
    static func chatRequestBody(
        messages: [ChatMessage], schema: [String: Any], numPredict: Int? = nil,
        think: AssistantThinking = .off, temperature: Double = 0.2
    ) throws -> Data {
        var payload: [String: Any] = [
            "messages": messages.map { ["role": $0.role.rawValue, "content": $0.content] },
            "response_format": ["type": "json_schema", "json_schema": ["name": "reply", "schema": schema]],
            "temperature": temperature,
            "reasoning_effort": think.apiValue ?? "none",
        ]
        if let numPredict { payload["max_tokens"] = numPredict }
        return try JSONSerialization.data(withJSONObject: payload)
    }

    /// `{"choices":[{"message":{"content":"...","reasoning_content":"..."}}]}`.
    static func parseChatContent(_ data: Data) throws -> (content: String, thinking: String) {
        struct Reply: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable { let content: String; let reasoning_content: String? }
                let message: Message
            }
            let choices: [Choice]
        }
        guard let reply = try? JSONDecoder().decode(Reply.self, from: data),
              let message = reply.choices.first?.message
        else {
            throw ClientError.empty
        }
        let text = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw ClientError.empty }
        let thinking = message.reasoning_content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return (text, thinking)
    }

    /// The OpenAI-compatible plain-text shape:
    /// `{"choices":[{"message":{"content":"..."}}]}`.
    static func parseContent(_ data: Data) throws -> String {
        struct Reply: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable { let content: String }
                let message: Message
            }
            let choices: [Choice]
        }
        guard let reply = try? JSONDecoder().decode(Reply.self, from: data),
              let content = reply.choices.first?.message.content
        else {
            throw ClientError.empty
        }
        let text = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw ClientError.empty }
        return text
    }

    // MARK: Embeddings (for RAG retrieval) — always the .embed-role server

    /// One vector per `texts` entry, same order. `model` accepted and
    /// ignored — the embed-role server is always nomic-embed-text-v1.5.
    func embed(model: String = "", texts: [String]) async throws -> [[Double]] {
        guard !texts.isEmpty else { return [] }
        let body = try Self.embedRequestBody(texts: texts)
        let (data, code): (Data, Int)
        do {
            (data, code) = try await sendEmbed(body)
        } catch {
            throw ClientError.offline
        }
        guard (200..<300).contains(code) else { throw ClientError.http(code) }
        return try Self.parseEmbeddings(data)
    }

    static func embedRequestBody(texts: [String]) throws -> Data {
        let payload: [String: Any] = ["input": texts]
        return try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
    }

    /// `{"data":[{"embedding":[...]}]}` — the OpenAI-compatible `/v1/embeddings` shape.
    static func parseEmbeddings(_ data: Data) throws -> [[Double]] {
        struct Reply: Decodable {
            struct Datum: Decodable { let embedding: [Double] }
            let data: [Datum]
        }
        guard let reply = try? JSONDecoder().decode(Reply.self, from: data), !reply.data.isEmpty else {
            throw ClientError.empty
        }
        return reply.data.map(\.embedding)
    }

    // MARK: Model download (Settings ▸ AI's in-app installer)

    /// A real `URLSessionDownloadTask` — the OS streams straight to a temp
    /// file (no multi-GB `Data` ever held in memory) and reports progress via
    /// the delegate below, moved to `destination` on completion, replacing
    /// anything already there. `AsyncThrowingStream` so a SwiftUI `.task` can
    /// `for try await` it directly; cancelling the stream cancels the task.
    static func download(from url: URL, to destination: URL) -> AsyncThrowingStream<Double, Error> {
        AsyncThrowingStream { continuation in
            let delegate = DownloadProgressDelegate(destination: destination, continuation: continuation)
            let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
            let task = session.downloadTask(with: url)
            continuation.onTermination = { _ in task.cancel() }
            task.resume()
        }
    }
}

/// Bridges `URLSessionDownloadDelegate`'s callback-based progress into
/// `LlamaCppClient.download`'s `AsyncThrowingStream`. `NSObject` because the
/// delegate protocols require it; holds nothing but what it needs to move the
/// finished file and report progress.
private final class DownloadProgressDelegate: NSObject, URLSessionDownloadDelegate {
    private let destination: URL
    private let continuation: AsyncThrowingStream<Double, Error>.Continuation

    init(destination: URL, continuation: AsyncThrowingStream<Double, Error>.Continuation) {
        self.destination = destination
        self.continuation = continuation
    }

    func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        continuation.yield(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        do {
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
            continuation.finish()
        } catch {
            continuation.finish(throwing: error)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        // Success is reported by didFinishDownloadingTo above; this fires for
        // every task, so only forward an actual failure — a nil error here on
        // the happy path must not double-finish an already-finished stream.
        if let error, (error as NSError).code != NSURLErrorCancelled {
            continuation.finish(throwing: error)
        }
    }
}
