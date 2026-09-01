import XCTest
@testable import PUPSISPortal

/// A fake executor that records what it was asked to do and returns
/// canned/queued results — the engine's tests never touch a real store.
private final class FakeExecutor: AssistantExecutor {
    var calls: [AssistantAction] = []
    var results: [AssistantToolResult] = []

    func execute(_ action: AssistantAction) async -> AssistantToolResult {
        calls.append(action)
        if !results.isEmpty { return results.removeFirst() }
        return AssistantToolResult(action: action, ok: true, message: "done")
    }
}

/// Every case drives the engine through an injected `LlamaCppClient` — no
/// network, no real `llama-server` needed for this suite to pass.
/// `ensureServerRunning: { true }` is pinned throughout — the real default
/// resolves through `LlamaRuntime`/`ModelCatalog`, which `"test-model"`
/// never matches.
final class AssistantEngineTests: XCTestCase {

    /// Fixed rather than `Date()` — several tests assert on `context.rendered`
    /// appearing verbatim in the prompt, which must not flip mid-run at a
    /// minute boundary.
    private static let fixedNow = Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 8, day: 26, hour: 14, minute: 30))!

    private let context = AssistantContext(
        destination: .today, openNoteKey: "class:COMP 001", openNoteText: "existing text",
        todayClasses: [], gradesSummary: nil,
        schedule: AssistantScheduleSnapshot(
            now: AssistantEngineTests.fixedNow, sessions: [], termEnd: nil, status: { _ in .regular }, time: { ($0.start, $0.end) }
        )
    )

    private func engine(sending: @escaping (Data) async throws -> (Data, Int),
                        executor: AssistantExecutor = FakeExecutor()) -> AssistantEngine {
        AssistantEngine(
            client: LlamaCppClient(send: sending), model: "test-model", executor: executor,
            ensureServerRunning: { true }
        )
    }

    /// Wraps `content` (the model's own JSON turn, itself a string) in the
    /// OpenAI-compatible `/v1/chat/completions` envelope. Built via
    /// `JSONSerialization` rather than string interpolation so
    /// quoting/escaping is never the thing under test.
    private func jsonResponse(_ content: String) -> (Data, Int) {
        let envelope: [String: Any] = ["choices": [["message": ["role": "assistant", "content": content]]]]
        let data = (try? JSONSerialization.data(withJSONObject: envelope)) ?? Data()
        return (data, 200)
    }

    // MARK: Schema decode — good, garbage, partial

    func testDecodesAWellFormedReplyWithNoActions() async throws {
        let sut = engine { _ in self.jsonResponse(#"{"reply":"Hi there.","actions":[]}"#) }
        let outcome = try await sut.respond(to: "hello", context: context, permission: .confirm)
        XCTAssertEqual(outcome.reply, "Hi there.")
        XCTAssertEqual(outcome.actions, [])
        XCTAssertEqual(outcome.results, [])
    }

    /// Regression: every `chat(...)` call used to omit `numPredict` entirely,
    /// so generation ran until *remaining context* ran out rather than a
    /// real output budget — the direct mechanism behind "generation
    /// sometimes incomplete" (a model that runs out of room mid-JSON throws
    /// `.malformedReply`). `max_tokens` must now actually be present in the
    /// real request body, equal to `Preferences.storedOutputTokenBudget()`.
    func testRespondReservesARealOutputBudget() async throws {
        var capturedBody: [String: Any]?
        let sut = engine { body in
            capturedBody = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
            return self.jsonResponse(#"{"reply":"ok","actions":[]}"#)
        }
        _ = try await sut.respond(to: "hello", context: context, permission: .confirm)
        XCTAssertEqual(capturedBody?["max_tokens"] as? Int, Preferences.storedOutputTokenBudget())
    }

    /// Same reservation in `.auto` mode's loop, not just the propose/confirm
    /// single-request path.
    func testRespondReservesARealOutputBudgetInAutoMode() async throws {
        var capturedBody: [String: Any]?
        let sut = engine { body in
            capturedBody = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
            return self.jsonResponse(#"{"reply":"done","actions":[]}"#)
        }
        _ = try await sut.respond(to: "hello", context: context, permission: .auto)
        XCTAssertEqual(capturedBody?["max_tokens"] as? Int, Preferences.storedOutputTokenBudget())
    }

    func testDecodesAReplyWithAProposedAction() async throws {
        let sut = engine { _ in
            self.jsonResponse(#"{"reply":"Adding that.","actions":[{"tool":"append_note","args":{"text":"review pointers"}}]}"#)
        }
        let outcome = try await sut.respond(to: "add a note", context: context, permission: .confirm)
        XCTAssertEqual(outcome.actions.first?.tool, "append_note")
        XCTAssertEqual(outcome.actions.first?.string("text"), "review pointers")
    }

    /// `actions` omitted entirely must decode as empty, not throw — a model
    /// that forgets the field on a no-op turn shouldn't break the reply.
    func testActionsFieldCanBeOmittedEntirely() async throws {
        let sut = engine { _ in self.jsonResponse(#"{"reply":"Just chatting."}"#) }
        let outcome = try await sut.respond(to: "hi", context: context, permission: .confirm)
        XCTAssertEqual(outcome.actions, [])
    }

    /// Regression for the real bug: a model writing multi-line code left a
    /// literal newline inside the JSON string instead of `\n`. Confirmed live
    /// that `JSONDecoder` doesn't throw on this — it decodes `reply`/`tool`
    /// fine and silently drops just the corrupted `text` argument, so the note
    /// gets created with the prose but no code. Built with a real embedded
    /// newline (not `\n`) to reproduce exactly that.
    func testALiteralNewlineInsideAStringIsSalvagedRatherThanDiscardingTheTurn() async throws {
        let content = """
        {"reply":"Added it.","actions":[{"tool":"append_note","args":{"text":"def add(a, b):
            return a + b"}}]}
        """
        let sut = engine { _ in self.jsonResponse(content) }
        let outcome = try await sut.respond(to: "add this code", context: context, permission: .confirm)

        XCTAssertEqual(outcome.reply, "Added it.")
        XCTAssertEqual(outcome.actions.first?.tool, "append_note")
        XCTAssertEqual(outcome.actions.first?.string("text"), "def add(a, b):\n    return a + b")
    }

    func testGarbageContentThrowsMalformedReply() async {
        let sut = engine { _ in self.jsonResponse("not json at all") }
        do {
            _ = try await sut.respond(to: "hello", context: context, permission: .confirm)
            XCTFail("expected malformedReply")
        } catch let error as AssistantEngineError {
            if case .malformedReply = error {} else { XCTFail("wrong case: \(error)") }
        } catch {
            XCTFail("wrong error type: \(error)")
        }
    }

    func testMissingRequiredReplyFieldThrowsMalformedReply() async {
        // A model that returns valid JSON but drops the required `reply` key —
        // Ollama's schema constraint doesn't guarantee every field survives.
        let sut = engine { _ in self.jsonResponse(#"{"actions":[]}"#) }
        do {
            _ = try await sut.respond(to: "hello", context: context, permission: .confirm)
            XCTFail("expected malformedReply")
        } catch is AssistantEngineError {
            // pass
        } catch {
            XCTFail("wrong error type: \(error)")
        }
    }

    /// An unrecognized tool name must decode, not throw — the engine surfaces
    /// it as a normal action so the caller (or the real executor) can reject
    /// it explicitly, rather than the whole turn silently vanishing.
    func testUnknownToolNameDecodesRatherThanThrows() async throws {
        let sut = engine { _ in
            self.jsonResponse(#"{"reply":"ok","actions":[{"tool":"delete_everything","args":{}}]}"#)
        }
        let outcome = try await sut.respond(to: "hello", context: context, permission: .confirm)
        XCTAssertEqual(outcome.actions.first?.tool, "delete_everything")
        XCTAssertNil(AssistantTool.named("delete_everything"))
    }

    /// No model downloaded / `llama-server` not installed — the engine fails
    /// closed with `.serverUnavailable` before ever calling the transport.
    func testThrowsServerUnavailableWhenTheServerCannotBeStarted() async {
        var called = false
        let sut = AssistantEngine(
            client: LlamaCppClient(send: { _ in called = true; return self.jsonResponse(#"{"reply":"x","actions":[]}"#) }),
            model: "test-model", executor: FakeExecutor(), ensureServerRunning: { false }
        )
        do {
            _ = try await sut.respond(to: "hello", context: context, permission: .confirm)
            XCTFail("expected serverUnavailable")
        } catch let error as AssistantEngineError {
            if case .serverUnavailable = error {} else { XCTFail("wrong case: \(error)") }
        } catch {
            XCTFail("wrong error type: \(error)")
        }
        XCTAssertFalse(called)
    }

    // MARK: propose/confirm never execute

    func testConfirmModeNeverCallsTheExecutor() async throws {
        let executor = FakeExecutor()
        let sut = engine(sending: { _ in
            self.jsonResponse(#"{"reply":"ok","actions":[{"tool":"append_note","args":{"text":"x"}}]}"#)
        }, executor: executor)
        _ = try await sut.respond(to: "add a note", context: context, permission: .confirm)
        XCTAssertTrue(executor.calls.isEmpty)
    }

    func testProposeModeNeverCallsTheExecutor() async throws {
        let executor = FakeExecutor()
        let sut = engine(sending: { _ in
            self.jsonResponse(#"{"reply":"ok","actions":[{"tool":"add_event","args":{}}]}"#)
        }, executor: executor)
        _ = try await sut.respond(to: "book something", context: context, permission: .propose)
        XCTAssertTrue(executor.calls.isEmpty)
    }

    // MARK: auto mode — the loop and its cap

    func testAutoModeExecutesAndReturnsResults() async throws {
        let executor = FakeExecutor()
        var call = 0
        let sut = engine(sending: { _ in
            call += 1
            if call == 1 {
                return self.jsonResponse(#"{"reply":"adding","actions":[{"tool":"append_note","args":{"text":"x"}}]}"#)
            }
            return self.jsonResponse(#"{"reply":"Done, added it.","actions":[]}"#)
        }, executor: executor)

        let outcome = try await sut.respond(to: "add a note", context: context, permission: .auto)
        XCTAssertEqual(executor.calls.count, 1)
        XCTAssertEqual(outcome.results.count, 1)
        XCTAssertEqual(outcome.reply, "Done, added it.")
        XCTAssertEqual(call, 2, "should stop as soon as a round proposes no actions")
    }

    /// A model that keeps proposing actions forever must not spin — the loop
    /// has to stop at `AssistantEngine.maxIterations` regardless.
    func testAutoModeStopsAtIterationCapRatherThanSpinning() async {
        let executor = FakeExecutor()
        var call = 0
        let sut = engine(sending: { _ in
            call += 1
            return self.jsonResponse(#"{"reply":"still going","actions":[{"tool":"append_note","args":{"text":"x"}}]}"#)
        }, executor: executor)

        do {
            _ = try await sut.respond(to: "loop forever", context: context, permission: .auto)
        } catch {
            // Either a clean stop or an explicit error is acceptable here —
            // what's not acceptable is more than maxIterations network calls.
        }
        XCTAssertEqual(call, AssistantEngine.maxIterations, "engine must not call the model more than the cap")
    }

    // MARK: Prompt assembly

    /// The actual fix this session: the model must be told today's date, not
    /// left to invent one — regression guard for that gap.
    func testSystemPromptIncludesTodaysDate() {
        let prompt = AssistantEngine.systemPrompt(context: context)
        XCTAssertTrue(prompt.contains("2026-08-26"), "prompt missing today's date")
    }

    func testSystemPromptTellsTheModelToLookUpNotComputeDates() {
        let prompt = AssistantEngine.systemPrompt(context: context)
        XCTAssertTrue(prompt.lowercased().contains("never compute a date"))
    }

    func testSystemPromptListsEveryCatalogTool() {
        let prompt = AssistantEngine.systemPrompt(context: context)
        for tool in AssistantTool.catalog {
            XCTAssertTrue(prompt.contains(tool.name), "prompt missing \(tool.name)")
        }
    }

    func testSystemPromptForbidsClaimingUnexecutedActions() {
        // Regression guard for the Phase 0 spike finding: small models
        // confidently claimed to have added notes / changed grades with an
        // empty actions array. The prompt must say not to do that.
        let prompt = AssistantEngine.systemPrompt(context: context)
        XCTAssertTrue(prompt.lowercased().contains("claim"))
    }

    func testSystemPromptIncludesRenderedContext() {
        let prompt = AssistantEngine.systemPrompt(context: context)
        XCTAssertTrue(prompt.contains(context.rendered))
    }

    func testSystemPromptIncludesUserInstructionsWhenGiven() {
        let prompt = AssistantEngine.systemPrompt(context: context, instructions: "Always use bullet points.")
        XCTAssertTrue(prompt.contains("Always use bullet points."))
    }

    func testSystemPromptOmitsInstructionsSectionWhenNil() {
        let withInstructions = AssistantEngine.systemPrompt(context: context, instructions: "x")
        let without = AssistantEngine.systemPrompt(context: context, instructions: nil)
        XCTAssertFalse(without.contains("own instructions"))
        XCTAssertTrue(withInstructions.contains("own instructions"))
    }

    // MARK: escapingRawControlCharacters — the salvage transform itself

    func testEscapingLeavesAlreadyValidJSONUnchanged() {
        let json = #"{"reply":"ok","actions":[]}"#
        XCTAssertEqual(AssistantEngine.escapingRawControlCharacters(in: json), json)
    }

    func testEscapingConvertsALiteralNewlineInsideAStringOnly() {
        let raw = "{\"text\":\"line one\nline two\"}"
        let fixed = AssistantEngine.escapingRawControlCharacters(in: raw)
        XCTAssertEqual(fixed, #"{"text":"line one\nline two"}"#)
    }

    /// Formatting whitespace between JSON tokens (outside any string) must
    /// survive untouched — only literal control characters *inside* a string
    /// are the target.
    func testEscapingDoesNotTouchWhitespaceOutsideAString() {
        let raw = "{\n  \"reply\": \"ok\"\n}"
        XCTAssertEqual(AssistantEngine.escapingRawControlCharacters(in: raw), raw)
    }

    /// An already-correct `\n` escape must not become `\\n` — the scanner has
    /// to track escape state, not just count backslashes.
    func testEscapingDoesNotDoubleEscapeAnAlreadyValidSequence() {
        let json = #"{"text":"already\nescaped"}"#
        XCTAssertEqual(AssistantEngine.escapingRawControlCharacters(in: json), json)
    }

    /// `actions.items` is `AssistantTool.argsSchema`'s `oneOf` — one branch
    /// per tool, each a `const` tool name — rather than a bare `enum`, since
    /// Granite can follow a schema this tight (the sub-3B models this catalog
    /// was first built against couldn't, see `AssistantEngine.responseSchema`'s
    /// own doc comment).
    func testResponseSchemaConstrainsToolNamesToTheCatalog() throws {
        let schema = AssistantEngine.responseSchema()
        let properties = try XCTUnwrap(schema["properties"] as? [String: Any])
        let actions = try XCTUnwrap(properties["actions"] as? [String: Any])
        let items = try XCTUnwrap(actions["items"] as? [String: Any])
        let branches = try XCTUnwrap(items["oneOf"] as? [[String: Any]])
        let names = try branches.map { branch -> String in
            let branchProps = try XCTUnwrap(branch["properties"] as? [String: Any])
            let toolSchema = try XCTUnwrap(branchProps["tool"] as? [String: Any])
            return try XCTUnwrap(toolSchema["const"] as? String)
        }
        XCTAssertEqual(Set(names), Set(AssistantTool.names))
    }
}

/// The append-note guard, pinned as a unit test since it's the one place
/// where the spike's failure mode (an action that silently destroys data)
/// would actually bite — see `NotesStore.setText` deleting on whitespace.
final class AssistantActionGuardTests: XCTestCase {
    func testBlankTextArgumentReadsAsAbsent() {
        let action = AssistantAction(tool: "append_note", args: ["text": .string("   ")])
        XCTAssertNil(action.string("text"), "whitespace-only text must not pass through as real content")
    }

    func testEmptyStringArgumentReadsAsAbsent() {
        let action = AssistantAction(tool: "append_note", args: ["text": .string("")])
        XCTAssertNil(action.string("text"))
    }

    func testMissingArgumentReadsAsAbsent() {
        let action = AssistantAction(tool: "append_note", args: [:])
        XCTAssertNil(action.string("text"))
    }

    func testRealTextPassesThroughTrimmed() {
        let action = AssistantAction(tool: "append_note", args: ["text": .string("  review pointers  ")])
        XCTAssertEqual(action.string("text"), "review pointers")
    }

    func testNumericArgumentReadsAsIntWhenAskedForInt() {
        let action = AssistantAction(tool: "add_event", args: ["start": .int(840)])
        XCTAssertEqual(action.int("start"), 840)
    }

    /// A model asked for an int argument occasionally sends it as a string —
    /// this must still resolve rather than silently failing the tool.
    func testStringifiedNumberReadsAsIntToo() {
        let action = AssistantAction(tool: "add_event", args: ["start": .string("840")])
        XCTAssertEqual(action.int("start"), 840)
    }
}
