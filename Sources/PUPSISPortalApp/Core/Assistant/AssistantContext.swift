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

    /// Notes and schedules can run long; the prompt is what actually gets sent
    /// to the model, so it's capped here rather than trusting every call site
    /// to remember to truncate.
    private static let noteCharLimit = 4000

    /// The block that goes into the system prompt, right after the tool
    /// catalog. Kept to plain lines rather than JSON — this is context for the
    /// model to read, not something it parses back.
    var rendered: String {
        var lines = [schedule.rendered, "Current screen: \(destination.title)"]

        if let key = openNoteKey {
            lines.append("Open note: \(key)")
            if let text = openNoteText, !text.isEmpty {
                let truncated = text.count > Self.noteCharLimit
                    ? String(text.prefix(Self.noteCharLimit)) + "\n[...truncated]"
                    : text
                lines.append("Open note text:\n\(truncated)")
            } else {
                lines.append("Open note is empty.")
            }
        } else {
            lines.append("No note is open.")
        }

        if let pinnedNote {
            let truncated = pinnedNote.text.count > Self.noteCharLimit
                ? String(pinnedNote.text.prefix(Self.noteCharLimit)) + "\n[...truncated]"
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
