import Foundation
import WebKit

enum PortalError: LocalizedError, Equatable {
    case timedOut
    /// A second navigation wait arrived while one was still outstanding —
    /// the older one is failed instead of being silently orphaned. See
    /// `NavigationGate.wait`.
    case superseded

    var errorDescription: String? {
        switch self {
        case .timedOut:
            return "The SIS took too long to respond. Check your connection and try again."
        case .superseded:
            return "Another request took over the connection."
        }
    }
}

enum LoginStatus: Equatable {
    case idle
    case loggingIn
    case success
    case failed(String)
}

/// Serializes every piece of web-view work that has to wait for a navigation
/// to settle — a page load, or a script that triggers one. Only one waiter
/// can be outstanding: arming a second used to just overwrite the first,
/// orphaning it with nothing left to ever resume it — that's what hung
/// sign-in forever (status stuck `.loggingIn`) when a menu-bar/Grades-tab
/// refresh fired mid sign-in. Now the older waiter is failed first.
///
/// Also the one place that knows about sign-out: `cancelAll()` bumps
/// `generation`, so a flow that captured its generation before awaiting can
/// tell, once its wait resolves (even in failure), whether it's still
/// current — and skip writing `@Published` state or a disk cache if not.
///
/// Internal (not private) and its own type so it can be driven directly by
/// a fake navigation driver in tests, without a real `WKWebView`.
@MainActor
final class NavigationGate {
    private var continuation: CheckedContinuation<Void, Error>?
    private var token: UUID?
    private(set) var generation = 0

    func isCurrent(_ gen: Int) -> Bool { gen == generation }

    /// Arms the wait, then runs `action` (kicking off the navigation) —
    /// arming first so a fast, synchronous completion can't resume nothing.
    func wait(timeout: TimeInterval = 25, _ action: @escaping () -> Void) async throws {
        fail(PortalError.superseded)

        let current = UUID()
        token = current
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.continuation = continuation
            action()
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                guard self.token == current else { return }
                self.fail(PortalError.timedOut)
            }
        }
    }

    func resume() {
        guard let continuation else { return }
        self.continuation = nil
        token = nil
        continuation.resume()
    }

    func fail(_ error: Error) {
        guard let continuation else { return }
        self.continuation = nil
        token = nil
        continuation.resume(throwing: error)
    }

    /// Sign-out: invalidate every in-flight flow's generation, and fail
    /// whatever navigation wait is outstanding right now rather than
    /// leaving it to run for up to 25s in the background.
    func cancelAll() {
        generation += 1
        fail(CancellationError())
    }
}

/// Drives the headless SIS session: signs in, then scrapes the schedule.
/// The web view is never shown — it exists only to hold the authenticated
/// session and run the scraping JS.
@MainActor
final class PortalController: NSObject, ObservableObject, WKNavigationDelegate {
    @Published var status: LoginStatus = .idle
    @Published var sessions: [ClassSession] = []
    /// When the on-screen schedule was last scraped — `nil` means never.
    @Published var lastUpdated: Date?
    /// Set instead of `status` when a refresh fails but a cached schedule is
    /// already on screen. Shown as a footer note, not an error screen.
    @Published var refreshError: String?

    /// The scraped grades, or the cache. `nil` means never loaded.
    @Published var grades: GradeReport?
    /// A grades refresh that failed. Kept apart from `refreshError` so a grades
    /// problem never disturbs the schedule screen, and vice versa.
    @Published var gradesError: String?

    /// Past terms, backfilled from the grades page's SY/Semester dropdowns.
    /// Sorted oldest-first. Empty until `loadGradeHistory()` runs.
    @Published var gradeHistory: [GradeReport] = []
    /// True while the (potentially slow) term-by-term backfill is running, so
    /// the UI can show progress rather than looking hung.
    @Published var isLoadingHistory = false

    private let webView: WKWebView
    private let gate = NavigationGate()
    private let defaults: UserDefaults
    /// Whether the user is currently signed in — `refresh()` is a no-op
    /// without this, so a stale menu-bar/scheduled refresh firing after
    /// sign-out can't re-scrape and rewrite `schedule.json`. Injectable so
    /// tests never touch the real Keychain.
    private let hasCredentials: () -> Bool

    /// The stored credentials, for `reauthenticateAfterExpiredSession()` to
    /// re-sign-in with when a refresh lands back on the login page.
    /// Injectable so tests never touch the real Keychain — mirrors
    /// `hasCredentials` above.
    private let loadCredentials: () -> Credentials?

    /// Test seam for `loadSchedule()`'s reauth path: a stub navigation/page
    /// driver standing in for the real WKWebView-backed
    /// `fetchScheduleRows`/`reauthenticateAfterExpiredSession` — "the
    /// request landed on the login page, sign-in ran, then the schedule
    /// loaded" becomes injectable closures instead of a real `WKWebView`
    /// round trip, the same reasoning as `NavigationGate`'s fake driver and
    /// `injectedClearWebsiteData` below. Both `nil` in production.
    private let injectedFetchScheduleRows: (() async throws -> [ClassSession])?
    private let injectedReauthenticate: (() async -> Bool)?

    /// Same idea, for the grades side (W1d): standing in for the `/grades`
    /// navigation that `loadGrades()`/`loadGradeHistory()` both start with,
    /// and for one term's fetch inside the history backfill loop. Both `nil`
    /// in production.
    private let injectedLoadGradesPage: (() async throws -> Void)?
    private let injectedGradeTermOptions: (() async throws -> SISScraper.GradeTermOptions)?
    private let injectedFetchGradeTermReport: (((schoolYear: String, semester: String)) async throws -> GradeReport)?

