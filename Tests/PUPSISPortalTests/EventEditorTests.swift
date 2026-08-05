import EventKit
import XCTest
@testable import PUPSISPortal

/// Pure-value tests only. Nothing here touches a real `EKEventStore`.
final class EventSnapshotTests: XCTestCase {
    private func snapshot(days: [Weekday]) -> EventSnapshot {
        EventSnapshot(
            title: "Study",
            calendarID: "cal-1",
            date: Date(timeIntervalSince1970: 1_754_400_000),
            start: 14 * 60,
            end: 16 * 60,
            repeatDays: days
        )
    }

    func testASingleDayIsNotTreatedAsRepeating() {
        XCTAssertFalse(snapshot(days: [.monday]).isMultiDay)
    }

    /// A drag across days used to become a weekly series with no way to say
    /// otherwise. Covering several days and repeating every week are separate
    /// choices now, and the repeat is off unless asked for.
    func testCoveringSeveralDaysDoesNotImplyRepeatingWeekly() {
        XCTAssertFalse(snapshot(days: [.monday, .wednesday, .friday]).repeatsWeekly)
    }

    /// Without a repeat, each covered day becomes its own one-off event.
    func testANonRepeatingSnapshotYieldsADateForEveryDayItCovers() {
        let weekStart = Date(timeIntervalSince1970: 1_754_265_600)
        let dates = snapshot(days: [.monday, .wednesday, .friday]).dates(inWeekStarting: weekStart)

        XCTAssertEqual(dates.count, 3)
        XCTAssertEqual(Set(dates).count, 3)
    }

    func testTheSummarySaysSoWhenItRepeats() {
        var repeating = snapshot(days: [.monday, .wednesday])
        repeating.repeatsWeekly = true

        XCTAssertTrue(repeating.summary.hasPrefix("every "), repeating.summary)
        XCTAssertFalse(snapshot(days: [.monday, .wednesday]).summary.hasPrefix("every "))
    }

    func testSeveralDaysCountAsRepeating() {
        XCTAssertTrue(snapshot(days: [.monday, .wednesday, .friday]).isMultiDay)
    }

    /// A repeating event is described by its weekdays; a one-off by its date.
    /// Showing a date for something that repeats would be a lie.
    func testTheSummaryNamesWeekdaysOnlyWhenItRepeats() {
        let repeating = snapshot(days: [.monday, .wednesday]).summary
        XCTAssertTrue(repeating.contains("Mon, Wed"), repeating)

        // A one-off names its date instead — "Mon, Wed" would be a lie.
        let single = snapshot(days: [.monday]).summary
        XCTAssertFalse(single.contains("Mon,"), single)
    }

    func testTheSummaryAlwaysCarriesTheTimeRange() {
        XCTAssertTrue(snapshot(days: [.monday]).summary.contains("2PM – 4PM"))
    }
}

final class RecurrenceMappingTests: XCTestCase {
    /// EventKit counts weekdays from Sunday and this enum counts from Monday.
    /// Getting the mapping wrong would repeat an event on the wrong days.
    func testEveryWeekdayRoundTripsThroughEventKit() {
        for day in Weekday.allCases {
            XCTAssertEqual(Weekday(ekWeekday: day.ekWeekday), day)
        }
    }

    func testMondayAndSundayMapToTheRightEventKitDays() {
        XCTAssertEqual(Weekday.monday.ekWeekday, .monday)
        XCTAssertEqual(Weekday.sunday.ekWeekday, .sunday)
    }

    func testAWeeklyRuleCarriesEveryRequestedDay() throws {
        let rule = CalendarBridge.weeklyRule(on: [.monday, .wednesday, .friday], until: nil)
        let days = try XCTUnwrap(rule.daysOfTheWeek).compactMap { Weekday(ekWeekday: $0.dayOfTheWeek) }

        XCTAssertEqual(Set(days), [.monday, .wednesday, .friday])
        XCTAssertEqual(rule.frequency, .weekly)
        XCTAssertEqual(rule.interval, 1)
    }

    /// Without an end date the series runs forever and turns up in the user's
    /// calendar years later.
    func testAWeeklyRuleStopsOnTheTermEndWhenGiven() throws {
        let end = Date(timeIntervalSince1970: 1_767_225_600)
        let rule = CalendarBridge.weeklyRule(on: [.monday, .tuesday], until: end)

        let recurrenceEnd = try XCTUnwrap(rule.recurrenceEnd)
        XCTAssertEqual(
            try XCTUnwrap(recurrenceEnd.endDate).timeIntervalSince1970,
            end.timeIntervalSince1970,
            accuracy: 1
        )
    }
}

/// Exporting the schedule and then ticking that calendar drew every class
/// twice: once from the SIS scrape, once as our own copy read back.
@MainActor
final class ExportEchoTests: XCTestCase {
    private let store = EKEventStore()

    private func event(notes: String?) -> EKEvent {
        let event = EKEvent(eventStore: store)
        event.title = "COMP 20073"
        event.notes = notes
        return event
    }

    func testOurOwnExportsAreRecognised() {
        XCTAssertTrue(CalendarBridge.isOurExport(event(notes: "Data Structures\n\n[PUPSISPortal]")))
    }

    /// The user's own events in the same calendar must survive — the export
    /// lands in a calendar they actually use.
    func testEventsTheUserWroteAreNotTreatedAsExports() {
        XCTAssertFalse(CalendarBridge.isOurExport(event(notes: nil)))
        XCTAssertFalse(CalendarBridge.isOurExport(event(notes: "")))
        XCTAssertFalse(CalendarBridge.isOurExport(event(notes: "Dentist, bring referral")))
    }

    /// The tag is appended after the description, so matching has to be a
    /// contains rather than an equality check.
    func testTheTagIsFoundAnywhereInTheNotes() {
        XCTAssertTrue(CalendarBridge.isOurExport(event(notes: "[PUPSISPortal] leading")))
        XCTAssertTrue(CalendarBridge.isOurExport(event(notes: "trailing [PUPSISPortal]")))
    }
}

final class OccurrenceIdentityTests: XCTestCase {
    /// Every occurrence of a repeating event shares one `eventIdentifier`. If
    /// the block id didn't include the occurrence date, three occurrences in
    /// one week would collapse into a single block for both SwiftUI and
    /// BlockLayout — and an edit would hit the wrong one.
    func testOccurrencesOfOneEventGetDistinctBlockIDs() {
        let identifier = "ABC-123"
        let monday = Date(timeIntervalSince1970: 1_754_400_000)
        let wednesday = monday.addingTimeInterval(2 * 24 * 60 * 60)

        let first = CalendarBridge.blockID(identifier: identifier, occurrence: monday)
        let second = CalendarBridge.blockID(identifier: identifier, occurrence: wednesday)

        XCTAssertNotEqual(first, second)
    }

    func testTheSameOccurrenceAlwaysGetsTheSameBlockID() {
        let date = Date(timeIntervalSince1970: 1_754_400_000)

        XCTAssertEqual(
            CalendarBridge.blockID(identifier: "ABC", occurrence: date),
            CalendarBridge.blockID(identifier: "ABC", occurrence: date)
        )
    }

    func testDifferentEventsAtTheSameMomentStayDistinct() {
        let date = Date(timeIntervalSince1970: 1_754_400_000)

        XCTAssertNotEqual(
            CalendarBridge.blockID(identifier: "ABC", occurrence: date),
            CalendarBridge.blockID(identifier: "XYZ", occurrence: date)
        )
    }
}
