import XCTest
@testable import PUPSISPortal

final class StudyStatsTests: XCTestCase {
    func testFirstReviewEverStartsStreakAtOne() {
        let stats = StudyStats.advance(QuizStats(), reviewedAt: Date())
        XCTAssertEqual(stats.streak, 1)
    }

    func testSameCalendarDayDoubleReviewDoesNotDoubleCount() {
        let now = Date()
        let later = now.addingTimeInterval(60)
        let first = StudyStats.advance(QuizStats(), reviewedAt: now)
        let second = StudyStats.advance(first, reviewedAt: later)
        XCTAssertEqual(second.streak, 1)
        // Same-day review still moves lastStudied forward, even though the
        // streak itself doesn't advance — otherwise the very next day would
        // wrongly read as "a day since the last review" instead of one.
        XCTAssertEqual(second.lastStudied, later)
    }

    func testConsecutiveDayAdvancesStreak() {
        let calendar = Calendar.current
        let day1 = Date()
        let day2 = calendar.date(byAdding: .day, value: 1, to: day1)!

        let first = StudyStats.advance(QuizStats(), reviewedAt: day1)
        let second = StudyStats.advance(first, reviewedAt: day2)
        XCTAssertEqual(second.streak, 2)
    }

    func testGapOfMoreThanADayResetsStreak() {
        let calendar = Calendar.current
        let day1 = Date()
        let day3 = calendar.date(byAdding: .day, value: 3, to: day1)!

        let first = StudyStats.advance(QuizStats(), reviewedAt: day1)
        let second = StudyStats.advance(first, reviewedAt: day3)
        XCTAssertEqual(second.streak, 1)
    }

    func testMissedDayThenResumingStartsOverAtOneNotZero() {
        let calendar = Calendar.current
        let day1 = Date()
        let day2 = calendar.date(byAdding: .day, value: 1, to: day1)!
        let day5 = calendar.date(byAdding: .day, value: 5, to: day1)!

        var stats = StudyStats.advance(QuizStats(), reviewedAt: day1)
        stats = StudyStats.advance(stats, reviewedAt: day2)
        XCTAssertEqual(stats.streak, 2)

        stats = StudyStats.advance(stats, reviewedAt: day5)
        XCTAssertEqual(stats.streak, 1)
    }
}
