import SwiftUI

/// A retro pixel-dither band for the top bar: an ordered (Bayer 4×4) dither of a
/// vertical fade — dense at the very top, thinning to nothing lower down — so the
/// chrome strip reads as textured rather than a flat fill. Purely decorative.
struct DitherBand: View {
    var color: Color
    var cell: CGFloat = 2

    // 4×4 Bayer matrix (values 0–15) — the classic ordered-dither threshold map.
    private static let bayer: [[Int]] = [
        [0, 8, 2, 10],
        [12, 4, 14, 6],
        [3, 11, 1, 9],
        [15, 7, 13, 5],
    ]

    var body: some View {
        Canvas { context, size in
            let cols = Int(size.width / cell) + 1
            let rows = Int(size.height / cell) + 1
            guard rows > 1 else { return }
            for r in 0..<rows {
                // 1 at the top → 0 at the bottom, so the dots thin out downward.
                let fade = 1.0 - Double(r) / Double(rows - 1)
                let threshold = Int((fade * fade) * 16) // squared → faster falloff
                let row = Self.bayer[r % 4]
                for c in 0..<cols where row[c % 4] < threshold {
                    let rect = CGRect(x: CGFloat(c) * cell, y: CGFloat(r) * cell, width: cell, height: cell)
                    context.fill(Path(rect), with: .color(color))
                }
            }
        }
        .drawingGroup()
        .allowsHitTesting(false)
    }
}
