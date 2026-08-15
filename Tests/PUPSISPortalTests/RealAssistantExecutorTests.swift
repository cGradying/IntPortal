import XCTest
@testable import PUPSISPortal

/// Everything here uses a temp-file `NotesStore` (never the real Application
/// Support path) and a fresh, never-`requestAccess`'d `CalendarBridge` — the
/// latter's `writableCalendars` starts empty, which is exactly what lets the
/// add_event validation paths be tested without touching real EventKit.
///
/// `PortalController` isn't constructed here — its `init()` reads the user's
/// real cached schedule/grades files (see `PortalController.swift:57-63`),
/// which isn't safe to do from a unit test. `read_week`/`read_grades` are thin
/// formatting over `ClassSession`/`GradeReport`, both already covered by their
/// own test suites; the guard-heavy paths (notes, add_event validation) are
/// what actually needed dedicated coverage here.
@MainActor
final class RealAssistantExecutorTests: XCTestCase {
    private var notesURL: URL!
    private var notesStore: NotesStore!

    override func setUpWithError() throws {
        notesURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("RealAssistantExecutorTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("notes.json")
        notesStore = NotesStore(url: notesURL)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: notesURL.deletingLastPathComponent())
    }

    private func executor(openKey: String? = nil) -> RealAssistantExecutor {
        RealAssistantExecutor(
            notes: notesStore,
            editor: EventEditor(bridge: CalendarBridge()),
            calendar: CalendarBridge(),
            portal: PortalController(),
            preferences: Preferences(defaults: UserDefaults(suiteName: "RealAssistantExecutorTests-\(UUID().uuidString)")!),
            openNoteKey: { openKey }
        )
    }

    // MARK: read_note / list_notes

    func testReadNoteReturnsExistingText() async {
        notesStore.setText("Lecture 1: intro to arrays.", for: "class:COMP 001")
        let result = await executor().execute(AssistantAction(tool: "read_note", args: ["key": .string("class:COMP 001")]))
        XCTAssertTrue(result.ok)
        XCTAssertTrue(result.message.contains("intro to arrays"))
    }

    func testReadNoteFallsBackToTheOpenNoteWhenNoKeyGiven() async {
        notesStore.setText("today's scratchpad", for: "day:2026-08-15")
        let result = await executor(openKey: "day:2026-08-15").execute(AssistantAction(tool: "read_note"))
        XCTAssertTrue(result.ok)
        XCTAssertTrue(result.message.contains("scratchpad"))
    }

    func testReadNoteFailsWithNoKeyAndNoOpenNote() async {
        let result = await executor(openKey: nil).execute(AssistantAction(tool: "read_note"))
        XCTAssertFalse(result.ok)
    }

    func testListNotesReportsVaultAndClassNotes() async {
        _ = notesStore.addFile(name: "Midterm plan", to: nil)
        notesStore.setText("x", for: "class:COMP 001")
        let result = await executor().execute(AssistantAction(tool: "list_notes"))
        XCTAssertTrue(result.ok)
        XCTAssertTrue(result.message.contains("Midterm plan"))
        XCTAssertTrue(result.message.contains("class:COMP 001"))
    }

    // MARK: append_note — the guard that matters most

    func testAppendNoteAddsToExistingText() async {
        notesStore.setText("Lecture 1.", for: "class:COMP 001")
        let action = AssistantAction(tool: "append_note",
            args: ["key": .string("class:COMP 001"), "text": .string("Review pointers.")])
        let result = await executor().execute(action)
        XCTAssertTrue(result.ok)
        let text = notesStore.text(for: "class:COMP 001")
        XCTAssertTrue(text.contains("Lecture 1."))
        XCTAssertTrue(text.contains("Review pointers."))
    }

    func testAppendNoteToEmptyNoteJustSetsTheText() async {
        let action = AssistantAction(tool: "append_note", args: ["key": .string("class:COMP 002"), "text": .string("First entry.")])
        _ = await executor().execute(action)
        XCTAssertEqual(notesStore.text(for: "class:COMP 002"), "First entry.")
    }

