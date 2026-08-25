import SwiftUI

/// The present moment, drawn across the week: a hairline in the accent plus a
/// glass lozenge in the gutter carrying the live clock.
///
/// This is the one place in the app that uses Liquid Glass for emphasis rather
/// than for chrome, and the one place that uses the accent as a tint — both
/// are spent here so the rest of the grid can stay quiet.
///
/// The clock ticks from a `TimelineView` one level up, in `WeekGrid`, because
/// the same minute also decides which blocks have already finished.
struct NowLine: View {
    @Environment(\.palette) private var palette
    @Environment(\.typography) private var typography
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Minutes from midnight, right now.
    let minutes: Int
    /// Minutes-from-midnight at the top of the grid.
    let axisStart: Int
    /// Minutes of grid drawn across `height` points.
    let span: CGFloat
    let height: CGFloat
    let gutter: CGFloat

    private let lozengeHeight: CGFloat = 18

    var body: some View {
        let offset = CGFloat(minutes - axisStart)

        if offset >= 0, offset <= span {
            HStack(spacing: 0) {
                Text(ClassSession.format(minutes))
                    .font(typography.nowClock)
                    .foregroundStyle(palette.nowTint)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .glassTintedCapsule(palette.nowTint.opacity(0.22))
                    .frame(width: gutter, alignment: .trailing)
                    .accessibilityLabel("Now, \(ClassSession.format(minutes))")

                // 1pt disappears against a dark canvas once the accent is
                // desaturated by the wash; 1.5 reads without becoming a bar.
                Rectangle()
                    .fill(palette.nowTint)
                    .frame(height: 1.5)
                    .accessibilityHidden(true)
            }
            .frame(height: lozengeHeight)
            .offset(y: offset / span * height - lozengeHeight / 2)
            // Glides to the new minute instead of jumping, which is the
            // difference between a clock and a thing that flickers.
            .animation(Motion.drift(reduced: reduceMotion), value: minutes)
        }
    }

    /// Ticking on a plain 60-second period drifts off the minute boundary, so
    /// the clock can read a minute stale for most of its life. Start on the
    /// next :00 instead.
    static var nextMinute: Date {
        Calendar.current.nextDate(
            after: .now,
            matching: DateComponents(second: 0),
            matchingPolicy: .nextTime
        ) ?? .now
    }

    /// Minutes from midnight for a date, in the given calendar's time zone.
    static func minutes(of date: Date, calendar: Calendar = .current) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
}
