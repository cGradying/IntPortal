import Foundation

/// A snapshot of "where the student is right now", rendered into the system
/// prompt so the model can answer "what's on my schedule" or "summarize this
/// note" without a tool round trip for context it already has. Built fresh
/// per turn from whatever the app already has in memory — nothing here reads
/// disk or the network by itself.
struct AssistantContext: Equatable {
    /// A today's class plus its resolved time — never `session.start`/`.end`
    /// directly, so a locally-moved class doesn't tell the model a time the
    /// grid already disagrees with.
    struct ClassEntry: Equatable {
        let session: ClassSession
        let start: Int
        let end: Int
    }

    let destination: Destination
    let openNoteKey: String?
    let openNoteText: String?
    let todayClasses: [ClassEntry]
    let gradesSummary: String?
    /// "Now" and the recurring weekly pattern, resolved once per turn — see
    /// its own doc comment for why the model needs this rather than
    /// inventing dates itself.
    let schedule: AssistantScheduleSnapshot
    /// Set by `/read` — a note the student explicitly pulled into the
    /// conversation, independent of whatever's open on screen.
    var pinnedNote: AssistantCommandRunner.PinnedNote? = nil

    /// The configured `llama-server --ctx-size` (`Preferences.aiContextSize`)
    /// — how much of it the note-truncation limits below scale to. Defaulted
    /// so every existing call site (including every test literal) keeps
    /// compiling unchanged; `AssistantFloating.buildContext()` is the one
    /// real call site and passes the student's actual setting.
    var tokenBudget: Int = Preferences.aiDefaultContextSize

    /// Confirmed live bug this fixes: the note-truncation limit used to be a
    /// flat 4000 chars regardless of the configured context size. At
    /// `aiContextSize`'s own minimum (2048 tokens), a system prompt built
    /// from the tool catalog + rules + one untruncated 4000-char note could
    /// already exceed the window before the model ever got to reply —
    /// llama-server rejects an over-budget request outright, so every tool
    /// call broke, not just ones that happened to need a long note.
    ///
    /// Not real tokenization (the model's own tokenizer isn't available
    /// client-side) — ~4 chars/English-token is the same rough heuristic
    /// most LLM tooling defaults to without one. `promptOverheadTokens` is
    /// reserved for the tool catalog + rules + the model's own reply,
    /// generous on purpose: better to under-fill a big window than overflow
    /// a small one. Floored at 500 chars (a couple of sentences survive even
    /// the smallest window) and capped at the old flat 4000 — a bigger
    /// window buys headroom for conversation history and tool results, not
    /// an unbounded single note dump.
    static let charsPerTokenEstimate = 4

    /// Measured from the real tool catalog (`AssistantTool.promptCatalog`)
    /// plus a fixed estimate for `AssistantEngine.systemPrompt`'s
    /// surrounding rules text — computed, not a hardcoded guess, so it can't
    /// quietly go stale as tools are added the way a fixed constant already
    /// did once: a first-pass guess of 1400 was already short of the real
    /// ~2029-token overhead the moment `AssistantContextTests` measured it
    /// against the current 16-tool catalog. `rulesTextCharEstimate` covers
    /// the rules block specifically because that text doesn't grow with the
    /// tool count the way the catalog does, so it's fine as a constant.
    private static let rulesTextCharEstimate = 2600
    static var promptOverheadTokens: Int {
        (AssistantTool.promptCatalog.count + rulesTextCharEstimate) / charsPerTokenEstimate
    }

    static func noteCharLimit(tokenBudget: Int, splitTwoWays: Bool = false) -> Int {
        let availableTokens = max(tokenBudget - promptOverheadTokens, 0)
        let availableChars = availableTokens * charsPerTokenEstimate
        let capped = min(max(availableChars, 500), 4000)
        // An open note and a pinned note both being present is the one case
        // that used to be able to cost up to 8000 chars at once — split the
        // same total budget between them instead of doubling it.
        return splitTwoWays ? max(capped / 2, 500) : capped
    }

    /// The block that goes into the system prompt, right after the tool
    /// catalog. Kept to plain lines rather than JSON — this is context for the
    /// model to read, not something it parses back.
    var rendered: String {
        var lines = [schedule.rendered, "Current screen: \(destination.title)"]
        let bothNotesPresent = openNoteKey != nil && openNoteText != nil && pinnedNote != nil
        let limit = Self.noteCharLimit(tokenBudget: tokenBudget, splitTwoWays: bothNotesPresent)

        if let key = openNoteKey {
            lines.append("Open note: \(key)")
            if let text = openNoteText, !text.isEmpty {
                let truncated = text.count > limit
                    ? String(text.prefix(limit)) + "\n[...truncated]"
                    : text
                lines.append("Open note text:\n\(truncated)")
            } else {
                lines.append("Open note is empty.")
            }
        } else {
            lines.append("No note is open.")
        }

        if let pinnedNote {
            let truncated = pinnedNote.text.count > limit
                ? String(pinnedNote.text.prefix(limit)) + "\n[...truncated]"
                : pinnedNote.text
            lines.append("Pinned note \"\(pinnedNote.name)\":\n\(truncated)")
        }

        if todayClasses.isEmpty {
            lines.append("No classes today.")
        } else {
            let classLines = todayClasses
                .sorted { $0.start < $1.start }
                .map { "\($0.session.subjectCode) \(ClassSession.format($0.start))-\(ClassSession.format($0.end))" }
            lines.append("Today's classes:\n" + classLines.joined(separator: "\n"))
        }

        if let gradesSummary {
            lines.append("Grades: \(gradesSummary)")
        }

        return lines.joined(separator: "\n\n")
    }
}