    private static let genericFailure = "Sign-in didn't go through — check your student number, birthdate, and password."

    // PUP SIS load-balances across several numbered hosts (sis1, sis8, …) and
    // the post-login redirect chain can land a session on a different one
    // than we started on — requesting /schedule against the wrong host hits
    // an unauthenticated instance and scrapes nothing. Start from whichever
    // host we last actually landed on (persisted across launches), falling
    // back to sis8 the very first time. See `SISHost` for the failover order
    // and docs/specs/00-sis-host.md for the full behaviour.
    private static let defaultBase = "https://sis8.pup.edu.ph/student"
    private static let baseDefaultsKey = "sisBaseHost"

    /// The host actually in use for the current/next request. Distinct from
    /// `base` (the *persisted* remembered host): while a sign-in is trying
    /// candidates, this moves from host to host, and only the one that
    /// proves good (signs in AND has schedule rows) gets written back to
    /// `base`. Everything mid-trial stays in memory only.
    private var activeBase: String

    private static func persistedBase(defaults: UserDefaults) -> String {
        guard let stored = defaults.string(forKey: baseDefaultsKey), isTrustedHost(stored)
        else { return defaultBase }
        return stored
    }

    private var base: String {
        get { Self.persistedBase(defaults: defaults) }
        set { defaults.set(newValue, forKey: Self.baseDefaultsKey) }
    }

    /// The bare host of whatever's remembered right now (e.g. `sis8.pup.edu.ph`),
    /// for `SISHost.candidates(remembered:)` — `nil` the first time there's
    /// nothing stored yet.
    private var rememberedHost: String? {
        defaults.string(forKey: Self.baseDefaultsKey).flatMap { URL(string: $0)?.host }
    }

    /// The host in use, short form ("sis8"), for the sidebar's sync line.
    var hostLabel: String {
        URL(string: activeBase)?.host?.split(separator: ".").first.map(String.init) ?? "sis"
    }

    private var loginURL: URL { URL(string: "\(activeBase)/")! }
    private var scheduleURL: URL { URL(string: "\(activeBase)/schedule")! }
    private var gradesURL: URL { URL(string: "\(activeBase)/grades")! }

    /// The SIS host actually in use right now, for the Settings pane's
    /// Technical Details — a hardcoded display string goes stale the moment
    /// `adoptActualHost()` follows the SIS to a different numbered host.
    var currentHost: String { URL(string: activeBase)?.host ?? "unknown" }

    /// Reconciles `activeBase` with wherever the web view actually ended up —
    /// called right after sign-in settles. If the SIS bounced us to a
    /// different host, the rest of this trial (schedule/grades) follows it.
    /// Persisting to `base` happens separately, only once the data check
    /// (schedule has rows) passes — see `runSignIn`.
    ///
    /// Only ever adopts an actual `pup.edu.ph` host over https — the web view
    /// could in principle be sitting on anything (a captive portal, a
    /// malicious redirect), and credentials go to whatever host is active
    /// next, so this can't trust the navigated URL blindly.
    private func adoptActualHost() {
        guard let url = webView.url, let host = url.host, url.scheme == "https",
              Self.isTrustedHost("https://\(host)")
        else { return }
        let actual = "https://\(host)/student"
        if actual != activeBase { activeBase = actual }
    }

    /// The credential gate: only ever send credentials to an https
    /// `*.pup.edu.ph` host. Deliberately looser than `SISHost.isCandidateHost`
    /// (which also requires the `sisN` shape) — this just has to keep
    /// credentials off a non-PUP host; `SISHost` decides which PUP host is
    /// worth trying. Internal, not private, so tests can drive it directly.
    static func isTrustedHost(_ base: String) -> Bool {
        guard let host = URL(string: base)?.host?.lowercased() else { return false }
        return host == "pup.edu.ph" || host.hasSuffix(".pup.edu.ph")
    }

    init(
        defaults: UserDefaults = .standard,
        hasCredentials: @escaping () -> Bool = { KeychainStore.load() != nil },
        loadCredentials: @escaping () -> Credentials? = { KeychainStore.load() },
        clearWebsiteData: (() async -> Void)? = nil,
        fetchScheduleRows: (() async throws -> [ClassSession])? = nil,
        reauthenticate: (() async -> Bool)? = nil,
        loadGradesPage: (() async throws -> Void)? = nil,
        gradeTermOptions: (() async throws -> SISScraper.GradeTermOptions)? = nil,
        fetchGradeTermReport: (((schoolYear: String, semester: String)) async throws -> GradeReport)? = nil
    ) {
        self.defaults = defaults
        self.hasCredentials = hasCredentials
        self.loadCredentials = loadCredentials
        self.injectedClearWebsiteData = clearWebsiteData
        self.injectedFetchScheduleRows = fetchScheduleRows
        self.injectedReauthenticate = reauthenticate
        self.injectedLoadGradesPage = loadGradesPage
        self.injectedGradeTermOptions = gradeTermOptions
        self.injectedFetchGradeTermReport = fetchGradeTermReport
        webView = WKWebView()
        activeBase = Self.persistedBase(defaults: defaults)
        super.init()
        webView.navigationDelegate = self

        // Synchronous on purpose: it's one small JSON file, and reading it
        // here is what lets the first frame already have a calendar in it.
        if let cached = ScheduleStore.load() {
            sessions = cached.sessions
            lastUpdated = cached.lastUpdated
        }
        grades = GradesStore.load()
        gradeHistory = GradesStore.loadHistory()
    }

