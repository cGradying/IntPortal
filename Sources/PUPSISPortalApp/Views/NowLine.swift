import SwiftUI
import Inject

/// The present moment, drawn across the week: a 2pt gold hairline plus a
/// gold time chip in the gutter carrying the live clock — spec 03 change 6.
///
/// DESIGN.md's Now Rule: gold marks the present and nothing else, so this is
/// the one place in the grid that reaches for it. No glass — Liquid Glass is
/// retired from the Registrar world, and a flat notched chip reads the time
/// just as well.
///
/// The clock ticks from a `TimelineView` one level up, in `WeekGrid`, because
/// the same minute also decides which blocks have already finished.
struct NowLine: View {
    @ObserveInjection var inject
    @Environment(\.palette) private var palette
    @Environment(\.typography) private var typography
    @Environment(\.reduceMotion) private var reduceMotion
    @Environment(\.uiScale) private var uiScale

    /// Minutes from midnight, right now.
    let minutes: Int
    /// Minutes-from-midnight at the top of the grid.
    let axisStart: Int
    /// Minutes of grid drawn across `height` points.
    let span: CGFloat
    let height: CGFloat
    let gutter: CGFloat

    private var lozengeHeight: CGFloat { 18 * uiScale }

    var body: some View {
        let offset = CGFloat(minutes - axisStart)

        Group {
            if offset >= 0, offset <= span {
                HStack(spacing: 0) {
                    Text(ClassSession.format(minutes))
                        .font(typography.nowClock)
                        .foregroundStyle(palette.roles.ink)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(palette.roles.gold, in: PixelNotch())
                        .frame(width: gutter, alignment: .trailing)
                        .accessibilityLabel("Now, \(ClassSession.format(minutes))")

                    Rectangle()
                        .fill(palette.roles.gold)
                        .frame(height: 2)
                        .accessibilityHidden(true)
                }
                .frame(height: lozengeHeight)
                .offset(y: offset / span * height - lozengeHeight / 2)
                // Glides to the new minute instead of jumping, which is the
                // difference between a clock and a thing that flickers.
                .animation(Motion.drift(reduced: reduceMotion), value: minutes)
            }
        }
        .enableInjection()
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
