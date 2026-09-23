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
    /// (`adoptActualHost`, `isSISDataRecordName`) hardcodes an `https://`
    /// prefix itself before calling it, and `adoptActualHost` additionally
    /// gates on `url.scheme == "https"` before it ever reaches this check.
    /// So credentials never actually reach a non-https URL in practice —
    /// documented here so a future caller doesn't assume this function
    /// enforces the scheme on its own.
    func testTrustedHostOnlyChecksTheHostNotTheScheme() {
        XCTAssertTrue(PortalController.isTrustedHost("http://sis8.pup.edu.ph"))
    }

    // MARK: - isSISDataRecordName (the sign-out website-data filter)

    /// The load-bearing assumption: WebKit's `WKWebsiteDataRecord.displayName`
    /// for a `sisN.pup.edu.ph` cookie is the eTLD+1, `"pup.edu.ph"` — not the
    /// full host. This locks in the matching *rule*; the actual displayName
    /// value WebKit reports still needs one manual check against a live
    /// `WKWebView` signed into the SIS (not done here — never signs into the
    /// live SIS).
    func testAcceptsTheExpectedETLDPlusOneDisplayName() {
        XCTAssertTrue(PortalController.isSISDataRecordName("pup.edu.ph"))
    }

    /// WebKit can also report the fuller host as the display name on some
    /// versions/configurations — accept that shape too.
    func testAcceptsAFullSubdomainDisplayName() {
        XCTAssertTrue(PortalController.isSISDataRecordName("sis8.pup.edu.ph"))
    }

    func testRejectsALookalikeWithoutTheDotSeparator() {
        XCTAssertFalse(PortalController.isSISDataRecordName("evilpup.edu.ph"))
    }

    func testRejectsASuffixTrick() {
        XCTAssertFalse(PortalController.isSISDataRecordName("pup.edu.ph.evil.com"))
    }

    func testRejectsEmpty() {
        XCTAssertFalse(PortalController.isSISDataRecordName(""))
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

    // MARK: - sign-out / sign-in ordering (security review)

    /// The race the security review caught: a fast Edit Credentials → Save →
    /// sign-in right after Sign Out must never touch the web view while the
    /// old session's `WKWebsiteDataStore` clear is still running.
    /// `awaitPendingClear()` is the exact call `runSignIn` makes as its very
    /// first step — this drives it directly (with an injected clear standing
    /// in for the real, slow WebKit round trip) rather than through a real
    /// `signIn()`, which would touch the live SIS.
    func testAwaitPendingClearBlocksUntilTheInjectedClearFinishes() async {
        let portal = PortalController(
            defaults: defaults,
            hasCredentials: { true },
            clearWebsiteData: { try? await Task.sleep(nanoseconds: 100_000_000) } // 100ms
        )

        portal.beginClearingWebsiteData()
        let start = Date()
        await portal.awaitPendingClear()
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertGreaterThanOrEqual(
            elapsed, 0.08,
            "awaitPendingClear() returned before the pending clear (100ms) finished"
        )
    }

    /// The common case — no sign-out just happened — must not pay any wait.
    func testAwaitPendingClearIsImmediateWithNothingPending() async {
        let portal = PortalController(defaults: defaults, hasCredentials: { true })
        let start = Date()

        await portal.awaitPendingClear()

        XCTAssertLessThan(Date().timeIntervalSince(start), 0.05)
    }

    /// A second wait (e.g. a retry after the first sign-in already consumed
    /// the pending clear) must not hang re-awaiting an already-finished task.
    /// Two quick sign-outs: the second clear queues behind the first, and a
    /// waiter returns only when both have finished.
    func testBackToBackClearsBothFinishBeforeTheWaitReturns() async {
        let finished = Counter()
        let portal = PortalController(
            defaults: defaults,
            hasCredentials: { true },
            clearWebsiteData: {
                try? await Task.sleep(nanoseconds: 60_000_000)
                await finished.bump()
            }
        )

        portal.beginClearingWebsiteData()
        portal.beginClearingWebsiteData()
        await portal.awaitPendingClear()

        let count = await finished.value
        XCTAssertEqual(count, 2)
    }

    private actor Counter {
        private(set) var value = 0
        func bump() { value += 1 }
    }

    func testAwaitPendingClearIsIdempotent() async {
        let portal = PortalController(
            defaults: defaults,
            hasCredentials: { true },
            clearWebsiteData: { try? await Task.sleep(nanoseconds: 20_000_000) }
        )

        portal.beginClearingWebsiteData()
        await portal.awaitPendingClear()

        let start = Date()
        await portal.awaitPendingClear() // nothing pending anymore
        XCTAssertLessThan(Date().timeIntervalSince(start), 0.05)
    }

    /// `AppState.signOut()` is deliberately synchronous (not `async`) — every
    /// reset (credentials, Keychain, caches) runs to completion before it
    /// returns, with no `await` anywhere in it. That's what makes the
    /// original bug structurally impossible rather than just less likely: a
    /// fast Edit Credentials → Save → sign-in immediately after Sign Out
    /// cannot observe `signOut()` mid-execution, because Swift can't
    /// interleave two synchronous `@MainActor` calls. Only the website-data
    /// clear itself is async, and it runs as its own tracked task
    /// (`beginClearingWebsiteData()`) that `signOut()` never awaits — this
    /// test is a compile-time guard against that regressing.
    func testSignOutIsSynchronous() {
        // An unbound reference, so this never constructs a real `AppState`
        // (heavy: Sparkle, EventKit, on-disk stores). The type annotation is
        // the assertion — this fails to *compile* if `signOut()` ever goes
        // back to `async`.
        let _: (AppState) -> () -> Void = AppState.signOut
    }
}