    func signIn(with credentials: Credentials) {
        guard !Demo.isOn else { status = .success; return }
        guard status != .loggingIn else { return }
        Task { await runSignIn(credentials) }
    }

    /// Tries each SIS mirror in `SISHost` order until one both signs in and
    /// actually carries this account's schedule (spec 00-sis-host.md) — a
    /// host that just signs in proves nothing (commit f763487: sis1 does,
    /// sis8 is the one with the data). A validation error (wrong
    /// credentials) stops the whole loop immediately rather than retrying
    /// the same bad password on a second server.
    private func runSignIn(_ credentials: Credentials) async {
        // A sign-out just before this could still be clearing the shared
        // WKWebView's cookies/local storage — wait for that to finish before
        // this sign-in ever touches the web view, or the old session's data
        // could leak into (or get raced by) the new one.
        await awaitPendingClear()

        let gen = gate.generation
        status = .loggingIn

        let candidates = SISHost.candidates(remembered: rememberedHost)
        var lastFailureMessage = Self.genericFailure
        var triedButEmpty = false

        for host in candidates {
            activeBase = "https://\(host)/student"
            let attempt: SISHost.Attempt
            var scraped: [ClassSession] = []

            do {
                try await load(loginURL)

                // Don't wait on navigation events here: signing in runs
                // through a redirect chain (POST to /student/ then on to
                // /student/home), so any single didFinish can land
                // mid-chain — and a validation error shows a modal with no
                // navigation at all. Poll the DOM until the outcome
                // actually settles instead.
                webView.evaluateJavaScript(fillAndSubmitScript(for: credentials), completionHandler: nil)

                let outcome = await awaitSignInOutcome()
                guard gate.isCurrent(gen) else { return }

                switch outcome {
                case .validationError(let message):
                    lastFailureMessage = message
                    attempt = .validationError
                case .timedOut:
                    lastFailureMessage = Self.genericFailure
                    attempt = .failed
                case .success:
                    adoptActualHost()
                    scraped = try await fetchScheduleRows(gen: gen)
                    guard gate.isCurrent(gen) else { return }
                    attempt = scraped.isEmpty ? .signedInEmpty : .signedInWithRows
                }
            } catch {
                lastFailureMessage = error.localizedDescription
                attempt = .failed
            }
            guard gate.isCurrent(gen) else { return }
            if case .signedInEmpty = attempt { triedButEmpty = true }

            // The decision itself is `SISHost.decide` — the same pure
            // function the tests exercise — so production behaviour can't
            // drift from what's tested.
            switch SISHost.decide(attempt, host: host) {
            case .stop:
                report(lastFailureMessage)
                return
            case .next:
                continue
            case .keep:
                base = activeBase // persist only a host that proved good
                status = .success
                commitSchedule(scraped)
                await loadGrades()
                return
            }
        }

        guard gate.isCurrent(gen) else { return }
        if triedButEmpty {
            // Every reachable host signed in but none had schedule rows —
            // a real empty term, not a failure. Keep the remembered host
            // and whatever schedule was already cached; the empty-state UI
            // ("No classes found") covers the rest.
            status = .success
            await loadGrades()
        } else {
            report("\(lastFailureMessage) (tried \(candidates.joined(separator: ", ")))")
        }
    }

    /// Schedule then grades, back-to-back, under one captured generation —
    /// `loadSchedule()`/`loadGrades()` each guard *their own* writes, but a
    /// sign-out landing in the gap between the two calls would otherwise let
    /// the second one start completely fresh, see itself as perfectly
    /// current, and legitimately write a grades cache the user just asked
    /// deleted. Shared by `runSignIn` and the public `refresh()` so neither
    /// caller has to remember the guard itself.
    private func loadScheduleThenGrades(_ gen: Int) async {
        await loadSchedule()
        guard gate.isCurrent(gen) else { return }
        await loadGrades()
    }

    /// "Refresh from anywhere" — the app menu, the menu bar, Settings. Single
    /// entry point so schedule+grades sequencing (and the sign-out guard
    /// between them) lives in one place rather than in every caller.
    func refresh() async {
        await loadScheduleThenGrades(gate.generation)
    }

    /// A no-op without credentials — guarded here, not just in `refresh()`,
    /// because several buttons call `loadSchedule`/`loadGrades`/
    /// `loadGradeHistory` directly: Settings' "Refresh Schedule",
    /// GradesView's "Try again"/"Refresh"/"Load past terms". Settings in
    /// particular stays open across sign-out (it's a sheet, not dismissed
    /// by it), so "Refresh Schedule" sits right there, still clickable, the
    /// moment "Sign Out" above it finishes. Without this each would
    /// sign-in-less scrape the login page and overwrite
    /// `schedule.json`/`grades.json` with garbage.
    func loadSchedule() async {
        guard !Demo.isOn else { return }
        guard hasCredentials() else { return }
        let gen = gate.generation
        do {
            let scraped: [ClassSession]
            if let injectedFetchScheduleRows {
                scraped = try await injectedFetchScheduleRows()
            } else {
                scraped = try await fetchScheduleRows(gen: gen)
            }
            guard gate.isCurrent(gen) else { return }

            // A scrape that parses to nothing while we already hold a schedule is
            // almost always a hiccup (page not settled, markup drift), not a real
            // empty term — never let it blank a good cache. Keep what we have and
            // surface it, the same way `report(_:)` protects a cached calendar.
            if scraped.isEmpty && !sessions.isEmpty {
                refreshError = "No classes found on the SIS schedule page — kept your last schedule."
                return
            }

            commitSchedule(scraped)
        } catch {
            guard gate.isCurrent(gen) else { return }
            if await reauthenticateAfterExpiredSession() { return }
            report("Couldn't refresh your schedule: \(error.localizedDescription)")
        }
    }

