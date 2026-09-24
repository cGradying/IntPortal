import XCTest
@testable import PUPSISPortal

final class CampusTests: XCTestCase {
    func testKnownCodeResolvesToStaMesa() {
        XCTAssertEqual(
            CampusCatalog.resolve(studentNumber: "2026-00000-MN-0", override: nil),
            .known(Campus(code: "MN", name: "Sta. Mesa", region: "Manila"))
        )
    }

    func testUnverifiedCodeIsUnknown() {
        XCTAssertEqual(CampusCatalog.resolve(studentNumber: "2026-00000-TG-0", override: nil), .unknownCode("TG"))
    }

    func testMalformedNumberIsIncomplete() {
        XCTAssertEqual(CampusCatalog.resolve(studentNumber: "2026-000", override: nil), .incomplete)
    }

    func testOverrideWinsRegardlessOfCode() {
        let pick = Campus(code: "MN", name: "Somewhere Else", region: "Nowhere")
        XCTAssertEqual(CampusCatalog.resolve(studentNumber: "2026-00000-MN-0", override: pick), .overridden(pick))
        XCTAssertEqual(CampusCatalog.resolve(studentNumber: "not a student number", override: pick), .overridden(pick))
    }

    func testLearnedCodeResolvesOnTheNextCall() {
        let resolution = CampusCatalog.resolve(
            studentNumber: "2026-00000-TG-0", override: nil, learnedCodes: ["TG": "Taguig"]
        )
        XCTAssertEqual(resolution, .overridden(Campus(code: "TG", name: "Taguig", region: "")))
    }

    func testOneAndTwoDigitSuffixBothAccepted() {
        XCTAssertEqual(CampusCatalog.code(fromStudentNumber: "2026-00000-MN-0"), "MN")
        XCTAssertEqual(CampusCatalog.code(fromStudentNumber: "2026-00000-MN-12"), "MN")
    }

    func testCodeIsUppercasedAndTrimmed() {
        XCTAssertEqual(CampusCatalog.code(fromStudentNumber: "  2026-00000-mn-0  "), "MN")
    }

    func testOnlyStaMesaHasAConfirmedCode() {
        let coded = CampusCatalog.all.filter { $0.code != nil }
        XCTAssertEqual(coded.map(\.name), ["Sta. Mesa"])
    }

    /// Spec 10's actual budget (5ms/10,000 calls) is a release-build number —
    /// the head's own perf lane measures that. This debug-build run only
    /// guards against a real regression (an accidental network/disk call, an
    /// O(n²) scan) landing in a function that's supposed to be a plain regex
    /// match and array lookup.
    func testResolveHasNoGrossPerformanceRegression() {
        let start = Date()
        for _ in 0..<10_000 {
            _ = CampusCatalog.resolve(studentNumber: "2026-00000-MN-0", override: nil)
        }
        XCTAssertLessThan(Date().timeIntervalSince(start), 0.25)
    }
}

@MainActor
final class CampusPreferencesTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        suiteName = "CampusPreferencesTests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testPickCampusSetsOverrideAndLearnsTheCode() {
        let preferences = Preferences(defaults: defaults)
        let taguig = Campus(code: "TG", name: "Taguig", region: "Metro Manila")

        preferences.pickCampus(taguig)

        XCTAssertEqual(preferences.campusOverride, taguig)
        XCTAssertEqual(preferences.learnedCampusCodes["TG"], "Taguig")
    }

    /// Spec 10: `campusOverride` and `learnedCampusCodes` are cleared on
    /// sign-out — `AppState.signOut()` calls this same `clearCampus()`.
    func testClearCampusUndoesBothOnSignOut() {
        let preferences = Preferences(defaults: defaults)
        preferences.pickCampus(Campus(code: "TG", name: "Taguig", region: "Metro Manila"))

        preferences.clearCampus()

        XCTAssertNil(preferences.campusOverride)
        XCTAssertTrue(preferences.learnedCampusCodes.isEmpty)
        // And a fresh sign-in with the same code no longer resolves it —
        // the whole point of clearing it, not just resetting in memory.
        XCTAssertEqual(CampusCatalog.resolve(studentNumber: "2026-00000-TG-0", override: preferences.campusOverride, learnedCodes: preferences.learnedCampusCodes), .unknownCode("TG"))
    }
}
