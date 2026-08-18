import SwiftUI

/// A retro pixel-dither fill: an ordered (Bayer 4×4) dither, drawn as
/// individual squares rather than a gradient or image, so it reads as
/// textured rather than a flat wash. Purely decorative on its own — call
/// sites give it a job (the chrome band's fade, a "this is finished/empty"
/// veil) rather than sprinkling it as pure decoration.
struct DitherFill: View, Animatable {
    var color: Color
    var cell: CGFloat = 2
    var ramp: Ramp = .topDown
    /// Scales the whole ramp: 0 draws nothing, 1 is the full ramp. Animatable,
    /// so a fill can dither *in* rather than appearing all at once.
    var density: Double = 1
    /// Only read by `.wave` — the travelling gradient's position in radians.
    /// A plain stored property, not in `animatableData`: the caller (a
    /// `TimelineView`) already hands in a smoothly-increasing value each
    /// tick, so there's nothing for SwiftUI to interpolate between draws.
    var phase: Double = 0

    enum Ramp {
        /// Dense at the top, gone at the bottom, quadratic falloff — the
        /// chrome band's fade.
        case topDown
        /// Uniform density at the given level — a veil over finished/empty
        /// content, rather than a directional fade.
        case flat(Double)
        /// Two overlapping sine gradients at different angles/speeds, so the
        /// dither's density itself sweeps and drifts like light on water
        /// rather than sitting at a fixed level. Deterministic in `phase`,
        /// not random — advancing `phase` reads as a wave travelling through
        /// the field, never a jump.
        case wave(Double)
    }

    var animatableData: Double {
        get { density }
        set { density = newValue }
    }

    // 4×4 Bayer matrix (values 0–15) — the classic ordered-dither threshold map.
    private static let bayer: [[Int]] = [
        [0, 8, 2, 10],
        [12, 4, 14, 6],
        [3, 11, 1, 9],
        [15, 7, 13, 5],
    ]

    var body: some View {
        Canvas { context, size in
            guard density > 0 else { return }
            let cols = Int(size.width / cell) + 1
            let rows = Int(size.height / cell) + 1
            guard rows > 0, cols > 0 else { return }
            for r in 0..<rows {
                let row = Self.bayer[r % 4]
                for c in 0..<cols {
                    let threshold = Int(level(col: c, row: r, rows: rows) * density * 16)
                    guard row[c % 4] < threshold else { continue }
                    let rect = CGRect(x: CGFloat(c) * cell, y: CGFloat(r) * cell, width: cell, height: cell)
                    context.fill(Path(rect), with: .color(color))
                }
            }
        }
        .drawingGroup()
        .allowsHitTesting(false)
    }

    private func level(col: Int, row: Int, rows: Int) -> Double {
        switch ramp {
        case .topDown:
            // 1 at the top → 0 at the bottom, so the dots thin out downward.
            let fade = rows > 1 ? 1.0 - Double(row) / Double(rows - 1) : 1
            return fade * fade
        case .flat(let value):
            return value
        case .wave(let intensity):
            return Self.waveLevel(col, row, phase: phase) * intensity
        }
    }

    /// Two sine waves at different spatial frequencies and speeds, summed and
    /// remapped to 0...1. The mismatched frequencies keep the pattern from
    /// ever exactly repeating on screen — it reads as drifting light, not a
    /// scrolling stripe.
    private static func waveLevel(_ x: Int, _ y: Int, phase: Double) -> Double {
        let wave1 = sin(Double(x) * 0.045 + phase)
        let wave2 = sin(Double(y) * 0.07 - phase * 0.6)
        return (wave1 + wave2) * 0.25 + 0.5
    }
}
