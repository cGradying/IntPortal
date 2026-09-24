import XCTest
@testable import PUPSISPortal

/// Fixed dates throughout — "next class" is the one feature whose whole job is
/// being right about the current moment, so nothing here may read the clock.
final class NextClassTests: XCTestCase {
    private var calendar = Calendar(identifier: .gregorian)

    override func setUpWithError() throws {
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Manila"))
        // Sunday-first, as en_US would have it. The week math must ignore it.
        calendar.firstWeekday = 1
    }

    /// 2026-08-03 is a Monday; 2026-08-09 the Sunday that closes that week.
    private func date(_ iso: String, _ hour: Int, _ minute: Int = 0) throws -> Date {
        let parts = iso.split(separator: "-").compactMap { Int($0) }
        var components = DateComponents()
        (components.year, components.month, components.day) = (parts[0], parts[1], parts[2])
        (components.hour, components.minute) = (hour, minute)
        return try XCTUnwrap(calendar.date(from: components))
    }

    private func session(_ code: String, _ day: Weekday, _ start: Int, _ end: Int) -> ClassSession {
        ClassSession(subjectCode: code, description: "Test Subject",
                     faculty: "SANTOS, JUAN", day: day, start: start, end: end)
    }

    private lazy var week = [
        session("COMP 20073", .monday, 8 * 60, 10 * 60),
        session("GEED 005", .monday, 14 * 60, 16 * 60),
        session("COMP 20073", .friday, 13 * 60 + 30, 16 * 60 + 30),
    ]

    func testBetweenClassesPicksTheNextOneNotThePast() throws {
        let upcoming = NextClass.next(in: week, at: try date("2026-08-03", 11),
                                      calendar: calendar)

        XCTAssertEqual(upcoming?.session.subjectCode, "GEED 005")
        XCTAssertEqual(upcoming?.isNow, false)
        XCTAssertEqual(upcoming?.start, try date("2026-08-03", 14))
    }

    /// A class already running is what you want to see, not the one after it.
    func testDuringAClassReportsItAsInSession() throws {
        let upcoming = NextClass.next(in: week, at: try date("2026-08-03", 9),
                                      calendar: calendar)

        XCTAssertEqual(upcoming?.session.subjectCode, "COMP 20073")
        XCTAssertEqual(upcoming?.isNow, true)
    }

    /// The moment a class ends it stops being the answer.
    func testAClassThatJustEndedIsNotTheNextOne() throws {
        let upcoming = NextClass.next(in: week, at: try date("2026-08-03", 10),
                                      calendar: calendar)

        XCTAssertEqual(upcoming?.session.subjectCode, "GEED 005")
    }

    /// Sunday night must find Monday's first class rather than reporting that
    /// the week is over — the schedule repeats, so there is always a next one.
    func testAfterTheLastClassOfTheWeekWrapsIntoTheNext() throws {
        let upcoming = NextClass.next(in: week, at: try date("2026-08-09", 20),
                                      calendar: calendar)

        XCTAssertEqual(upcoming?.session.subjectCode, "COMP 20073")
        XCTAssertEqual(upcoming?.session.day, .monday)
        XCTAssertEqual(upcoming?.start, try date("2026-08-10", 8))
    }

    func testVacantMeetingsAreSkipped() throws {
        let vacant = week[1].id // Monday's GEED 005
        let upcoming = NextClass.next(in: week, at: try date("2026-08-03", 11),
                                      isVacant: { s, _ in s.id == vacant }, calendar: calendar)

        XCTAssertEqual(upcoming?.session.subjectCode, "COMP 20073")
        XCTAssertEqual(upcoming?.session.day, .friday)
    }

    /// Skipping is per meeting, not per subject: COMP 20073 meets twice, and
    /// marking Monday vacant must leave Friday alone.
    func testSkippingOneMeetingLeavesTheSubjectsOtherMeeting() throws {
        let mondayComp = week[0].id
        let upcoming = NextClass.next(in: week, at: try date("2026-08-03", 7),
                                      isVacant: { s, _ in s.id == mondayComp }, calendar: calendar)

        XCTAssertEqual(upcoming?.session.subjectCode, "GEED 005")
    }

    /// Per-occurrence vacancy: a class vacant only *this* week is skipped now
    /// but must still surface as next week's candidate — the reason `isVacant`
    /// takes the occurrence date rather than a flat set of ids.
    func testThisWeekOnlyVacancyStillSurfacesNextWeek() throws {
        let only = [session("COMP 20073", .monday, 8 * 60, 10 * 60)]
        let thisMonday = try date("2026-08-03", 7)
        let nextMonday = try date("2026-08-10", 8)

        let upcoming = NextClass.next(in: only, at: thisMonday,
                                      isVacant: { _, occurrence in occurrence < nextMonday },
                                      calendar: calendar)

        // This week's Monday is vacant, so the answer is next week's occurrence.
        XCTAssertEqual(upcoming?.session.subjectCode, "COMP 20073")
        XCTAssertEqual(upcoming?.start, try date("2026-08-10", 8))
    }

