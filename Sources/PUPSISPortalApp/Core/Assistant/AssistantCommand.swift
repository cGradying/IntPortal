import Foundation

/// A slash-command typed into the assistant panel. Parsed **before** anything
/// touches the model's tool-picking — `/summary "Physics"` never asks a small
/// local model to guess an action, it resolves the note and makes one plain
/// completion call. Deterministic where it can be; the model only writes text.
///
/// `parse` returns `nil` for anything not starting with `/`, so ordinary prose
/// is untouched and falls through to `AssistantEngine` exactly as before.
enum AssistantCommand: Equatable {
    /// No argument = the currently open note (resolved by the runner, not here).
    case read(name: String?)
    case summary(name: String)
    case create(prompt: String)
    /// Answers `prompt` from the notes vault via `RAGQuery` — the same
    /// retrieval + grounded-answer pipeline as the `ask_notes` tool, just
    /// deterministic: it always runs, no model tool-picking involved. Exists
    /// because a small assistant model can be unreliable at calling
    /// `ask_notes` on its own (confirmed live: `qwen2.5-coder:1.5b` never
    /// called it, even asked to by name) — `/rag` is the guaranteed path in.
    case rag(prompt: String)
    /// Deterministic path onto `read_date` — same reasoning as `/rag`: typing
    /// a date shouldn't depend on a small model correctly picking the right
    /// tool out of the whole calendar catalog.
    case date(String)
    /// Deterministic path onto `set_class_status` — the literal "turn this
    /// class vacant" ask, guaranteed to hit the right tool with the right
    /// status rather than routed through the model's own tool-picking.
    /// `status` is fixed by which of /vacant, /online, /regular was typed.
    case classStatus(subject: String, date: String, status: String)
    case help
    /// An unrecognized `/word` — still not prose, so it must not silently fall
    /// through to the model; the runner replies with what commands do exist.
    case unknown(String)

    static func parse(_ input: String) -> AssistantCommand? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/") else { return nil }

        let body = trimmed.dropFirst()
        let firstSpace = body.firstIndex(where: \.isWhitespace)
        let word = (firstSpace.map { body[..<$0] } ?? body[...]).lowercased()
        let rest = firstSpace.map { body[$0...].trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""

        switch word {
        case "read":
            let arg = quotedOrBare(rest)
            return .read(name: arg.isEmpty ? nil : arg)
        case "summary", "summarize":
            return .summary(name: quotedOrBare(rest))
        case "create":
            return .create(prompt: rest)
        case "rag":
            return .rag(prompt: quotedOrBare(rest))
        case "date":
            return .date(rest)
        case "vacant", "online", "regular":
            let (subject, date) = splitFirstArg(rest)
            return .classStatus(subject: subject, date: date, status: String(word))
        case "help":
            return .help
        default:
            return .unknown(String(word))
        }
    }

    /// `"quoted text"` (allowing an embedded leading `/`, per the user's own
    /// `/read "/notes name"` form) or, absent quotes, the whole trimmed string.
    private static func quotedOrBare(_ s: String) -> String {
        guard s.hasPrefix("\""), let closing = s.dropFirst().firstIndex(of: "\"") else {
            return s
        }
        return String(s[s.index(after: s.startIndex)..<closing])
    }

    /// The two-argument shape `/vacant "COMP 20073" 2026-08-30` needs: a
    /// leading `"quoted"` (or single bare-word) first argument, then
    /// whatever's left over, trimmed. `quotedOrBare` above only ever handles
    /// one trailing argument, so this is its two-argument sibling.
    private static func splitFirstArg(_ s: String) -> (first: String, rest: String) {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("\""), let closing = trimmed.dropFirst().firstIndex(of: "\"") {
            let first = String(trimmed[trimmed.index(after: trimmed.startIndex)..<closing])
            let rest = String(trimmed[trimmed.index(after: closing)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            return (first, rest)
        }
        guard let spaceIndex = trimmed.firstIndex(where: \.isWhitespace) else {
            return (trimmed, "")
        }
        let first = String(trimmed[..<spaceIndex])
        let rest = String(trimmed[trimmed.index(after: spaceIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)
        return (first, rest)
    }

    /// Shown for `/help` and for any unrecognized `/word` — generated from
    /// `catalog` rather than typed out twice, so the two can't drift apart.
    static var helpText: String {
        "Commands:\n" + catalog.map { "\($0.usage) — \($0.description)" }.joined(separator: "\n")
    }

    /// One command's shape, for the input bar's autocomplete palette
    /// (`Views/AssistantFloating.swift`) — `parse` above is the source of
    /// truth for *behavior* (aliases, quote handling), this is the source of
    /// truth for what to *show* while the user is still typing the name.
    struct Spec: Identifiable, Equatable {
        let name: String
        /// Argument placeholder names, in order — empty for a command that
        /// takes none.
        let params: [String]
        let description: String
        var id: String { name }

        /// What autocompleting this command fills into the input: `/read `
        /// for a command with an argument to type next, bare `/help` for one
        /// that doesn't (so Return can send it immediately).
        var usage: String {
            params.isEmpty ? "/\(name)" : "/\(name) " + params.map { "\"\($0)\"" }.joined(separator: " ")
        }
    }

    static let catalog: [Spec] = [
        Spec(name: "read", params: ["name"], description: "Pin a note into the conversation (no name = the open note)"),
        Spec(name: "summary", params: ["name"], description: "Summarize a note"),
        Spec(name: "create", params: ["prompt"], description: "Write a new note from a prompt"),
        Spec(name: "rag", params: ["prompt"], description: "Answer a question from your notes (RAG), guaranteed to actually search them"),
        Spec(name: "date", params: ["yyyy-MM-dd"], description: "What's on a specific date — classes and calendar events"),
        Spec(name: "vacant", params: ["subject", "yyyy-MM-dd"], description: "Mark a class vacant that day (or every week — ask in chat for that)"),
        Spec(name: "online", params: ["subject", "yyyy-MM-dd"], description: "Mark a class online that day"),
        Spec(name: "regular", params: ["subject", "yyyy-MM-dd"], description: "Clear a vacant/online exception, back to in person"),
        Spec(name: "help", params: [], description: "Show this list"),
    ]
}
