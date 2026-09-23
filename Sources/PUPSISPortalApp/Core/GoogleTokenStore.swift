import Foundation
import Security

/// The Google OAuth refresh token, in the Keychain. Separate from `KeychainStore`
/// (SIS credentials) only by account, so both live under the same service and a
/// sign-out can clear either independently.
///
/// The refresh token is the sensitive part — it mints access tokens — so it never
/// touches disk, logs, or `UserDefaults`. The client ID is not secret and lives
/// in `Preferences`.
///
/// A value type over `service`/`account` so tests can point at an isolated
/// Keychain item instead of the user's real one. `.production` (the default
/// everywhere in the app) is the only instance that should ever touch a real token.
struct GoogleTokenStore {
    static let production = GoogleTokenStore()

    let service: String
    let account: String

    init(service: String = "ph.edu.pup.sis8.portal", account: String = "google-refresh") {
        self.service = service
        self.account = account
    }

    func save(refreshToken: String) {
        guard let data = refreshToken.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        if SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess {
            SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        } else {
            var add = query
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    func load() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
