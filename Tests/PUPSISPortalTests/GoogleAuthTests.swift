import XCTest
@testable import PUPSISPortal

/// The pure PKCE / helper bits of the Google OAuth flow. The network and the
/// browser session aren't exercised here.
@MainActor
final class GoogleAuthTests: XCTestCase {
    /// RFC 7636 Appendix B test vector for S256.
    func testCodeChallengeMatchesRFCVector() {
        let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        XCTAssertEqual(GoogleAuth.challenge(for: verifier),
                       "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    func testReversedSchemeFromClientID() {
        XCTAssertEqual(
            GoogleAuth.reversedScheme(clientID: "1234-abcXYZ.apps.googleusercontent.com"),
            "com.googleusercontent.apps.1234-abcXYZ"
        )
    }

    /// base64url has no +, /, or = padding.
    func testBase64URLIsURLSafe() {
        let s = GoogleAuth.base64URL(Data([251, 255, 191, 0]))
        XCTAssertFalse(s.contains("+"))
        XCTAssertFalse(s.contains("/"))
        XCTAssertFalse(s.contains("="))
    }

    func testPKCEChallengeDerivesFromVerifier() {
        let pkce = GoogleAuth.makePKCE()
        XCTAssertEqual(pkce.challenge, GoogleAuth.challenge(for: pkce.verifier))
        XCTAssertFalse(pkce.verifier.isEmpty)
    }

    func testFormEncodeEscapesReservedCharacters() {
        // A single field so ordering isn't a factor.
        XCTAssertEqual(GoogleAuth.formEncode(["redirect_uri": "com.x.y:/a b"]),
                       "redirect_uri=com.x.y%3A%2Fa%20b")
    }

    // MARK: - invalid_grant on refresh (W7)

    /// An `invalid_grant` refresh means the stored refresh token is dead, not
    /// just momentarily unavailable — `validAccessToken` must drop it and flip
    /// `isConnected` false rather than keep reporting a session that can't
    /// actually mint tokens anymore.
    func testInvalidGrantOnRefreshClearsStoredTokenAndDisconnects() async {
        let store = Self.isolatedTokenStore()
        defer { store.delete() }
        store.save(refreshToken: "stale-refresh-token")

        StubURLProtocol.handler = { _ in
            (400, Data(#"{"error":"invalid_grant","error_description":"Token has been expired or revoked."}"#.utf8))
        }
        let auth = GoogleAuth(clientID: { "test-client-id" }, urlSession: Self.stubbedURLSession(), tokenStore: store)
        XCTAssertTrue(auth.isConnected)

        do {
            _ = try await auth.validAccessToken()
            XCTFail("expected an error from an invalid_grant refresh")
        } catch GoogleAuth.AuthError.reconnectRequired {
            // expected
        } catch {
            XCTFail("wrong error: \(error)")
        }

        XCTAssertFalse(auth.isConnected)
        XCTAssertNil(store.load())
    }

    /// A non-`invalid_grant` failure (e.g. a network hiccup) must not be
    /// mistaken for a dead token — the app should retry later, not disconnect.
    func testOtherRefreshFailureLeavesTokenAndConnectionIntact() async {
        let store = Self.isolatedTokenStore()
        defer { store.delete() }
        store.save(refreshToken: "still-good-refresh-token")

        StubURLProtocol.handler = { _ in
            (500, Data(#"{"error":"server_error","error_description":"try again"}"#.utf8))
        }
        let auth = GoogleAuth(clientID: { "test-client-id" }, urlSession: Self.stubbedURLSession(), tokenStore: store)
        XCTAssertTrue(auth.isConnected)

        do {
            _ = try await auth.validAccessToken()
            XCTFail("expected an error from the stubbed 500")
        } catch GoogleAuth.AuthError.badResponse {
            // expected
        } catch {
            XCTFail("wrong error: \(error)")
        }

        XCTAssertTrue(auth.isConnected)
        XCTAssertEqual(store.load(), "still-good-refresh-token")
    }

    // MARK: - ASWebAuthenticationSession.start() returning false (W7)

    /// `start()` returning false (e.g. no window yet) must resume the
    /// continuation with an error, not leave `connect()` hanging forever.
    func testFailedSessionStartResumesWithErrorInsteadOfHanging() async {
        let auth = GoogleAuth(
            clientID: { "1234.apps.googleusercontent.com" },
            sessionStarter: { _ in false },
            tokenStore: Self.isolatedTokenStore()
        )

        do {
            try await auth.connect()
            XCTFail("expected connect() to throw when the auth session fails to start")
        } catch GoogleAuth.AuthError.badResponse {
            // expected — resumed with an error instead of hanging
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    // MARK: - Isolated doubles

    private static func stubbedURLSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }

    /// A Keychain item scoped to this test run only — never the production
    /// `ph.edu.pup.sis8.portal` / `google-refresh` item that might hold the
    /// user's real Google refresh token.
    private static func isolatedTokenStore() -> GoogleTokenStore {
        GoogleTokenStore(service: "ph.edu.pup.sis8.portal.tests.\(UUID())", account: "google-refresh")
    }
}

/// Intercepts every request made through a `URLSession` configured with it, so
/// `GoogleAuth`'s token-endpoint tests never reach `oauth2.googleapis.com`.
private final class StubURLProtocol: URLProtocol {
    static var handler: ((URLRequest) -> (Int, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler, let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        let (status, data) = handler(request)
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
