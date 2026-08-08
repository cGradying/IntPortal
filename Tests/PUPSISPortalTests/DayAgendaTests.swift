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

    // MARK: Merged timeline (classes + custom events)

    private func event(_ title: String, _ day: Weekday, _ start: Int, _ end: Int) -> DayBlock {
        DayBlock(id: "\(title)-\(start)", day: day, start: start, end: end,
                 title: title, subtitle: "\(start)–\(end)")
    }

    private func timeline(_ classes: [ClassSession], _ events: [DayBlock], now: Date,
                          vacant: Set<String> = []) -> [DayAgenda.AgendaEntry] {
        DayAgenda.timeline(classes: classes, events: events, now: now,
                           isVacant: { s, _ in vacant.contains(s.id) }, calendar: utc)
    }

    /// Classes and events interleave in start order, not classes-then-events.
    func testTimelineMergesAndOrdersByStart() {
        let math = session("MATH", .monday, 8 * 60, 10 * 60)
        let phys = session("PHYS", .monday, 14 * 60, 16 * 60)
        let lunch = event("LUNCH", .monday, 12 * 60, 13 * 60)

        let entries = timeline([math, phys], [lunch], now: date(weekday: .monday, minute: 9 * 60))
        XCTAssertEqual(entries.map(\.title), ["MATH", "LUNCH", "PHYS"])
    }

    func testTimelineTagsPhaseAcrossBoth() {
        let math = session("MATH", .monday, 8 * 60, 10 * 60)
        let lunch = event("LUNCH", .monday, 12 * 60, 13 * 60)

        let entries = timeline([math], [lunch], now: date(weekday: .monday, minute: 9 * 60))
        XCTAssertEqual(entries.first { $0.title == "MATH" }?.phase, .inSession)
        XCTAssertEqual(entries.first { $0.title == "LUNCH" }?.phase, .upcoming)
    }

    /// Events on another day, and vacant classes, are left out.
    func testTimelineFiltersOtherDaysAndVacant() {
        let math = session("MATH", .monday, 8 * 60, 10 * 60)
        let tomorrowEvent = event("TMRW", .tuesday, 9 * 60, 10 * 60)
        let now = date(weekday: .monday, minute: 7 * 60)

        let entries = timeline([math], [tomorrowEvent], now: now, vacant: [math.id])
        XCTAssertTrue(entries.isEmpty)
    }

    /// Free time ahead sums the ≥15-minute gaps between entries that haven't passed.
    func testRemainingFreeMinutesCountsGapsAhead() {
        let math = session("MATH", .monday, 8 * 60, 10 * 60)
        let phys = session("PHYS", .monday, 14 * 60, 16 * 60)
        let lunch = event("LUNCH", .monday, 12 * 60, 13 * 60)
        let entries = timeline([math, phys], [lunch], now: date(weekday: .monday, minute: 9 * 60))

        // 10:00→12:00 (120) + 13:00→14:00 (60) = 180, both still ahead of 9:00.
        XCTAssertEqual(DayAgenda.remainingFreeMinutes(entries, nowMinutes: 9 * 60), 180)
    }

    func testRemainingFreeMinutesSkipsPassedGaps() {
        let math = session("MATH", .monday, 8 * 60, 10 * 60)
        let phys = session("PHYS", .monday, 14 * 60, 16 * 60)
        let lunch = event("LUNCH", .monday, 12 * 60, 13 * 60)
        let entries = timeline([math, phys], [lunch], now: date(weekday: .monday, minute: 13 * 60 + 20))

        // At 1:20PM the 10:00→12:00 gap has passed (its next entry, LUNCH at 12:00,
        // is behind now); only 13:00→14:00 (60, PHYS still ahead) counts.
        XCTAssertEqual(DayAgenda.remainingFreeMinutes(entries, nowMinutes: 13 * 60 + 20), 60)
    }
}
