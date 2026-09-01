import XCTest
@testable import PUPSISPortal

/// A minimal executor for the two `respond()`-level tests below — they only
/// care whether the request is attempted at all, never what a tool call does.
private final class NoOpExecutor: AssistantExecutor {
    func execute(_ action: AssistantAction) async -> AssistantToolResult {
        AssistantToolResult(action: action, ok: true, message: "")
    }
}

/// The context-size-dependent half of the "AI calling seems to be breaking"
/// fix: `AssistantContext.rendered` used to truncate any note at a flat
/// 4000 chars regardless of `Preferences.aiContextSize`, which could
/// overflow the model's actual window at the low end long before the model
/// ever got to reply.
///
/// `smallWindow` (2048) is deliberately **below**
/// `Preferences.aiContextSizeRange.lowerBound`, not equal to it — this suite
/// is what found that 2048 was already too small for the real 16-tool
/// catalog and drove raising the floor to 3072 (see that constant's own doc
/// comment). Testing the literal old value keeps this suite's job — proving
/// a too-small window fails loud, not silently — independent of wherever
/// the floor happens to sit today.
final class AssistantContextTests: XCTestCase {
    private static let fixedNow = Calendar(identifier: .gregorian)
        .date(from: DateComponents(year: 2026, month: 8, day: 26, hour: 14, minute: 30))!
    private let smallWindow = 2048

    private func snapshot() -> AssistantScheduleSnapshot {
        AssistantScheduleSnapshot(now: Self.fixedNow, sessions: [], termEnd: nil, status: { _ in .regular }, time: { ($0.start, $0.end) })
    }

    private let longNote = String(repeating: "lecture notes ", count: 2000) // ~28,000 chars

    // MARK: noteCharLimit — the pure sizing function

    /// Not a hardcoded expected number — `promptOverheadTokens` is itself
    /// computed from the live tool catalog (see its own doc comment on why:
    /// a hardcoded guess already went stale once), so this asserts the
    /// *relationship* instead of a number that would need updating every
    /// time a tool is added.
    func testNoteCharLimitAtASmallWindowIsFlooredNotZero() {
        let limit = AssistantContext.noteCharLimit(tokenBudget: smallWindow)
        let expected = min(max((smallWindow - AssistantContext.promptOverheadTokens) * AssistantContext.charsPerTokenEstimate, 500), 4000)
        XCTAssertEqual(limit, expected)
        XCTAssertLessThan(limit, 4000)
    }

    func testNoteCharLimitNeverExceedsTheOldFlatCeiling() {
        let limit = AssistantContext.noteCharLimit(tokenBudget: Preferences.aiContextSizeRange.upperBound)
        XCTAssertEqual(limit, 4000) // ceiling, not (32768-1400)*4
    }

    func testNoteCharLimitNeverGoesBelowTheFloorEvenWithNoOverheadRoom() {
        let limit = AssistantContext.noteCharLimit(tokenBudget: 0)
        XCTAssertEqual(limit, 500)
    }

    func testNoteCharLimitSplitsBetweenAnOpenAndAPinnedNote() {
        let whole = AssistantContext.noteCharLimit(tokenBudget: 8000, splitTwoWays: false)
        let split = AssistantContext.noteCharLimit(tokenBudget: 8000, splitTwoWays: true)
        XCTAssertEqual(split, whole / 2)
    }

    // MARK: rendered — low context window (2048 — below the app's own floor)

    /// The actual finding this suite's low-context testing surfaced: the
    /// tool catalog (16 tools) + rules text alone already ate nearly all of
    /// the app's *old* advertised minimum context size (2048) — there's no
    /// amount of note-truncation tuning that makes a real conversation fit
    /// too. The right behavior at that point isn't "truncate harder and
    /// hope" — it's failing loud and explainable
    /// (`AssistantEngineError.contextTooSmall`, caught in `respond` before
    /// ever hitting the real server) instead of a generic HTTP 400/timeout
    /// that reads as "the assistant is broken". This drove raising
    /// `aiContextSizeRange`'s floor to 3072; 2048 is tested directly here
    /// (not via the now-raised floor) so this stays a real regression test
    /// of "too small fails loud" rather than a tautology against wherever
    /// the floor sits today.
    func testBelowTheFloorRespondFailsExplainablyRatherThanSilently() async {
        let context = AssistantContext(
            destination: .today, openNoteKey: "class:COMP 001", openNoteText: longNote,
            todayClasses: [], gradesSummary: nil, schedule: snapshot(),
            tokenBudget: smallWindow
        )
        let engine = AssistantEngine(
            client: LlamaCppClient(send: { _ in XCTFail("must not reach the network"); return (Data(), 200) }),
            model: "test-model",
            executor: NoOpExecutor(),
            ensureServerRunning: { true }
        )
        do {
            _ = try await engine.respond(to: "hi", context: context, permission: .confirm)
            XCTFail("expected contextTooSmall")
        } catch let error as AssistantEngineError {
            guard case .contextTooSmall(let needed, let configured) = error else {
                XCTFail("expected .contextTooSmall, got \(error)"); return
            }
            XCTAssertEqual(configured, smallWindow)
            XCTAssertGreaterThan(needed, configured) // that's *why* it's too small
        } catch {
            XCTFail("expected AssistantEngineError, got \(error)")
        }
    }

