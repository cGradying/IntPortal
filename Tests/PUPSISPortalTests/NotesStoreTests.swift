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

    // MARK: key(forName:) / noteNames() — resolving what /read and /summary type in

    func testKeyForNameMatchesVaultFileCaseInsensitively() {
        let store = NotesStore(url: url)
        let key = store.addFile(name: "Physics Midterm", to: nil)
        XCTAssertEqual(store.key(forName: "physics midterm"), key)
        XCTAssertEqual(store.key(forName: "PHYSICS MIDTERM"), key)
    }

    func testKeyForNameMatchesClassAndDayKeys() {
        let store = NotesStore(url: url)
        store.setText("bring calculator", for: "class:MATH101")
        XCTAssertEqual(store.key(forName: "MATH101"), "class:MATH101")
        XCTAssertEqual(store.key(forName: "math101"), "class:MATH101")
    }

    func testKeyForNameReturnsNilForAMiss() {
        let store = NotesStore(url: url)
        store.setText("draft", for: "class:MATH")
        XCTAssertNil(store.key(forName: "nonsense"))
        XCTAssertNil(store.key(forName: "")) // blank input, nothing to match
    }

    func testNoteNamesListsVaultAndScheduleNotes() {
        let store = NotesStore(url: url)
        store.addFile(name: "Limits", to: nil)
        store.setText("bring calculator", for: "class:MATH101")
        XCTAssertEqual(store.noteNames(), ["Limits", "class:MATH101"])
    }

    // MARK: colour labels / RAG inclusion

    func testSetColorRoundTripsThroughDisk() {
        let store = NotesStore(url: url)
        let id = store.addFolder(name: "Books", to: nil)
        store.setColor("#FF0000", for: id)
        XCTAssertEqual(store.node(withID: id)?.colorHex, "#FF0000")

        let second = NotesStore(url: url)
        XCTAssertEqual(second.node(withID: id)?.colorHex, "#FF0000")

        store.setColor(nil, for: id)
        XCTAssertNil(store.node(withID: id)?.colorHex)
    }

    func testEverythingIsRAGIncludedByDefault() {
        let store = NotesStore(url: url)
        let key = store.addFile(name: "Sapiens", to: nil)
        store.setText("about the agricultural revolution", for: key)
        XCTAssertTrue(store.ragIncludedKeys().contains(key))
    }

    func testExcludingAFileDropsItFromRAGKeys() {
        let store = NotesStore(url: url)
        let key = store.addFile(name: "Sapiens", to: nil)
        let id = store.vault.first { $0.noteKey == key }!.id
        store.setRAGExcluded(true, for: id)
        XCTAssertFalse(store.ragIncludedKeys().contains(key))

        store.setRAGExcluded(false, for: id)
        XCTAssertTrue(store.ragIncludedKeys().contains(key))
    }

    /// Excluding a folder excludes its whole subtree — the inherited-toggle
    /// behavior the right-click menu promises.
    func testExcludingAFolderExcludesEveryDescendantFile() {
        let store = NotesStore(url: url)
        let folderID = store.addFolder(name: "Books", to: nil)
        let key = store.addFile(name: "Sapiens", to: folderID)

        store.setRAGExcluded(true, for: folderID)
        XCTAssertFalse(store.ragIncludedKeys().contains(key))
    }

    func testClassAndDayNotesAreAlwaysRAGIncluded() {
        let store = NotesStore(url: url)
        store.setText("bring calculator", for: "class:MATH101")
        XCTAssertTrue(store.ragIncludedKeys().contains("class:MATH101"))
    }

    /// Old `notes.json` files (written before colour/RAG existed) decode fine
    /// and read as unlabeled + included.
    func testLegacyVaultNodeWithoutNewFieldsStillDecodes() throws {
        let legacyJSON = """
        {"notes":{},"vault":[{"id":"\(UUID().uuidString)","name":"Old note","isFolder":false,"noteKey":"vault:old"}]}
        """
        try legacyJSON.write(to: url, atomically: true, encoding: .utf8)

        let store = NotesStore(url: url)
        XCTAssertEqual(store.vault.first?.colorHex, nil)
        XCTAssertTrue(store.ragIncludedKeys().contains("vault:old"))
    }

    // MARK: wipeAll — Settings ▸ Misc "Delete All Notes"

    func testWipeAllClearsNotesAndVault() {
        let store = NotesStore(url: url)
        _ = store.addFile(name: "Sapiens", to: nil)
        store.setText("draft", for: "class:MATH")

        store.wipeAll(deleteImages: {}) // never touch the real note-images directory in a test

        XCTAssertTrue(store.notes.isEmpty)
        XCTAssertTrue(store.vault.isEmpty)
    }

    func testWipeAllPersists() {
        let store = NotesStore(url: url)
        _ = store.addFile(name: "Sapiens", to: nil)
        store.wipeAll(deleteImages: {})

        let reloaded = NotesStore(url: url)
        XCTAssertTrue(reloaded.notes.isEmpty)
        XCTAssertTrue(reloaded.vault.isEmpty)
    }
}
