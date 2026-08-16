import Foundation

/// The local RAG-answer model (llama.cpp, e.g. `LFM2-1.2B-RAG-GGUF`) — used
/// only by the `ask_notes` tool, to synthesize a grounded answer over notes
/// `RealAssistantExecutor` already found by keyword search. This is **not** a
/// second brain for the whole assistant.
///
/// A live spike (this session) fed this class of small RAG-tuned model the
/// assistant's actual tool-calling prompt shape: it ignored the request and
/// picked the wrong tool, fabricating content. Given the same information as
/// a plain "here's context, answer the question" completion — no schema, no
/// tool menu — it answered correctly and stayed grounded. So it never drives
/// tool selection; it only ever answers what it's handed directly.
///
/// **Localhost only, deliberately** — same promise as `OllamaClient`: the
/// endpoint is a constant, not a setting.
struct LlamaCppClient {
    static let endpoint = URL(string: "http://127.0.0.1:8080/v1/chat/completions")!

    enum ClientError: LocalizedError {
        case offline
        case http(Int)
        case empty

        var errorDescription: String? {
            switch self {
            case .offline:
                "Couldn't reach the local notes-answering server. Start it with `llama-server -hf LiquidAI/LFM2-1.2B-RAG-GGUF`."
            case .http(let code):
                "The local notes-answering server returned HTTP \(code)."
            case .empty:
                "The local notes-answering server returned an empty response."
            }
        }
    }

    private let send: (Data) async throws -> (Data, Int)

    init(send: ((Data) async throws -> (Data, Int))? = nil) {
        self.send = send ?? Self.post
    }

    private static func post(_ body: Data) async throws -> (Data, Int) {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        // A cold local model can genuinely take a while on the first request.
        request.timeoutInterval = 60
        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        return (data, code)
    }

    /// A plain grounded-answer completion — deliberately no JSON schema and no
    /// tool menu in the prompt, per the spike finding above. Throws rather
    /// than returning nil so the caller (the `ask_notes` tool) can tell the
    /// student *why* nothing came back, same rationale as `OllamaClient.generate`.
    func complete(system: String, user: String) async throws -> String {
        let body = try Self.requestBody(system: system, user: user)
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
    /// llama.cpp happened to accept the day it was written. `model` is omitted
    /// deliberately — llama.cpp's server serves exactly one model per running
    /// process, unlike Ollama's multi-model `/api/generate`.
    static func requestBody(system: String, user: String) throws -> Data {
        let payload: [String: Any] = [
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user],
            ],
            "temperature": 0.2,
            "max_tokens": 500,
        ]
        return try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
    }

    /// The OpenAI-compatible shape llama.cpp's server replies with:
    /// `{"choices":[{"message":{"content":"..."}}]}`.
    static func parse(_ data: Data) throws -> String {
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
}