    /// The one path that would otherwise reach `NotesStore.setText` with
    /// blank text and delete the note (`NotesStore.swift:88`). Must refuse
    /// before ever calling into the store.
    func testAppendNoteRefusesWhitespaceOnlyText() async {
        notesStore.setText("existing content", for: "class:COMP 001")
        let action = AssistantAction(tool: "append_note", args: ["key": .string("class:COMP 001"), "text": .string("   ")])
        let result = await executor().execute(action)
        XCTAssertFalse(result.ok)
        XCTAssertEqual(notesStore.text(for: "class:COMP 001"), "existing content", "must not touch the note at all")
    }

    func testAppendNoteRefusesMissingText() async {
        let result = await executor().execute(AssistantAction(tool: "append_note", args: ["key": .string("class:COMP 001")]))
        XCTAssertFalse(result.ok)
    }

    func testAppendNoteRefusesWithNoResolvableKey() async {
        let result = await executor(openKey: nil).execute(
            AssistantAction(tool: "append_note", args: ["text": .string("hello")]))
        XCTAssertFalse(result.ok)
    }

    // MARK: create_note

    func testCreateNoteMakesANewVaultFileWithText() async {
        let action = AssistantAction(tool: "create_note", args: ["name": .string("Exam prep"), "text": .string("Chapter 4.")])
        let result = await executor().execute(action)
        XCTAssertTrue(result.ok)
        XCTAssertTrue(notesStore.vault.contains { $0.name == "Exam prep" })
        let key = notesStore.vault.first { $0.name == "Exam prep" }?.noteKey
        XCTAssertEqual(key.map(notesStore.text(for:)), "Chapter 4.")
    }

    func testCreateNoteWithNoTextStillCreatesTheFile() async {
        let action = AssistantAction(tool: "create_note", args: ["name": .string("Blank note")])
        let result = await executor().execute(action)
        XCTAssertTrue(result.ok)
        XCTAssertTrue(notesStore.vault.contains { $0.name == "Blank note" })
    }

    // MARK: add_event — validation, no real EventKit write

    func testAddEventRefusesMissingDate() async {
        let action = AssistantAction(tool: "add_event", args: ["title": .string("Study"), "start": .int(600), "end": .int(660)])
        let result = await executor().execute(action)
        XCTAssertFalse(result.ok)
    }

    func testAddEventRefusesMalformedDate() async {
        let action = AssistantAction(tool: "add_event",
            args: ["title": .string("Study"), "date": .string("not-a-date"), "start": .int(600), "end": .int(660)])
        let result = await executor().execute(action)
        XCTAssertFalse(result.ok)
    }

    func testAddEventRefusesEndBeforeStart() async {
        let action = AssistantAction(tool: "add_event",
            args: ["title": .string("Study"), "date": .string("2026-08-18"), "start": .int(660), "end": .int(600)])
        let result = await executor().execute(action)
        XCTAssertFalse(result.ok)
    }

    func testAddEventRefusesMissingTimes() async {
        let action = AssistantAction(tool: "add_event", args: ["title": .string("Study"), "date": .string("2026-08-18")])
        let result = await executor().execute(action)
        XCTAssertFalse(result.ok)
    }

    /// A fresh `CalendarBridge` that's never called `requestAccess()` has an
    /// empty `writableCalendars` — the exact "nowhere to put this" case a
    /// real machine with no writable calendar would also hit.
    func testAddEventRefusesWhenNoWritableCalendarExists() async {
        let action = AssistantAction(tool: "add_event",
            args: ["title": .string("Study"), "date": .string("2026-08-18"), "start": .int(600), "end": .int(660)])
        let result = await executor().execute(action)
        XCTAssertFalse(result.ok)
        XCTAssertTrue(result.message.lowercased().contains("calendar"))
    }

    // MARK: Unknown tool

    func testUnknownToolFailsCleanlyRatherThanCrashing() async {
        let result = await executor().execute(AssistantAction(tool: "delete_everything", args: [:]))
        XCTAssertFalse(result.ok)
    }
}
