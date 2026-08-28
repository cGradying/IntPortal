import XCTest
@testable import PUPSISPortal

/// Syllabus persistence + status derivation. Points the store at a temp file,
/// same convention as `NotesStoreTests`.
@MainActor
final class SyllabusStoreTests: XCTestCase {
    private var url: URL!

    override func setUp() {
        super.setUp()
        url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("syllabus-test-\(UUID().uuidString).json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: url)
        super.tearDown()
    }

    private func item(
        subject: String = "MATH01", week: Int? = 3, topic: String = "Chain rule",
        date: Date? = nil, type: SyllabusItemType = .lecture, source: SyllabusItemSource = .imported
    ) -> SyllabusItem {
        SyllabusItem(subjectCode: subject, week: week, topic: topic, date: date, type: type, source: source)
    }

    func testAddAndReadBackBySubject() {
        let store = SyllabusStore(url: url)
        store.addItem(item(subject: "MATH01", topic: "Limits"))
        store.addItem(item(subject: "MATH01", topic: "Derivatives"))
        store.addItem(item(subject: "PHYS01", topic: "Kinematics"))

        XCTAssertEqual(store.items(for: "MATH01").map(\.topic), ["Limits", "Derivatives"])
        XCTAssertEqual(store.items(for: "PHYS01").map(\.topic), ["Kinematics"])
        XCTAssertEqual(store.items(for: "COMP01"), [])
        XCTAssertEqual(store.allItems().count, 3)
    }

    func testUpdateItemInPlace() {
        let store = SyllabusStore(url: url)
        let added = store.addItem(item(topic: "Draft topic"))

        var updated = added
        updated.topic = "Final topic"
        updated.week = 4
        store.updateItem(updated)

        XCTAssertEqual(store.items(for: "MATH01").count, 1)
        XCTAssertEqual(store.items(for: "MATH01").first?.topic, "Final topic")
        XCTAssertEqual(store.items(for: "MATH01").first?.week, 4)
    }

    /// Changing `subjectCode` on update moves the item to the new subject's
    /// list rather than leaving a stale duplicate behind on the old one.
    func testUpdateItemMovesBetweenSubjectsOnSubjectCodeChange() {
        let store = SyllabusStore(url: url)
        let added = store.addItem(item(subject: "MATH01"))

        var moved = added
        moved.subjectCode = "PHYS01"
        store.updateItem(moved)

        XCTAssertEqual(store.items(for: "MATH01"), [])
        XCTAssertEqual(store.items(for: "PHYS01").count, 1)
        XCTAssertEqual(store.items(for: "PHYS01").first?.id, added.id)
    }

    func testRemoveItem() {
        let store = SyllabusStore(url: url)
        let added = store.addItem(item())
        store.addItem(item(topic: "Stays"))

        store.removeItem(added.id, subjectCode: "MATH01")

        XCTAssertEqual(store.items(for: "MATH01").map(\.topic), ["Stays"])
    }

    func testPersistsAcrossInstances() {
        let store = SyllabusStore(url: url)
        store.addItem(item(topic: "Limits"))

        let reloaded = SyllabusStore(url: url)
        XCTAssertEqual(reloaded.items(for: "MATH01").map(\.topic), ["Limits"])
    }

    func testMissingFileLoadsEmpty() {
        let store = SyllabusStore(url: url)
        XCTAssertEqual(store.allItems(), [])
    }

    func testWipeAllClears() {
        let store = SyllabusStore(url: url)
        store.addItem(item())
        store.wipeAll()
        XCTAssertEqual(store.allItems(), [])

        let reloaded = SyllabusStore(url: url)
        XCTAssertEqual(reloaded.allItems(), [])
    }

    // MARK: Status derivation

    private let calendar = Calendar.current
    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d))!
    }
    /// A trivial "week" for these tests: same calendar week number == same week.
    private func weekOf(_ d: Date) -> Date {
        let comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: d)
        return calendar.date(from: comps)!
    }

    func testPastDateIsDone() {
        let past = item(date: date(2026, 8, 1))
        XCTAssertEqual(past.status(now: date(2026, 8, 20), weekOf: weekOf), .done)
    }

    func testSameWeekIsOngoing() {
        // 2026-08-20 is a Thursday; 2026-08-17 is the Monday of the same week.
        let thisWeek = item(date: date(2026, 8, 17))
        XCTAssertEqual(thisWeek.status(now: date(2026, 8, 20), weekOf: weekOf), .ongoing)
    }

    func testFutureDateIsUpcoming() {
        let future = item(date: date(2026, 9, 1))
        XCTAssertEqual(future.status(now: date(2026, 8, 20), weekOf: weekOf), .upcoming)
    }

    func testNoDateIsUpcoming() {
        let noDate = item(date: nil)
        XCTAssertEqual(noDate.status(now: date(2026, 8, 20), weekOf: weekOf), .upcoming)
    }

    func testCompletedOverrideTrueForcesDoneEvenInTheFuture() {
        var future = item(date: date(2026, 9, 1))
        future.completedOverride = true
        XCTAssertEqual(future.status(now: date(2026, 8, 20), weekOf: weekOf), .done)
    }

    func testCompletedOverrideFalseKeepsItNotDoneEvenPastItsDate() {
        var past = item(date: date(2026, 8, 1))
        past.completedOverride = false
        // Not done, but still date-based ongoing/upcoming — past its date and
        // not this week, so upcoming (not "done").
        XCTAssertEqual(past.status(now: date(2026, 8, 20), weekOf: weekOf), .upcoming)
    }
}
