import XCTest
@testable import PUPSISPortal

/// The .ics builder. Pure string output, so it's checked here rather than by
/// importing into a live calendar. Fake subjects — never a real schedule.
final class ICSExporterTests: XCTestCase {
    private var utc: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    /// 2026-08-03 is a Monday.
    private var weekStart: Date {
        utc.date(from: DateComponents(year: 2026, month: 8, day: 3))!
    }

    private var termEnd: Date {
        utc.date(from: DateComponents(year: 2026, month: 8, day: 31))!
    }

    private func session(_ code: String, _ day: Weekday, _ start: Int, _ end: Int,
                         description: String = "Test Subject", faculty: String = "SANTOS, JUAN") -> ClassSession {
        ClassSession(subjectCode: code, description: description, faculty: faculty,
                     day: day, start: start, end: end)
    }

    private func ics(_ sessions: [ClassSession],
                     status: @escaping (ClassSession) -> SessionStatus = { _ in .regular }) -> String {
        ICSExporter.ics(for: sessions, weekStart: weekStart, until: termEnd,
                        status: status, calendar: utc,
                        now: utc.date(from: DateComponents(year: 2026, month: 8, day: 1))!)
    }

    private func eventCount(_ text: String) -> Int {
        text.components(separatedBy: "BEGIN:VEVENT").count - 1
    }

    // MARK: Structure

    func testWrapsEventsInACalendar() {
        let text = ics([session("MATH", .monday, 8 * 60, 10 * 60)])
        XCTAssertTrue(text.hasPrefix("BEGIN:VCALENDAR"))
        XCTAssertTrue(text.contains("VERSION:2.0"))
        XCTAssertTrue(text.contains("END:VCALENDAR"))
        XCTAssertTrue(text.hasSuffix("\r\n"))
        XCTAssertEqual(eventCount(text), 1)
    }

    func testOneEventPerSession() {
        let text = ics([
            session("MATH", .monday, 8 * 60, 10 * 60),
            session("PHYS", .thursday, 13 * 60, 15 * 60),
        ])
        XCTAssertEqual(eventCount(text), 2)
    }

    /// Weekly repeat, ending on the term-end day, on the class's own weekday.
    func testWeeklyRuleWithByDayAndUntil() {
        let text = ics([session("PHYS", .thursday, 13 * 60, 15 * 60)])
        XCTAssertTrue(text.contains("RRULE:FREQ=WEEKLY;UNTIL=20260831T235959;BYDAY=TH"),
                      "missing/incorrect RRULE in:\n\(text)")
        // First occurrence is Thursday of the given week (Aug 6) at 1PM.
        XCTAssertTrue(text.contains("DTSTART:20260806T130000"))
        XCTAssertTrue(text.contains("DTEND:20260806T150000"))
    }

    func testEveryWeekdayMapsToItsByDayCode() {
        let pairs: [(Weekday, String)] = [
            (.monday, "MO"), (.tuesday, "TU"), (.wednesday, "WE"), (.thursday, "TH"),
            (.friday, "FR"), (.saturday, "SA"), (.sunday, "SU"),
        ]
        for (day, code) in pairs {
            let text = ics([session("X", day, 9 * 60, 10 * 60)])
            XCTAssertTrue(text.contains("BYDAY=\(code)"), "\(day) should map to \(code)")
        }
    }

    // MARK: Status

    func testVacantClassesAreSkipped() {
        let vacant = session("SKIP", .monday, 8 * 60, 10 * 60)
        let kept = session("KEEP", .tuesday, 8 * 60, 10 * 60)
        let text = ics([vacant, kept]) { $0.subjectCode == "SKIP" ? .vacant : .regular }
        XCTAssertEqual(eventCount(text), 1)
        XCTAssertFalse(text.contains("SUMMARY:SKIP"))
        XCTAssertTrue(text.contains("SUMMARY:KEEP"))
    }

    func testOnlineClassesAreMarked() {
        let text = ics([session("CS", .monday, 8 * 60, 10 * 60)]) { _ in .online }
        XCTAssertTrue(text.contains("SUMMARY:CS (Online)"))
        XCTAssertTrue(text.contains("LOCATION:Online"))
    }

    func testInPersonClassesHaveNoLocation() {
        let text = ics([session("CS", .monday, 8 * 60, 10 * 60)])
        XCTAssertFalse(text.contains("LOCATION:"))
    }

    // MARK: Escaping

    func testSpecialCharactersAreEscaped() {
        let text = ics([session("ENG", .monday, 8 * 60, 10 * 60,
                                 description: "Reading, Writing; Speaking", faculty: "")])
        XCTAssertTrue(text.contains("DESCRIPTION:Reading\\, Writing\\; Speaking"),
                      "commas/semicolons not escaped in:\n\(text)")
    }

    func testFacultyJoinedIntoDescription() {
        let text = ics([session("ENG", .monday, 8 * 60, 10 * 60,
                                 description: "English", faculty: "REYES\\, MARIA")])
        // Backslash and comma both escaped, newline between description and faculty.
        XCTAssertTrue(text.contains("DESCRIPTION:English\\nREYES\\\\\\, MARIA"),
                      "faculty not joined/escaped in:\n\(text)")
    }
}