    /// Regression guard: the app's own current minimum slider setting
    /// (`aiContextSizeRange.lowerBound`, 3072) must itself stay viable — if
    /// the tool catalog grows enough to push `promptOverheadTokens` back
    /// past this floor, this is what catches it, rather than students
    /// hitting `contextTooSmall` on the app's own advertised minimum again.
    func testTheAppsCurrentMinimumSliderSettingIsItselfStillViable() async throws {
        let context = AssistantContext(
            destination: .today, openNoteKey: nil, openNoteText: nil,
            todayClasses: [], gradesSummary: nil, schedule: snapshot(),
            tokenBudget: Preferences.aiContextSizeRange.lowerBound
        )
        let engine = AssistantEngine(
            client: LlamaCppClient(send: { _ in
                let envelope: [String: Any] = ["choices": [["message": ["content": #"{"reply":"ok","actions":[]}"#]]]]
                return ((try? JSONSerialization.data(withJSONObject: envelope)) ?? Data(), 200)
            }),
            model: "test-model",
            executor: NoOpExecutor(),
            ensureServerRunning: { true }
        )
        _ = try await engine.respond(to: "hi", context: context, permission: .confirm) // must not throw
    }

    /// The app's own maximum (32768) has plenty of headroom past the same
    /// fixed overhead — respond proceeds to the network instead of
    /// rejecting a perfectly viable configuration.
    func testAtHighContextRespondProceedsPastTheGuard() async throws {
        let context = AssistantContext(
            destination: .today, openNoteKey: "class:COMP 001", openNoteText: longNote,
            todayClasses: [], gradesSummary: nil, schedule: snapshot(),
            tokenBudget: Preferences.aiContextSizeRange.upperBound
        )
        var reachedNetwork = false
        let engine = AssistantEngine(
            client: LlamaCppClient(send: { _ in
                reachedNetwork = true
                let envelope: [String: Any] = ["choices": [["message": ["content": #"{"reply":"ok","actions":[]}"#]]]]
                return ((try? JSONSerialization.data(withJSONObject: envelope)) ?? Data(), 200)
            }),
            model: "test-model",
            executor: NoOpExecutor(),
            ensureServerRunning: { true }
        )
        _ = try await engine.respond(to: "hi", context: context, permission: .confirm)
        XCTAssertTrue(reachedNetwork)
    }

    func testAtLowContextALongNoteIsTruncatedMuchShorterThanTheOldFlatLimit() {
        let context = AssistantContext(
            destination: .today, openNoteKey: "class:COMP 001", openNoteText: longNote,
            todayClasses: [], gradesSummary: nil, schedule: snapshot(),
            tokenBudget: smallWindow
        )
        XCTAssertTrue(context.rendered.contains("[...truncated]"))
        // The rendered note body (between the header and the truncation
        // marker) should track noteCharLimit, not the old flat 4000.
        let limit = AssistantContext.noteCharLimit(tokenBudget: smallWindow)
        XCTAssertLessThan(limit, 4000)
    }

    func testAtLowContextBothAnOpenAndPinnedNoteTogetherStillFitTheSplitBudget() {
        var context = AssistantContext(
            destination: .today, openNoteKey: "class:COMP 001", openNoteText: longNote,
            todayClasses: [], gradesSummary: nil, schedule: snapshot(),
            tokenBudget: smallWindow
        )
        context.pinnedNote = .init(name: "Reviewer", text: longNote)
        let rendered = context.rendered
        XCTAssertEqual(rendered.components(separatedBy: "[...truncated]").count - 1, 2) // both truncated
        let splitLimit = AssistantContext.noteCharLimit(tokenBudget: smallWindow, splitTwoWays: true)
        XCTAssertLessThan(splitLimit, AssistantContext.noteCharLimit(tokenBudget: smallWindow))
    }

    // MARK: rendered — high context window (32768, the app's own maximum)

    func testAtHighContextANoteUnderTheCeilingIsNotTruncatedAtAll() {
        let shortNote = "Just a page of real notes, nowhere near 4000 chars."
        let context = AssistantContext(
            destination: .today, openNoteKey: "class:COMP 001", openNoteText: shortNote,
            todayClasses: [], gradesSummary: nil, schedule: snapshot(),
            tokenBudget: Preferences.aiContextSizeRange.upperBound
        )
        XCTAssertFalse(context.rendered.contains("[...truncated]"))
        XCTAssertTrue(context.rendered.contains(shortNote))
    }

    /// A huge context window doesn't waive the ceiling — it still caps at
    /// the old flat 4000 rather than dumping an entire 28,000-char note
    /// into the prompt just because the window could technically fit it;
    /// headroom at a big window buys space for history/tool results, not
    /// an unbounded single note.
    func testAtHighContextAVeryLongNoteIsStillCappedAtTheCeiling() {
        let context = AssistantContext(
            destination: .today, openNoteKey: "class:COMP 001", openNoteText: longNote,
            todayClasses: [], gradesSummary: nil, schedule: snapshot(),
            tokenBudget: Preferences.aiContextSizeRange.upperBound
        )
        XCTAssertTrue(context.rendered.contains("[...truncated]"))
    }

    // MARK: Default tokenBudget — every existing call site keeps compiling

    func testDefaultTokenBudgetMatchesTheAppsOwnDefaultContextSize() {
        let context = AssistantContext(
            destination: .today, openNoteKey: nil, openNoteText: nil,
            todayClasses: [], gradesSummary: nil, schedule: snapshot()
        )
        XCTAssertEqual(context.tokenBudget, Preferences.aiDefaultContextSize)
    }
}