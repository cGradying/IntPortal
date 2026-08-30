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
                "The local model server returned an empty response. This usually means the selected text was too long for the current Context size (Settings ▸ AI) — try selecting less, or raising Context size."
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

    private static func post(_ body: Data, to url: URL, bearer: String? = nil) async throws -> (Data, Int) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let bearer { request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }
        request.httpBody = body
        // A cold local model can genuinely take a while on the first request.
        // A cloud provider is never this slow, but the same generous timeout
        // does no harm on a fast connection.
        request.timeoutInterval = 180
        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        return (data, code)
    }

    /// A client posting to `provider`'s OpenAI-compatible endpoint with
    /// `apiKey` as a Bearer token and `model` in the body, instead of the
    /// local hardcoded default — only for `.openai`/`.google` (see
    /// `AIProvider.isOpenAICompatible`). Every request/response method
    /// (`generate`, `chat`, `embed`, parsing) is reused completely
    /// unchanged; only where `send` posts to, and what it posts, differs.
    /// `sendEmbed` still targets nothing real for a cloud provider — neither
    /// OpenAI's nor Google's key covers the local `.embed`-role server, and
    /// RAG stays local-only regardless of `aiProvider` (wayfinder ticket #17
    /// deliberately scoped this to chat/generate only).
    static func forOpenAICompatibleProvider(_ provider: AIProvider, apiKey: String, model: String) -> LlamaCppClient {
        precondition(provider.isOpenAICompatible, "forOpenAICompatibleProvider called with \(provider)")
        let endpoint = provider.chatEndpoint!
        return LlamaCppClient(send: { body in
            try await Self.post(Self.injectingModel(model, into: body), to: endpoint, bearer: apiKey)
        })
    }

    /// A real cloud provider requires a top-level `"model"` field the local
    /// path deliberately never sends (see this type's own doc comment on
    /// why) — injected here, after the shared request-body builders already
    /// ran, rather than threading a cloud-only parameter through every one
    /// of them and risking it leaking into a local request. Also strips
    /// `reasoning_effort` — an llama.cpp/vLLM extension, not part of the
    /// OpenAI Chat Completions spec; several providers 400 on an unrecognized
    /// top-level field rather than silently ignoring it, so `AssistantThinking`
    /// has no effect on a cloud provider for now rather than breaking the
    /// request outright.
    static func injectingModel(_ model: String, into body: Data) -> Data {
        guard var json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { return body }
        json["model"] = model
        json["reasoning_effort"] = nil
        return (try? JSONSerialization.data(withJSONObject: json)) ?? body
    }

    // MARK: Plain completion — note drafting, /summary, /create, quiz explanations

    /// The floor/default output cap — used directly by short transforms and
    /// as `requestBody`/`truncatedForContext`'s default when a caller
    /// doesn't compute its own via `generateMaxTokens(forSelectionLength:)`.
    static let generateMaxTokensFloor = 800

    /// Structuring/expanding a note can legitimately produce more output
    /// than the input, unlike a summary — scale to input size rather than
    /// guessing one fixed number for every mode (confirmed live: "Structure
    /// this" on a long note just stopped at the old flat 800 with no way to
    /// ask for more). Floor matches the old flat cap; ceiling keeps a
    /// single request from running away.
    static func generateMaxTokens(forSelectionLength charCount: Int) -> Int {
        min(max(charCount / 3, generateMaxTokensFloor), 2400)
    }

    /// Deliberately no JSON schema and no tool menu in the prompt — a plain
    /// "here's context, answer/continue" completion. `model` is accepted and
    /// ignored, see the type's own doc comment. `contextSize` bounds
    /// `selection` before it's ever sent — see `truncatedForContext`'s own
    /// doc comment for the bug this fixes. The output cap scales with
    /// `selection`'s length (`generateMaxTokens(forSelectionLength:)`), and
    /// the *same* computed value is what `truncatedForContext` reserves
    /// room for — one number, not two independent guesses.
    func generate(
        model: String = "", selection: String, instruction: String = Self.instruction,
        contextSize: Int = Preferences.aiDefaultContextSize
    ) async throws -> String {
        let maxTokens = Self.generateMaxTokens(forSelectionLength: selection.count)
        let bounded = Self.truncatedForContext(selection, instruction: instruction, contextSize: contextSize, maxTokens: maxTokens)
        let body = try Self.requestBody(selection: bounded, instruction: instruction, maxTokens: maxTokens)
        let (data, code): (Data, Int)
        do {
            (data, code) = try await send(body)
        } catch {
            throw ClientError.offline
        }
        guard (200..<300).contains(code) else { throw ClientError.http(code) }
        return try Self.parseContent(data)
    }

    /// Confirmed live bug this fixes: the note editor's "Ask AI" pill
    /// (Structure/Summarize/Answer) sent the selected text completely
    /// unbounded — a long note plus `structureInstruction`'s own ~400 tokens
    /// plus the output reserve could exceed the configured context size
    /// with no warning, and llama-server's response to that is an *empty*
    /// completion (`ClientError.empty`), not a clear error. Same underlying
    /// problem, same ~4 chars/token heuristic, as
    /// `AssistantContext.noteCharLimit` fixes for the chat/tool path — this
    /// is that fix's sibling for the plain-completion path. `maxTokens`
    /// must be the same value the actual request reserves via
    /// `requestBody` — not read from `generateMaxTokensFloor` independently
    /// — or this reserves room for the wrong output size.
    static func truncatedForContext(
        _ selection: String, instruction: String, contextSize: Int, maxTokens: Int = generateMaxTokensFloor
    ) -> String {
        let charsPerToken = AssistantContext.charsPerTokenEstimate
        let instructionTokens = instruction.count / charsPerToken
        // 100-token safety margin for message-formatting overhead the raw
        // char count doesn't capture; floored at 200 tokens so a very small
        // context size still gets *something* rather than an empty prompt.
        let availableTokens = max(contextSize - instructionTokens - maxTokens - 100, 200)
        let availableChars = availableTokens * charsPerToken
        guard selection.count > availableChars else { return selection }
        return String(selection.prefix(availableChars)) + "\n[...truncated to fit the configured context size]"
    }

    /// Confirmed live — the real cause behind `ClientError.empty` on the
    /// note editor's "Ask AI" pill, independent of `truncatedForContext`
    /// above (that fix alone didn't resolve it): unlike `chatRequestBody`,
    /// this never set `reasoning_effort` at all. Qwen3 (this app's default
    /// local model) reasons by default when the field is omitted — its
    /// `<think>…</think>` block can burn through the entire fixed
    /// `generateMaxTokens` (800) budget before the model ever starts
    /// writing the actual answer, leaving `parseContent`'s `content` field
    /// genuinely empty even though `reasoning_content` has text (`parseContent`
    /// doesn't read that field at all — this is a plain completion, not a
    /// chat turn with its own thinking UI to show it in). A quick
    /// structure/summarize/answer transform has no need for chain-of-thought
    /// regardless, so it's forced off outright rather than budgeted for.
    static func requestBody(
        selection: String, instruction: String = Self.instruction, maxTokens: Int = generateMaxTokensFloor
    ) throws -> Data {
        let payload: [String: Any] = [
            "messages": [
                ["role": "system", "content": instruction],
                ["role": "user", "content": selection],
            ],
            "temperature": 0.2,
            "max_tokens": maxTokens,
            "reasoning_effort": "none",
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
