import Foundation
import MLX
import MLXLMCommon
import MLXLLM
import MLXGuidedGeneration

/// The MLX transport for the `.chat` role on Apple Silicon — an in-process
/// alternative to `LlamaServerManager`'s spawned `llama-server`, exposed
/// through the same `LlamaCppClient(send:)` seam `AnthropicClient` and
/// `LlamaCppClient.forOpenAICompatibleProvider` already use. It decodes only
/// what `LlamaCppClient`'s own request builders (`chatRequestBody`,
/// `requestBody`) ever emit, and re-envelopes the result as the exact
/// OpenAI-compatible shape `parseChatContent`/`parseContent` already read —
/// so those builders/parsers, and every one of the eleven `LlamaCppClient()`
/// call sites, stay unaware a second backend exists at all.
///
/// One loaded model at a time, matching `LlamaServerManager.Role.chat`'s own
/// "one process, one model" contract — switching `ModelCatalog` entries
/// reloads rather than juggling containers.
actor MLXBackend {
    static let shared = MLXBackend()

    enum BackendError: LocalizedError {
        case notLoaded
        case malformedRequest

        var errorDescription: String? {
            switch self {
            case .notLoaded: "The MLX model isn't loaded yet."
            case .malformedRequest: "The local model request body was malformed."
            }
        }
    }

    private var container: ModelContainer?
    private var loadedDirectory: URL?

    /// Loads (or reuses) `directory`'s weights into a `ModelContainer`. Mirrors
    /// `LlamaServerManager.ensureRunning`'s "no-op once running, restart on a
    /// different path" contract — `LlamaRuntime.ensureChatServer` is this
    /// backend's equivalent entry point for an `.mlx` catalog entry.
    func ensureLoaded(directory: URL) async throws {
        guard loadedDirectory != directory else { return }
        container = try await LLMModelFactory.shared.loadContainer(from: directory, using: MLXTokenizerLoader())
        loadedDirectory = directory
    }

    /// The `send` closure `LlamaCppClient(send:)` expects: request JSON in,
    /// `(response JSON, HTTP-style status code)` out.
    func send(_ body: Data) async throws -> (Data, Int) {
        guard let container else { return (Data(), 503) }
        guard let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            return (Data(), 400)
        }
        do {
            let (content, thinking) = try await respond(json: json, container: container)
            let envelope: [String: Any] = [
                "choices": [["message": ["content": content, "reasoning_content": thinking]]]
            ]
            return (try JSONSerialization.data(withJSONObject: envelope), 200)
        } catch {
            return (Data(), 500)
        }
    }

    // MARK: Request decoding — the exact shapes chatRequestBody/requestBody emit

    private func respond(json: [String: Any], container: ModelContainer) async throws -> (content: String, thinking: String) {
        guard let rawMessages = json["messages"] as? [[String: String]] else { throw BackendError.malformedRequest }
        let messages = rawMessages.compactMap { m -> Chat.Message? in
            guard let role = m["role"].flatMap(Chat.Message.Role.init(rawValue:)), let content = m["content"] else { return nil }
            return Chat.Message(role: role, content: content)
        }
        let maxTokens = json["max_tokens"] as? Int ?? LlamaCppClient.generateMaxTokensFloor
        let temperature = json["temperature"] as? Double ?? 0.2
        // "none" (or absent — requestBody never sets it at all) disables
        // thinking, same convention `AssistantThinking.apiValue` already
        // encodes for llama-server. mlx-swift-lm has no separate knob for
        // this — the model's own chat template decides whether a `<think>`
        // block appears; we only ever split it back out below.
        let reasoningOff = (json["reasoning_effort"] as? String ?? "none") == "none"
        let input = UserInput(chat: messages)

        if let schema = (json["response_format"] as? [String: Any])?["json_schema"] as? [String: Any],
           let schemaBody = schema["schema"] {
            let schemaData = try JSONSerialization.data(withJSONObject: schemaBody)
            let schemaString = String(data: schemaData, encoding: .utf8) ?? "{}"
            let raw = try await respondConstrained(
                input: input, container: container, jsonSchema: schemaString, maxTokens: maxTokens
            )
            return splitThinking(raw, keepReasoning: !reasoningOff)
        }

        let raw = try await respondPlain(input: input, container: container, maxTokens: maxTokens, temperature: temperature)
        return splitThinking(raw, keepReasoning: !reasoningOff)
    }

    // MARK: Plain generation — note drafting, summaries, quiz explanations

    private func respondPlain(input: UserInput, container: ModelContainer, maxTokens: Int, temperature: Double) async throws -> String {
        // kvBits: 8 mirrors the .gguf path's `--cache-type-k/v q8_0` — same
        // reasoning (halves KV RAM, negligible quality cost), and it's what
        // `ModelCatalog.Entry.kvCacheBytesPerToken`'s q8_0 math assumes for
        // the .mlx entries.
        let parameters = GenerateParameters(maxTokens: maxTokens, kvBits: 8, temperature: Float(temperature))
        let lmInput = try await container.prepare(input: input)
        var text = ""
        for try await event in try await container.generate(input: lmInput, parameters: parameters) {
            if case .chunk(let chunk) = event { text += chunk }
        }
        return text
    }

    // MARK: Schema-constrained generation — assistant tool loop, quiz card generation

    /// `GuidedGenerationLoop.run` (Apple's own driver, also what
    /// `MLXFoundationModels`'s constrained decoding path reduces to) rather
    /// than hand-rolling xgrammar's bitmask application ourselves — that mask
    /// format is exactly the sort of detail this file has no business
    /// re-deriving when a maintained, tested implementation already does it.
    private func respondConstrained(
        input: UserInput, container: ModelContainer, jsonSchema: String, maxTokens: Int
    ) async throws -> String {
        let lmInput = try await container.prepare(input: input)
        return try await container.perform { context in
            let vocab = TokenizerVocabExtractor.extractForGrammar(from: context.tokenizer)
            let grammarTokenizer = try GrammarTokenizer(
                vocab: vocab.vocab, vocabType: vocab.vocabType,
                eosTokenId: Int32(context.tokenizer.eosTokenId ?? 0)
            )
            let constraint = try GrammarConstraint(
                tokenizer: grammarTokenizer, jsonSchema: jsonSchema, fastForward: true, hostTokenizer: context.tokenizer
            )
            var text = ""
            _ = try GuidedGenerationLoop.run(
                input: lmInput, context: context, constraint: constraint,
                maxTokens: maxTokens, vocabSize: grammarTokenizer.vocabSize,
                kvBits: 8 // same q8_0-equivalent reasoning as respondPlain, above
            ) { chunk in
                text += chunk
                return true
            }
            return text
        }
    }

    /// mlx-swift-lm's raw generation carries `<think>…</think>` inline —
    /// unlike llama-server, which already separates it into its own
    /// `reasoning_content` field (see `LlamaCppClient`'s doc comment on
    /// `chat(...)`). This is that split, done here so `parseChatContent`
    /// stays byte-identical between both backends. `keepReasoning` mirrors
    /// `reasoning_effort`: when thinking was off, any stray `<think>` block
    /// is dropped entirely rather than surfaced.
    private func splitThinking(_ raw: String, keepReasoning: Bool) -> (content: String, thinking: String) {
        guard let openRange = raw.range(of: "<think>"), let closeRange = raw.range(of: "</think>", range: openRange.upperBound..<raw.endIndex) else {
            return (raw.trimmingCharacters(in: .whitespacesAndNewlines), "")
        }
        let thinking = String(raw[openRange.upperBound..<closeRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        let content = (String(raw[raw.startIndex..<openRange.lowerBound]) + String(raw[closeRange.upperBound...]))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (content, keepReasoning ? thinking : "")
    }
}
