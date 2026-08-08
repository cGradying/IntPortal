import XCTest
@testable import PUPSISPortal

/// Notes persistence. Points the store at a temp file so nothing touches the
/// real Application Support notes.
@MainActor
final class NotesStoreTests: XCTestCase {
    private var url: URL!

    override func setUp() {
        super.setUp()
        url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("notes-test-\(UUID().uuidString).json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: url)
        super.tearDown()
    }

    func testSetAndGet() {
        let store = NotesStore(url: url)
        store.setText("bring calculator", for: "class:MATH")

        XCTAssertEqual(store.text(for: "class:MATH"), "bring calculator")
        XCTAssertTrue(store.hasNote(for: "class:MATH"))
        XCTAssertFalse(store.hasNote(for: "class:PHYS"))
    }

    func testEmptyTextDeletesTheNote() {
        let store = NotesStore(url: url)
        store.setText("temp", for: "day:2026-08-08")
        store.setText("   \n ", for: "day:2026-08-08")

        XCTAssertFalse(store.hasNote(for: "day:2026-08-08"))
        XCTAssertNil(store.note(for: "day:2026-08-08"))
        XCTAssertEqual(store.text(for: "day:2026-08-08"), "")
    }

    /// Whitespace-only content isn't a note, so no dot appears for it.
    func testWhitespaceIsNotANote() {
        let store = NotesStore(url: url)
        store.setText("   ", for: "class:CS")
        XCTAssertFalse(store.hasNote(for: "class:CS"))
    }

    /// A fresh store reads what the last one wrote.
    func testPersistsAcrossInstances() {
        let first = NotesStore(url: url)
        first.setText("study group at 3", for: "event:evt-123")

        let second = NotesStore(url: url)
        XCTAssertEqual(second.text(for: "event:evt-123"), "study group at 3")
    }

    func testMissingFileLoadsEmpty() {
        let store = NotesStore(url: url)
        XCTAssertTrue(store.notes.isEmpty)
    }
}
