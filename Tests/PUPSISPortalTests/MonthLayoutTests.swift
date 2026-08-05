import XCTest
@testable import PUPSISPortal

final class MonthLayoutTests: XCTestCase {
    private var calendar = Calendar(identifier: .gregorian)

    override func setUpWithError() throws {
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Manila"))
        // Sunday-first, as en_US would have it — the layout must ignore this.
        calendar.firstWeekday = 1
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: year, month: month, day: day)))
    }

    func testAMonthGridIsAlwaysSixFullWeeks() throws {
        for month in 1...12 {
            let days = MonthLayout.days(ofMonthContaining: try date(2026, month, 1), calendar: calendar)
            XCTAssertEqual(days.count, 42, "month \(month)")
        }
    }

    /// January 2026 opens on a Thursday, so the grid has to start on the
    /// Monday of the week before — 29 December 2025.
    func testTheGridStartsOnTheMondayOnOrBeforeTheFirst() throws {
        let days = MonthLayout.days(ofMonthContaining: try date(2026, 1, 15), calendar: calendar)

        XCTAssertEqual(days.first, try date(2025, 12, 29))
        XCTAssertEqual(Weekday.on(try XCTUnwrap(days.first), calendar: calendar), .monday)
    }

    /// A Sunday-first calendar would put the 1st in a different cell and slide
    /// every date in the month by one.
    func testGridIsMondayFirstRegardlessOfLocale() throws {
        for month in 1...12 {
            let days = MonthLayout.days(ofMonthContaining: try date(2026, month, 1), calendar: calendar)
            let first = try XCTUnwrap(days.first)
            XCTAssertEqual(Weekday.on(first, calendar: calendar), .monday, "month \(month)")
        }
    }

    func testDaysAreConsecutiveWithNoGaps() throws {
        let days = MonthLayout.days(ofMonthContaining: try date(2026, 8, 5), calendar: calendar)

        for (earlier, later) in zip(days, days.dropFirst()) {
            let gap = calendar.dateComponents([.day], from: earlier, to: later).day
            XCTAssertEqual(gap, 1)
        }
    }

    /// Padding cells are real neighbouring dates, and have to be drawn faintly
    /// rather than treated as part of the month.
    func testPaddingCellsAreMarkedAsOutsideTheMonth() throws {
        let august = try date(2026, 8, 1)
        let days = MonthLayout.days(ofMonthContaining: august, calendar: calendar)

        let inMonth = days.filter { MonthLayout.isSameMonth($0, as: august, calendar: calendar) }
        XCTAssertEqual(inMonth.count, 31)
        XCTAssertFalse(MonthLayout.isSameMonth(try XCTUnwrap(days.first), as: august, calendar: calendar))
    }

    func testAYearHasTwelveMonthsInOrder() {
        let months = MonthLayout.months(in: 2026, calendar: calendar)

        XCTAssertEqual(months.count, 12)
        XCTAssertEqual(months.map { calendar.component(.month, from: $0) }, Array(1...12))
        XCTAssertEqual(Set(months.map { calendar.component(.year, from: $0) }), [2026])
    }

    /// February 2027 starts on a Monday and has 28 days — exactly four weeks,
    /// the case most likely to produce a short grid.
    func testAnExactlyFourWeekMonthStillFillsSixRows() throws {
        let february = try date(2027, 2, 1)
        let days = MonthLayout.days(ofMonthContaining: february, calendar: calendar)

        XCTAssertEqual(Weekday.on(february, calendar: calendar), .monday)
        XCTAssertEqual(days.count, 42)
        XCTAssertEqual(days.first, february)
    }
}
