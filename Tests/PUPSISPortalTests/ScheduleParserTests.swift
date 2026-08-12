import XCTest
@testable import PUPSISPortal

/// Cases are the real schedule lines scraped from the live SIS page.
final class ScheduleParserTests: XCTestCase {
    private func parse(_ line: String) -> [ClassSession] {
        ScheduleParser.parse([
            "subjectCode": "TEST 001",
            "description": "Test Subject",
            "faculty": "SANTOS, JUAN",
            "scheduleLine": line,
        ])
    }

    func testTwoDaysPairWithTheirOwnTimes() {
        let sessions = parse("1N - BSCS 1-1N - T/F 02:00PM-04:00PM/01:30PM-04:30PM")
        XCTAssertEqual(sessions.count, 2)
        XCTAssertEqual(sessions[0].day, .tuesday)
        XCTAssertEqual(sessions[0].start, 14 * 60)
        XCTAssertEqual(sessions[0].end, 16 * 60)
        XCTAssertEqual(sessions[1].day, .friday)
        XCTAssertEqual(sessions[1].start, 13 * 60 + 30)
        XCTAssertEqual(sessions[1].end, 16 * 60 + 30)
    }

    func testSameDayTwiceBecomesTwoBlocks() {
        let sessions = parse("1N - BSCS 1-1N - SUN/SUN 08:00AM-12:00PM/01:00PM-06:00PM")
        XCTAssertEqual(sessions.count, 2)
        XCTAssertTrue(sessions.allSatisfy { $0.day == .sunday })
        XCTAssertEqual(sessions[0].start, 8 * 60)
        XCTAssertEqual(sessions[0].end, 12 * 60)
        XCTAssertEqual(sessions[1].start, 13 * 60)
        XCTAssertEqual(sessions[1].end, 18 * 60)
    }

    func testSingleDaySingleRange() {
        let sessions = parse("1N - BSCS 1-1N - S 07:30AM-10:30AM")
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].day, .saturday)
        XCTAssertEqual(sessions[0].start, 7 * 60 + 30)
        XCTAssertEqual(sessions[0].end, 10 * 60 + 30)
    }

    /// `TH` and `SUN` must win over the single-letter `T`/`S` codes.
    func testMultiLetterDayCodesArentSwallowed() {
        XCTAssertEqual(parse("1N - X - TH 09:00AM-11:00AM").first?.day, .thursday)
        XCTAssertEqual(parse("1N - X - SUN 09:00AM-11:00AM").first?.day, .sunday)
    }

    func testNoonAndMidnightBoundaries() {
        let noon = parse("1N - X - M 12:00PM-01:00PM")
        XCTAssertEqual(noon.first?.start, 12 * 60)
        XCTAssertEqual(noon.first?.end, 13 * 60)

        let earlyMorning = parse("1N - X - M 12:30AM-01:30AM")
        XCTAssertEqual(earlyMorning.first?.start, 30)
        XCTAssertEqual(earlyMorning.first?.end, 90)
    }

    func testUnparseableRowsAreSkippedNotCrashed() {
        XCTAssertTrue(parse("").isEmpty)
        XCTAssertTrue(parse("1N - BSCS 1-1N - TBA").isEmpty)
        XCTAssertTrue(parse("no times here at all").isEmpty)
    }
}

/// `Calendar` counts weekdays from Sunday, this enum counts from Monday.
/// Getting the shift wrong puts the now-line in the wrong column.
final class WeekdayTests: XCTestCase {
    private func weekday(_ iso: String) throws -> Weekday {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Manila"))

        var formatter = DateComponents()
        let parts = iso.split(separator: "-").compactMap { Int($0) }
        (formatter.year, formatter.month, formatter.day) = (parts[0], parts[1], parts[2])
        formatter.hour = 12

        return Weekday.on(try XCTUnwrap(calendar.date(from: formatter)), calendar: calendar)
    }

