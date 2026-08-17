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

    /// A reply the model produced but that isn't fit to show as-is — the
    /// Phase 0 spike's `"reply": "[]"` rough edge, or a genuinely empty
    /// string. Falls back to something that still reflects what happened,
    /// rather than showing the model's raw non-answer.
    static func displayReply(_ reply: String, actionCount: Int) -> String {
        let trimmed = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        let looksUseless = trimmed.isEmpty || trimmed == "[]" || trimmed == "{}"
        guard looksUseless else { return trimmed }
        return actionCount > 0 ? "Done." : "…"
    }

    func appendUser(_ text: String) {
        transcript.append(AssistantTurn(role: .user, content: text))
    }

    func appendAssistant(_ text: String, sources: [String] = []) {
        transcript.append(AssistantTurn(role: .assistant, content: text, sources: sources))
    }

    func reset() {
        transcript = []
        pendingActions = []
        lastError = nil
        isThinking = false
        pinnedNote = nil
    }
}