    /// A `/schedule` request that never reaches `/schedule` (the timeout
    /// above) can mean the SIS session expired mid-refresh and bounced back
    /// to the login page — the login form's *presence* here is a reliable
    /// positive signal on its own (unlike its *absence*, which
    /// `awaitSignInOutcome` no longer trusts alone). Re-runs sign-in through
    /// the exact same single-flight, host-failover path `signIn(with:)`
    /// uses — never retried after a validation error, since `SISHost.decide`
    /// stops the loop right there. A successful `runSignIn` already
    /// re-fetches and commits the schedule (and grades) as part of proving
    /// the host, so on success there's nothing left for the caller to load;
    /// `loadScheduleThenGrades`'s own `loadGrades()` right after this still
    /// runs too — a harmless redundant fetch on this rare path, not worth
    /// extra plumbing to skip.
    ///
    /// Returns whether a reauth was actually attempted, so the caller can
    /// tell "handled" from "still needs its own generic failure report".
    ///
    /// Internal (not private) — like `awaitPendingClear` — so the guard
    /// (`status != .loggingIn`) is directly testable without a real
    /// `WKWebView`: that branch returns before ever touching `probeLoginPage()`.
    func reauthenticateAfterExpiredSession() async -> Bool {
        if let injectedReauthenticate { return await injectedReauthenticate() }
        guard status != .loggingIn,
              let probe = try? await probeLoginPage(), probe.loginFormPresent,
              let credentials = loadCredentials()
        else { return false }
        await runSignIn(credentials)
        return true
    }

    /// Loads `/schedule` on whatever host is currently active and returns
    /// the parsed rows — no side effects on `sessions`/`status`/the on-disk
    /// cache. Shared by `loadSchedule()` (which commits the result) and the
    /// sign-in failover loop's data check (spec 00-sis-host.md step 4):
    /// trying a second host must never touch the screen or disk until it's
    /// the one being kept.
    private func fetchScheduleRows(gen: Int) async throws -> [ClassSession] {
        try await load(scheduleURL)
        let rows = try await awaitPageRows(suffix: "/schedule") {
            try await SISScraper.scrapeSchedule(from: $0)
        } isEmpty: { $0.isEmpty }
        return ScheduleParser.parse(rows)
    }

    /// Writes freshly scraped rows into `sessions` and the on-disk cache.
    private func commitSchedule(_ rows: [ClassSession]) {
        let now = Date()
        sessions = rows
        lastUpdated = now
        refreshError = nil
        ScheduleStore.save(rows, lastUpdated: now)
    }

    /// Same shape as `loadSchedule`, on its own error channel. A grades failure
    /// sets `gradesError` and leaves the schedule screen untouched — the two
    /// pages fail independently. No-op without credentials — see the comment
    /// on `loadSchedule`.
    func loadGrades() async {
        guard !Demo.isOn else { return }
        guard hasCredentials() else { return }
        let gen = gate.generation
        do {
            if let injectedLoadGradesPage {
                try await injectedLoadGradesPage()
            } else {
                try await load(gradesURL)
            }
            // The subject rows carry the page; an empty summary is fine, but an
            // empty row set is what "page not settled yet" looks like.
            let scraped = try await awaitPageRows(suffix: "/grades") {
                try await SISScraper.scrapeGrades(from: $0)
            } isEmpty: { $0.rows.isEmpty }

            let options = try? await SISScraper.gradeTermOptions(from: webView)
            let report = GradeReport(
                lastUpdated: Date(),
                subjects: GradesParser.parse(scraped.rows),
                summary: scraped.summary,
                schoolYear: options?.currentSchoolYear,
                semester: options?.currentSemester
            )
            guard gate.isCurrent(gen) else { return }
            // Same protection as the schedule: don't let an empty parse wipe grades
            // we already hold.
            if report.subjects.isEmpty, let existing = grades, !existing.subjects.isEmpty {
                gradesError = "No grades found on the SIS page — kept your last grades."
                return
            }

            grades = report
            gradesError = nil
            GradesStore.save(report)

            // Fold the current term into history too, so the trend has at least
            // one real point before any backfill and stays current after one.
            // Only when the term is actually identified: without a school
            // year/semester the label falls back to the update date, and a
            // monthly refresh would then land the same real term under a new
            // label each time, piling up duplicate trend points.
            if report.hasPostedGrades, report.schoolYear != nil {
                gradeHistory = GradesStore.merged(report, into: gradeHistory)
                GradesStore.saveHistory(gradeHistory)
            }
        } catch {
            guard gate.isCurrent(gen) else { return }
            // Same expired-session path `loadSchedule()` uses — GradesView's
            // "Try again"/"Refresh" call this directly, so the reauth has to
            // live here rather than at each button (W1d).
            if await reauthenticateAfterExpiredSession() { return }
            // Never through `report(_:)` — that governs the schedule screen.
            gradesError = "Couldn't refresh your grades: \(error.localizedDescription)"
        }
    }

