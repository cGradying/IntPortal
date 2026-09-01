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

    // MARK: exportableDeadlines

    private func item(
        topic: String = "Topic", date: Date? = Date(), type: SyllabusItemType = .exam
    ) -> SyllabusItem {
        SyllabusItem(subjectCode: "MATH01", topic: topic, date: date, type: type, source: .imported)
    }

    func testExportableDeadlinesKeepsDatedNonLectureItems() {
        let deadline = item(type: .exam)
        XCTAssertEqual(CalendarBridge.exportableDeadlines([deadline]).map(\.id), [deadline.id])
    }

    func testExportableDeadlinesDropsLectureTopicsEvenWhenDated() {
        let lecture = item(type: .lecture)
        XCTAssertTrue(CalendarBridge.exportableDeadlines([lecture]).isEmpty)
    }

    func testExportableDeadlinesDropsUndatedItemsRegardlessOfType() {
        let undated = item(date: nil, type: .quiz)
        XCTAssertTrue(CalendarBridge.exportableDeadlines([undated]).isEmpty)
    }

    func testExportableDeadlinesKeepsQuizAndProjectToo() {
        let quiz = item(type: .quiz)
        let project = item(type: .project)
        let result = CalendarBridge.exportableDeadlines([quiz, project])
        XCTAssertEqual(Set(result.map(\.id)), Set([quiz.id, project.id]))
    }
}
