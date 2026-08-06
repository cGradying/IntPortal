import XCTest
@testable import PUPSISPortal

/// The status → calendar-export rule. Pure, so it's tested here rather than
/// against a live EventKit store.
final class CalendarExportTests: XCTestCase {
    func testRegularClassesAreWrittenPlain() {
        XCTAssertEqual(CalendarBridge.ClassExport.plan(for: .regular),
                       .event(titleSuffix: nil, location: nil))
    }

    /// Online is marked, not hidden — you still have the class, just remotely.
    func testOnlineClassesAreMarkedOnline() {
        XCTAssertEqual(CalendarBridge.ClassExport.plan(for: .online),
                       .event(titleSuffix: " (Online)", location: "Online"))
    }

    /// Vacant-all-term classes are deliberately left off the calendar.
    func testVacantClassesAreSkipped() {
        XCTAssertEqual(CalendarBridge.ClassExport.plan(for: .vacant), .skip)
    }
}