    /// Backfills every term the account exposes, by driving the grades page's
    /// School Year / Semester dropdowns one combination at a time. On its own
    /// error channel, like `loadGrades` — a backfill problem never blanks the
    /// current-term screen. Degrades to whatever it managed to collect (at least
    /// the current term) rather than failing the whole run.
    ///
    /// Unverified against a live grades page — the user has no posted grades yet
    /// (see the term-select heuristics in `SISScraper`). Kept on-demand, not on
    /// every sign-in, so its cost is only paid when asked for.
    func loadGradeHistory() async {
        guard !isLoadingHistory, hasCredentials() else { return }
        let gen = gate.generation
        isLoadingHistory = true
        defer { isLoadingHistory = false }

        do {
            if let injectedLoadGradesPage {
                try await injectedLoadGradesPage()
            } else {
                try await load(gradesURL)
            }
            let options: SISScraper.GradeTermOptions
            if let injectedGradeTermOptions {
                options = try await injectedGradeTermOptions()
            } else {
                options = try await SISScraper.gradeTermOptions(from: webView)
            }
            let combos = options.combinations
            // No dropdowns found (or an unexpected page shape): keep whatever
            // history we already have rather than erroring.
            guard !combos.isEmpty else { return }

            var collected = gradeHistory
            for combo in combos {
                guard gate.isCurrent(gen) else { return }
                // Each term's whole fetch (submit + settle + scrape) is its
                // own do/catch — this used to only wrap the submit, so a term
                // whose page never settled (`awaitPageRows` timing out) threw
                // past the loop into the outer catch and discarded every term
                // already collected, not just the one that failed.
                do {
                    let report: GradeReport
                    if let injectedFetchGradeTermReport {
                        report = try await injectedFetchGradeTermReport(combo)
                    } else {
                        report = try await fetchGradeTermReport(combo)
                    }
                    // Empty or unposted terms don't belong on a GPA trend.
                    if report.hasPostedGrades {
                        collected = GradesStore.merged(report, into: collected)
                    }
                } catch {
                    // This term's submit didn't navigate, or its page never
                    // settled — skip it, keep what succeeded for the rest.
                    continue
                }
            }

            guard gate.isCurrent(gen) else { return }
            gradeHistory = collected
            gradesError = nil
            GradesStore.saveHistory(collected)
        } catch {
            guard gate.isCurrent(gen) else { return }
            // Same reauth as loadGrades()/loadSchedule() — "Load past terms"
            // calls this directly too (W1d).
            if await reauthenticateAfterExpiredSession() { return }
            gradesError = "Couldn't load your grade history: \(error.localizedDescription)"
        }
    }

    /// Selects one school-year/semester combo on the grades page and scrapes
    /// the result — the unit of work `loadGradeHistory` repeats once per
    /// term. Broken out (like `fetchScheduleRows`) so it's independently
    /// injectable in tests, and so the loop above can catch its failure
    /// per-term instead of per-run.
    private func fetchGradeTermReport(_ combo: (schoolYear: String, semester: String)) async throws -> GradeReport {
        // Arm the navigation wait *before* the submit fires it.
        let script = SISScraper.selectGradeTermScript(
            schoolYear: combo.schoolYear,
            semester: combo.semester
        )
        try await gate.wait { [weak self] in
            self?.webView.evaluateJavaScript(script, completionHandler: nil)
        }

        let scraped = try await awaitPageRows(suffix: "/grades") {
            try await SISScraper.scrapeGrades(from: $0)
        } isEmpty: { $0.rows.isEmpty }

        return GradeReport(
            lastUpdated: Date(),
            subjects: GradesParser.parse(scraped.rows),
            summary: scraped.summary,
            schoolYear: combo.schoolYear,
            semester: combo.semester
        )
    }

    /// A failed refresh must never replace a schedule we already have — the
    /// cached calendar is more useful than an error screen. With nothing
    /// cached there's nothing to protect, so the error takes the whole view.
    ///
    /// Falls back to `.idle` rather than staying `.loggingIn`, or the
    /// single-flight guard in `signIn` would make Retry a no-op.
    private func report(_ message: String) {
        if sessions.isEmpty {
            status = .failed(message)
        } else {
            refreshError = message
            status = .idle
        }
    }

    /// Same reason sign-in polls: one `didFinish` is not proof we've arrived.
    /// The redirect chain after sign-in can resume a navigation's wait early, so
    /// a single scrape lands on whatever page happened to be loaded — and even
    /// on the right page, DataTables may not have filled the body yet. Poll
    /// until the path matches *and* the scrape yields rows.
    ///
    /// The path check here is *not* the URL-based sign-in detection that
    /// CLAUDE.md warns about. That one asked "am I authenticated"; this one
    /// asks "which page is loaded", which is exactly what a path is for.
    ///
    /// Generic over the scrape so Schedule and Grades share one settling loop
    /// rather than each keeping its own copy of the race handling.
    ///
    /// `pageRowsPollOutcome` below is `awaitPageRows`'s per-poll decision,
    /// pulled out the same way `signInOutcome` is: a stateless function
    /// tested directly with fixture-shaped inputs, so the empty-settle
    /// window (`emptyPageSettleDelay`) can't drift from what's exercised
    /// here. `nil`/`.keepPolling` means "not resolved yet, poll again".
    enum PageRowsPoll: Equatable {
        case keepPolling
        case gotRows
        /// Reached the page and a stable empty scrape has held for
        /// `emptyPageSettleDelay` — a genuinely empty term, not a still-
        /// loading table. Stops `awaitPageRows` from burning the rest of its
        /// timeout on a real "no classes"/"no grades yet" page.
        case settledEmpty
    }

