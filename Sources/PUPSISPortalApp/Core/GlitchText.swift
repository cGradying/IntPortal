import SwiftUI

/// A light, ambient character-flicker — Matrix decode-screen in spirit, but
/// scoped down to a minority of letters per tick so a whole sentence stays
/// readable instead of turning into noise. Pure and deterministic: the same
/// `(target, tick, seed)` always produces the same string, which is what lets
/// `GlitchGradientText` below redraw from a `TimelineView` with no extra
/// `@State` beyond the seed itself.
enum MatrixScramble {
    private static let glyphs = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789$#%&@")

    static func glitched(_ target: String, tick: Int, seed: UInt64) -> String {
        String(target.enumerated().map { index, character -> Character in
            guard character.isLetter || character.isNumber else { return character }

            // Stable per-character odds, independent of tick: only a minority
            // of positions are ever flicker candidates, so a run reads as a
            // light glitch rather than a full re-scramble.
            let eligibility = hash(seed: seed, a: UInt64(index), b: 0xE1)
            guard eligibility % 100 < 18 else { return character }

            // Whether *this* candidate is actually flickering *this* tick —
            // keeps any single frame sparse even among eligible positions.
            let firing = hash(seed: seed, a: UInt64(index), b: UInt64(tick))
            guard firing % 5 == 0 else { return character }

            let glyphIndex = Int(hash(seed: seed, a: UInt64(index) &+ 1, b: UInt64(tick)) % UInt64(glyphs.count))
            return glyphs[glyphIndex]
        })
    }

    /// SplitMix64 — cheap, well-distributed, no `import` beyond Foundation's
    /// integer types. Not cryptographic; doesn't need to be.
    private static func hash(seed: UInt64, a: UInt64, b: UInt64) -> UInt64 {
        var z = seed &+ (a &* 0x9E3779B97F4A7C15) &+ (b &* 0xBF58476D1CE4E5B9)
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

/// The reusable wrapper: a gradient `Text` that ambiently glitches, styled
/// from two palette colors so it recolors with the theme. Degrades to a
/// static gradient `Text` under Reduce Motion — same contract every other
/// ambient loop in this app follows (`HomeNoiseField`, `Motion.drift`).
struct GlitchGradientText: View {
    let text: String
    let font: Font
    let gradient: [Color]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var seed = UInt64.random(in: .min ... .max)

    private var style: LinearGradient {
        LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var body: some View {
        if reduceMotion {
            Text(text).font(font).foregroundStyle(style)
        } else {
            TimelineView(.periodic(from: .now, by: 1.0 / 12)) { context in
                let tick = Int(context.date.timeIntervalSinceReferenceDate * 12)
                Text(MatrixScramble.glitched(text, tick: tick, seed: seed))
                    .font(font)
                    .foregroundStyle(style)
            }
        }
    }
}
