import XCTest
@testable import PUPSISPortal

/// `AssistantCommandRunner` never lets a bad `/read`/`/summary` name reach the
/// model — this suite checks that boundary as much as the happy paths.
@MainActor
final class AssistantCommandRunnerTests: XCTestCase {
    private var notesURL: URL!
    private var notesStore: NotesStore!

    override func setUpWithError() throws {
        notesURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("AssistantCommandRunnerTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("notes.json")
        notesStore = NotesStore(url: notesURL)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: notesURL.deletingLastPathComponent())
    }

    private func runner(
        openKey: String? = nil,
        client: OllamaClient = OllamaClient(send: { _ in (Data(#"{"response":"unused"}"#.utf8), 200) }),
        ragQuery: RAGQuery? = nil
    ) -> AssistantCommandRunner {
        let preferences = Preferences(defaults: UserDefaults(suiteName: "AssistantCommandRunnerTests-\(UUID().uuidString)")!)
        // Same reasoning as RealAssistantExecutorTests: a never-`requestAccess`'d
        // CalendarBridge and a never-constructed-for-real PortalController keep
        // /date, /vacant, /online, /regular's validation paths testable without
        // touching real EventKit or the user's cached schedule.
        let executor = RealAssistantExecutor(
            notes: notesStore, editor: EventEditor(bridge: CalendarBridge()), calendar: CalendarBridge(),
            portal: PortalController(), preferences: preferences, openNoteKey: { openKey }
        )
        return AssistantCommandRunner(
            notes: notesStore, openNoteKey: { openKey }, model: "test-model", preferences: preferences,
            executor: executor, client: client, ragQuery: ragQuery
        )
    }

    // MARK: /read

    func testReadPinsAnExistingNote() async {
        let key = notesStore.addFile(name: "Physics", to: nil)
        notesStore.setText("Newton's laws.", for: key)
        let outcome = await runner().run(.read(name: "Physics"))
        XCTAssertEqual(outcome.pin?.name, "Physics")
        XCTAssertEqual(outcome.pin?.text, "Newton's laws.")
    }

    func testReadWithNoNameFallsBackToTheOpenNote() async {
        notesStore.setText("today's scratchpad", for: "day:2026-08-16")
        let outcome = await runner(openKey: "day:2026-08-16").run(.read(name: nil))
        XCTAssertEqual(outcome.pin?.text, "today's scratchpad")
    }

    func testReadOnAMissingNameListsRealNotesAndCallsNoModel() async {
        _ = notesStore.addFile(name: "Physics", to: nil)
        var modelCalled = false
        let client = OllamaClient(send: { _ in modelCalled = true; return (Data(), 200) })
        let outcome = await runner(client: client).run(.read(name: "nonsense"))
        XCTAssertNil(outcome.pin)
        XCTAssertTrue(outcome.reply.contains("Physics"))
        XCTAssertFalse(modelCalled)
    }

    // MARK: /summary

    func testSummaryReturnsTheModelsText() async {
        let key = notesStore.addFile(name: "Physics", to: nil)
        notesStore.setText("Newton's laws of motion.", for: key)
        let client = OllamaClient(send: { _ in (Data(#"{"response":"A summary."}"#.utf8), 200) })
        let outcome = await runner(client: client).run(.summary(name: "Physics"))
        XCTAssertEqual(outcome.reply, "A summary.")
        XCTAssertNil(outcome.pin, "summary never pins — that's /read's job")
    }

    func testSummaryOnAnEmptyNoteCallsNoModel() async {
        _ = notesStore.addFile(name: "Blank", to: nil)
        var modelCalled = false
        let client = OllamaClient(send: { _ in modelCalled = true; return (Data(), 200) })
        _ = await runner(client: client).run(.summary(name: "Blank"))
        XCTAssertFalse(modelCalled)
    }

    // MARK: /create

    func testCreateWritesANewNoteFromTheModelsText() async {
        let client = OllamaClient(send: { _ in (Data(#"{"response":"Plants use light to make sugar."}"#.utf8), 200) })
        let outcome = await runner(client: client).run(.create(prompt: "photosynthesis basics"))
        XCTAssertTrue(outcome.wroteNote)
        XCTAssertTrue(outcome.reply.contains("photosynthesis basics"))

        let names = notesStore.noteNames()
        XCTAssertEqual(names.count, 1)
        let key = notesStore.key(forName: names[0])
        XCTAssertEqual(key.map(notesStore.text(for:)), "Plants use light to make sugar.")
    }

    func testCreateWithBlankPromptWritesNothing() async {
        var modelCalled = false
        let client = OllamaClient(send: { _ in modelCalled = true; return (Data(), 200) })
        let outcome = await runner(client: client).run(.create(prompt: "   "))
        XCTAssertFalse(outcome.wroteNote)
        XCTAssertFalse(modelCalled)
        XCTAssertTrue(notesStore.noteNames().isEmpty)
    }

    // MARK: /rag — the guaranteed, non-model-dependent search path

    func testRagWithBlankPromptCallsNothing() async {
        var called = false
        let ragQuery = RAGQuery(
            notes: notesStore,
            ollamaClient: OllamaClient(sendEmbed: { _ in called = true; return (Data(), 200) })
        )
        let outcome = await runner(ragQuery: ragQuery).run(.rag(prompt: "   "))
        XCTAssertFalse(called)
        XCTAssertTrue(outcome.reply.contains("/rag"))
    }

    func testRagReturnsTheGroundedAnswerAndItsSources() async {
        notesStore.setText("Recursion has a base case and a recursive case.", for: "class:COMP 001")
        let ragQuery = RAGQuery(
            notes: notesStore,
            ollamaClient: OllamaClient(sendEmbed: { _ in throw URLError(.notConnectedToInternet) }), // forces the term-match fallback
            llamaCppClient: LlamaCppClient(send: { _ in
                (Data(#"{"choices":[{"message":{"content":"A base case and a recursive case."}}]}"#.utf8), 200)
            }),
            ensureServerRunning: { true } // never spawn/health-check a real llama-server in a test
        )
        let outcome = await runner(ragQuery: ragQuery).run(.rag(prompt: "recursion"))
        XCTAssertEqual(outcome.reply, "A base case and a recursive case.")
        XCTAssertEqual(outcome.sources, ["COMP 001"])
    }

    func testRagReportsWhenNothingMatches() async {
        notesStore.setText("unrelated content", for: "class:COMP 001")
        let ragQuery = RAGQuery(
            notes: notesStore,
            ollamaClient: OllamaClient(sendEmbed: { _ in throw URLError(.notConnectedToInternet) })
        )
        let outcome = await runner(ragQuery: ragQuery).run(.rag(prompt: "nonexistent"))
        XCTAssertTrue(outcome.reply.contains("No notes matched"))
        XCTAssertTrue(outcome.sources.isEmpty)
    }

    // MARK: /date, /vacant, /online, /regular — deterministic onto the same
    // calendar tools the model can call, via the injected `RealAssistantExecutor`.
    //
    // Same boundary `RealAssistantExecutorTests` already draws for itself:
    // `PortalController()`'s real cached-schedule read means only the guards
    // that run before touching `portal.sessions` are safe to assert on here
    // — which for these commands means the ones the runner itself checks
    // before ever calling the executor.

    func testDateWithNoArgumentAsksForOne() async {
        let outcome = await runner().run(.date("   "))
        XCTAssertTrue(outcome.reply.contains("/date"))
    }

    func testVacantWithNoSubjectOrDateAsksForBoth() async {
        let outcome = await runner().run(.classStatus(subject: "", date: "", status: "vacant"))
        XCTAssertTrue(outcome.reply.contains("/vacant"))
    }

    func testOnlineWithNoDateAsksForOne() async {
        let outcome = await runner().run(.classStatus(subject: "COMP 20073", date: "", status: "online"))
        XCTAssertTrue(outcome.reply.contains("/online"))
    }

    // MARK: /help and unknown

    func testHelpListsCommands() async {
        let outcome = await runner().run(.help)
        XCTAssertTrue(outcome.reply.contains("/read"))
        XCTAssertTrue(outcome.reply.contains("/summary"))
        XCTAssertTrue(outcome.reply.contains("/create"))
    }

    func testUnknownCommandRepliesWithHelp() async {
        let outcome = await runner().run(.unknown("frobnicate"))
        XCTAssertTrue(outcome.reply.contains("frobnicate"))
        XCTAssertTrue(outcome.reply.contains("/read"))
    }
}