    static func pageRowsPollOutcome(
        scrapeSucceeded: Bool, isEmpty: Bool, emptySettledDuration: TimeInterval
    ) -> PageRowsPoll {
        guard scrapeSucceeded else { return .keepPolling }
        if !isEmpty { return .gotRows }
        return emptySettledDuration >= emptyPageSettleDelay ? .settledEmpty : .keepPolling
    }

    private func awaitPageRows<T>(
        suffix: String,
        timeout: TimeInterval = 12,
        scrape: @escaping (WKWebView) async throws -> T,
        isEmpty: (T) -> Bool
    ) async throws -> T {
        let deadline = Date().addingTimeInterval(timeout)
        var reachedPage = false
        var lastScrape: T?
        // When a stable empty scrape was first observed — reset the instant
        // it isn't (wrong page, scrape error, or rows show up), so a brief
        // empty blip while DataTables is still filling can't bank time
        // toward the early return.
        var emptySince: Date?

        while Date() < deadline {
            let onPage = await isOnPage(suffix: suffix)
            let scraped = onPage ? try? await scrape(webView) : nil
            if let scraped {
                reachedPage = true
                lastScrape = scraped
            }
            let empty = scraped.map(isEmpty) ?? false
            emptySince = (scraped != nil && empty) ? (emptySince ?? Date()) : nil
            let emptySettledDuration = emptySince.map { Date().timeIntervalSince($0) } ?? 0

            switch Self.pageRowsPollOutcome(
                scrapeSucceeded: scraped != nil, isEmpty: empty, emptySettledDuration: emptySettledDuration
            ) {
            case .keepPolling: break
            case .gotRows, .settledEmpty: return scraped!
            }
            try? await Task.sleep(nanoseconds: 300_000_000)
        }

        // Reaching the page and finding nothing is a real answer — an empty term
        // (or a semester with no grades yet) looks exactly like this. Return the
        // last empty scrape so its shape survives; never reaching the page is a
        // genuine failure.
        guard reachedPage, let lastScrape else { throw PortalError.timedOut }
        return lastScrape
    }

    private func isOnPage(suffix: String) async -> Bool {
        let path = try? await webView.evaluateJavaScript("document.location.pathname") as? String
        return (path ?? "")?.hasSuffix(suffix) ?? false
    }

    /// Result of polling for sign-in to settle. Kept as three distinct cases
    /// rather than a `(success, message)` tuple — a timeout used to also
    /// carry a non-empty `genericFailure` message, indistinguishable from a
    /// real validation modal, which would have made the host-failover loop
    /// stop on a network hiccup instead of trying the next mirror.
    ///
    /// Internal (not private) so `signInOutcome(...)` below — and this type —
    /// can be driven directly by tests, without a real `WKWebView`. Same
    /// reasoning as `NavigationGate` and `SISHost.decide`.
    enum SignInOutcome: Equatable {
        /// `viaFallback` is true when this fired from the settled-duration
        /// fallback below rather than a matched marker — `awaitSignInOutcome`
        /// logs a one-line note on that path so a live check can catch a
        /// stale/wrong selector before it's the only way sign-in succeeds.
        case success(viaFallback: Bool)
        /// The SIS itself rejected the credentials (modal shown). Never
        /// worth retrying on another host.
        case validationError(String)
        /// Neither the form disappeared nor a modal appeared before the
        /// timeout — a stuck/unreachable host, worth trying the next one.
        case timedOut
    }

    /// How long the page has to sit settled (readyState complete, login form
    /// gone) with *no* positive marker before it counts as signed in anyway.
    /// The fallback for an unmatched/stale marker selector: without it, a
    /// selector that doesn't match the live SIS's actual markup would make
    /// every sign-in run the full 25s timeout and fail outright, a regression
    /// of the whole flow over one unverified CSS selector. Long enough to
    /// reject the mid-parse false positive the marker requirement targets (a
    /// page settles itself well under a second); short enough not to read as
    /// a hang.
    static let markerFallbackDelay: TimeInterval = 3

    /// How long `awaitPageRows` waits with a *stable* empty scrape, on the
    /// right page, before treating it as a genuinely empty term rather than
    /// polling out the whole `timeout`. Same settled-state reasoning as
    /// `markerFallbackDelay` above: any single empty poll can't tell "empty
    /// term" apart from "DataTables hasn't filled the body yet", but a result
    /// that holds steady for a beat can.
    static let emptyPageSettleDelay: TimeInterval = 1.5

