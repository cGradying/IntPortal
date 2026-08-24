import AppKit
import SwiftUI

/// What a scroll gesture over the Schedule screen asks for.
enum CalendarScrollAction {
    /// ±1 week.
    case stepWeek(Int)
    /// Overscrolled past the top of the week grid — switch to Year.
    case zoomOut
    /// Overscrolled past the top of the year view, the other direction —
    /// switch back to Week, landing on whatever week was left.
    case zoomIn
}

extension View {
    /// Two-finger horizontal swipe steps the week; overscrolling past the
    /// top edge switches Week↔Year — the same "one edge, two directions"
    /// gesture every calendar app uses to zoom its scale.
    ///
    /// `atTop` gates the scale switches: only a scroll that had nowhere
    /// left to go counts, never one that still moved real content.
    func calendarScroll(
        enabled: Bool,
        scale: CalendarScale,
        atTop: Bool,
        perform: @escaping (CalendarScrollAction) -> Void
    ) -> some View {
        modifier(CalendarScrollModifier(enabled: enabled, scale: scale, atTop: atTop, perform: perform))
    }
}

private struct CalendarScrollModifier: ViewModifier {
    let enabled: Bool
    let scale: CalendarScale
    let atTop: Bool
    let perform: (CalendarScrollAction) -> Void

    // A class held via @State so its identity — and the installed monitor —
    // survives across re-renders; its properties are kept in step with the
    // view's own state on every body evaluation below.
    @State private var monitor = CalendarScrollMonitor()

    func body(content: Content) -> some View {
        monitor.enabled = enabled
        monitor.scale = scale
        monitor.atTop = atTop
        monitor.perform = perform
        return content
            .onAppear { monitor.install() }
            .onDisappear { monitor.teardown() }
    }
}

/// A local `NSEvent` monitor, not a `DragGesture`. `GridInteractionLayer`
/// already owns a `DragGesture` across the whole grid for create/rubber-band,
/// and adding a second one there would mean arbitrating between them. Scroll
/// events never enter the gesture system, so the two can't collide.
/// `WindowChrome.swift`'s `TrafficLights.Coordinator` is this repo's existing
/// precedent for a local monitor tied to a view's lifetime.
private final class CalendarScrollMonitor {
    var enabled = false
    var scale: CalendarScale = .week
    var atTop = false
    var perform: (CalendarScrollAction) -> Void = { _ in }

    private var eventMonitor: Any?

    /// Accumulated horizontal drag for the trackpad swipe in progress.
    private var horizontalAccum: CGFloat = 0
    /// Accumulated vertical overscroll past the top edge.
    private var verticalAccum: CGFloat = 0
    /// One flick fires at most once, however far past the threshold it
    /// travels — set the moment an action fires, cleared when the gesture ends.
    private var latched = false
    /// A physical mouse wheel carries no phase to latch on, so its ticks get
    /// a plain time debounce instead of the accumulate/latch path.
    private var lastWheelStep = Date.distantPast

    private let stepThreshold: CGFloat = 50
    /// Higher than the week-step threshold on purpose: this gesture changes
    /// the whole screen, so it has to be harder to trigger by accident.
    private let zoomThreshold: CGFloat = 80
    private let wheelDebounce: TimeInterval = 0.15

    func install() {
        guard eventMonitor == nil else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel]) { [weak self] event in
            self?.handle(event)
            return event
        }
    }

    func teardown() {
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        eventMonitor = nil
    }

    private func handle(_ event: NSEvent) {
        guard enabled else { return }
        // Coasting after a hard flick would otherwise carry straight through
        // the top edge into a scale switch with no way to correct mid-flight.
        guard event.momentumPhase.isEmpty else { return }

        guard event.hasPreciseScrollingDeltas else {
            handleWheelTick(event)
            return
        }

        switch event.phase {
        case .began:
            horizontalAccum = 0
            verticalAccum = 0
            latched = false
        case .changed:
            accumulate(event)
        case .ended, .cancelled:
            horizontalAccum = 0
            verticalAccum = 0
            latched = false
        default:
            break
        }
    }

    private func accumulate(_ event: NSEvent) {
        guard !latched else { return }
        let dx = event.scrollingDeltaX
        let dy = event.scrollingDeltaY

        if abs(dx) > abs(dy) {
            guard scale == .week else { return }
            horizontalAccum += dx
            guard abs(horizontalAccum) >= stepThreshold else { return }
            latched = true
            perform(.stepWeek(dx > 0 ? -1 : 1))
        } else {
            guard atTop else { return }
            verticalAccum += dy
            switch scale {
            case .week where verticalAccum >= zoomThreshold:
                latched = true
                perform(.zoomOut)
            case .year where verticalAccum <= -zoomThreshold:
                latched = true
                perform(.zoomIn)
            default:
                break
            }
        }
    }

    private func handleWheelTick(_ event: NSEvent) {
        guard Date().timeIntervalSince(lastWheelStep) >= wheelDebounce else { return }
        let dx = event.scrollingDeltaX
        let dy = event.scrollingDeltaY

        if abs(dx) > abs(dy) {
            guard scale == .week else { return }
            perform(.stepWeek(dx > 0 ? -1 : 1))
            lastWheelStep = Date()
        } else if atTop {
            switch scale {
            case .week where dy > 0:
                perform(.zoomOut)
                lastWheelStep = Date()
            case .year where dy < 0:
                perform(.zoomIn)
                lastWheelStep = Date()
            default:
                break
            }
        }
    }
}
