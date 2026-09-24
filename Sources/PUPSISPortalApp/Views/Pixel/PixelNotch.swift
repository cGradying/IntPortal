import SwiftUI

/// A rectangle whose corners step in twice, 2pt then 2pt: the pixel stand-in
/// for a rounded rectangle, used for every sheet, button, chip and block.
struct PixelNotch: InsettableShape {
    var step: CGFloat = 2
    var inset: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: inset, dy: inset)
        guard r.width >= 4 * step, r.height >= 4 * step else { return Path(r) }
        var path = Path()
        path.addLines(Self.points(in: r, step: step))
        path.closeSubpath()
        return path
    }

    func inset(by amount: CGFloat) -> PixelNotch {
        var copy = self
        copy.inset += amount
        return copy
    }

    /// Clockwise from the top of the left edge, five points per corner.
    static func points(in r: CGRect, step s: CGFloat) -> [CGPoint] {
        let (x0, y0, x1, y1) = (r.minX, r.minY, r.maxX, r.maxY)
        return [
            CGPoint(x: x0, y: y0 + 2 * s), CGPoint(x: x0 + s, y: y0 + 2 * s), CGPoint(x: x0 + s, y: y0 + s),
            CGPoint(x: x0 + 2 * s, y: y0 + s), CGPoint(x: x0 + 2 * s, y: y0),
            CGPoint(x: x1 - 2 * s, y: y0), CGPoint(x: x1 - 2 * s, y: y0 + s), CGPoint(x: x1 - s, y: y0 + s),
            CGPoint(x: x1 - s, y: y0 + 2 * s), CGPoint(x: x1, y: y0 + 2 * s),
            CGPoint(x: x1, y: y1 - 2 * s), CGPoint(x: x1 - s, y: y1 - 2 * s), CGPoint(x: x1 - s, y: y1 - s),
            CGPoint(x: x1 - 2 * s, y: y1 - s), CGPoint(x: x1 - 2 * s, y: y1),
            CGPoint(x: x0 + 2 * s, y: y1), CGPoint(x: x0 + 2 * s, y: y1 - s), CGPoint(x: x0 + s, y: y1 - s),
            CGPoint(x: x0 + s, y: y1 - 2 * s), CGPoint(x: x0, y: y1 - 2 * s),
        ]
    }
}