    /// Interprets the DOM probe's raw signals into a settled outcome —
    /// pulled out as its own pure function, same reasoning as
    /// `SISHost.decide`: tested directly with fixture-shaped signals here,
    /// so production behaviour can't drift from what the tests exercise.
    /// `settledDuration` is how long the *caller* has observed the page
    /// sitting settled across consecutive polls — this function itself is
    /// stateless, so that accumulation lives in `awaitSignInOutcome` below.
    ///
    /// `nil` means "not settled yet, keep polling" — `readyState` isn't
    /// `"complete"`, or the login form is still there. That's deliberately
    /// not "success": a page mid-parse can momentarily lack `#studno` before
    /// its markup has fully landed, which used to be read as "signed in" and
    /// is exactly the bug this replaces — success now needs either a
    /// positive marker, or the settled state to have actually held for a
    /// beat, not just a one-off poll.
    static func signInOutcome(
        readyState: String,
        loginFormPresent: Bool,
        signedInMarkerPresent: Bool,
        settledDuration: TimeInterval,
        validationMessage: String
    ) -> SignInOutcome? {
        let settled = readyState == "complete" && !loginFormPresent
        if settled, signedInMarkerPresent { return .success(viaFallback: false) }
        if settled, settledDuration >= markerFallbackDelay { return .success(viaFallback: true) }
        if loginFormPresent, !validationMessage.isEmpty { return .validationError(validationMessage) }
        return nil
    }

    /// Polls until sign-in resolves one way or the other: a positive
    /// signed-in marker (not just the login form's absence — that's also
    /// true mid-parse or on a stray error page) means we're in immediately;
    /// failing that, the settled state holding for `markerFallbackDelay`
    /// straight also means we're in (the marker-selector fallback). A
    /// validation modal means we're not. Polling (rather than watching
    /// navigations) is what makes this survive the redirect chain and the
    /// no-navigation error case.
    private func awaitSignInOutcome(timeout: TimeInterval = 25) async -> SignInOutcome {
        let deadline = Date().addingTimeInterval(timeout)
        // When the settled state (readyState complete, login form gone) was
        // first observed, across consecutive polls — reset the moment it
        // isn't, so a brief settle-then-unsettle blip can't bank time toward
        // the fallback.
        var settledSince: Date?
        while Date() < deadline {
            // Probing mid-navigation can throw; that just means "not settled".
            if let probe = try? await probeLoginPage() {
                let settledNow = probe.readyState == "complete" && !probe.loginFormPresent
                settledSince = settledNow ? (settledSince ?? Date()) : nil
                let settledDuration = settledSince.map { Date().timeIntervalSince($0) } ?? 0

                if let outcome = Self.signInOutcome(
                    readyState: probe.readyState,
                    loginFormPresent: probe.loginFormPresent,
                    signedInMarkerPresent: probe.signedInMarkerPresent,
                    settledDuration: settledDuration,
                    validationMessage: probe.message
                ) {
                    if case .success(true) = outcome {
                        // Non-PII: names no page content, credentials, or
                        // scraped data — just that the marker never matched.
                        print("PortalController: signed in without a logout marker after \(Int(Self.markerFallbackDelay))s settled — selector may need updating")
                    }
                    return outcome
                }
            } else {
                settledSince = nil
            }
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
        return .timedOut
    }

    /// Reads the DOM's raw signals — never decides anything itself
    /// (`signInOutcome(...)` above does, on the Swift side, so it's
    /// testable). Not a URL match: the form POSTs to /student/ and the
    /// logged-in page can render at that same URL.
    ///
    /// ponytail: the logout-link selector below is a best-guess heuristic —
    /// no captured signed-in-page fixture exists in this repo to confirm the
    /// SIS's actual markup. `markerFallbackDelay` above keeps a wrong/stale
    /// selector from being a hard sign-in failure (a few seconds' delay
    /// instead), but it should still get one live check; widen the selector
    /// if the fallback-path log line ever fires.
    private func probeLoginPage() async throws -> (
        readyState: String, loginFormPresent: Bool, signedInMarkerPresent: Bool, message: String
    ) {
        let script = """
        (function () {
            var modal = document.querySelector('.modal.show .modal-body, .modal[style*="block"] .modal-body');
            return {
                readyState: document.readyState,
                loginFormPresent: !!document.getElementById('studno'),
                signedInMarkerPresent: !!document.querySelector(
                    'a[href*="logout" i], a[href*="signout" i], #logout, .logout'
                ),
                message: modal ? modal.textContent.trim() : ''
            };
        })();
        """
        let result = try await webView.evaluateJavaScript(script) as? [String: Any]
        return (
            result?["readyState"] as? String ?? "loading",
            result?["loginFormPresent"] as? Bool ?? true,
            result?["signedInMarkerPresent"] as? Bool ?? false,
            result?["message"] as? String ?? ""
        )
    }

    /// Every navigation of the shared web view routes through here, so every
    /// caller (sign-in, refresh, the Settings and Grades buttons) waits for a
    /// sign-out's website-data clear before touching the SIS.
    private func load(_ url: URL) async throws {
        await awaitPendingClear()
        try await gate.wait { [weak self] in
            self?.webView.load(URLRequest(url: url))
        }
    }

    private func fillAndSubmitScript(for credentials: Credentials) -> String {
        func js(_ value: String) -> String {
            let data = try? JSONSerialization.data(withJSONObject: [value])
            let encoded = data.flatMap { String(data: $0, encoding: .utf8) } ?? "[\"\"]"
            return String(encoded.dropFirst().dropLast())
        }

        return """
        (function () {
            function setField(id, value) {
                var el = document.getElementById(id);
                if (!el) return;
                el.value = value;
                el.dispatchEvent(new Event('change', { bubbles: true }));
            }
            setField('studno', \(js(credentials.studentNumber)));
            setField('SelectMonth', \(js(String(credentials.birthMonth))));
            setField('SelectDay', \(js(String(credentials.birthDay))));
            setField('SelectYear', \(js(String(credentials.birthYear))));
            setField('password', \(js(credentials.password)));
            var submit = document.querySelector('input[type=submit]');
            if (submit) submit.click();
        })();
        """
    }

    /// Call on sign-out: any sign-in or refresh already running must not
    /// touch `@Published` state or write a cache after the caches were just
    /// deleted. See `NavigationGate.cancelAll()`.
    func cancelInFlight() {
        gate.cancelAll()
    }

    /// Sign-out's `WKWebsiteDataStore` clear, tracked so `runSignIn` can wait
    /// on it before ever touching the shared `WKWebView`. `AppState.signOut()`
    /// runs its synchronous reset (credentials, Keychain, on-disk caches)
    /// *before* calling `beginClearingWebsiteData()` and never awaits this —
    /// a fast Edit Credentials → Save → sign-in right after Sign Out must not
    /// have its brand-new credentials undone by a sign-out call that's still
    /// suspended, and must not let its own sign-in touch the web view while
    /// the old session's cookies are still being stripped from under it. This
    /// is the one place that guarantees the ordering instead.
    private var pendingClear: Task<Void, Never>?

    /// Test seam for `beginClearingWebsiteData()`: when set, replaces the
    /// real `WKWebsiteDataStore` round trip. Lets a test make the clear
    /// suspend for a controlled duration and then confirm `awaitPendingClear()`
    /// — the exact call `runSignIn` makes — actually waits for it, without
    /// ever driving a real sign-in against the live SIS to observe it. `nil`
    /// in production, where the real store-based clear runs instead.
    private let injectedClearWebsiteData: (() async -> Void)?

    /// Call on sign-out: starts clearing whatever cookies/local storage the
    /// SIS session left in the shared `WKWebsiteDataStore`, without blocking
    /// the caller. Without this clear ever happening, `#studno` is still
    /// missing on the next sign-in attempt — the DOM polling this app uses
    /// to detect "signed in" (see CLAUDE.md) reads that as
    /// already-authenticated, so typing in a *different* account's
    /// credentials silently re-scrapes the previous account instead of
    /// signing in fresh.
    func beginClearingWebsiteData() {
        // Queued behind any clear still running, so a second sign-out can't
        // drop the only handle on the first one.
        let previous = pendingClear
        pendingClear = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            if let injectedClearWebsiteData = self.injectedClearWebsiteData {
                await injectedClearWebsiteData()
            } else {
                await self.clearSISWebsiteData()
            }
        }
    }

