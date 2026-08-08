import AppKit
import AuthenticationServices
import CryptoKit
import Foundation

/// Google OAuth for a public (PKCE) client — no client secret. The user brings
/// their own **iOS-type** OAuth client ID; the app derives the reversed-client-ID
/// redirect scheme, runs the consent flow in `ASWebAuthenticationSession` (which
/// captures the redirect itself, so nothing needs registering in Info.plist), and
/// exchanges the code for tokens. The refresh token lands in the Keychain
/// (`GoogleTokenStore`); the access token is kept only in memory.
///
/// ponytail: while the user's OAuth consent screen is in "testing", Google expires
/// the refresh token after ~7 days, so Connect gets re-run about weekly. Publishing
/// the consent screen removes that; not worth automating for a personal app.
@MainActor
final class GoogleAuth: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    @Published private(set) var isConnected: Bool

    private let clientID: () -> String
    private var accessToken: String?
    private var accessExpiry: Date = .distantPast
    private var session: ASWebAuthenticationSession?

    private let scopes = "https://www.googleapis.com/auth/calendar"

    init(clientID: @escaping () -> String) {
        self.clientID = clientID
        isConnected = GoogleTokenStore.load() != nil
    }

    enum AuthError: LocalizedError {
        case noClientID
        case cancelled
        case badResponse(String)
        case notConnected

        var errorDescription: String? {
            switch self {
            case .noClientID: "Enter your Google OAuth client ID first."
            case .cancelled: "Google sign-in was cancelled."
            case .badResponse(let m): m
            case .notConnected: "Connect your Google account first."
            }
        }
    }

    // MARK: Connect

    func connect() async throws {
        let id = clientID().trimmingCharacters(in: .whitespaces)
        guard !id.isEmpty else { throw AuthError.noClientID }

        let scheme = Self.reversedScheme(clientID: id)
        let redirect = "\(scheme):/oauth2redirect"
        let pkce = Self.makePKCE()
        let state = Self.randomString(32)

        var comps = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        comps.queryItems = [
            .init(name: "client_id", value: id),
            .init(name: "redirect_uri", value: redirect),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: scopes),
            .init(name: "code_challenge", value: pkce.challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "state", value: state),
            // Ask for a refresh token, and force the consent that returns one.
            .init(name: "access_type", value: "offline"),
            .init(name: "prompt", value: "consent"),
        ]

        let callback = try await runSession(url: comps.url!, scheme: scheme)
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard items.first(where: { $0.name == "state" })?.value == state else {
            throw AuthError.badResponse("Sign-in response didn't match the request.")
        }
        guard let code = items.first(where: { $0.name == "code" })?.value else {
            let err = items.first(where: { $0.name == "error" })?.value ?? "no authorization code"
            throw AuthError.badResponse(err)
        }

        let token = try await exchange(code: code, verifier: pkce.verifier, redirect: redirect, clientID: id)
        if let refresh = token.refresh_token {
            GoogleTokenStore.save(refreshToken: refresh)
        }
        accessToken = token.access_token
        accessExpiry = Date().addingTimeInterval(token.expires_in)
        isConnected = true
    }

    func disconnect() {
        GoogleTokenStore.delete()
        accessToken = nil
        accessExpiry = .distantPast
        isConnected = false
    }

    /// A valid access token, refreshing from the stored refresh token when the
    /// cached one has expired. This is what `GoogleCalendarClient` calls.
    func validAccessToken() async throws -> String {
        if let token = accessToken, accessExpiry.timeIntervalSinceNow > 60 { return token }
        guard let refresh = GoogleTokenStore.load() else { throw AuthError.notConnected }

        let id = clientID().trimmingCharacters(in: .whitespaces)
        guard !id.isEmpty else { throw AuthError.noClientID }

        let token = try await refreshToken(refresh, clientID: id)
        accessToken = token.access_token
        accessExpiry = Date().addingTimeInterval(token.expires_in)
        return token.access_token
    }

    // MARK: Token endpoint

    private struct TokenResponse: Decodable {
        let access_token: String
        let expires_in: Double
        let refresh_token: String?
    }

    private func exchange(code: String, verifier: String, redirect: String, clientID id: String) async throws -> TokenResponse {
        try await postToken([
            "grant_type": "authorization_code",
            "code": code,
            "code_verifier": verifier,
            "client_id": id,
            "redirect_uri": redirect,
        ])
    }

    private func refreshToken(_ refresh: String, clientID id: String) async throws -> TokenResponse {
        try await postToken([
            "grant_type": "refresh_token",
            "refresh_token": refresh,
            "client_id": id,
        ])
    }

    private func postToken(_ fields: [String: String]) async throws -> TokenResponse {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formEncode(fields).data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw AuthError.badResponse(Self.googleError(data))
        }
        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }

    // MARK: Session

    private func runSession(url: URL, scheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: scheme) { callback, error in
                if let callback {
                    continuation.resume(returning: callback)
                } else if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    continuation.resume(throwing: AuthError.cancelled)
                } else {
                    continuation.resume(throwing: error ?? AuthError.cancelled)
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            session.start()
        }
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first ?? ASPresentationAnchor()
        }
    }

    // MARK: PKCE / helpers (pure, tested)

    struct PKCE { let verifier: String; let challenge: String }

    static func makePKCE() -> PKCE {
        let verifier = randomString(64)
        return PKCE(verifier: verifier, challenge: challenge(for: verifier))
    }

    static func challenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return base64URL(Data(digest))
    }

    /// `com.googleusercontent.apps.<id>` from `<id>.apps.googleusercontent.com`.
    static func reversedScheme(clientID: String) -> String {
        let id = clientID.replacingOccurrences(of: ".apps.googleusercontent.com", with: "")
        return "com.googleusercontent.apps.\(id)"
    }

    static func randomString(_ bytes: Int) -> String {
        base64URL(Data((0..<bytes).map { _ in UInt8.random(in: 0...255) }))
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func formEncode(_ fields: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return fields.map { key, value in
            let v = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(key)=\(v)"
        }.joined(separator: "&")
    }

    private static func googleError(_ data: Data) -> String {
        struct E: Decodable { let error: String?; let error_description: String? }
        if let e = try? JSONDecoder().decode(E.self, from: data) {
            return e.error_description ?? e.error ?? "Google rejected the request."
        }
        return "Google rejected the request."
    }
}
