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

    private static let genericFailure = "Sign-in didn't go through — check your student number, birthdate, and password."

    // PUP SIS load-balances across several numbered hosts (sis1, sis8, …) and
    // the post-login redirect chain can land a session on a different one
    // than we started on — requesting /schedule against the wrong host hits
    // an unauthenticated instance and scrapes nothing. Start from whichever
    // host we last actually landed on (persisted across launches), falling
    // back to sis8 the very first time.
    private static let defaultBase = "https://sis8.pup.edu.ph/student"
    private static let baseDefaultsKey = "sisBaseHost"

    private var base: String {
        get {
            guard let stored = UserDefaults.standard.string(forKey: Self.baseDefaultsKey),
                  Self.isTrustedHost(stored)
            else { return Self.defaultBase }
            return stored
        }
        set { UserDefaults.standard.set(newValue, forKey: Self.baseDefaultsKey) }
    }

    private var loginURL: URL { URL(string: "\(base)/")! }
    private var scheduleURL: URL { URL(string: "\(base)/schedule")! }
    private var gradesURL: URL { URL(string: "\(base)/grades")! }

    /// The SIS host actually in use right now, for the Settings pane's
    /// Technical Details — a hardcoded display string goes stale the moment
    /// `adoptActualHost()` follows the SIS to a different numbered host.
    var currentHost: String { URL(string: base)?.host ?? "unknown" }

    /// Reconciles `base` with wherever the web view actually ended up —
    /// called right after sign-in settles. If the SIS bounced us to a
    /// different host, every later refresh in this run (and future launches)
    /// follows it instead of retrying the stale one.
    ///
    /// Only ever adopts an actual `pup.edu.ph` host over https — the web view
    /// could in principle be sitting on anything (a captive portal, a
    /// malicious redirect), and credentials go to whatever `base` resolves
    /// to next, so this can't trust the navigated URL blindly.
    private func adoptActualHost() {
        guard let url = webView.url, let host = url.host, url.scheme == "https",
              Self.isTrustedHost("https://\(host)")
        else { return }
        let actual = "https://\(host)/student"
        if actual != base { base = actual }
    }

    private static func isTrustedHost(_ base: String) -> Bool {
        guard let host = URL(string: base)?.host?.lowercased() else { return false }
        return host == "pup.edu.ph" || host.hasSuffix(".pup.edu.ph")
    }

    override init() {
        webView = WKWebView()
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
        guard status != .loggingIn else { return }
        Task { await runSignIn(credentials) }
    }

    private func runSignIn(_ credentials: Credentials) async {
        let gen = gate.generation
        status = .loggingIn
        do {
            try await load(loginURL)

            // Don't wait on navigation events here: signing in runs through a
            // redirect chain (POST to /student/ then on to /student/home), so
            // any single didFinish can land mid-chain — and a validation error
            // shows a modal with no navigation at all. Poll the DOM until the
            // outcome actually settles instead.
            webView.evaluateJavaScript(fillAndSubmitScript(for: credentials), completionHandler: nil)

            let outcome = await awaitSignInOutcome()
            guard gate.isCurrent(gen) else { return }
            guard outcome.success else {
                report(outcome.message)
                return
            }

            adoptActualHost()
            status = .success
            await loadScheduleThenGrades(gen)
        } catch {
            guard gate.isCurrent(gen) else { return }
            report(error.localizedDescription)
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

    func loadSchedule() async {
        let gen = gate.generation
        do {
            try await load(scheduleURL)
            let rows = try await awaitPageRows(suffix: "/schedule") {
                try await SISScraper.scrapeSchedule(from: $0)
            } isEmpty: { $0.isEmpty }
            let scraped = rows.flatMap(ScheduleParser.parse)
            let now = Date()
            guard gate.isCurrent(gen) else { return }

            // A scrape that parses to nothing while we already hold a schedule is
            // almost always a hiccup (page not settled, markup drift), not a real
            // empty term — never let it blank a good cache. Keep what we have and
            // surface it, the same way `report(_:)` protects a cached calendar.
            if scraped.isEmpty && !sessions.isEmpty {
                refreshError = "No classes found on the SIS schedule page — kept your last schedule."
                return
            }

            sessions = scraped
            lastUpdated = now
            refreshError = nil
            ScheduleStore.save(scraped, lastUpdated: now)
        } catch {
            guard gate.isCurrent(gen) else { return }
            report("Couldn't refresh your schedule: \(error.localizedDescription)")
        }
    }

    /// Same shape as `loadSchedule`, on its own error channel. A grades failure
    /// sets `gradesError` and leaves the schedule screen untouched — the two
    /// pages fail independently.
    func loadGrades() async {
        let gen = gate.generation
        do {
            try await load(gradesURL)
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
        guard !isLoadingHistory else { return }
        let gen = gate.generation
        isLoadingHistory = true
        defer { isLoadingHistory = false }

        do {
            try await load(gradesURL)
            let options = try await SISScraper.gradeTermOptions(from: webView)
            let combos = options.combinations
            // No dropdowns found (or an unexpected page shape): keep whatever
            // history we already have rather than erroring.
            guard !combos.isEmpty else { return }

            var collected = gradeHistory
            for combo in combos {
                guard gate.isCurrent(gen) else { return }
                // Arm the navigation wait *before* the submit fires it.
                let script = SISScraper.selectGradeTermScript(
                    schoolYear: combo.schoolYear,
                    semester: combo.semester
                )
                do {
                    try await gate.wait { [weak self] in
                        self?.webView.evaluateJavaScript(script, completionHandler: nil)
                    }
                } catch {
                    // This term's submit didn't navigate — skip it, keep going.
                    continue
                }

                let scraped = try await awaitPageRows(suffix: "/grades") {
                    try await SISScraper.scrapeGrades(from: $0)
                } isEmpty: { $0.rows.isEmpty }

                let report = GradeReport(
                    lastUpdated: Date(),
                    subjects: GradesParser.parse(scraped.rows),
                    summary: scraped.summary,
                    schoolYear: combo.schoolYear,
                    semester: combo.semester
                )
                // Empty or unposted terms don't belong on a GPA trend.
                if report.hasPostedGrades {
                    collected = GradesStore.merged(report, into: collected)
                }
            }

            guard gate.isCurrent(gen) else { return }
            gradeHistory = collected
            gradesError = nil
            GradesStore.saveHistory(collected)
        } catch {
            guard gate.isCurrent(gen) else { return }
            gradesError = "Couldn't load your grade history: \(error.localizedDescription)"
        }
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
    private func awaitPageRows<T>(
        suffix: String,
        timeout: TimeInterval = 12,
        scrape: @escaping (WKWebView) async throws -> T,
        isEmpty: (T) -> Bool
    ) async throws -> T {
        let deadline = Date().addingTimeInterval(timeout)
        var reachedPage = false
        var lastScrape: T?

        while Date() < deadline {
            if await isOnPage(suffix: suffix) {
                reachedPage = true
                if let scraped = try? await scrape(webView) {
                    lastScrape = scraped
                    if !isEmpty(scraped) { return scraped }
                }
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

    /// Polls until sign-in resolves one way or the other: the login form
    /// disappearing means we're in, a validation modal means we're not.
    /// Polling (rather than watching navigations) is what makes this survive
    /// the redirect chain and the no-navigation error case.
    private func awaitSignInOutcome(timeout: TimeInterval = 25) async -> (success: Bool, message: String) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            // Probing mid-navigation can throw; that just means "not settled".
            if let probe = try? await probeLoginPage() {
                if !probe.stillOnLoginForm { return (true, "") }
                if !probe.message.isEmpty { return (false, probe.message) }
            }
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
        return (false, Self.genericFailure)
    }

    /// Success is "the login form is gone", not a URL match — the form POSTs
    /// to /student/ and the logged-in page can render at that same URL, so
    /// matching on /student/home reports a failure even when sign-in worked.
    private func probeLoginPage() async throws -> (stillOnLoginForm: Bool, message: String) {
        let script = """
        (function () {
            var modal = document.querySelector('.modal.show .modal-body, .modal[style*="block"] .modal-body');
            return {
                stillOnLoginForm: !!document.getElementById('studno'),
                message: modal ? modal.textContent.trim() : ''
            };
        })();
        """
        let result = try await webView.evaluateJavaScript(script) as? [String: Any]
        return (
            result?["stillOnLoginForm"] as? Bool ?? true,
            result?["message"] as? String ?? ""
        )
    }

    private func load(_ url: URL) async throws {
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