    func testEveryDayOfAKnownWeekMaps() throws {
        // 2026-08-03 is a Monday.
        XCTAssertEqual(try weekday("2026-08-03"), .monday)
        XCTAssertEqual(try weekday("2026-08-04"), .tuesday)
        XCTAssertEqual(try weekday("2026-08-05"), .wednesday)
        XCTAssertEqual(try weekday("2026-08-06"), .thursday)
        XCTAssertEqual(try weekday("2026-08-07"), .friday)
        XCTAssertEqual(try weekday("2026-08-08"), .saturday)
        XCTAssertEqual(try weekday("2026-08-09"), .sunday)
    }

    /// `Calendar.firstWeekday` is locale-dependent — in a US locale the week
    /// starts Sunday, which would slide the whole grid by a day.
    func testWeekStartIsMondayRegardlessOfLocale() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Manila"))
        calendar.firstWeekday = 1 // Sunday, as en_US would have it

        let monday = try date("2026-08-03", calendar)

        for iso in ["2026-08-03", "2026-08-05", "2026-08-09"] {
            let start = Weekday.weekStart(containing: try date(iso, calendar), calendar: calendar)
            XCTAssertEqual(start, monday, "week containing \(iso)")
        }
    }

    /// Sunday belongs to the week that started six days earlier, not the one
    /// about to begin.
    func testSundayClosesTheWeekRatherThanOpeningTheNext() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Manila"))

        let sunday = try date("2026-08-09", calendar)
        let start = Weekday.weekStart(containing: sunday, calendar: calendar)

        XCTAssertEqual(start, try date("2026-08-03", calendar))
        XCTAssertEqual(Weekday.sunday.date(inWeekStarting: start, calendar: calendar), sunday)
    }

    func testEachWeekdayLandsOnItsOwnDate() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Manila"))
        let start = try date("2026-08-03", calendar)

        let dates = Weekday.allCases.map { $0.date(inWeekStarting: start, calendar: calendar) }

        XCTAssertEqual(dates.count, Set(dates).count)
        XCTAssertEqual(dates.first, start)
        XCTAssertEqual(dates.last, try date("2026-08-09", calendar))
    }

    private func date(_ iso: String, _ calendar: Calendar) throws -> Date {
        let parts = iso.split(separator: "-").compactMap { Int($0) }
        var components = DateComponents()
        (components.year, components.month, components.day) = (parts[0], parts[1], parts[2])
        return try XCTUnwrap(calendar.date(from: components))
    }
}

/// `ClassSession.nextMeetingDate` — drives the class-note Add-date menu's
/// "Next class" default.
final class ClassSessionNextMeetingTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Manila")!
        return c
    }()

    private func date(_ iso: String) throws -> Date {
        let parts = iso.split(separator: "-").compactMap { Int($0) }
        var components = DateComponents()
        (components.year, components.month, components.day) = (parts[0], parts[1], parts[2])
        return try XCTUnwrap(calendar.date(from: components))
    }

    private func session(_ subject: String, _ day: Weekday) -> ClassSession {
        ClassSession(subjectCode: subject, description: "", faculty: "", day: day, start: 480, end: 600)
    }

    /// Subject meets Sunday; asking from Saturday (the 15th) should land on
    /// Sunday the 16th, not today.
    func testWrapsForwardToTheNextScheduledWeekday() throws {
        let sessions = [session("COMP1", .sunday)]
        let saturday = try date("2026-08-15")

        let next = ClassSession.nextMeetingDate(for: "COMP1", in: sessions, from: saturday, calendar: calendar)

        XCTAssertEqual(next, try date("2026-08-16"))
    }

    /// Asking on the meeting day itself returns that same day, not a week out.
    func testReturnsTodayWhenTodayIsAMeetingDay() throws {
        let sessions = [session("COMP1", .sunday)]
        let sunday = try date("2026-08-16")

        let next = ClassSession.nextMeetingDate(for: "COMP1", in: sessions, from: sunday, calendar: calendar)

        XCTAssertEqual(next, sunday)
    }

    func testNilForASubjectNotOnTheSchedule() throws {
        let sessions = [session("COMP1", .sunday)]

        let next = ClassSession.nextMeetingDate(for: "MATH1", in: sessions, from: try date("2026-08-15"), calendar: calendar)

        XCTAssertNil(next)
    }
}
