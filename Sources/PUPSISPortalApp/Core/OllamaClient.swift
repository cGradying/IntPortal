import Foundation

/// Drafting help from a model running on the user's own machine, via Ollama's
/// local HTTP API. Opt-in and off by default — see `Preferences.aiEnabled`.
///
/// **Localhost only, deliberately.** The endpoint is a constant rather than a
/// setting: the promise this feature makes is that note text never leaves the
/// machine, and a configurable host would quietly turn that from a fact into
/// something the user has to verify. A remote provider is a separate decision
/// with its own consent, not a field in a text box.
///
/// Non-streaming: one request, one insert. Ollama can stream NDJSON, which
/// would let text appear as it's generated — worth doing later, not needed to
/// find out whether this is useful at all.
struct OllamaClient {
    static let endpoint = URL(string: "http://localhost:11434/api/generate")!

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
                "Couldn't reach Ollama. Is it running? Start it with `ollama serve`."
            case .http(let code):
                "Ollama returned HTTP \(code). Check the model name in Settings."
            case .empty:
                "Ollama returned an empty response."
            }
        }
    }

    /// The assistant's structured turn: `/api/chat` with a JSON-schema `format`,
    /// used by `AssistantEngine`. Separate endpoint and transport from
    /// `generate` — a distinct injectable so each surface's tests stay
    /// independent of the other's.
    static let chatEndpoint = URL(string: "http://localhost:11434/api/chat")!

    struct ChatMessage: Equatable {
        enum Role: String { case system, user, assistant, tool }
        let role: Role
        let content: String
    }

    /// `/api/embed` — turns text into a vector for `NoteRetrieval`'s
    /// cosine-similarity ranking. Separate endpoint from `generate`/`chat`
    /// because it takes a *different model* (`RealAssistantExecutor`'s
    /// `embedModel`, a small purpose-built embedding model, not whatever chat
    /// model the assistant itself is set to) — Ollama 404s if you ask a plain
    /// chat model for embeddings.
    static let embedEndpoint = URL(string: "http://localhost:11434/api/embed")!

    private let send: (Data) async throws -> (Data, Int)
    private let sendChat: (Data) async throws -> (Data, Int)
    private let sendEmbed: (Data) async throws -> (Data, Int)

    init(
        send: ((Data) async throws -> (Data, Int))? = nil,
        sendChat: ((Data) async throws -> (Data, Int))? = nil,
        sendEmbed: ((Data) async throws -> (Data, Int))? = nil
    ) {
        self.send = send ?? Self.post
        self.sendChat = sendChat ?? Self.postChat
        self.sendEmbed = sendEmbed ?? Self.postEmbed
    }

    /// Model names already pulled on this machine, newest API shape first.
    /// Empty when Ollama isn't running — which is exactly what Settings needs
    /// to say "start it first" instead of offering a list of nothing.
    ///
    /// Settings offers these as a picker rather than a free-text field: a typo'd
    /// or not-yet-pulled name is otherwise a 404 the user has to decode, and the
    /// stock default won't match what any given machine actually has.
    static func installedModels() async -> [String] {
        let url = URL(string: "http://localhost:11434/api/tags")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        guard let (data, _) = try? await URLSession.shared.data(for: request) else { return [] }
        return parseModels(data)
    }

    static func parseModels(_ data: Data) -> [String] {
        struct Tags: Decodable {
            struct Model: Decodable { let name: String }
            let models: [Model]
        }
        guard let tags = try? JSONDecoder().decode(Tags.self, from: data) else { return [] }
        return tags.models.map(\.name).sorted()
    }

    /// A model's name plus its on-disk weight size, for the memory-check
    /// confirmation before switching to it — `/api/tags` already reports this,
    /// `parseModels` above just didn't keep it. Separate method rather than
    /// changing `installedModels`'s return type: that one's shipped and
    /// tested, and nothing else needs the size.
    struct ModelInfo: Decodable, Equatable {
        let name: String
        let size: Int64
    }

    static func installedModelsDetailed() async -> [ModelInfo] {
        let url = URL(string: "http://localhost:11434/api/tags")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        guard let (data, _) = try? await URLSession.shared.data(for: request) else { return [] }
        return parseModelDetails(data)
    }

    static func parseModelDetails(_ data: Data) -> [ModelInfo] {
        struct Tags: Decodable { let models: [ModelInfo] }
        guard let tags = try? JSONDecoder().decode(Tags.self, from: data) else { return [] }
        return tags.models.sorted { $0.name < $1.name }
    }

    /// Models Ollama currently has **loaded in memory**, not just installed —
    /// `/api/ps`, distinct from `/api/tags`. Switching the assistant's model
    /// in Settings doesn't replace what's resident, it adds to it: the old
    /// model stays loaded until Ollama's own idle timeout, so two models can
    /// end up competing for the same machine. This is what lets Settings
    /// unload the one that's no longer wanted instead of waiting that out.
    static func runningModels() async -> [String] {
        let url = URL(string: "http://localhost:11434/api/ps")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        guard let (data, _) = try? await URLSession.shared.data(for: request) else { return [] }
        return parseRunningModels(data)
    }

    static func parseRunningModels(_ data: Data) -> [String] {
        struct Ps: Decodable {
            struct Model: Decodable { let name: String }
            let models: [Model]
        }
        guard let ps = try? JSONDecoder().decode(Ps.self, from: data) else { return [] }
        return ps.models.map(\.name)
    }

    /// Asks Ollama to drop `model` from memory right away — `keep_alive: 0`
    /// on the same endpoint `generate` uses, with no prompt. Silent failure
    /// (model already gone, Ollama offline) is fine here: the caller is
    /// freeing resources, not performing an action the user is waiting on.
    func unload(model: String) async {
        guard let body = try? Self.unloadRequestBody(model: model) else { return }
        _ = try? await send(body)
    }

    static func unloadRequestBody(model: String) throws -> Data {
        let payload: [String: Any] = ["model": model, "keep_alive": 0]
        return try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
    }

    private static func post(_ body: Data) async throws -> (Data, Int) {
        try await post(body, to: endpoint)
    }

    private static func postChat(_ body: Data) async throws -> (Data, Int) {
        try await post(body, to: chatEndpoint)
    }

    private static func postEmbed(_ body: Data) async throws -> (Data, Int) {
        try await post(body, to: embedEndpoint)
    }

    private static func post(_ body: Data, to url: URL) async throws -> (Data, Int) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        // A local model on a busy machine can genuinely take a while to answer;
        // the default 60s times out mid-generation on a cold model load.
        request.timeoutInterval = 180
        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        return (data, code)
    }

    /// Ask `model` to continue `selection`. Throws rather than returning nil so
    /// the caller can tell the user *why* nothing appeared — a silent no-op
    /// looks identical to a broken feature. `instruction` defaults to the note-
    /// drafting house style; the selection-popup summarize/answer/custom
    /// prompts pass their own.
    func generate(model: String, selection: String, instruction: String = Self.instruction) async throws -> String {
        let body = try Self.requestBody(model: model, selection: selection, instruction: instruction)
        let (data, code): (Data, Int)
        do {
            (data, code) = try await send(body)
        } catch {
            throw ClientError.offline
        }
        guard (200..<300).contains(code) else { throw ClientError.http(code) }
        return try Self.parse(data)
    }

    /// Pure, so the request shape is pinned by a test rather than by whatever
    /// Ollama happened to accept the day it was written.
    static func requestBody(model: String, selection: String, instruction: String = Self.instruction) throws -> Data {
        let payload: [String: Any] = [
            "model": model,
            "prompt": "\(instruction)\n\n\(selection)",
            "stream": false,
        ]
        return try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
    }

    /// Ollama wraps the text in `{"response": "..."}`. Trailing newlines are
    /// stripped because the insert adds its own spacing.
    static func parse(_ data: Data) throws -> String {
        struct Reply: Decodable { let response: String }
        guard let reply = try? JSONDecoder().decode(Reply.self, from: data) else {
            throw ClientError.empty
        }
        let text = reply.response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw ClientError.empty }
        return text
    }

    // MARK: Structured chat (for AssistantEngine)

    /// One structured turn: `messages` is the whole conversation so far
    /// (system prompt + history + the new user message); `schema` constrains
    /// the reply to valid JSON via Ollama's `format` field. Returns the raw
    /// JSON string the model produced — `AssistantEngine` decodes it, since
    /// what "valid" means is the engine's concern, not the transport's.
    func chat(model: String, messages: [ChatMessage], schema: [String: Any], numPredict: Int? = nil) async throws -> String {
        let body = try Self.chatRequestBody(model: model, messages: messages, schema: schema, numPredict: numPredict)
        let (data, code): (Data, Int)
        do {
            (data, code) = try await sendChat(body)
        } catch {
            throw ClientError.offline
        }
        guard (200..<300).contains(code) else { throw ClientError.http(code) }
        return try Self.parseChatContent(data)
    }

    /// `numPredict` caps how many tokens the model is allowed to generate —
    /// omitted (Ollama's own default) unless a caller knows roughly how much
    /// output to expect and wants to catch a runaway/truncated reply early.
    /// `CardGenerator` sets this; `AssistantEngine`'s free-form replies don't.
    static func chatRequestBody(
        model: String, messages: [ChatMessage], schema: [String: Any], numPredict: Int? = nil
    ) throws -> Data {
        var options: [String: Any] = [
            // Structured output is brittle enough at small model sizes without
            // also inviting creative deviation from the schema.
            "temperature": 0.2,
        ]
        if let numPredict { options["num_predict"] = numPredict }
        let payload: [String: Any] = [
            "model": model,
            "messages": messages.map { ["role": $0.role.rawValue, "content": $0.content] },
            "format": schema,
            "stream": false,
            "options": options,
        ]
        return try JSONSerialization.data(withJSONObject: payload)
    }

    /// Ollama wraps the model's turn in `{"message": {"role": ..., "content": "..."}}`.
    /// `content` is itself a JSON string (constrained by `format`, not parsed by
    /// Ollama) — this only unwraps the envelope, not the schema inside it.
    static func parseChatContent(_ data: Data) throws -> String {
        struct Reply: Decodable {
            struct Message: Decodable { let content: String }
            let message: Message
        }
        guard let reply = try? JSONDecoder().decode(Reply.self, from: data) else {
            throw ClientError.empty
        }
        let text = reply.message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw ClientError.empty }
        return text
    }

    // MARK: Embeddings (for RAG retrieval)

    /// One vector per `texts` entry, same order — batched into a single
    /// request rather than one call per chunk, so ranking a whole vault's
    /// worth of chunks against a query costs one round trip either way.
    func embed(model: String, texts: [String]) async throws -> [[Double]] {
        guard !texts.isEmpty else { return [] }
        let body = try Self.embedRequestBody(model: model, texts: texts)
        let (data, code): (Data, Int)
        do {
            (data, code) = try await sendEmbed(body)
        } catch {
            throw ClientError.offline
        }
        guard (200..<300).contains(code) else { throw ClientError.http(code) }
        return try Self.parseEmbeddings(data)
    }

    static func embedRequestBody(model: String, texts: [String]) throws -> Data {
        let payload: [String: Any] = ["model": model, "input": texts]
        return try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
    }

    /// `{"embeddings": [[...], [...]]}`.
    static func parseEmbeddings(_ data: Data) throws -> [[Double]] {
        struct Reply: Decodable { let embeddings: [[Double]] }
        guard let reply = try? JSONDecoder().decode(Reply.self, from: data), !reply.embeddings.isEmpty else {
            throw ClientError.empty
        }
        return reply.embeddings
    }
}
