import XCTest
@testable import PUPSISPortal

/// Pure weighted-grade math — no store, no view. Mirrors `GradesParserTests`'
/// coverage of `neededAverage` at the subject-component level instead of the
/// term-GPA level.
final class GradingCalculatorTests: XCTestCase {
    private func component(_ name: String = "Exam", weight: Double, score: Double? = nil) -> GradingComponent {
        GradingComponent(name: name, weight: weight, score: score)
    }

    // MARK: currentWeightedScore

    func testCurrentWeightedScoreSumsScoredComponentsOnly() {
        let components = [
            component("Midterm", weight: 30, score: 90),
            component("Quizzes", weight: 20, score: 80),
            component("Final", weight: 50, score: nil),
        ]
        // 90·0.30 + 80·0.20 = 27 + 16 = 43
        XCTAssertEqual(GradingCalculator.currentWeightedScore(components), 43, accuracy: 0.0001)
    }

    func testCurrentWeightedScoreIsZeroWhenNothingIsScoredYet() {
        let components = [component("Midterm", weight: 30), component("Final", weight: 70)]
        XCTAssertEqual(GradingCalculator.currentWeightedScore(components), 0, accuracy: 0.0001)
    }

    // MARK: neededAverage

    func testNeededAverageSolvesForTheUnscoredRemainder() throws {
        let components = [
            component("Midterm", weight: 30, score: 90), // contributes 27
            component("Final", weight: 70, score: nil),
        ]
        // (75 - 27) / 70 * 100 = 68.57...
        let needed = try XCTUnwrap(GradingCalculator.neededAverage(components, target: 75))
        XCTAssertEqual(needed, 48.0 / 70.0 * 100, accuracy: 0.0001)
    }

    func testNeededAverageIsNilWhenEveryComponentIsAlreadyScored() {
        let components = [component("Midterm", weight: 30, score: 90), component("Final", weight: 70, score: 85)]
        XCTAssertNil(GradingCalculator.neededAverage(components, target: 75))
    }

    /// Nothing scored yet: needed average is just the target itself, same
    /// shape as `GradesParser.neededAverage`'s equivalent case.
    func testNeededAverageWithNothingScoredEqualsTheTargetItself() throws {
        let components = [component("Midterm", weight: 30), component("Final", weight: 70)]
        let needed = try XCTUnwrap(GradingCalculator.neededAverage(components, target: 82))
        XCTAssertEqual(needed, 82, accuracy: 0.0001)
    }

    /// Already ahead of a lax target — the needed average can fall below
    /// zero, meaning "any score at all secures it." The UI reports this
    /// plainly rather than the function clamping it away.
    func testNeededAverageCanFallBelowZeroWhenAlreadyWellAheadOfALaxTarget() throws {
        let components = [component("Midterm", weight: 50, score: 100), component("Final", weight: 50)]
        // (60 - 50) / 50 * 100 = 20 -- still positive; push the target lower.
        let needed = try XCTUnwrap(GradingCalculator.neededAverage(components, target: 40))
        XCTAssertEqual(needed, -20, accuracy: 0.0001)
    }
}
