import Foundation
import MLXLMCommon
import Tokenizers

/// Adapts `swift-transformers`' `Tokenizers.Tokenizer` (BPE + chat-template
/// parsing, already maintained upstream — see `Core/MLXBackend.swift`'s own
/// doc comment on why this isn't hand-rolled) into `MLXLMCommon`'s own
/// `Tokenizer`/`TokenizerLoader` protocols, which mlx-swift-lm 2.x defines
/// itself rather than depending on swift-transformers directly.
struct MLXTokenizerLoader: MLXLMCommon.TokenizerLoader {
    func load(from directory: URL) async throws -> any MLXLMCommon.Tokenizer {
        MLXTokenizerAdapter(upstream: try await Tokenizers.AutoTokenizer.from(modelFolder: directory))
    }
}

private struct MLXTokenizerAdapter: MLXLMCommon.Tokenizer {
    let upstream: Tokenizers.Tokenizer

    func encode(text: String, addSpecialTokens: Bool) -> [Int] {
        upstream.encode(text: text, addSpecialTokens: addSpecialTokens)
    }

    func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String {
        upstream.decode(tokens: tokenIds, skipSpecialTokens: skipSpecialTokens)
    }

    func convertTokenToId(_ token: String) -> Int? { upstream.convertTokenToId(token) }
    func convertIdToToken(_ id: Int) -> String? { upstream.convertIdToToken(id) }

    var bosToken: String? { upstream.bosToken }
    var eosToken: String? { upstream.eosToken }
    var unknownToken: String? { upstream.unknownToken }

    /// `MLXLMCommon.Tokenizer` passes `any Sendable` values (room for a
    /// richer chat-template context); swift-transformers' own
    /// `applyChatTemplate` only ever takes `[String: String]`. Every message
    /// this app ever builds (`LlamaCppClient.ChatMessage`) is plain
    /// role/content strings, so the values are always already `String` —
    /// `additionalContext`/`tools` are dropped rather than force-cast, since
    /// nothing populates them for the local MLX path today (tool-calling
    /// here goes through JSON-schema-constrained plain completions, not
    /// swift-transformers' own tool-template support).
    func applyChatTemplate(
        messages: [[String: any Sendable]], tools: [[String: any Sendable]]?, additionalContext: [String: any Sendable]?
    ) throws -> [Int] {
        let stringMessages = messages.map { message in
            message.compactMapValues { $0 as? String }
        }
        return try upstream.applyChatTemplate(messages: stringMessages)
    }
}
