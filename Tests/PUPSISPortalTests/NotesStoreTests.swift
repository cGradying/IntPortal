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

    /// A title is recorded for history, and a later nil-title edit keeps it
    /// rather than wiping it.
    func testTitleIsStoredAndPreservedAcrossNilEdits() {
        let store = NotesStore(url: url)
        store.setText("draft", for: "class:MATH", title: "MATH 101")
        XCTAssertEqual(store.note(for: "class:MATH")?.title, "MATH 101")

        store.setText("draft 2", for: "class:MATH") // no title passed
        XCTAssertEqual(store.note(for: "class:MATH")?.title, "MATH 101")

        // Survives a reload from disk.
        let reloaded = NotesStore(url: url)
        XCTAssertEqual(reloaded.note(for: "class:MATH")?.title, "MATH 101")
    }

    /// Folders and files nest, files carry a note key, and the whole tree +
    /// contents survive a reload — including the legacy bare-dict migration.
    func testVaultCreateNestAndPersist() {
        let store = NotesStore(url: url)
        let folder = store.addFolder(name: "Math", to: nil)
        let fileKey = store.addFile(name: "Limits", to: folder)
        store.setText("lim x->0", for: fileKey, title: "Limits")

        // Tree shape.
        XCTAssertEqual(store.vault.count, 1)
        XCTAssertEqual(store.vault.first?.name, "Math")
        XCTAssertEqual(store.vault.first?.children?.first?.noteKey, fileKey)
        XCTAssertEqual(store.vaultName(forKey: fileKey), "Limits")

        // Reloads from disk with the same tree and text.
        let reloaded = NotesStore(url: url)
        XCTAssertEqual(reloaded.vault.first?.children?.first?.name, "Limits")
        XCTAssertEqual(reloaded.text(for: fileKey), "lim x->0")

        // Deleting the folder removes the subtree and its notes.
        reloaded.deleteItem(folder)
        XCTAssertTrue(reloaded.vault.isEmpty)
        XCTAssertEqual(reloaded.text(for: fileKey), "")
    }

    func testMoveFileBetweenFoldersAndRejectCycles() {
        let store = NotesStore(url: url)
        let a = store.addFolder(name: "A", to: nil)
        let b = store.addFolder(name: "B", to: nil)
        let fileKey = store.addFile(name: "note", to: a)
        let fileID = store.vault.first { $0.id == a }?.children?.first?.id

        // Move the file from A into B.
        store.move(fileID!, to: b)
        XCTAssertTrue(store.vault.first { $0.id == a }?.children?.isEmpty ?? false)
        XCTAssertEqual(store.vault.first { $0.id == b }?.children?.first?.noteKey, fileKey)

        // Moving a folder into its own descendant is rejected (no detach/loss).
        let child = store.addFolder(name: "child", to: a)
        store.move(a, to: child)
        XCTAssertNotNil(store.vault.first { $0.id == a })
        XCTAssertNotNil(store.vault.first { $0.id == a }?.children?.first { $0.id == child })
    }

    func testLegacyBareDictStillLoads() throws {
        // A pre-vault notes.json is a bare [String: Note] dict.
        let legacy = ["day:2026-08-08": Note(text: "old", updated: Date(), title: nil)]
        try JSONEncoder().encode(legacy).write(to: url)

        let store = NotesStore(url: url)
        XCTAssertEqual(store.text(for: "day:2026-08-08"), "old")
        XCTAssertTrue(store.vault.isEmpty)
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
