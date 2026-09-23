import SwiftUI

/// A 12×12 bitmap icon drawn cell by cell in the current foreground style.
/// Integer sizes only (12 inline, 24 in the menu and on the orb) so every
/// cell lands on whole points.
struct PixelIcon: View {
    let glyph: Glyph
    var size: CGFloat = 12

    init(_ glyph: Glyph, size: CGFloat = 12) {
        self.glyph = glyph
        self.size = size
    }

    var body: some View {
        Canvas { context, canvasSize in
            var path = Path()
            PixelBitmap.cells(PixelBitmap.grid(glyph.rows, on: "#"), in: canvasSize).forEach { path.addRect($0) }
            context.fill(path, with: .foreground)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Where each lit cell of a bitmap falls inside a given size: square cells,
/// centered. Shared by `PixelIcon` and `PixelBadge`.
enum PixelBitmap {
    static func grid(_ rows: [String], on: Character) -> [[Bool]] {
        rows.map { row in row.map { $0 == on } }
    }

    static func cells(_ grid: [[Bool]], in size: CGSize) -> [CGRect] {
        let rows = grid.count, cols = grid.first?.count ?? 0
        guard rows > 0, cols > 0 else { return [] }
        let cell = min(size.width / CGFloat(cols), size.height / CGFloat(rows))
        let originX = (size.width - cell * CGFloat(cols)) / 2
        let originY = (size.height - cell * CGFloat(rows)) / 2
        return grid.enumerated().flatMap { row, line in
            line.enumerated().compactMap { col, on in
                on ? CGRect(x: originX + CGFloat(col) * cell, y: originY + CGFloat(row) * cell, width: cell, height: cell) : nil
            }
        }
    }
}
