import XCTest
@testable import PUPSISPortal

/// `Notifier.plan` is the pure decision behind the reminder split — weekly vs
/// dated — so it's tested directly rather than through `UNUserNotificationCenter`.
final class NotifierPlanTests: XCTestCase {
    private var calendar = Calendar(identifier: .gregorian)

    override func setUpWithError() throws {
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Manila"))
        calendar.firstWeekday = 1
    }

    /// 2026-08-03 is a Monday.
    private func date(_ iso: String, _ hour: Int = 0, _ minute: Int = 0) throws -> Date {
        let parts = iso.split(separator: "-").compactMap { Int($0) }
        var components = DateComponents()
        (components.year, components.month, components.day) = (parts[0], parts[1], parts[2])
        (components.hour, components.minute) = (hour, minute)
        return try XCTUnwrap(calendar.date(from: components))
    }

    private let session = ClassSession(subjectCode: "COMP 20073", description: "Data Structures",
                                       faculty: "SANTOS, JUAN", day: .tuesday, start: 14 * 60, end: 16 * 60)

    /// The steady-state case: every week in the horizon resolves the same —
    /// no override, or a uniform term override — so one repeating trigger covers it.
    func testUnvaryingTimeStaysAWeeklyTrigger() throws {
        let plan = Notifier.plan(
            for: session, now: try date("2026-08-03"),
            resolvedStart: { _ in 14 * 60 },
            isVacant: { _ in false },
            calendar: calendar
        )

        XCTAssertEqual(plan, .weekly(day: .tuesday, start: 14 * 60))
    }

    /// A recurring (term-wide) move is still uniform across every week — still
    /// a single weekly trigger, just at the new time.
    func testAUniformlyMovedTimeStaysAWeeklyTriggerAtTheNewTime() throws {
        let plan = Notifier.plan(
            for: session, now: try date("2026-08-03"),
            resolvedStart: { _ in 13 * 60 + 30 },
            isVacant: { _ in false },
            calendar: calendar
        )

        XCTAssertEqual(plan, .weekly(day: .tuesday, start: 13 * 60 + 30))
    }

    /// One week in the horizon resolves differently (a this-week-only move) —
    /// the whole session expands to dated, non-repeating occurrences.
    func testAOneWeekDeviationExpandsToDatedOccurrences() throws {
        let thisWeek = try date("2026-08-03")

        let plan = Notifier.plan(
            for: session, now: thisWeek, horizonWeeks: 3,
            resolvedStart: { weekStart in
                calendar.isDate(weekStart, inSameDayAs: thisWeek) ? 13 * 60 + 30 : 14 * 60
            },
            isVacant: { _ in false },
            calendar: calendar
        )

        guard case .dated(let occurrences) = plan else {
            return XCTFail("expected .dated, got \(plan)")
        }
        XCTAssertEqual(occurrences.count, 3, "every week in the horizon, not just the deviating one")
        XCTAssertEqual(occurrences[0].start, 13 * 60 + 30, "this week: the moved time")
        XCTAssertEqual(occurrences[1].start, 14 * 60, "next week: back to the default")
    }

    /// A vacant week is dropped from the dated expansion entirely — no
    /// notification for a class that isn't happening.
    func testAVacantWeekIsSkippedInTheDatedExpansion() throws {
        let thisWeek = try date("2026-08-03")

        let plan = Notifier.plan(
            for: session, now: thisWeek, horizonWeeks: 2,
            resolvedStart: { weekStart in
                calendar.isDate(weekStart, inSameDayAs: thisWeek) ? 13 * 60 + 30 : 14 * 60
            },
            isVacant: { weekStart in calendar.isDate(weekStart, inSameDayAs: thisWeek) },
            calendar: calendar
        )

        guard case .dated(let occurrences) = plan else {
            return XCTFail("expected .dated, got \(plan)")
        }
        XCTAssertEqual(occurrences.count, 1, "the vacant week must not produce an occurrence")
    }

    /// Each dated occurrence's midnight lands on the session's own weekday —
    /// the reminder shouldn't drift onto the wrong day of a moved week.
    func testDatedOccurrencesLandOnTheSessionsWeekday() throws {
        let thisWeek = try date("2026-08-03")

        let plan = Notifier.plan(
            for: session, now: thisWeek, horizonWeeks: 2,
            resolvedStart: { weekStart in
                calendar.isDate(weekStart, inSameDayAs: thisWeek) ? 13 * 60 + 30 : 14 * 60
            },
            isVacant: { _ in false },
            calendar: calendar
        )

        guard case .dated(let occurrences) = plan, let first = occurrences.first else {
            return XCTFail("expected dated occurrences")
        }
        XCTAssertEqual(Weekday.on(first.midnight, calendar: calendar), .tuesday)
    }
}
