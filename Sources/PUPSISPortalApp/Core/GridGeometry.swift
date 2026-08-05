import CoreGraphics
import Foundation

/// Maps points in the week grid to days and times.
///
/// This exists because the creation gesture used to live inside each day
/// column, which made a horizontal drag physically unable to cross into
/// another day. One layer spans all seven columns and resolves x itself.
struct GridGeometry {
    /// Width of the whole seven-column body, gutter excluded.
    let width: CGFloat
    let height: CGFloat
    let axis: (start: Int, end: Int)
    /// Horizontal gap drawn between columns.
    let columnSpacing: CGFloat

    init(width: CGFloat, height: CGFloat, axis: (start: Int, end: Int), columnSpacing: CGFloat = 5) {
        self.width = width
        self.height = height
        self.axis = axis
        self.columnSpacing = columnSpacing
    }

    var columnWidth: CGFloat {
        let days = CGFloat(Weekday.allCases.count)
        return (width - columnSpacing * (days - 1)) / days
    }

    /// Leading edge of a day's column.
    func x(of day: Weekday) -> CGFloat {
        CGFloat(day.rawValue - 1) * (columnWidth + columnSpacing)
    }

    /// Which column a point falls in. Clamped, so a drag that runs off either
    /// side of the grid keeps selecting the first or last day instead of
    /// stopping dead.
    func day(atX x: CGFloat) -> Weekday {
        guard columnWidth > 0 else { return .monday }

        let index = Int((x / (columnWidth + columnSpacing)).rounded(.down))
        let clamped = min(max(index, 0), Weekday.allCases.count - 1)
        return Weekday(rawValue: clamped + 1) ?? .monday
    }

    func minutes(atY y: CGFloat) -> Int {
        TimeSnap.minutes(atY: y, axis: axis, height: height)
    }

    /// The rectangle a block occupies, for positioning and for anchoring the
    /// editor popover.
    func rect(day: Weekday, start: Int, end: Int) -> CGRect {
        let span = CGFloat(max(axis.end - axis.start, 1))
        let top = CGFloat(start - axis.start) / span * height
        let bottom = CGFloat(end - axis.start) / span * height

        return CGRect(
            x: x(of: day),
            y: top,
            width: columnWidth,
            height: max(bottom - top, 1)
        )
    }

    /// A drag, resolved into the days it covered and the time range it drew.
    ///
    /// Vertical decides the time, horizontal decides the days, and either can
    /// be drawn in either direction.
    func drag(from origin: CGPoint, to current: CGPoint) -> DragRange {
        let days = self.days(from: origin.x, to: current.x)
        let range = TimeSnap.range(
            from: minutes(atY: origin.y),
            to: minutes(atY: current.y),
            axis: axis
        )

        return DragRange(days: days, start: range.start, end: range.end)
    }

    /// Every column between two x positions, inclusive, in weekday order
    /// regardless of which way the drag was drawn.
    func days(from startX: CGFloat, to endX: CGFloat) -> [Weekday] {
        let first = day(atX: min(startX, endX)).rawValue
        let last = day(atX: max(startX, endX)).rawValue

        return (first...last).compactMap(Weekday.init(rawValue:))
    }

    /// Weekdays touched by a rubber-band rectangle, for multi-select.
    func days(in rect: CGRect) -> [Weekday] {
        days(from: rect.minX, to: rect.maxX)
    }
}

/// What a create-drag produced: a time range plus the days it applies to.
struct DragRange: Equatable {
    let days: [Weekday]
    let start: Int
    let end: Int

    var isMultiDay: Bool { days.count > 1 }

    /// The day the event itself starts on; the rest come from recurrence.
    var anchorDay: Weekday { days.first ?? .monday }
}
