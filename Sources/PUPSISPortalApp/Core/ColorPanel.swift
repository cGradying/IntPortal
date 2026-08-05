import AppKit
import SwiftUI

/// macOS parks the shared color panel wherever it was last dragged — usually
/// nowhere near the block being recolored. SwiftUI's `ColorPicker` opens that
/// same panel and gives no hook to move it, so this drives `NSColorPanel`
/// directly and puts it beside the pointer.
///
/// One shared panel, one shared controller: AppKit only has one color panel,
/// and it needs a target that outlives the view that opened it.
@MainActor
final class ColorPanelController: NSObject {
    static let shared = ColorPanelController()

    private var onChange: (@MainActor (Color) -> Void)?
    private var resignObserver: NSObjectProtocol?

    func present(
        current: Color,
        near point: NSPoint,
        onChange: @escaping @MainActor (Color) -> Void
    ) {
        self.onChange = onChange

        let panel = NSColorPanel.shared
        panel.showsAlpha = false
        panel.color = NSColor(current)
        panel.setTarget(self)
        panel.setAction(#selector(colorChanged))
        panel.makeKeyAndOrderFront(nil)
        place(panel, near: point)
        dismissWhenDone(panel)
    }

    /// A color panel left open is a window the user has to go and close. Any
    /// click outside it — back on the schedule, or another app — resigns key,
    /// which is exactly the "I'm done" signal.
    private func dismissWhenDone(_ panel: NSColorPanel) {
        stopObserving()
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: panel,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated { ColorPanelController.shared.dismiss() }
        }
    }

    func dismiss() {
        stopObserving()
        onChange = nil

        let panel = NSColorPanel.shared
        // Clear the target too: the panel is shared, and a stale action would
        // keep recoloring a subject the user has moved on from.
        panel.setTarget(nil)
        panel.setAction(nil)
        panel.orderOut(nil)
    }

    private func stopObserving() {
        guard let resignObserver else { return }
        NotificationCenter.default.removeObserver(resignObserver)
        self.resignObserver = nil
    }

    /// Opens to the right of the pointer, then gets pulled back inside the
    /// screen — near a right-edge block it would otherwise open off-screen.
    private func place(_ panel: NSColorPanel, near point: NSPoint) {
        let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }

        let size = panel.frame.size
        let x = min(max(visible.minX, point.x + 24), visible.maxX - size.width)
        let top = min(max(visible.minY + size.height, point.y + size.height / 2), visible.maxY)
        panel.setFrameTopLeftPoint(NSPoint(x: x, y: top))
    }

    @objc private func colorChanged(_ sender: NSColorPanel) {
        // The panel can hand back a color in any space; hex storage needs sRGB.
        guard let srgb = sender.color.usingColorSpace(.sRGB) else { return }
        onChange?(Color(nsColor: srgb))
    }
}
