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

    private let webView: WKWebView
    private var pendingContinuation: CheckedContinuation<Void, Error>?
    private var pendingToken: UUID?

    private static let genericFailure = "Sign-in didn't go through — check your student number, birthdate, and password."

    private static let base = "https://sis8.pup.edu.ph/student"
    private static let loginURL = URL(string: "\(base)/")!
    private static let scheduleURL = URL(string: "\(base)/schedule")!

    override init() {
        webView = WKWebView()
        super.init()
        webView.navigationDelegate = self
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
                status = .failed(outcome.message)
                return
            }

            status = .success
            await loadSchedule()
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    func loadSchedule() async {
        do {
            try await load(Self.scheduleURL)
            let rows = try await SISScraper.scrapeSchedule(from: webView)
            sessions = rows.flatMap(ScheduleParser.parse)
        } catch {
            status = .failed("Couldn't load your schedule: \(error.localizedDescription)")
        }
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
        Task { @MainActor in resumePending(throwing: error) }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in resumePending(throwing: error) }
    }
}
