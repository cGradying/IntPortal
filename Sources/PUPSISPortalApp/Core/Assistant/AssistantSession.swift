import Foundation

/// The floating assistant's live conversation state — one instance, owned by
/// `AppState`, so the conversation survives switching between Schedule/Today/
/// Grades (which is the whole point of it floating instead of living on one
/// screen). `Views/AssistantOrb.swift`/`AssistantChat.swift` are the only
/// things that read this; the engine and executor never touch UI state.
@MainActor
final class AssistantSession: ObservableObject {
    @Published var isOpen = false
    @Published var transcript: [AssistantTurn] = []
    @Published var isThinking = false

    /// The note `/read` pinned into the conversation, if any — shown as a chip
    /// in the panel header, cleared by `reset()` or a fresh `/read`.
    @Published var pinnedNote: AssistantCommandRunner.PinnedNote?

    /// Set only in `.propose`/`.confirm` — the actions from the most recent
    /// reply, waiting on the user to apply or skip each one. Cleared once
    /// resolved. Always empty in `.auto`, since the engine executes those
    /// itself before this session ever sees the outcome.
    @Published var pendingActions: [AssistantAction] = []

    /// Set on a failed turn (offline, malformed reply, HTTP error) — shown as
    /// a line in the panel. Cleared at the start of the next send.
    @Published var lastError: String?

    /// The most recently completed turn's actual reasoning text — empty when
    /// thinking was off, the model returned none, or nothing has been asked
    /// yet. Shown in the header's brain popover, not inline in the
    /// transcript — it's the model's scratch work, not part of the reply.
    @Published var lastThinking = ""

    /// A slash-command string set by the floating deck's hover-rail
    /// ("jump + narrate" cross-page shortcuts, wayfinder ticket #8) — opens
    /// chat and sends this immediately, same as if the user had typed and
    /// submitted it themselves. `AssistantChat` consumes and clears it on
    /// appear/change; nil the rest of the time.
    @Published var pendingCommand: String?

    /// A reply the model produced but that isn't fit to show as-is — the
    /// Phase 0 spike's `"reply": "[]"` rough edge, or a genuinely empty
    /// string. Falls back to something that still reflects what happened,
    /// rather than showing the model's raw non-answer.
    ///
    /// `ranCount` must be how many actions actually *executed*
    /// (`AssistantOutcome.results.count`), not how many were proposed
    /// (`.actions.count`) — in `.propose`/`.confirm` mode `.actions` is
    /// non-empty exactly when nothing has run yet (the user hasn't applied
    /// anything), so using it here said "Done." for a turn that only
    /// proposed actions and did nothing.
    static func displayReply(_ reply: String, ranCount: Int) -> String {
        let trimmed = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        let looksUseless = trimmed.isEmpty || trimmed == "[]" || trimmed == "{}"
        guard looksUseless else { return trimmed }
        return ranCount > 0 ? "Done." : "…"
    }

    /// Incremented by `reset()` and by `beginTurn()` (once per `send()`).
    /// A turn in flight tags its eventual write-back with the id `beginTurn()`
    /// handed it; `isCurrent(_:)` is checked before that write actually lands.
    /// Clear (or a fresh send while one is still running) moves this forward,
    /// so a turn already in flight can no longer deposit its result — actions
    /// it proposes, or (in `.auto`) tool calls it already made — into a
    /// conversation that has since moved on. Paired with cancelling the
    /// still-running `Task` itself (`AssistantFloating`'s `send()`/Clear
    /// button): cancellation alone doesn't guarantee no write lands before
    /// it's observed, and this alone doesn't stop a tool call already in
    /// flight — together they close the race.
    @Published private(set) var turnID = 0

    @discardableResult
    func beginTurn() -> Int {
        turnID += 1
        return turnID
    }

    func isCurrent(_ turn: Int) -> Bool { turn == turnID }

    func appendUser(_ text: String) {
        transcript.append(AssistantTurn(role: .user, content: text))
    }

    func appendAssistant(_ text: String, sources: [String] = []) {
        transcript.append(AssistantTurn(role: .assistant, content: text, sources: sources))
    }

    func reset() {
        turnID += 1 // invalidate any turn still in flight
        transcript = []
        pendingActions = []
        lastError = nil
        isThinking = false
        pinnedNote = nil
        lastThinking = ""
    }
}