    func testNoSessionsMeansNoAnswerRatherThanACrash() throws {
        XCTAssertNil(NextClass.next(in: [], at: try date("2026-08-03", 11), calendar: calendar))
    }

    /// Every meeting marked vacant is the same as having none.
    func testSkippingEverythingReturnsNil() throws {
        let all = Set(week.map(\.id))

        XCTAssertNil(NextClass.next(in: week, at: try date("2026-08-03", 7),
                                    isVacant: { s, _ in all.contains(s.id) }, calendar: calendar))
    }

    func testMinutesAwayCountsDownInWholeMinutes() throws {
        let now = try date("2026-08-03", 13, 35)
        let upcoming = try XCTUnwrap(NextClass.next(in: week, at: now, calendar: calendar))

        XCTAssertEqual(upcoming.minutesAway(from: now), 25)
    }

    /// Once it's started the countdown is zero, not negative.
    func testMinutesAwayNeverGoesNegative() throws {
        let now = try date("2026-08-03", 9)
        let upcoming = try XCTUnwrap(NextClass.next(in: week, at: now, calendar: calendar))

        XCTAssertEqual(upcoming.minutesAway(from: now), 0)
    }

    // MARK: Countdown phrasing (shared by the banner and the menu bar)

    private func upcoming(at now: Date) throws -> NextClass.Upcoming {
        try XCTUnwrap(NextClass.next(in: week, at: now, calendar: calendar))
    }

    func testCountdownReadsInSessionWhileAClassRuns() throws {
        let phrase = try upcoming(at: try date("2026-08-03", 9)).countdown(now: try date("2026-08-03", 9), calendar: calendar)
        XCTAssertEqual(phrase, "in session until 10AM")
    }

    func testCountdownUnderAnHourIsMinutes() throws {
        let now = try date("2026-08-03", 13, 35)
        XCTAssertEqual(try upcoming(at: now).countdown(now: now, calendar: calendar), "in 25 min")
    }

    func testCountdownSameDayButOverAnHourIsAClockTime() throws {
        let now = try date("2026-08-03", 11)   // next is GEED 005 at 2pm
        XCTAssertEqual(try upcoming(at: now).countdown(now: now, calendar: calendar), "at 2PM")
    }

    func testCountdownOnAnotherDayCarriesTheDay() throws {
        let now = try date("2026-08-03", 17)   // Monday done; next is Friday
        XCTAssertEqual(try upcoming(at: now).countdown(now: now, calendar: calendar), "FRI 1:30PM")
    }

    // MARK: DST

    /// 2026-03-08 is when US Eastern springs forward (2:00 AM clocks jump to
    /// 3:00 AM). Building the start time as "midnight + 510 elapsed minutes"
    /// lands on 9:30 — an hour late — because 60 of those minutes are spent
    /// crossing the gap the clock skips; reading the wall-clock hour/minute
    /// directly still gives 8:30, exactly what the SIS shows.
    func testClassStartTimeDoesNotDriftAcrossASpringForwardTransition() throws {
        var dstCalendar = Calendar(identifier: .gregorian)
        dstCalendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))

        let sunday = session("COMP 20073", .sunday, 8 * 60 + 30, 10 * 60)
        var midnightComponents = DateComponents()
        (midnightComponents.year, midnightComponents.month, midnightComponents.day) = (2026, 3, 8)
        (midnightComponents.hour, midnightComponents.minute) = (0, 30)
        let now = try XCTUnwrap(dstCalendar.date(from: midnightComponents))

        let upcoming = try XCTUnwrap(NextClass.next(in: [sunday], at: now, calendar: dstCalendar))

        var expectedComponents = DateComponents()
        (expectedComponents.year, expectedComponents.month, expectedComponents.day) = (2026, 3, 8)
        (expectedComponents.hour, expectedComponents.minute) = (8, 30)
        let expectedStart = try XCTUnwrap(dstCalendar.date(from: expectedComponents))

        XCTAssertEqual(upcoming.start, expectedStart)
    }
}

