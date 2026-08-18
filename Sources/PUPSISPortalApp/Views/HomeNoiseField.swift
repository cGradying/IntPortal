import SwiftUI

/// Animated accent-tinted waves behind the home launcher. The one ambient,
/// continuous loop in the app besides the now-line — deliberately scoped:
/// mounted/unmounted with `isHome` at the call site (never runs elsewhere),
/// throttled well below display rate, and paused to a single static frame
/// under Reduce Motion rather than merely shortened.
///
/// ponytail: if this stutters on older hardware, the fix is a bigger `cell`
/// or a slower `minimumInterval` on the TimelineView below, not a rewrite.
struct HomeNoiseField: View {
    var color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? nil : 0.16, paused: reduceMotion)) { context in
            DitherFill(
                color: color.opacity(0.08),
                cell: 3,
                ramp: .wave(0.22),
                phase: reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate * 0.35
            )
        }
        .allowsHitTesting(false)
    }
}
