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

    private func executor(
        openKey: String? = nil,
        llamaCppClient: LlamaCppClient = LlamaCppClient(),
        ensureServerRunning: @escaping () async -> Bool = { true }
    ) -> RealAssistantExecutor {
        RealAssistantExecutor(
            notes: notesStore,
            editor: EventEditor(bridge: CalendarBridge()),
            calendar: CalendarBridge(),
            portal: PortalController(),
            preferences: Preferences(defaults: UserDefaults(suiteName: "RealAssistantExecutorTests-\(UUID().uuidString)")!),
            openNoteKey: { openKey },
            llamaCppClient: llamaCppClient,
            ensureServerRunning: ensureServerRunning
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

    // MARK: search_notes

    func testSearchNotesFindsAMatchWithASnippet() async {
        notesStore.setText("Lecture 1: intro to arrays and linked lists.", for: "class:COMP 001")
        let result = await executor().execute(AssistantAction(tool: "search_notes", args: ["query": .string("linked lists")]))
        XCTAssertTrue(result.ok)
        XCTAssertTrue(result.message.contains("linked lists"))
        XCTAssertTrue(result.message.contains("COMP 001"))
    }

    func testSearchNotesIsCaseInsensitive() async {
        notesStore.setText("Review Recursion before the exam.", for: "class:COMP 001")
        let result = await executor().execute(AssistantAction(tool: "search_notes", args: ["query": .string("recursion")]))
        XCTAssertTrue(result.ok)
        XCTAssertTrue(result.message.lowercased().contains("recursion"))
    }

    func testSearchNotesReportsNoMatches() async {
        notesStore.setText("unrelated content", for: "class:COMP 001")
        let result = await executor().execute(AssistantAction(tool: "search_notes", args: ["query": .string("nonexistent")]))
        XCTAssertTrue(result.ok)
        XCTAssertTrue(result.message.contains("No notes matched"))
    }

    func testSearchNotesRefusesEmptyQuery() async {
        let result = await executor().execute(AssistantAction(tool: "search_notes", args: [:]))
        XCTAssertFalse(result.ok)
    }

    // MARK: ask_notes — the grounded-answer tool

    func testAskNotesReturnsTheModelsGroundedAnswer() async {
        notesStore.setText("Recursion has a base case and a recursive case.", for: "class:COMP 001")
        let client = LlamaCppClient(send: { _ in
            (Data(#"{"choices":[{"message":{"content":"A base case and a recursive case."}}]}"#.utf8), 200)
        })
        let result = await executor(llamaCppClient: client)
            .execute(AssistantAction(tool: "ask_notes", args: ["query": .string("recursion")]))

        XCTAssertTrue(result.ok)
        XCTAssertEqual(result.message, "A base case and a recursive case.")
    }

    /// Nothing matched — the model is never even called, since there's
    /// nothing to ground an answer in.
    func testAskNotesSkipsTheModelWhenNothingMatches() async {
        notesStore.setText("unrelated content", for: "class:COMP 001")
        var called = false
        let client = LlamaCppClient(send: { body in
            called = true
            return (Data(#"{"choices":[{"message":{"content":"x"}}]}"#.utf8), 200)
        })
        let result = await executor(llamaCppClient: client)
            .execute(AssistantAction(tool: "ask_notes", args: ["query": .string("nonexistent")]))

        XCTAssertTrue(result.ok)
        XCTAssertTrue(result.message.contains("nothing to answer from"))
        XCTAssertFalse(called, "the model must not be called with no context")
    }

    func testAskNotesRefusesEmptyQuery() async {
        let result = await executor().execute(AssistantAction(tool: "ask_notes", args: [:]))
        XCTAssertFalse(result.ok)
    }

    /// The server can't be started — fails clearly, and never even tries the
    /// client, since there's nothing to talk to.
    func testAskNotesFailsClearlyWhenTheServerCannotBeStarted() async {
        notesStore.setText("Recursion has a base case.", for: "class:COMP 001")
        var clientCalled = false
        let client = LlamaCppClient(send: { _ in
            clientCalled = true
            return (Data(#"{"choices":[{"message":{"content":"x"}}]}"#.utf8), 200)
        })
        let result = await executor(llamaCppClient: client, ensureServerRunning: { false })
            .execute(AssistantAction(tool: "ask_notes", args: ["query": .string("recursion")]))

        XCTAssertFalse(result.ok)
        XCTAssertFalse(clientCalled, "must not talk to a server that failed to start")
    }

    /// Starting the server is skipped entirely when nothing matched — no
    /// point paying a cold start for a question there's nothing to answer.
    func testAskNotesNeverStartsTheServerWhenNothingMatches() async {
        notesStore.setText("unrelated content", for: "class:COMP 001")
        var startAttempted = false
        let result = await executor(ensureServerRunning: { startAttempted = true; return true })
            .execute(AssistantAction(tool: "ask_notes", args: ["query": .string("nonexistent")]))

        XCTAssertTrue(result.ok)
        XCTAssertFalse(startAttempted)
    }

    /// The server isn't running (or unreachable) — fails clearly rather than
    /// crashing or silently returning nothing.
    func testAskNotesFailsClearlyWhenTheServerIsUnreachable() async {
        notesStore.setText("Recursion has a base case.", for: "class:COMP 001")
        struct Boom: Error {}
        let client = LlamaCppClient(send: { _ in throw Boom() })
        let result = await executor(llamaCppClient: client)
            .execute(AssistantAction(tool: "ask_notes", args: ["query": .string("recursion")]))

        XCTAssertFalse(result.ok)
        XCTAssertTrue(result.message.lowercased().contains("llama-server") || result.message.lowercased().contains("reach"))
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