/// `Calendar.wallClock` itself — every DST-elapsed-minutes fix (W12) routes
/// through this one helper, so its correctness is tested directly rather
/// than through each caller.
final class CalendarWallClockTests: XCTestCase {
    private func newYork() throws -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        return cal
    }

    private func manila() throws -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Manila"))
        return cal
    }

    private func midnight(_ cal: Calendar, _ year: Int, _ month: Int, _ day: Int) throws -> Date {
        try XCTUnwrap(cal.date(from: DateComponents(year: year, month: month, day: day)))
    }

    /// 2026-03-08: US Eastern springs forward, 2:00 AM clocks jump to 3:00 AM.
    /// 8:30 must still read as 8:30, not the hour-late 9:30 that "midnight +
    /// 510 elapsed minutes" would give.
    func testSpringForwardResolvesTheLiteralWallClockTime() throws {
        let cal = try newYork()
        let day = try midnight(cal, 2026, 3, 8)
        let start = try XCTUnwrap(cal.wallClock(minutes: 8 * 60 + 30, on: day))

        XCTAssertEqual(cal.component(.hour, from: start), 8)
        XCTAssertEqual(cal.component(.minute, from: start), 30)
    }

    /// The 2:00–3:00 AM gap that spring-forward skips never happened, so a
    /// class "at" 2:30 that day has no wall-clock time to resolve to.
    func testSpringForwardGapReturnsNil() throws {
        let cal = try newYork()
        let day = try midnight(cal, 2026, 3, 8)

        XCTAssertNil(cal.wallClock(minutes: 2 * 60 + 30, on: day))
    }

    /// 2026-11-01: US Eastern falls back, 2:00 AM clocks repeat as 1:00 AM —
    /// a 25-hour day. 10:00 AM must still resolve to the literal 10:00, which
    /// is 11 *elapsed* hours past midnight that day, not 10.
    func testFallBackResolvesTheLiteralWallClockTimeAcrossTheRepeatedHour() throws {
        let cal = try newYork()
        let day = try midnight(cal, 2026, 11, 1)
        let start = try XCTUnwrap(cal.wallClock(minutes: 10 * 60, on: day))

        XCTAssertEqual(cal.component(.hour, from: start), 10)
        XCTAssertEqual(cal.component(.minute, from: start), 0)
        XCTAssertEqual(start.timeIntervalSince(day), 11 * 3600)
    }

    /// Asia/Manila has observed no DST since 1978 — every day is 24 real
    /// hours, so `wallClock` must agree exactly with naive elapsed-minute
    /// addition on both an ordinary day and the date US Eastern transitions.
    func testNoDSTZoneMatchesElapsedMinutesOnAnOrdinaryDay() throws {
        let cal = try manila()
        let day = try midnight(cal, 2026, 6, 15)
        let wallClock = try XCTUnwrap(cal.wallClock(minutes: 8 * 60 + 30, on: day))
        let elapsed = try XCTUnwrap(cal.date(byAdding: .minute, value: 8 * 60 + 30, to: day))

        XCTAssertEqual(wallClock, elapsed)
    }

    func testNoDSTZoneMatchesElapsedMinutesOnTheUSTransitionDate() throws {
        let cal = try manila()
        let day = try midnight(cal, 2026, 3, 8)
        let wallClock = try XCTUnwrap(cal.wallClock(minutes: 10 * 60, on: day))
        let elapsed = try XCTUnwrap(cal.date(byAdding: .minute, value: 10 * 60, to: day))

        XCTAssertEqual(wallClock, elapsed)
    }
}

/// The reminder's fire time is plain arithmetic, and the only part of
/// `Notifier`'s weekly path worth testing — the rest is `UNUserNotificationCenter`.
final class NotifierFireTimeTests: XCTestCase {
    func testTheLeadTimeIsSubtractedFromTheStart() {
        let fire = Notifier.fireTime(day: .tuesday, start: 14 * 60, leadMinutes: 15)

        XCTAssertEqual(fire.day, .tuesday)
        XCTAssertEqual(fire.minutes, 13 * 60 + 45)
    }

    func testAZeroLeadFiresExactlyAtTheStart() {
        let fire = Notifier.fireTime(day: .tuesday, start: 14 * 60, leadMinutes: 0)

        XCTAssertEqual(fire.minutes, 14 * 60)
    }

    /// A lead that runs back past midnight belongs to the previous day. Left
    /// negative it would ask for a minute no day has, and never fire.
    func testALeadCrossingMidnightMovesToThePreviousDay() {
        let fire = Notifier.fireTime(day: .tuesday, start: 15, leadMinutes: 30)

        XCTAssertEqual(fire.day, .monday)
        XCTAssertEqual(fire.minutes, 23 * 60 + 45)
    }

    /// Monday is the enum's first day, so wrapping backwards off it has to land
    /// on Sunday rather than clamping.
    func testCrossingMidnightOnMondayWrapsToSunday() {
        let fire = Notifier.fireTime(day: .monday, start: 0, leadMinutes: 10)

        XCTAssertEqual(fire.day, .sunday)
        XCTAssertEqual(fire.minutes, 23 * 60 + 50)
    }
}
