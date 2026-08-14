import AppKit
import SwiftUI

/// The window's traffic-light buttons (close / minimize / zoom). When
/// `autoHide` is on they stay hidden and reveal only while the cursor is near
/// the top-left corner (like fullscreen); off keeps them always visible. The
/// window still closes with ⌘W, minimizes with ⌘M, and quits with ⌘Q.
struct TrafficLights: NSViewRepresentable {
    var autoHide: Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.view = view
        DispatchQueue.main.async { context.coordinator.apply(autoHide: autoHide) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.apply(autoHide: autoHide)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.teardown()
    }

    final class Coordinator {
        weak var view: NSView?
        private var monitor: Any?
        private var autoHide = true

        func apply(autoHide: Bool) {
            self.autoHide = autoHide
            guard let window = view?.window else { return }
            configure(window)
            if autoHide {
                window.acceptsMouseMovedEvents = true
                if monitor == nil {
                    monitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
                        self?.update(with: event)
                        return event
                    }
                }
                setHidden(true) // hidden until the cursor visits the corner
            } else {
                teardown()
                setHidden(false)
            }
        }

        func teardown() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        /// Push the content under the title bar and drop its background, so there's
        /// no empty strip left at the top — the island is the only chrome.
        private func configure(_ window: NSWindow) {
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert(.fullSizeContentView)
            // Not movable by arbitrary background: AppKit hit-tests the calendar's
            // clear create-drag rectangle as draggable background and steals the
            // gesture, so a drag-to-add-event moved the whole window instead. The
            // top strip gets an explicit drag handle (`WindowDragArea`) instead.
            window.isMovableByWindowBackground = false
            // Drop the hairline under the title bar — the last remnant of the bar.
            window.titlebarSeparatorStyle = .none
            window.toolbar = nil
        }

        private func update(with event: NSEvent) {
            guard autoHide, let window = view?.window else { return }
            let p = event.locationInWindow // origin bottom-left
            let nearTopLeft = p.x < 116 && p.y > window.frame.height - 52
            setHidden(!nearTopLeft)
        }

        private func setHidden(_ hidden: Bool) {
            guard let window = view?.window else { return }
            for button: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
                window.standardWindowButton(button)?.isHidden = hidden
            }
        }
    }
}

/// A transparent strip that moves the window on drag, replacing
/// `isMovableByWindowBackground`. That flag dragged the window from *any*
/// background — including the calendar's clear create-gesture rectangle, which
/// broke drag-to-add-event. This drives the move explicitly, so only where it's
/// placed (the top chrome strip, under the nav island) moves the window; the
/// grid below is left alone. A double-click still zooms, like a real title bar.
struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DraggingView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class DraggingView: NSView {
        override func mouseDown(with event: NSEvent) {
            guard let window else { return }
            if event.clickCount == 2 {
                window.performZoom(nil)
            } else {
                window.performDrag(with: event)
            }
        }
    }
}
