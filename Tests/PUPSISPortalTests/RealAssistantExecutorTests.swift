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

    /// Offline embeddings by default — `search_notes`/`ask_notes` tests
    /// exercise the term-ranking fallback path deterministically, with no
    /// dependency on a real `llama-server`/embedding model being installed.
    /// Tests that care about the embedding path inject their own `client`.
    private static let offlineClient = LlamaCppClient(sendEmbed: { _ in throw URLError(.notConnectedToInternet) })

    private func executor(
        openKey: String? = nil,
        client: LlamaCppClient = offlineClient,
        ensureChatServerRunning: @escaping () async -> Bool = { true },
        ensureEmbedServerRunning: @escaping () async -> Bool = { true }
    ) -> RealAssistantExecutor {
        let preferences = Preferences(defaults: UserDefaults(suiteName: "RealAssistantExecutorTests-\(UUID().uuidString)")!)
        return RealAssistantExecutor(
            notes: notesStore,
            editor: EventEditor(bridge: CalendarBridge()),
            calendar: CalendarBridge(),
            portal: PortalController(),
            preferences: preferences,
            openNoteKey: { openKey },
            client: client,
            ensureChatServerRunning: ensureChatServerRunning,
            ensureEmbedServerRunning: ensureEmbedServerRunning
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
        XCTAssertEqual(result.sources, ["COMP 001"])
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
            (Data(#"{"choices":[{"message":{"content":"{\"answer\":\"A base case and a recursive case.\"}"}}]}"#.utf8), 200)
        }, sendEmbed: { _ in throw URLError(.notConnectedToInternet) })
        let result = await executor(client: client)
            .execute(AssistantAction(tool: "ask_notes", args: ["query": .string("recursion")]))

        XCTAssertTrue(result.ok)
        XCTAssertEqual(result.message, "A base case and a recursive case.")
        XCTAssertEqual(result.sources, ["COMP 001"])
    }

    /// Nothing matched — the model is never even called, since there's
    /// nothing to ground an answer in.
    func testAskNotesSkipsTheModelWhenNothingMatches() async {
        notesStore.setText("unrelated content", for: "class:COMP 001")
        var called = false
        let client = LlamaCppClient(send: { _ in
            called = true
            return (Data(#"{"choices":[{"message":{"content":"{\"answer\":\"x\"}"}}]}"#.utf8), 200)
        })
        let result = await executor(client: client)
            .execute(AssistantAction(tool: "ask_notes", args: ["query": .string("nonexistent")]))

        XCTAssertTrue(result.ok)
        XCTAssertTrue(result.message.contains("nothing to answer from"))
        XCTAssertFalse(called, "the model must not be called with no context")
    }

    // MARK: embedding-based retrieval — the semantic-match upgrade

    /// A fake `/v1/embeddings` keyed by exact input text, so a test can
    /// assign a deterministic vector to each string without depending on
    /// chunk/dict iteration order.
    private func embedClient(_ vectors: [String: [Double]], send: ((Data) async throws -> (Data, Int))? = nil) -> LlamaCppClient {
        LlamaCppClient(send: send, sendEmbed: { body in
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            let inputs = try XCTUnwrap(json["input"] as? [String])
            let embeddings = inputs.map { vectors[$0] ?? [0, 0] }
            let data = try JSONSerialization.data(withJSONObject: ["data": embeddings.map { ["embedding": $0] }])
            return (data, 200)
        })
    }

    /// Proves retrieval actually uses the embedding vectors, not a term-match
    /// fallback in disguise: the matching chunk shares *no* words with the
    /// query, and the decoy chunk is stuffed with the query's literal words —
    /// term ranking would pick the decoy, embeddings correctly pick the other.
    func testAskNotesPrefersEmbeddingSimilarityOverLiteralWordOverlap() async {
        notesStore.setText("Humans began farming and settling into villages during the Neolithic period.", for: "class:HIST")
        notesStore.setText("agricultural revolution agricultural revolution agricultural revolution (decoy, unrelated)", for: "class:DECOY")

        let query = "what does my note say about the agricultural revolution?"
        let client = embedClient(
            [
                query: [1, 0],
                "Humans began farming and settling into villages during the Neolithic period.": [0.95, 0.05],
                "agricultural revolution agricultural revolution agricultural revolution (decoy, unrelated)": [0, 1],
            ],
            send: { _ in (Data(#"{"choices":[{"message":{"content":"{\"answer\":\"Farming began and people settled into villages.\"}"}}]}"#.utf8), 200) }
        )

        let result = await executor(client: client)
            .execute(AssistantAction(tool: "ask_notes", args: ["query": .string(query)]))

        XCTAssertTrue(result.ok)
        XCTAssertTrue(result.sources.contains("HIST"))
        XCTAssertFalse(result.sources.contains("DECOY"))
    }

    /// If the embed call fails (no embedding model downloaded, server
    /// offline), retrieval falls back to term matching instead of dead-ending.
    func testSearchNotesFallsBackToTermMatchingWhenEmbeddingFails() async {
        notesStore.setText("Review recursion before the exam.", for: "class:COMP 001")
        let failingClient = LlamaCppClient(sendEmbed: { _ in throw URLError(.notConnectedToInternet) })

        let result = await executor(client: failingClient)
            .execute(AssistantAction(tool: "search_notes", args: ["query": .string("recursion")]))

        XCTAssertTrue(result.ok)
        XCTAssertTrue(result.message.contains("COMP 001"))
    }

    func testAskNotesRefusesEmptyQuery() async {
        let result = await executor().execute(AssistantAction(tool: "ask_notes", args: [:]))
        XCTAssertFalse(result.ok)
    }

    /// The chat server can't be started — fails clearly, and never even
    /// tries the client, since there's nothing to talk to.
    func testAskNotesFailsClearlyWhenTheServerCannotBeStarted() async {
        notesStore.setText("Recursion has a base case.", for: "class:COMP 001")
        var clientCalled = false
        let client = LlamaCppClient(send: { _ in
            clientCalled = true
            return (Data(#"{"choices":[{"message":{"content":"{\"answer\":\"x\"}"}}]}"#.utf8), 200)
        }, sendEmbed: { _ in throw URLError(.notConnectedToInternet) })
        let result = await executor(client: client, ensureChatServerRunning: { false })
            .execute(AssistantAction(tool: "ask_notes", args: ["query": .string("recursion")]))

        XCTAssertFalse(result.ok)
        XCTAssertFalse(clientCalled, "must not talk to a server that failed to start")
    }

    /// Starting the chat server is skipped entirely when nothing matched —
    /// no point paying a cold start for a question there's nothing to answer.
    func testAskNotesNeverStartsTheServerWhenNothingMatches() async {
        notesStore.setText("unrelated content", for: "class:COMP 001")
        var startAttempted = false
        let result = await executor(ensureChatServerRunning: { startAttempted = true; return true })
            .execute(AssistantAction(tool: "ask_notes", args: ["query": .string("nonexistent")]))

        XCTAssertTrue(result.ok)
        XCTAssertFalse(startAttempted)
    }

    /// The server isn't running (or unreachable) — fails clearly rather than
    /// crashing or silently returning nothing.
    func testAskNotesFailsClearlyWhenTheServerIsUnreachable() async {
        notesStore.setText("Recursion has a base case.", for: "class:COMP 001")
        struct Boom: Error {}
        let client = LlamaCppClient(send: { _ in throw Boom() }, sendEmbed: { _ in throw URLError(.notConnectedToInternet) })
        let result = await executor(client: client)
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

    func testAddEventWithRepeatDaysStillRefusesWhenNoWritableCalendarExists() async {
        // Confirms the new optional `repeat_days` arg doesn't skip the same
        // "somewhere to put this" guard `testAddEventRefusesWhenNoWritableCalendarExists`
        // already covers — the recurrence branch is parsed before that guard
        // fires, so this exercises it without ever touching real EventKit.
        let action = AssistantAction(tool: "add_event",
            args: ["title": .string("Study"), "date": .string("2026-08-18"), "start": .int(600), "end": .int(660),
                   "repeat_days": .string("mon,wed,fri")])
        let result = await executor().execute(action)
        XCTAssertFalse(result.ok)
        XCTAssertTrue(result.message.lowercased().contains("calendar"))
    }

    // MARK: move_event — validation, no real EventKit access
    //
    // Like add_event above, a fresh `CalendarBridge` never grants EventKit
    // access, so `calendar.events(on:calendarIDs:)` deterministically returns
    // `[]` — a real, OS-level permission gate, not a data cache like
    // `PortalController`'s (see the file header comment for why that one
    // stays untouched). That makes "no event found" the one outcome safely
    // testable here without a real calendar in the loop.

    func testMoveEventRefusesMissingTitle() async {
        let action = AssistantAction(tool: "move_event",
            args: ["date": .string("2026-08-18"), "new_date": .string("2026-08-19"), "new_start": .int(600), "new_end": .int(660)])
        let result = await executor().execute(action)
        XCTAssertFalse(result.ok)
    }

    func testMoveEventRefusesMalformedDate() async {
        let action = AssistantAction(tool: "move_event",
            args: ["title": .string("Dentist"), "date": .string("not-a-date"),
                   "new_date": .string("2026-08-19"), "new_start": .int(600), "new_end": .int(660)])
        let result = await executor().execute(action)
        XCTAssertFalse(result.ok)
    }

    func testMoveEventRefusesMalformedNewDate() async {
        let action = AssistantAction(tool: "move_event",
            args: ["title": .string("Dentist"), "date": .string("2026-08-18"),
                   "new_date": .string("not-a-date"), "new_start": .int(600), "new_end": .int(660)])
        let result = await executor().execute(action)
        XCTAssertFalse(result.ok)
    }

    func testMoveEventRefusesEndBeforeStart() async {
        let action = AssistantAction(tool: "move_event",
            args: ["title": .string("Dentist"), "date": .string("2026-08-18"),
                   "new_date": .string("2026-08-19"), "new_start": .int(660), "new_end": .int(600)])
        let result = await executor().execute(action)
        XCTAssertFalse(result.ok)
    }

    func testMoveEventReportsNoMatchWithoutCalendarAccess() async {
        let action = AssistantAction(tool: "move_event",
            args: ["title": .string("Dentist"), "date": .string("2026-08-18"),
                   "new_date": .string("2026-08-19"), "new_start": .int(600), "new_end": .int(660)])
        let result = await executor().execute(action)
        XCTAssertFalse(result.ok)
        XCTAssertTrue(result.message.contains("No event named"))
    }

    // MARK: read_date — validation only
    //
    // `readDate` reads `portal.sessions` once its date guard passes, and
    // `PortalController()`'s real cached-schedule read (see the file header
    // comment) means what's in there isn't safe to assert on — only the
    // guard that runs before touching it is tested here, same boundary
    // `read_week`/`read_grades` already draw for themselves.

    func testReadDateRefusesMalformedDate() async {
        let result = await executor().execute(AssistantAction(tool: "read_date", args: ["date": .string("not-a-date")]))
        XCTAssertFalse(result.ok)
    }

    func testReadDateRefusesMissingDate() async {
        let result = await executor().execute(AssistantAction(tool: "read_date"))
        XCTAssertFalse(result.ok)
    }

    // MARK: set_class_status / set_class_time — validation only
    //
    // Same boundary as read_date above: `findSession` reads `portal.sessions`,
    // so only the guards that run before it — bad args, bad date, bad status,
    // bad time range — are safe to assert on here.

    func testSetClassStatusRefusesMissingSubjectCode() async {
        let action = AssistantAction(tool: "set_class_status",
            args: ["date": .string("2026-08-18"), "status": .string("vacant")])
        let result = await executor().execute(action)
        XCTAssertFalse(result.ok)
    }

    func testSetClassStatusRefusesMalformedDate() async {
        let action = AssistantAction(tool: "set_class_status",
            args: ["subject_code": .string("COMP 20073"), "date": .string("not-a-date"), "status": .string("vacant")])
        let result = await executor().execute(action)
        XCTAssertFalse(result.ok)
    }

    func testSetClassStatusRefusesInvalidStatus() async {
        let action = AssistantAction(tool: "set_class_status",
            args: ["subject_code": .string("COMP 20073"), "date": .string("2026-08-18"), "status": .string("cancelled")])
        let result = await executor().execute(action)
        XCTAssertFalse(result.ok)
    }

    func testSetClassStatusRefusesMissingStatus() async {
        let action = AssistantAction(tool: "set_class_status",
            args: ["subject_code": .string("COMP 20073"), "date": .string("2026-08-18")])
        let result = await executor().execute(action)
        XCTAssertFalse(result.ok)
    }

    func testSetClassTimeRefusesMissingSubjectCode() async {
        let action = AssistantAction(tool: "set_class_time",
            args: ["date": .string("2026-08-18"), "start": .int(600), "end": .int(660)])
        let result = await executor().execute(action)
        XCTAssertFalse(result.ok)
    }

    func testSetClassTimeRefusesMalformedDate() async {
        let action = AssistantAction(tool: "set_class_time",
            args: ["subject_code": .string("COMP 20073"), "date": .string("not-a-date"), "start": .int(600), "end": .int(660)])
        let result = await executor().execute(action)
        XCTAssertFalse(result.ok)
    }

    func testSetClassTimeRefusesEndBeforeStart() async {
        let action = AssistantAction(tool: "set_class_time",
            args: ["subject_code": .string("COMP 20073"), "date": .string("2026-08-18"), "start": .int(660), "end": .int(600)])
        let result = await executor().execute(action)
        XCTAssertFalse(result.ok)
    }

    func testSetClassTimeRefusesMissingTimes() async {
        let action = AssistantAction(tool: "set_class_time",
            args: ["subject_code": .string("COMP 20073"), "date": .string("2026-08-18")])
        let result = await executor().execute(action)
        XCTAssertFalse(result.ok)
    }

    // MARK: Unknown tool

    func testUnknownToolFailsCleanlyRatherThanCrashing() async {
        let result = await executor().execute(AssistantAction(tool: "delete_everything", args: [:]))
        XCTAssertFalse(result.ok)
    }
}
