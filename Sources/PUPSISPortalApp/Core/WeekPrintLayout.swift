import CoreGraphics
import Foundation

/// Fixed page geometry for printing a week. The live grid measures its width
/// from the window (`GeometryReader` in `WeekGrid`) — a print page has no
/// window, so this pins concrete dimensions instead. Landscape-shaped, sized
/// for seven comfortable columns; height is derived per-week from the actual
/// hour span so a short day doesn't waste paper and a long one doesn't clip.
enum WeekPrintLayout {
    static let gutter: CGFloat = 50
    static let headerHeight: CGFloat = 30
    static let hourHeight: CGFloat = 44
    static let columnSpacing: CGFloat = 4
    static let bodyWidth: CGFloat = 900
    /// Outer padding the page view adds around gutter + body.
    static let margin: CGFloat = 24

    /// Same wrapper `WeekGrid.axis` uses — kept as its own name here so a
    /// print-specific window override could diverge later without touching
    /// the live grid's call.
    static func axis(for blocks: [DayBlock]) -> (start: Int, end: Int) {
        GridAxis.hours(covering: blocks)
    }

    static func bodyHeight(for blocks: [DayBlock]) -> CGFloat {
        let span = axis(for: blocks)
        let hours = CGFloat(max(span.end - span.start, 60)) / 60
        return hours * hourHeight
    }

    static func geometry(for blocks: [DayBlock]) -> GridGeometry {
        GridGeometry(
            width: bodyWidth,
            height: bodyHeight(for: blocks),
            axis: axis(for: blocks),
            columnSpacing: columnSpacing
        )
    }

    static func pageSize(for blocks: [DayBlock]) -> CGSize {
        CGSize(
            width: gutter + bodyWidth + margin * 2,
            height: headerHeight + bodyHeight(for: blocks) + margin * 2
        )
    }
}
