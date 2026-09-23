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

    // MARK: - signInOutcome (the DOM probe's decision, W1c)

    /// The bug being fixed: "no `#studno`" alone used to mean "signed in",
    /// which is also true for a page still mid-parse. A settled document
    /// (`readyState == "complete"`) plus a *positive* signed-in marker is
    /// the fast path now; an unverified/stale marker selector degrades to a
    /// `markerFallbackDelay`-second settled-stability wait rather than a
    /// hard failure (head review on c668aa7: a non-matching selector must
    /// not turn every sign-in into a 25s timeout). These are captured-shape
    /// (redacted) signal combinations a real probe would report, exercised
    /// as fixtures the same way `SISHost.decide` is: no real `WKWebView`,
    /// and production can't drift from what's tested here.

    func testMarkerPresentIsImmediateSuccessRegardlessOfSettledDuration() {
        let outcome = PortalController.signInOutcome(
            readyState: "complete", loginFormPresent: false,
            signedInMarkerPresent: true, settledDuration: 0, validationMessage: ""
        )
        XCTAssertEqual(outcome, .success(viaFallback: false))
    }

    /// No marker, but the settled state has held for the full fallback
    /// window — a stale/wrong selector must not block sign-in forever.
    func testNoMarkerButSettledForTheFallbackWindowIsSuccess() {
        let outcome = PortalController.signInOutcome(
            readyState: "complete", loginFormPresent: false, signedInMarkerPresent: false,
            settledDuration: PortalController.markerFallbackDelay, validationMessage: ""
        )
        XCTAssertEqual(outcome, .success(viaFallback: true))
    }

    /// No marker, settled for only a beat — short of the fallback window, so
    /// still not a confirmed success. This is what keeps the fallback from
    /// swallowing the mid-parse false positive the marker requirement
    /// targeted in the first place.
    func testNoMarkerSettledOnlyBrieflyIsNotYetSuccess() {
        let outcome = PortalController.signInOutcome(
            readyState: "complete", loginFormPresent: false, signedInMarkerPresent: false,
            settledDuration: 1, validationMessage: ""
        )
        XCTAssertNil(outcome, "under the fallback window, an unmatched marker must not yet count as signed in")
    }

    /// The exact original regression: login form already gone, but the page
    /// hasn't finished settling and no positive marker has shown up yet —
    /// used to read as success, must now keep polling (and the fallback
    /// clock hasn't even started, since `settled` itself is false here).
    func testLoginFormGoneButNotYetSettledIsNotSuccess() {
        let outcome = PortalController.signInOutcome(
            readyState: "loading", loginFormPresent: false,
            signedInMarkerPresent: false, settledDuration: 0, validationMessage: ""
        )
        XCTAssertNil(outcome, "a mid-parse page must not be read as signed in")
    }

    func testValidationModalOnTheLoginFormIsAValidationError() {
        let outcome = PortalController.signInOutcome(
            readyState: "complete", loginFormPresent: true, signedInMarkerPresent: false,
            settledDuration: 0, validationMessage: "Invalid student number or password."
        )
        XCTAssertEqual(outcome, .validationError("Invalid student number or password."))
    }

    /// The login form is still up and rendering, but no modal has appeared
    /// yet — inconclusive, not a rejection.
    func testLoginFormPresentWithNoModalYetIsNotSettled() {
        let outcome = PortalController.signInOutcome(
            readyState: "complete", loginFormPresent: true, signedInMarkerPresent: false,
            settledDuration: 0, validationMessage: ""
        )
        XCTAssertNil(outcome)
    }

    // MARK: - reauthenticateAfterExpiredSession (W1c: refresh re-auth)

    /// The core scenario from the brief, as a stub navigation/page driver:
    /// `fetchScheduleRows` throws (standing in for `/schedule` bouncing back
    /// to the login page and timing out), so `loadSchedule()` must run
    /// reauth — and once "sign-in" reports success, the schedule it commits
    /// (standing in for `runSignIn`'s own real commit) must be what's on
    /// screen after. Never touches a real `WKWebView` or the live SIS.
    func testLoadScheduleReauthenticatesAfterLandingOnLoginPageThenLoads() async {
        let freshSession = ClassSession(
            subjectCode: "COMP 20073", description: "Data Structures",
            faculty: "SANTOS, JUAN", day: .tuesday, start: 14 * 60, end: 16 * 60
        )
        var reauthRan = false
        let portal = PortalController(
            defaults: defaults,
            hasCredentials: { true },
            fetchScheduleRows: { throw PortalError.timedOut }, // "landed on the login page"
            reauthenticate: {
                reauthRan = true
                return true // "sign-in ran" — nothing left for loadSchedule to do
            }
        )
        // Simulates what a successful `runSignIn` would already have
        // committed by the time it returns.
        portal.sessions = [freshSession]
        portal.status = .success

        await portal.loadSchedule()

        XCTAssertTrue(reauthRan, "a schedule fetch that fails must trigger reauth")
        XCTAssertEqual(portal.sessions, [freshSession], "the schedule reauth loaded must survive")
        XCTAssertNil(portal.refreshError, "a successful reauth must not also report a generic failure")
    }

    /// When reauth doesn't apply (not actually a login-page landing, or no
    /// stored credentials), `loadSchedule()` must fall back to its ordinary
    /// failure reporting rather than silently swallowing the error.
    func testLoadScheduleReportsFailureWhenReauthDoesNotApply() async {
        let portal = PortalController(
            defaults: defaults,
            hasCredentials: { true },
            fetchScheduleRows: { throw PortalError.timedOut },
            reauthenticate: { false }
        )
        // `report(_:)` only becomes `.failed` with nothing cached — forced
        // empty here so this doesn't depend on whatever `ScheduleStore`'s
        // real on-disk cache happens to hold on the machine running the test.
        portal.sessions = []

        await portal.loadSchedule()

        guard case .failed = portal.status else {
            return XCTFail("expected .failed with nothing cached, got \(portal.status)")
        }
    }

    /// Single-flight: a reauth already in progress (`status == .loggingIn`)
    /// must not kick off a second one. This exercises the *real*
    /// (non-stubbed) `reauthenticateAfterExpiredSession()` — safe to call
    /// directly because the guard returns before ever touching the
    /// `WKWebView`-backed probe.
    func testReauthenticateSkipsWhileASignInIsAlreadyInFlight() async {
        let portal = PortalController(defaults: defaults, hasCredentials: { true })
        portal.status = .loggingIn

        let attempted = await portal.reauthenticateAfterExpiredSession()

        XCTAssertFalse(attempted, "must not start a second sign-in while one is already running")
    }

    // MARK: - loadGrades / loadGradeHistory reauth (W1d)

    /// The gap W1c's own reauth fix left open: GradesView's "Try again"/
    /// "Refresh" call `loadGrades()` directly, so it needs the same expired-
    /// session recovery `loadSchedule()` already has.
    func testLoadGradesReauthenticatesAfterLandingOnLoginPage() async {
        var reauthRan = false
        let portal = PortalController(
            defaults: defaults,
            hasCredentials: { true },
            reauthenticate: {
                reauthRan = true
                return true
            },
            loadGradesPage: { throw PortalError.timedOut } // "landed on the login page"
        )

        await portal.loadGrades()

        XCTAssertTrue(reauthRan, "a grades fetch that fails must trigger reauth")
        XCTAssertNil(portal.gradesError, "a successful reauth must not also report a generic failure")
    }

    func testLoadGradesReportsFailureWhenReauthDoesNotApply() async {
        let portal = PortalController(
            defaults: defaults,
            hasCredentials: { true },
            reauthenticate: { false },
            loadGradesPage: { throw PortalError.timedOut }
        )

        await portal.loadGrades()

        XCTAssertNotNil(portal.gradesError, "a grades failure that isn't a reauth case must still be reported")
    }

    /// Same gap for "Load past terms", which calls `loadGradeHistory()` directly.
    func testLoadGradeHistoryReauthenticatesAfterLandingOnLoginPage() async {
        var reauthRan = false
        let portal = PortalController(
            defaults: defaults,
            hasCredentials: { true },
            reauthenticate: {
                reauthRan = true
                return true
            },
            loadGradesPage: { throw PortalError.timedOut }
        )

        await portal.loadGradeHistory()

        XCTAssertTrue(reauthRan, "a history fetch that fails must trigger reauth")
        XCTAssertNil(portal.gradesError)
    }

    // MARK: - grade-history backfill resilience (W1d)

    /// The bug: one term's fetch throwing used to escape the per-term submit's
    /// own `do`/`catch` into the *outer* one, aborting the whole backfill and
    /// discarding every term already collected — not just the one that failed.
    func testLoadGradeHistoryKeepsSuccessfulTermsWhenOneTermFails() async {
        let goodTerm = SubjectGrade(
            subjectCode: "COMP 20073", description: "Data Structures", faculty: "SANTOS, JUAN",
            units: 3, sectionCode: "1", finalGrade: "1.00", gradeStatus: ""
        )
        let portal = PortalController(
            defaults: defaults,
            hasCredentials: { true },
            loadGradesPage: {},
            gradeTermOptions: {
                SISScraper.GradeTermOptions(
                    schoolYears: ["2023-2024", "2024-2025"],
                    semesters: ["1st Semester"],
                    currentSchoolYear: "2024-2025",
                    currentSemester: "1st Semester"
                )
            },
            fetchGradeTermReport: { combo in
                if combo.schoolYear == "2023-2024" { throw PortalError.timedOut }
                return GradeReport(
                    lastUpdated: Date(timeIntervalSince1970: 1_754_400_000),
                    subjects: [goodTerm],
                    summary: [:],
                    schoolYear: combo.schoolYear,
                    semester: combo.semester
                )
            }
        )

        await portal.loadGradeHistory()

        XCTAssertEqual(
            portal.gradeHistory.map(\.schoolYear), ["2024-2025"],
            "the failed term must be skipped, not lose the whole backfill"
        )
        XCTAssertNil(portal.gradesError, "a partial backfill is still a success, not an error")
    }

    // MARK: - pageRowsPollOutcome (W1d: empty terms shouldn't poll the full timeout)

    /// A scrape that hasn't succeeded yet (wrong page, or a transient scrape
    /// error) is always "keep polling" regardless of any prior empty streak.
    func testScrapeFailureKeepsPolling() {
        let outcome = PortalController.pageRowsPollOutcome(
            scrapeSucceeded: false, isEmpty: false, emptySettledDuration: 999
        )
        XCTAssertEqual(outcome, .keepPolling)
    }

    func testNonEmptyScrapeIsImmediateSuccess() {
        let outcome = PortalController.pageRowsPollOutcome(
            scrapeSucceeded: true, isEmpty: false, emptySettledDuration: 0
        )
        XCTAssertEqual(outcome, .gotRows)
    }

    /// A single empty poll can't tell "genuinely empty term" apart from "the
    /// table hasn't filled in yet" — must not stop early on just one.
    func testEmptyScrapeBelowTheSettleWindowKeepsPolling() {
        let outcome = PortalController.pageRowsPollOutcome(
            scrapeSucceeded: true, isEmpty: true, emptySettledDuration: 0.5
        )
        XCTAssertEqual(outcome, .keepPolling)
    }

    /// The fix: once empty has held steady for the settle window, stop
    /// polling out the rest of the 12s timeout.
    func testEmptyScrapeHeldForTheSettleWindowStopsPolling() {
        let outcome = PortalController.pageRowsPollOutcome(
            scrapeSucceeded: true, isEmpty: true, emptySettledDuration: PortalController.emptyPageSettleDelay
        )
        XCTAssertEqual(outcome, .settledEmpty)
    }

    // MARK: - AppState.didSave (W1d: surface Keychain save failures)

    private let fakeCredentials = Credentials(
        studentNumber: "2000-00000-MN-0", birthMonth: 1, birthDay: 1, birthYear: 2000, password: "x"
    )

    /// The bug: `AppState.save` used `try? KeychainStore.save`, so a write
    /// failure was silently swallowed and the app proceeded as signed in with
    /// nothing actually persisted. `didSave` is the pulled-out decision,
    /// testable without a real (heavy) `AppState`.
    func testDidSaveReturnsFalseWhenTheKeychainWriteThrows() {
        let saved = AppState.didSave(fakeCredentials) { _ in throw KeychainError(status: -1) }
        XCTAssertFalse(saved)
    }

    func testDidSaveReturnsTrueWhenTheKeychainWriteSucceeds() {
        let saved = AppState.didSave(fakeCredentials) { _ in }
        XCTAssertTrue(saved)
    }
}
