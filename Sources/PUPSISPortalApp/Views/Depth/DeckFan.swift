import SwiftUI

/// A deck's due cards fanned in 3D: the fan's width is the due count, so a
/// heavy deck looks heavy before you read the number.
struct DeckFan: View {
    let count: Int
    var tint: Color
    /// 0 stacked, 1 fanned.
    var progress: Double = 1

    static let maxCards = 24

    /// Degrees per card, left to right, for `count` due cards.
    static func angles(count: Int) -> [Double] {
        let n = min(max(count, 0), maxCards)
        guard n > 1 else { return Array(repeating: 0, count: n) }
        let spread = min(150, 10 + Double(n) * 6)
        return (0..<n).map { (Double($0) / Double(n - 1) - 0.5) * spread }
    }

    @Environment(\.palette) private var palette

    var body: some View {
        let angles = Self.angles(count: count)
        ZStack {
            ForEach(Array(angles.enumerated()), id: \.offset) { k, angle in
                PixelNotch()
                    .fill(k == angles.count - 1 ? tint.opacity(0.14) : .clear)
                    .background(palette.roles.sheet, in: PixelNotch())
                    .overlay(PixelNotch().strokeBorder(tint.opacity(0.6), lineWidth: 2))
                    .frame(width: 92, height: 128)
                    .rotationEffect(.degrees(angle * progress), anchor: UnitPoint(x: 0.5, y: 1.65))
                    .rotation3DEffect(.degrees(Double(k) * 0.4 * progress), axis: (1, 0, 0))
            }
        }
        .frame(height: 300)
        .accessibilityElement()
        .accessibilityLabel("\(count) cards due")
    }
}
