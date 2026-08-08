import XCTest
@testable import PUPSISPortal

/// The pure Google event builder — summary/RRULE/tag/skip rules — without the
/// network. The REST calls themselves are verified by running the app.
@MainActor
final class GoogleCalendarClientTests: XCTestCase {
    private var utc: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    private var weekStart: Date { utc.date(from: DateComponents(year: 2026, month: 8, day: 3))! }
    private var termEnd: Date { utc.date(from: DateComponents(year: 2026, month: 8, day: 31))! }
    private var tz: TimeZone { TimeZone(identifier: "UTC")! }

    private func session(_ code: String, _ day: Weekday, _ start: Int, _ end: Int) -> ClassSession {
        ClassSession(subjectCode: code, description: "Desc", faculty: "SANTOS, JUAN",
                     day: day, start: start, end: end)
    }

    private func event(_ session: ClassSession, _ status: SessionStatus) -> GoogleEvent? {
        GoogleCalendarClient.event(for: session, status: status, weekStart: weekStart,
                                   until: termEnd, calendar: utc, timeZone: tz)
    }

    func testRegularClassBuildsATaggedRecurringEvent() {
        let e = event(session("PHYS", .thursday, 13 * 60, 15 * 60), .regular)
        XCTAssertEqual(e?.summary, "PHYS")
        XCTAssertNil(e?.location)
        XCTAssertEqual(e?.start.dateTime, "2026-08-06T13:00:00Z")
        XCTAssertEqual(e?.end.dateTime, "2026-08-06T15:00:00Z")
        XCTAssertEqual(e?.recurrence, ["RRULE:FREQ=WEEKLY;UNTIL=20260831T235959Z;BYDAY=TH"])
        XCTAssertEqual(e?.extendedProperties.private[GoogleCalendarClient.tagKey],
                       GoogleCalendarClient.tagValue)
    }

    func testVacantClassIsSkipped() {
        XCTAssertNil(event(session("SKIP", .monday, 8 * 60, 10 * 60), .vacant))
    }

    func testOnlineClassIsMarked() {
        let e = event(session("CS", .monday, 8 * 60, 10 * 60), .online)
        XCTAssertEqual(e?.summary, "CS (Online)")
        XCTAssertEqual(e?.location, "Online")
    }

    /// The exported body must be valid JSON with the tag nested under
    /// extendedProperties.private, which is how a re-export finds its own events.
    func testEncodesToJSONWithPrivateTag() throws {
        let e = try XCTUnwrap(event(session("MATH", .monday, 8 * 60, 10 * 60), .regular))
        let data = try JSONEncoder().encode(e)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let ext = obj?["extendedProperties"] as? [String: Any]
        let priv = ext?["private"] as? [String: String]
        XCTAssertEqual(priv?["pupsisportal"], "1")
    }
}
