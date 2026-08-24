import AppKit
import SwiftUI

/// Turns off the real AppKit scroller on the nearest enclosing
/// `NSScrollView` — SwiftUI's `.scrollIndicators(.hidden)` only suppresses
/// the flash-on-scroll indicator; with System Settings' "Show scroll bars:
/// Always", the underlying `NSScrollView` still draws a persistent one
/// regardless of that modifier. This reaches into AppKit directly instead.
/// Scrolling itself — trackpad, drag, keyboard, `ScrollViewReader.scrollTo`
/// — goes through the scroll view's document/clip view and is completely
/// unaffected; only the visual scroller widget is turned off.
private struct HiddenScroller: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        // The scroll view isn't in the hierarchy yet on this pass.
        DispatchQueue.main.async { Self.hide(from: view) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        Self.hide(from: nsView)
    }

    private static func hide(from view: NSView) {
        var current: NSView? = view
        while let candidate = current {
            if let scrollView = candidate as? NSScrollView {
                scrollView.hasVerticalScroller = false
                scrollView.hasHorizontalScroller = false
                return
            }
            current = candidate.superview
        }
    }
}

extension View {
    /// Apply to a `ScrollView`'s content — see `HiddenScroller`'s doc comment.
    func hidingRealScroller() -> some View {
        background(HiddenScroller())
    }
}
