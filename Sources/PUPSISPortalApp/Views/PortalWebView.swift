import SwiftUI
import WebKit

/// Wraps the single shared, already-authenticated `WKWebView` — used to show
/// SIS pages the dashboard doesn't render natively (Enrollment, Accounts,
/// Forms, HDF), without spinning up a second, separately-authenticated view.
struct PortalWebView: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
