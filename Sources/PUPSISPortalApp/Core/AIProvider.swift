import Foundation
import Security

/// Which model answers a chat/generate request — local `llama.cpp` (the
/// default, no key, no network, ships with the app) or a named cloud
/// provider the student supplies their own API key for (wayfinder ticket
/// #17). `.local` staying the default is load-bearing: the DMG must never
/// require a cloud key just to use the assistant.
enum AIProvider: String, CaseIterable, Identifiable, Codable {
    case local
    case openai
    case google
    case anthropic

    var id: String { rawValue }

    var label: String {
        switch self {
        case .local: "Local (offline)"
        case .openai: "OpenAI"
        case .google: "Google"
        case .anthropic: "Anthropic"
        }
    }

    /// OpenAI and Google's Gemini both actually speak the OpenAI
    /// chat-completions request/response shape — Google via its own
    /// `/openai/` compatibility endpoint — so both reuse `LlamaCppClient`'s
    /// exact parsing unchanged (`LlamaCppClient.forOpenAICompatibleProvider`),
    /// just a different endpoint and an `Authorization: Bearer` header
    /// instead of the local hardcoded default. Anthropic's Messages API
    /// genuinely isn't OpenAI-shaped (different endpoint, `x-api-key`
    /// header, a different content envelope, tool-forcing instead of
    /// `response_format`) — it gets its own `AnthropicClient`.
    var isOpenAICompatible: Bool {
        switch self {
        case .openai, .google: true
        case .local, .anthropic: false
        }
    }

    var chatEndpoint: URL? {
        switch self {
        case .local: nil // LlamaCppClient.endpoint — always localhost, never this
        case .openai: URL(string: "https://api.openai.com/v1/chat/completions")
        case .google: URL(string: "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions")
        case .anthropic: URL(string: "https://api.anthropic.com/v1/messages")
        }
    }

    /// A reasonable starting model per provider — small/cheap, not the
    /// flagship, since this is a study assistant, not a coding agent. Shown
    /// as a placeholder/default in Settings; the student can type a
    /// different model id.
    var defaultModel: String {
        switch self {
        case .local: "" // ignored — llama-server serves exactly one model
        case .openai: "gpt-4o-mini"
        case .google: "gemini-2.0-flash"
        case .anthropic: "claude-3-5-haiku-latest"
        }
    }

    /// Whether this provider needs a key at all — `.local` never does.
    var needsAPIKey: Bool { self != .local }
}

/// One API key per cloud provider, in the Keychain — never `UserDefaults`,
/// never a plain file. **Its own service name**, distinct from both
/// `ph.edu.pup.sis8.portal` (this app's own SIS credentials, `KeychainStore`)
/// and `ph.edu.pup.sis8` (the sibling PUPSIS app) — a wrong guess here would
/// either leak an SIS password lookup into AI code or collide two apps'
/// Keychain items under one identity. Same save/load/delete shape as
/// `KeychainStore`, keyed by provider instead of a fixed account.
enum AIProviderKeyStore {
    private static let service = "ph.edu.pup.sis8.portal.ai-providers"

    static func save(_ key: String, for provider: AIProvider) throws {
        let data = Data(key.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue,
        ]
        if SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess {
            let update: [String: Any] = [kSecValueData as String: data]
            let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
            guard status == errSecSuccess else { throw KeychainError(status: status) }
        } else {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let status = SecItemAdd(addQuery as CFDictionary, nil)
            guard status == errSecSuccess else { throw KeychainError(status: status) }
        }
    }

    static func load(for provider: AIProvider) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue,
            kSecReturnData as String: true,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8)
        else {
            return nil
        }
        return key
    }

    static func delete(for provider: AIProvider) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
