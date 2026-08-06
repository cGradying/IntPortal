import Foundation
import WebKit

enum PortalError: LocalizedError {
    case timedOut

    var errorDescription: String? {
        "The SIS took too long to respond. Check your connection and try again."
    }
}

enum LoginStatus: Equatable {
    case idle
    case loggingIn
    case success
    case failed(String)
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

    private let webView: WKWebView
    private var pendingContinuation: CheckedContinuation<Void, Error>?
    private var pendingToken: UUID?

    private static let genericFailure = "Sign-in didn't go through — check your student number, birthdate, and password."

    private static let base = "https://sis8.pup.edu.ph/student"
    private static let loginURL = URL(string: "\(base)/")!
    private static let scheduleURL = URL(string: "\(base)/schedule")!
    private static let gradesURL = URL(string: "\(base)/grades")!

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
    }

    func signIn(with credentials: Credentials) {
        guard status != .loggingIn else { return }
        Task { await runSignIn(credentials) }
    }

    private func runSignIn(_ credentials: Credentials) async {
        status = .loggingIn
        do {
            try await load(Self.loginURL)

            // Don't wait on navigation events here: signing in runs through a
            // redirect chain (POST to /student/ then on to /student/home), so
            // any single didFinish can land mid-chain — and a validation error
            // shows a modal with no navigation at all. Poll the DOM until the
            // outcome actually settles instead.
            webView.evaluateJavaScript(fillAndSubmitScript(for: credentials), completionHandler: nil)

            let outcome = await awaitSignInOutcome()
            guard outcome.success else {
                report(outcome.message)
                return
            }

            status = .success
            await loadSchedule()
            await loadGrades()
        } catch {
            report(error.localizedDescription)
        }
    }

    func loadSchedule() async {
        do {
            try await load(Self.scheduleURL)
            let rows = try await awaitPageRows(suffix: "/schedule") {
                try await SISScraper.scrapeSchedule(from: $0)
            } isEmpty: { $0.isEmpty }
            let scraped = rows.flatMap(ScheduleParser.parse)
            let now = Date()

            sessions = scraped
            lastUpdated = now
            refreshError = nil
            ScheduleStore.save(scraped, lastUpdated: now)
        } catch {
            report("Couldn't refresh your schedule: \(error.localizedDescription)")
        }
    }

    /// Same shape as `loadSchedule`, on its own error channel. A grades failure
    /// sets `gradesError` and leaves the schedule screen untouched — the two
    /// pages fail independently.
    func loadGrades() async {
        do {
            try await load(Self.gradesURL)
            // The subject rows carry the page; an empty summary is fine, but an
            // empty row set is what "page not settled yet" looks like.
            let scraped = try await awaitPageRows(suffix: "/grades") {
                try await SISScraper.scrapeGrades(from: $0)
            } isEmpty: { $0.rows.isEmpty }

            let report = GradeReport(
                lastUpdated: Date(),
                subjects: GradesParser.parse(scraped.rows),
                summary: scraped.summary
            )
            grades = report
            gradesError = nil
            GradesStore.save(report)
        } catch {
            // Never through `report(_:)` — that governs the schedule screen.
            gradesError = "Couldn't refresh your grades: \(error.localizedDescription)"
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
        try await performAndWait { [weak self] in
            self?.webView.load(URLRequest(url: url))
        }
    }

    /// Arms the continuation *before* kicking off the navigation — otherwise a
    /// fast `didFinish` resumes nothing and the next navigation resumes the
    /// wrong await.
    private func performAndWait(timeout: TimeInterval = 25, _ action: @escaping () -> Void) async throws {
        let token = UUID()
        pendingToken = token
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            pendingContinuation = continuation
            action()
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                guard pendingToken == token else { return }
                resumePending(throwing: PortalError.timedOut)
            }
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

    private func resumePending(throwing error: Error?) {
        guard let continuation = pendingContinuation else { return }
        pendingContinuation = nil
        pendingToken = nil
        if let error {
            continuation.resume(throwing: error)
        } else {
            continuation.resume()
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in resumePending(throwing: nil) }
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
    /// timeout in `performAndWait` covers the case where nothing does.
    private nonisolated func fail(with error: Error) {
        guard (error as NSError).code != NSURLErrorCancelled else { return }
        Task { @MainActor in resumePending(throwing: error) }
    }
}
