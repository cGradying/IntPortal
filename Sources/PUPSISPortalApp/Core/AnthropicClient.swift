import Foundation

/// Anthropic support (wayfinder ticket #17) — not a separate client type,
/// an `LlamaCppClient` whose `send` closure fully translates between the
/// OpenAI shape every request/response builder in that file already
/// produces and Anthropic's genuinely different Messages API:
/// - the system prompt is its own top-level field, not a `"system"`-role
///   message;
/// - a schema-locked reply is forced via `tool_choice` + a single tool
///   whose `input_schema` IS the JSON schema, not `response_format`;
/// - the reply comes back as `content: [{type, text|input}]`, not
///   `choices[0].message`.
///
/// Translating inside `send` — rather than writing parallel
/// `anthropicChat`/`anthropicGenerate` methods and their own parsers — means
/// `generate`/`chat`/`parseContent`/`parseChatContent` stay completely
/// unchanged. This is still exactly a `LlamaCppClient`; only what's on the
/// wire underneath differs, the same seam `forOpenAICompatibleProvider`
/// uses for OpenAI/Google.
extension LlamaCppClient {
    private static let anthropicEndpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private static let anthropicVersion = "2023-06-01"

    static func forAnthropicProvider(apiKey: String, model: String) -> LlamaCppClient {
        // `sendEmbed` is left at its local default deliberately — Anthropic
        // has no embeddings API at all, and RAG stays local-only regardless
        // of `aiProvider` (same scoping as the OpenAI-compatible factory).
        LlamaCppClient(send: { body in try await Self.postToAnthropic(body, apiKey: apiKey, model: model) })
    }

    private static func postToAnthropic(_ openAIBody: Data, apiKey: String, model: String) async throws -> (Data, Int) {
        guard let openAI = try? JSONSerialization.jsonObject(with: openAIBody) as? [String: Any] else {
            return (openAIBody, 0)
        }
        let messages = (openAI["messages"] as? [[String: Any]]) ?? []
        let system = messages.first { $0["role"] as? String == "system" }?["content"] as? String
        let conversational = messages.filter { $0["role"] as? String != "system" }

        var anthropicBody: [String: Any] = [
            "model": model,
            "max_tokens": (openAI["max_tokens"] as? Int) ?? 1024,
            "messages": conversational,
        ]
        if let system { anthropicBody["system"] = system }
        if let temperature = openAI["temperature"] { anthropicBody["temperature"] = temperature }

        // A schema-locked turn (AssistantEngine's tool-picking loop, quiz
        // generation): Anthropic has no response_format equivalent — force a
        // single tool call whose input_schema IS the JSON schema, so the
        // reply arrives already-structured as content[0].input.
        var forcedToolName: String?
        if let responseFormat = openAI["response_format"] as? [String: Any],
           let jsonSchema = responseFormat["json_schema"] as? [String: Any],
           let schema = jsonSchema["schema"] {
            let name = (jsonSchema["name"] as? String) ?? "reply"
            forcedToolName = name
            anthropicBody["tools"] = [["name": name, "description": "Structured reply", "input_schema": schema]]
            anthropicBody["tool_choice"] = ["type": "tool", "name": name]
        }

        var request = URLRequest(url: anthropicEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(anthropicVersion, forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: anthropicBody)
        request.timeoutInterval = 180

        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else { return (data, code) } // let the shared HTTP-error path handle it

        return (reenvelopingAsOpenAI(data, forcedToolName: forcedToolName), code)
    }

    /// `{"content":[{"type":"text","text":"..."}]}` (or, tool-forced,
    /// `{"content":[{"type":"tool_use","input":{...}}]}`) →
    /// `{"choices":[{"message":{"content":"...","reasoning_content":""}}]}`
    /// — the exact envelope `parseContent`/`parseChatContent` already
    /// decode, so nothing downstream needs to know a translation happened.
    /// Anthropic has no separate reasoning-trace field in this shape (no
    /// extended-thinking request was made), so `reasoning_content` is
    /// always empty here.
    static func reenvelopingAsOpenAI(_ anthropicData: Data, forcedToolName: String?) -> Data {
        guard let reply = try? JSONSerialization.jsonObject(with: anthropicData) as? [String: Any],
              let blocks = reply["content"] as? [[String: Any]]
        else {
            return anthropicData
        }
        let content: String
        if forcedToolName != nil, let toolBlock = blocks.first(where: { $0["type"] as? String == "tool_use" }),
           let input = toolBlock["input"] {
            content = (try? JSONSerialization.data(withJSONObject: input))
                .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        } else {
            content = (blocks.first { $0["type"] as? String == "text" }?["text"] as? String) ?? ""
        }
        let envelope: [String: Any] = ["choices": [["message": ["content": content, "reasoning_content": ""]]]]
        return (try? JSONSerialization.data(withJSONObject: envelope)) ?? anthropicData
    }
}
