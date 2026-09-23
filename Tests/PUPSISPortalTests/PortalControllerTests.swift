import XCTest
@testable import PUPSISPortal

/// Covers the two sign-out/host bugs directly on `PortalController`: never
/// hits the real Keychain (injects `hasCredentials`) or the user's real
/// settings (its own `UserDefaults` suite per test, same convention as
/// `PreferencesTests`). Never signs into the live SIS.
@MainActor
final class PortalControllerTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        suiteName = "PortalControllerTests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    // MARK: - isTrustedHost (the credential gate)

    func testTrustedHostAcceptsAnyPupSubdomainIncludingWww() {
        // Deliberately permissive — it only has to keep credentials off a
        // non-PUP host. `SISHost.isCandidateHost` is the stricter gate that
        // decides which PUP host is actually worth trying.
        XCTAssertTrue(PortalController.isTrustedHost("https://www.pup.edu.ph"))
        XCTAssertTrue(PortalController.isTrustedHost("https://sis8.pup.edu.ph"))
        XCTAssertTrue(PortalController.isTrustedHost("https://pup.edu.ph"))
    }

    func testTrustedHostRejectsALookalikeDomain() {
        XCTAssertFalse(PortalController.isTrustedHost("https://sis8.pup.edu.ph.evil.com"))
    }

    /// `isTrustedHost` only ever checks the *host*; every call site
    /// (`adoptActualHost`, `clearWebsiteData`) hardcodes an `https://`
    /// prefix itself before calling it, and `adoptActualHost` additionally
    /// gates on `url.scheme == "https"` before it ever reaches this check.
    /// So credentials never actually reach a non-https URL in practice —
    /// documented here so a future caller doesn't assume this function
    /// enforces the scheme on its own.
    func testTrustedHostOnlyChecksTheHostNotTheScheme() {
        XCTAssertTrue(PortalController.isTrustedHost("http://sis8.pup.edu.ph"))
    }

    // MARK: - no-op without credentials

    /// The bug: a menu-bar/scheduled `refresh()` firing after sign-out had
    /// no credentials check, so it would sign-in-less scrape the login page
    /// and overwrite `schedule.json` with garbage. `hasCredentials: { false }`
    /// stands in for a post-sign-out Keychain.
    func testRefreshIsANoOpWithoutCredentials() async {
        let portal = PortalController(defaults: defaults, hasCredentials: { false })
        let sessionsBefore = portal.sessions
        let lastUpdatedBefore = portal.lastUpdated
        let statusBefore = portal.status

        await portal.refresh()

        XCTAssertEqual(portal.sessions.count, sessionsBefore.count)
        XCTAssertEqual(portal.lastUpdated, lastUpdatedBefore)
        XCTAssertEqual(portal.status, statusBefore)
    }

    /// The sibling gap `refresh()`'s own guard wouldn't have caught: Settings'
    /// "Refresh Schedule" button calls `loadSchedule()` directly (and the
    /// Settings sheet stays open across sign-out), so the guard has to live
    /// in the loader itself, not just in `refresh()`.
    func testLoadScheduleIsANoOpWithoutCredentials() async {
        let portal = PortalController(defaults: defaults, hasCredentials: { false })
        let lastUpdatedBefore = portal.lastUpdated

        await portal.loadSchedule()

        XCTAssertEqual(portal.lastUpdated, lastUpdatedBefore)
        XCTAssertEqual(portal.status, .idle)
    }

    /// Same gap, GradesView's "Try again"/"Refresh"/"Load past terms" call
    /// `loadGrades()`/`loadGradeHistory()` directly.
    func testLoadGradesIsANoOpWithoutCredentials() async {
        let portal = PortalController(defaults: defaults, hasCredentials: { false })
        let gradesBefore = portal.grades

        await portal.loadGrades()

        XCTAssertEqual(portal.grades, gradesBefore)
        XCTAssertNil(portal.gradesError)
    }

    // MARK: - remembered host

    func testCurrentHostDefaultsToSis8WithNothingRemembered() {
        let portal = PortalController(defaults: defaults, hasCredentials: { false })
        XCTAssertEqual(portal.currentHost, "sis8.pup.edu.ph")
    }

    func testCurrentHostReadsWhateverIsRemembered() {
        defaults.set("https://sis1.pup.edu.ph/student", forKey: "sisBaseHost")
        let portal = PortalController(defaults: defaults, hasCredentials: { false })
        XCTAssertEqual(portal.currentHost, "sis1.pup.edu.ph")
    }

    /// Sign-out must clear the remembered host — trusting whatever the
    /// previous account happened to land on forever was part of the bug.
    func testForgetHostClearsTheRememberedHostAndResetsToDefault() {
        defaults.set("https://sis1.pup.edu.ph/student", forKey: "sisBaseHost")
        let portal = PortalController(defaults: defaults, hasCredentials: { false })
        XCTAssertEqual(portal.currentHost, "sis1.pup.edu.ph")

        portal.forgetHost()

        XCTAssertNil(defaults.string(forKey: "sisBaseHost"))
        XCTAssertEqual(portal.currentHost, "sis8.pup.edu.ph")
    }
}
