import XCTest
@testable import PUPSISPortal

/// `AssistantSession` itself, decoupled from the engine/executor — the
/// turn-id race guard and the "Done."/"…" fallback text are both pure
/// decision logic worth covering directly, no fakes needed beyond the
/// session itself.
@MainActor
final class AssistantSessionTests: XCTestCase {

    // MARK: displayReply — "Done." only when something actually ran

    func testUselessReplyWithNothingRunFallsBackToEllipsis() {
        XCTAssertEqual(AssistantSession.displayReply("", ranCount: 0), "…")
        XCTAssertEqual(AssistantSession.displayReply("[]", ranCount: 0), "…")
        XCTAssertEqual(AssistantSession.displayReply("{}", ranCount: 0), "…")
    }

    /// Regression: this used to be driven by how many actions were
    /// *proposed* (`AssistantOutcome.actions.count`), which in
    /// `.propose`/`.confirm` mode is non-empty exactly when nothing has run
    /// yet — so a turn that only proposed actions, and executed none of
    /// them, said "Done." `ranCount` must reflect what actually executed
    /// (`.results.count`) instead.
    func testUselessReplyWithSomethingRunSaysDone() {
        XCTAssertEqual(AssistantSession.displayReply("", ranCount: 2), "Done.")
        XCTAssertEqual(AssistantSession.displayReply("[]", ranCount: 1), "Done.")
    }

    func testARealReplyPassesThroughRegardlessOfRanCount() {
        XCTAssertEqual(AssistantSession.displayReply("Here's your schedule.", ranCount: 0), "Here's your schedule.")
        XCTAssertEqual(AssistantSession.displayReply("  Here's your schedule.  ", ranCount: 3), "Here's your schedule.")
    }

    // MARK: turnID — the Clear-mid-turn race guard

    func testFreshSessionsFirstTurnIsCurrent() {
        let session = AssistantSession()
        let turn = session.beginTurn()
        XCTAssertTrue(session.isCurrent(turn))
    }

    /// The actual bug this guards: Clear (or a second `send()`) mid-turn
    /// must invalidate the turn already in flight, so its eventual result
    /// (actions proposed, or — in Auto mode — tool calls already made) can't
    /// land in a conversation that has moved on.
    func testResetInvalidatesATurnAlreadyInFlight() {
        let session = AssistantSession()
        let staleTurn = session.beginTurn()
        session.reset()
        XCTAssertFalse(session.isCurrent(staleTurn))
    }

    func testASecondSendInvalidatesTheFirstTurn() {
        let session = AssistantSession()
        let firstTurn = session.beginTurn()
        let secondTurn = session.beginTurn()
        XCTAssertFalse(session.isCurrent(firstTurn))
        XCTAssertTrue(session.isCurrent(secondTurn))
    }
}
