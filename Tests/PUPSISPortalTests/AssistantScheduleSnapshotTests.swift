import XCTest
@testable import PUPSISPortal

/// The date-reference table is the whole point of this type — it's what
/// lets the model resolve "tomorrow" by lookup instead of computing it
/// (unreliable even when told today's date). Pinned against a known date so
/// weekday/date pairing is checked exactly, not just "some string appeared."
final class AssistantScheduleSnapshotTests: XCTestCase {
    /// A Wednesday, deliberately — exercises both "today"/"tomorrow" labels
    /// and a plain mid-week day in the same 14-day window.
    private static let wednesday = Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 8, day: 26, hour: 14, minute: 30))!

    func testDateReferenceCoversFourteenDaysStartingToday() {
        let snapshot = AssistantScheduleSnapshot(
            now: Self.wednesday, sessions: [], termEnd: nil, status: { _ in .regular }, time: { ($0.start, $0.end) }
        )
        XCTAssertEqual(snapshot.dateReference.count, 14)
        XCTAssertEqual(snapshot.dateReference[0].date, "2026-08-26")
        XCTAssertEqual(snapshot.dateReference[0].weekday, "WED")
        XCTAssertEqual(snapshot.dateReference[0].label, "today")
        XCTAssertEqual(snapshot.dateReference[1].date, "2026-08-27")
        XCTAssertEqual(snapshot.dateReference[1].weekday, "THU")
        XCTAssertEqual(snapshot.dateReference[1].label, "tomorrow")
        XCTAssertNil(snapshot.dateReference[2].label)
    }

    func testRenderedIncludesTodaysDateAndTime() {
        let snapshot = AssistantScheduleSnapshot(
            now: Self.wednesday, sessions: [], termEnd: nil, status: { _ in .regular }, time: { ($0.start, $0.end) }
        )
        XCTAssertTrue(snapshot.rendered.contains("2026-08-26"))
        XCTAssertTrue(snapshot.rendered.contains("14:30"))
    }

    /// The pattern shown must be the *term-wide* resolution, not just
    /// today's — that's the "remembers the schedule ranging months" part.
    func testRenderedShowsEveryClassNotJustToday() {
        let sessions = [
            ClassSession(subjectCode: "COMP 20073", description: "", faculty: "", day: .monday, start: 480, end: 600),
            ClassSession(subjectCode: "MATH 10123", description: "", faculty: "", day: .friday, start: 780, end: 900),
        ]
        let snapshot = AssistantScheduleSnapshot(
            now: Self.wednesday, sessions: sessions, termEnd: nil,
            status: { _ in .regular }, time: { ($0.start, $0.end) }
        )
        XCTAssertTrue(snapshot.rendered.contains("COMP 20073"))
        XCTAssertTrue(snapshot.rendered.contains("MATH 10123"))
        XCTAssertTrue(snapshot.rendered.contains("MON"))
        XCTAssertTrue(snapshot.rendered.contains("FRI"))
    }

    /// A permanently-moved class (`set_class_time`) must show its moved
    /// time, not the scraped one — otherwise the model would propose
    /// conflicting times right after the tool that's supposed to fix this.
    func testRenderedUsesTheResolvedTimeNotTheScrapedOne() {
        let session = ClassSession(subjectCode: "COMP 20073", description: "", faculty: "", day: .monday, start: 480, end: 600)
        let snapshot = AssistantScheduleSnapshot(
            now: Self.wednesday, sessions: [session], termEnd: nil,
            status: { _ in .regular }, time: { _ in (540, 660) } // moved an hour later
        )
        XCTAssertTrue(snapshot.rendered.contains("9AM"), "expected the moved 9AM start, not the scraped 8AM")
        XCTAssertFalse(snapshot.rendered.contains("8AM-10AM"))
    }

    func testJSONDataRoundTrips() throws {
        let sessions = [ClassSession(subjectCode: "COMP 20073", description: "", faculty: "", day: .monday, start: 480, end: 600)]
        let snapshot = AssistantScheduleSnapshot(
            now: Self.wednesday, sessions: sessions, termEnd: Self.wednesday,
            status: { _ in .vacant }, time: { ($0.start, $0.end) }
        )
        let data = try XCTUnwrap(snapshot.jsonData)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNotNil(json["now"])
        XCTAssertNotNil(json["termEnd"])
        let pattern = try XCTUnwrap(json["weeklyPattern"] as? [[String: Any]])
        XCTAssertEqual(pattern.first?["status"] as? String, "Vacant")
    }
}
