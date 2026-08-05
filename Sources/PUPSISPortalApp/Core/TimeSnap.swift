import CoreGraphics
import Foundation

/// Converting between a point in the grid and a time, kept out of the views so
/// the arithmetic can be tested rather than eyeballed by dragging.
enum TimeSnap {
    /// Quarter hours. Fine enough for a real timetable, coarse enough that a
    /// drag lands on a round number instead of 2:07pm.
    static let step = 15

    /// Shortest event a drag can produce. Below this the block has no room for
    /// its own title and reads as a rendering glitch.
    static let minimumDuration = 15

    static func snap(_ minutes: Int, to step: Int = step) -> Int {
        Int((Double(minutes) / Double(step)).rounded()) * step
    }

    /// Vertical offset in the grid body to minutes from midnight, snapped and
    /// clamped to the drawn range.
    static func minutes(
        atY y: CGFloat,
        axis: (start: Int, end: Int),
        height: CGFloat
    ) -> Int {
        guard height > 0 else { return axis.start }

        let span = Double(axis.end - axis.start)
        let raw = Double(axis.start) + Double(y / height) * span
        return min(max(snap(Int(raw.rounded())), axis.start), axis.end)
    }

    /// A drag start and end into an ordered range, whichever way it was drawn,
    /// never shorter than `minimumDuration` and never past the axis.
    static func range(
        from anchor: Int,
        to current: Int,
        axis: (start: Int, end: Int)
    ) -> (start: Int, end: Int) {
        var start = min(anchor, current)
        var end = max(anchor, current)

        if end - start < minimumDuration {
            // Grow away from whichever edge has room, so dragging at the
            // bottom of the day doesn't silently produce nothing.
            if start + minimumDuration <= axis.end {
                end = start + minimumDuration
            } else {
                start = max(axis.start, axis.end - minimumDuration)
                end = axis.end
            }
        }

        return (start, end)
    }

    /// Moving one edge of an existing block, keeping the other fixed.
    static func resize(
        start: Int,
        end: Int,
        movingEdge edge: Edge,
        to minutes: Int,
        axis: (start: Int, end: Int)
    ) -> (start: Int, end: Int) {
        switch edge {
        case .top:
            let capped = min(minutes, end - minimumDuration)
            return (max(axis.start, capped), end)
        case .bottom:
            let capped = max(minutes, start + minimumDuration)
            return (start, min(axis.end, capped))
        }
    }

    enum Edge {
        case top
        case bottom
    }
}