    /// Waits for any pending sign-out website-data clear, then clears the
    /// slot. `runSignIn` calls this as its very first step so no sign-in can
    /// touch the web view before the old session's cookies/local storage
    /// finish clearing. Internal, not private, so this exact ordering
    /// guarantee is unit-testable (via `clearWebsiteData` injection) without
    /// driving a real sign-in against the live SIS.
    func awaitPendingClear() async {
        guard let task = pendingClear else { return }
        await task.value
        // A newer clear may have been queued while this one ran; keep it.
        if pendingClear == task { pendingClear = nil }
    }

    /// Filtered to `pup.edu.ph` hosts so the notes editor's own `WKWebView`
    /// (`WebNoteEditor.swift`, same default/shared data store) is untouched.
    private func clearSISWebsiteData() async {
        let store = webView.configuration.websiteDataStore
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        let records = await withCheckedContinuation { (continuation: CheckedContinuation<[WKWebsiteDataRecord], Never>) in
            store.fetchDataRecords(ofTypes: types) { continuation.resume(returning: $0) }
        }
        let sisRecords = records.filter { Self.isSISDataRecordName($0.displayName) }
        guard !sisRecords.isEmpty else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            store.removeData(ofTypes: types, for: sisRecords) { continuation.resume() }
        }
    }

    /// Whether a `WKWebsiteDataRecord.displayName` belongs to the SIS —
    /// pulled out as its own pure function because the filter's correctness
    /// hinges on knowing what shape WebKit's `displayName` actually takes for
    /// a `sisN.pup.edu.ph` cookie (the eTLD+1, e.g. `"pup.edu.ph"`, not the
    /// full host) — get that assumption wrong and sign-out silently clears
    /// nothing. That specific value is unverified against a live `WKWebView`;
    /// this only locks in the matching rule once the shape is known.
    static func isSISDataRecordName(_ displayName: String) -> Bool {
        isTrustedHost("https://\(displayName)")
    }

    /// Call on sign-out: forgets which host we last landed on. Persisting a
    /// host forever (the old `adoptActualHost` behaviour) meant a stale or
    /// wrong host could get baked in permanently — a fresh sign-in should
    /// always re-run the full candidate order (`SISHost.candidates`), not
    /// retry whatever the previous account happened to land on.
    func forgetHost() {
        defaults.removeObject(forKey: Self.baseDefaultsKey)
        activeBase = Self.defaultBase
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in gate.resume() }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        fail(with: error)
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        fail(with: error)
    }

    /// `NSURLErrorCancelled` means another navigation superseded this one, not
    /// that anything went wrong — the sign-in redirect chain is still settling
    /// when we ask for `/student/schedule`, so the older load gets cancelled
    /// and reports here. Surfacing it turned a working sign-in into
    /// "error -999". The superseding navigation reports for itself, and the
    /// timeout in `NavigationGate.wait` covers the case where nothing does.
    private nonisolated func fail(with error: Error) {
        guard (error as NSError).code != NSURLErrorCancelled else { return }
        Task { @MainActor in gate.fail(error) }
    }
}
