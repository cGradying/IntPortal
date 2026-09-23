import XCTest
@testable import PUPSISPortal

/// `SISHost` is the pure logic behind spec 00-sis-host.md's failover — which
/// host to try, in what order, and whether a signed-in host is worth
/// keeping — pulled out of `PortalController` so it's testable without a
/// real `WKWebView`.
final class SISHostTests: XCTestCase {
    // MARK: - isCandidateHost

    func testAcceptsTheThreeConfirmedLiveMirrors() {
        XCTAssertTrue(SISHost.isCandidateHost("sis1.pup.edu.ph"))
        XCTAssertTrue(SISHost.isCandidateHost("sis2.pup.edu.ph"))
        XCTAssertTrue(SISHost.isCandidateHost("sis8.pup.edu.ph"))
    }

    func testAcceptsAnyNumberedMirrorShape() {
        XCTAssertTrue(SISHost.isCandidateHost("sis23.pup.edu.ph"))
    }

    /// `www` is a real pup.edu.ph subdomain (and passes `isTrustedHost`,
    /// the credential gate) but it's not a numbered SIS mirror — adopting it
    /// as a candidate host was the bug (`adoptActualHost` used to trust any
    /// `*.pup.edu.ph`, `www` included, and persist it forever).
    func testRejectsANonNumberedPupSubdomain() {
        XCTAssertFalse(SISHost.isCandidateHost("www.pup.edu.ph"))
    }

    /// A lookalike domain that merely ends with the right-looking text —
    /// the host must be exactly `sisN.pup.edu.ph`, not just contain it.
    func testRejectsADomainThatOnlyPiggybacksTheSuffix() {
        XCTAssertFalse(SISHost.isCandidateHost("sis8.pup.edu.ph.evil.com"))
    }

    func testRejectsGarbage() {
        XCTAssertFalse(SISHost.isCandidateHost(""))
        XCTAssertFalse(SISHost.isCandidateHost("pup.edu.ph"))
        XCTAssertFalse(SISHost.isCandidateHost("sis.pup.edu.ph"))
    }

    // MARK: - candidates(remembered:)

    func testNoRememberedHostUsesTheSpecDefaultOrder() {
        XCTAssertEqual(
            SISHost.candidates(remembered: nil),
            ["sis8.pup.edu.ph", "sis1.pup.edu.ph", "sis2.pup.edu.ph"]
        )
    }

    func testRememberedHostGoesFirst() {
        XCTAssertEqual(
            SISHost.candidates(remembered: "sis1.pup.edu.ph"),
            ["sis1.pup.edu.ph", "sis8.pup.edu.ph", "sis2.pup.edu.ph"]
        )
    }

    /// The remembered host is already first in the default order — must not
    /// appear twice.
    func testRememberedHostAlreadyFirstIsNotDuplicated() {
        XCTAssertEqual(
            SISHost.candidates(remembered: "sis8.pup.edu.ph"),
            ["sis8.pup.edu.ph", "sis1.pup.edu.ph", "sis2.pup.edu.ph"]
        )
    }

    /// An invalid remembered host (e.g. left over from before this fix, or
    /// tampered with) is dropped rather than tried — falls back to the plain
    /// default order.
    func testInvalidRememberedHostIsIgnored() {
        XCTAssertEqual(
            SISHost.candidates(remembered: "www.pup.edu.ph"),
            ["sis8.pup.edu.ph", "sis1.pup.edu.ph", "sis2.pup.edu.ph"]
        )
    }

    // MARK: - decide(_:host:)

    func testValidationErrorStops() {
        XCTAssertEqual(SISHost.decide(.validationError, host: "sis8.pup.edu.ph"), .stop)
    }

    func testFailedTriesTheNextHost() {
        XCTAssertEqual(SISHost.decide(.failed, host: "sis8.pup.edu.ph"), .next)
    }

    func testSignedInButEmptyTriesTheNextHost() {
        XCTAssertEqual(SISHost.decide(.signedInEmpty, host: "sis1.pup.edu.ph"), .next)
    }

    func testSignedInWithRowsKeepsThatHost() {
        XCTAssertEqual(SISHost.decide(.signedInWithRows, host: "sis8.pup.edu.ph"), .keep(host: "sis8.pup.edu.ph"))
    }

    /// The acceptance case: simulates a consumer looping over candidates and
    /// applying `decide` to each outcome. A validation error on the very
    /// first host must end the loop right there — a second host is never
    /// even considered, let alone tried.
    func testWrongPasswordNeverTriesASecondHost() {
        let candidates = SISHost.candidates(remembered: nil)
        var tried: [String] = []

        for host in candidates {
            tried.append(host)
            // First host: wrong password. Every candidate after would also
            // report validationError if this loop kept going — the test is
            // that it doesn't.
            let decision = SISHost.decide(.validationError, host: host)
            if decision == .stop { break }
        }

        XCTAssertEqual(tried, ["sis8.pup.edu.ph"])
    }

    /// A host that signs in but comes up empty moves on; the next candidate
    /// that has rows is the one kept — mirrors the sis1/sis8 case from
    /// commit f763487.
    func testEmptyHostFailsOverToTheNextOneWithRows() {
        let candidates = SISHost.candidates(remembered: nil) // [sis8, sis1, sis2]
        let outcomes: [SISHost.Attempt] = [.signedInEmpty, .signedInWithRows, .signedInWithRows]
        var kept: String?

        for (host, outcome) in zip(candidates, outcomes) {
            switch SISHost.decide(outcome, host: host) {
            case .keep(let host): kept = host
            case .next: continue
            case .stop: break
            }
            if kept != nil { break }
        }

        XCTAssertEqual(kept, "sis1.pup.edu.ph")
    }
}
