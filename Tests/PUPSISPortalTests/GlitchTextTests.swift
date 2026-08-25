import XCTest
@testable import PUPSISPortal

final class GlitchTextTests: XCTestCase {
    /// Word shape has to stay readable while letters flicker — punctuation and
    /// whitespace are never candidates.
    func testWhitespaceAndPunctuationNeverGlitch() {
        let target = "Welcome.\nStart your study session now with Int Portal!"
        for tick in 0..<50 {
            let result = MatrixScramble.glitched(target, tick: tick, seed: 42)
            for (original, glitched) in zip(target, result) {
                if !(original.isLetter || original.isNumber) {
                    XCTAssertEqual(glitched, original, "tick \(tick) altered a non-letter character")
                }
            }
        }
    }

    /// Same inputs, same output — the whole point of a pure function, and what
    /// lets `TimelineView` redraw without extra state.
    func testSameInputsAreDeterministic() {
        let target = String(repeating: "abcdefghijklmnopqrstuvwxyz", count: 4)
        let first = MatrixScramble.glitched(target, tick: 7, seed: 99)
        let second = MatrixScramble.glitched(target, tick: 7, seed: 99)
        XCTAssertEqual(first, second)

        // Different seeds must actually change the result somewhere across a
        // spread of ticks — otherwise `seed` isn't doing anything and every
        // login screen would flicker in lockstep. A single tick on a short
        // string can coincidentally agree, so check a range instead of one.
        let diverges = (0..<20).contains { tick in
            MatrixScramble.glitched(target, tick: tick, seed: 99)
                != MatrixScramble.glitched(target, tick: tick, seed: 100)
        }
        XCTAssertTrue(diverges, "seed 99 and 100 agreed on every tick 0..<20")
    }

    /// A flicker, not a re-scramble: only a small minority of letters should
    /// ever differ from the target at a single tick.
    func testOnlyAMinorityOfLettersFlickerPerTick() {
        let target = String(repeating: "abcdefghijklmnopqrstuvwxyz", count: 4)
        for tick in 0..<20 {
            let result = MatrixScramble.glitched(target, tick: tick, seed: 5)
            let altered = zip(target, result).filter { $0 != $1 }.count
            let fraction = Double(altered) / Double(target.count)
            XCTAssertLessThanOrEqual(fraction, 0.25, "tick \(tick) altered \(fraction * 100)% of letters")
        }
    }

    /// Proves it actually animates rather than freezing on one substitution
    /// pattern.
    func testDifferentTicksProduceDifferentFlickerPatterns() {
        let target = String(repeating: "abcdefghijklmnopqrstuvwxyz", count: 4)
        let early = MatrixScramble.glitched(target, tick: 0, seed: 5)
        let later = MatrixScramble.glitched(target, tick: 40, seed: 5)
        XCTAssertNotEqual(early, later)
    }
}
