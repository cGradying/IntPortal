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
}
