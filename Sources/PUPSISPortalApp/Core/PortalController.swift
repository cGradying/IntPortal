import Foundation
import WebKit

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
            webView.evaluateJavaScript(fillAndSubmitScript(for: credentials), completionHandler: nil)
            try await waitForNavigation()

            // ponytail: assumes the post-submit redirect lands on a /student
            // page in one navigation. If the SIS ever adds a client-side
            // interstitial, this reads as a failed login. Upgrade: loop
            // waitForNavigation() until the URL settles or a timeout elapses.
            guard webView.url?.path.hasPrefix("/student/home") == true else {
                status = .failed("Sign-in didn't go through — check your student number, birthdate, and password.")
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

    private func load(_ url: URL) async throws {
        webView.load(URLRequest(url: url))
        try await waitForNavigation()
    }

    private func waitForNavigation() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            pendingContinuation = continuation
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
