import Foundation
import WebKit

enum LoginStatus: Equatable {
    case idle
    case loggingIn
    case success
    case failed(String)
}

/// Owns the single WKWebView that carries the authenticated SIS session.
/// Drives sign-in to completion (rather than PUPSIS's fire-and-forget
/// one-shot autofill), then scrapes Schedule/Grades out of it. The same
/// web view is reused to display raw SIS pages the dashboard doesn't model
/// natively, so navigating there doesn't need a second, separately
/// authenticated view.
@MainActor
final class PortalController: NSObject, ObservableObject, WKNavigationDelegate {
    @Published var status: LoginStatus = .idle
    @Published var schedule: [ScheduleEntry] = []
    @Published var grades: [GradeEntry] = []
    @Published var summary = AcademicSummary()

    let webView: WKWebView
    private var pendingContinuation: CheckedContinuation<Void, Error>?

    private static let base = "https://sis8.pup.edu.ph/student"
    private static let loginURL = URL(string: "\(base)/")!
    private static let scheduleURL = URL(string: "\(base)/schedule")!
    private static let gradesURL = URL(string: "\(base)/grades")!
    private static let homeURL = URL(string: "\(base)/home")!

    override init() {
        webView = WKWebView()
        super.init()
        webView.navigationDelegate = self
    }

    func signIn(with credentials: Credentials) {
        Task { await runSignIn(credentials) }
    }

    /// Navigate the shared web view to a raw SIS page not modeled natively
    /// (Enrollment, Accounts, Forms, HDF).
    func openRawPage(path: String) {
        guard let url = URL(string: "\(Self.base)/\(path)") else { return }
        webView.load(URLRequest(url: url))
    }

    private func runSignIn(_ credentials: Credentials) async {
        status = .loggingIn
        do {
            try await load(Self.loginURL)
            webView.evaluateJavaScript(fillAndSubmitScript(for: credentials), completionHandler: nil)
            try await waitForNavigation()

            // ponytail: assumes the post-submit redirect lands directly on
            // /student/home in one navigation. If the SIS ever adds a
            // client-side-JS interstitial redirect, this will read as a
            // failed login. Upgrade: loop waitForNavigation() until the URL
            // stabilizes or a short timeout elapses.
            if webView.url?.path.hasPrefix("/student/home") == true {
                status = .success
                await refreshData()
            } else {
                status = .failed("Sign-in didn't go through — check your student number, birthdate, and password.")
            }
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    func refreshData() async {
        do {
            try await load(Self.scheduleURL)
            schedule = try await SISScraper.scrapeTable(from: webView).compactMap(ScheduleEntry.init)

            try await load(Self.gradesURL)
            grades = try await SISScraper.scrapeTable(from: webView).compactMap(GradeEntry.init)
            summary = AcademicSummary(fields: try await SISScraper.scrapeSummary(from: webView))

            try await load(Self.homeURL)
        } catch {
            status = .failed("Couldn't load schedule/grades: \(error.localizedDescription)")
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

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            pendingContinuation?.resume()
            pendingContinuation = nil
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            pendingContinuation?.resume(throwing: error)
            pendingContinuation = nil
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            pendingContinuation?.resume(throwing: error)
            pendingContinuation = nil
        }
    }
}
