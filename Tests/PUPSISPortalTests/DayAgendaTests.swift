import XCTest
@testable import PUPSISPortal

/// The shared "today at a glance" reading behind the Today screen and the menu
/// bar. Fixed clock, fake subjects — never a real schedule.
final class DayAgendaTests: XCTestCase {
    /// A meeting on `day`, minutes-from-midnight.
    private func session(_ code: String, _ day: Weekday, _ start: Int, _ end: Int) -> ClassSession {
        ClassSession(subjectCode: code, description: "Test", faculty: "SANTOS, JUAN",
                     day: day, start: start, end: end)
    }

    /// A fixed `Date` on a known weekday at a given minute-of-day, UTC so the
    /// test doesn't drift with the runner's zone.
    private func date(weekday: Weekday, minute: Int) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        // 2026-08-03 is a Monday; add the enum's day offset.
        var comps = DateComponents()
        comps.year = 2026; comps.month = 8; comps.day = 3 + (weekday.rawValue - 1)
        comps.hour = minute / 60; comps.minute = minute % 60
        return cal.date(from: comps)!
    }

    private var utc: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    private func agenda(_ sessions: [ClassSession], now: Date,
                        vacant: Set<String> = []) -> DayAgenda {
        DayAgenda.make(sessions: sessions, now: now,
                       isVacant: { s, _ in vacant.contains(s.id) }, calendar: utc)
    }

    // MARK: Phase

    func testPhaseClassifiesPastNowUpcoming() {
        let sessions = [
            session("PAST", .wednesday, 8 * 60, 9 * 60),    // 8–9
            session("NOW", .wednesday, 10 * 60, 11 * 60),   // 10–11
            session("SOON", .wednesday, 13 * 60, 14 * 60),  // 1–2pm
        ]
        // 10:30 on Wednesday.
        let result = agenda(sessions, now: date(weekday: .wednesday, minute: 10 * 60 + 30))

        XCTAssertEqual(result.items.map(\.phase), [.past, .inSession, .upcoming])
        XCTAssertEqual(result.items.map(\.session.subjectCode), ["PAST", "NOW", "SOON"])
    }

    // MARK: Vacancy + sort

    func testVacantIsDroppedAndItemsSortByStart() {
        let out = session("OUT", .wednesday, 9 * 60, 10 * 60)
        let sessions = [
            session("LATE", .wednesday, 15 * 60, 16 * 60),
            out,
            session("EARLY", .wednesday, 8 * 60, 9 * 60),
        ]
        let result = agenda(sessions, now: date(weekday: .wednesday, minute: 7 * 60),
                            vacant: [out.id])

        XCTAssertEqual(result.items.map(\.session.subjectCode), ["EARLY", "LATE"])
    }

    func testRemainingExcludesFinishedClasses() {
        let sessions = [
            session("DONE", .wednesday, 8 * 60, 9 * 60),
            session("LEFT", .wednesday, 14 * 60, 15 * 60),
        ]
        let result = agenda(sessions, now: date(weekday: .wednesday, minute: 12 * 60))

        XCTAssertEqual(result.remaining.map(\.session.subjectCode), ["LEFT"])
    }

    // MARK: Tomorrow

    func testTomorrowFirstPicksEarliestNextDay() {
        let sessions = [
            session("TUE_LATE", .thursday, 15 * 60, 16 * 60),
            session("TUE_EARLY", .thursday, 8 * 60, 9 * 60),
        ]
        // Now is Wednesday; tomorrow is Thursday.
        let result = agenda(sessions, now: date(weekday: .wednesday, minute: 20 * 60))

        XCTAssertEqual(result.tomorrowFirst?.subjectCode, "TUE_EARLY")
    }

    /// Sunday evening must look ahead to Monday — the week rolls over.
    func testSundayEveningLooksAheadToMonday() {
        let monday = session("MON", .monday, 7 * 60, 8 * 60)
        let result = agenda([monday], now: date(weekday: .sunday, minute: 21 * 60))

        XCTAssertEqual(result.tomorrowFirst?.subjectCode, "MON")
    }

    func testEmptyDayHasNoItemsButStillFindsTomorrow() {
        let sessions = [session("TMRW", .thursday, 9 * 60, 10 * 60)]
        // Wednesday with nothing scheduled.
        let result = agenda(sessions, now: date(weekday: .wednesday, minute: 10 * 60))

        XCTAssertTrue(result.items.isEmpty)
        XCTAssertEqual(result.tomorrowFirst?.subjectCode, "TMRW")
    }
}
