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

    private let send: (Data) async throws -> (Data, Int)

    init(send: ((Data) async throws -> (Data, Int))? = nil) {
        self.send = send ?? Self.post
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

    private static func post(_ body: Data) async throws -> (Data, Int) {
        var request = URLRequest(url: endpoint)
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
    /// looks identical to a broken feature.
    func generate(model: String, selection: String) async throws -> String {
        let body = try Self.requestBody(model: model, selection: selection)
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
    static func requestBody(model: String, selection: String) throws -> Data {
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
}
