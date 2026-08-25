import Foundation

/// One capability the assistant can invoke. This is documentation, not code —
/// `AssistantEngine` renders the catalog into the system prompt and into the
/// JSON schema's `tool` enum, so the prompt and the parser can never disagree
/// about what tools exist. The actual behavior behind each name lives in
/// whatever `AssistantExecutor` is wired in (the real one in Phase 3, a fake
/// one in tests) — this struct never runs anything itself.
struct AssistantTool: Equatable {
    struct Arg: Equatable {
        let name: String
        let description: String
    }

    let name: String
    /// One line, written for the model: what it does and when to use it.
    let description: String
    /// Argument name → one-line description, for the system prompt only.
    /// **Not** JSON-Schema-validated per tool — see the note on `AssistantEngine`
    /// for why the response schema keeps `args` generic.
    let args: [Arg]

    /// v1 scope, per the plan: notes read+write, calendar read + write
    /// (add/move an event, mark a class vacant/online, move a class's time),
    /// grades read-only. No delete or rename tool exists anywhere in this
    /// catalog — that's deliberate, not an oversight to fill in later.
    static let catalog: [AssistantTool] = [
        AssistantTool(
            name: "read_note",
            description: "Read a note's text.",
            args: [Arg(name: "key", description: "note key, or omitted for the currently open note")]
        ),
        AssistantTool(
            name: "list_notes",
            description: "List the names of notes and vault files the student has.",
            args: []
        ),
        AssistantTool(
            name: "search_notes",
            description: "Search the student's notes for a word or phrase; returns matching notes with a snippet. Use this before answering a question the open note and today's schedule don't already cover.",
            args: [Arg(name: "query", description: "word or phrase to search for")]
        ),
        AssistantTool(
            name: "ask_notes",
            description: "Answer a question by searching the student's notes and having a second, specialized local model synthesize a grounded answer from what's found — not just a list of matches like search_notes. Use this when the student wants an actual answer synthesized from their notes, not just to see what matched. Requires a local llama.cpp server running separately; fails clearly if it isn't.",
            args: [Arg(name: "query", description: "the question to answer from the student's notes")]
        ),
        AssistantTool(
            name: "append_note",
            description: "Add text to the end of a note, keeping what's already there.",
            args: [
                Arg(name: "key", description: "note key, or omitted for the currently open note"),
                Arg(name: "text", description: "markdown to add — must not be empty"),
            ]
        ),
        AssistantTool(
            name: "create_note",
            description: "Create a new note in the vault with a title and starting text.",
            args: [Arg(name: "name", description: "title for the new note"), Arg(name: "text", description: "starting markdown text")]
        ),
        AssistantTool(
            name: "read_week",
            description: "Read the student's classes and calendar events for a week.",
            args: [Arg(name: "weekStart", description: "yyyy-MM-dd, or omitted for the current week")]
        ),
        AssistantTool(
            name: "add_event",
            description: "Add a new calendar event, optionally repeating weekly. Cannot rename or delete existing events.",
            args: [
                Arg(name: "title", description: "event title"),
                Arg(name: "date", description: "yyyy-MM-dd — for a repeating event, the first occurrence"),
                Arg(name: "start", description: "start time, minutes from midnight"),
                Arg(name: "end", description: "end time, minutes from midnight"),
                Arg(name: "repeat_days", description: "optional — only when the student actually asked for a recurring event: comma-separated weekdays, e.g. \"mon,wed,fri\". Omit for a one-off event."),
            ]
        ),
        AssistantTool(
            name: "move_event",
            description: "Move an existing calendar event to a new date and/or time. Cannot rename or delete it.",
            args: [
                Arg(name: "title", description: "the event's current title, to find it"),
                Arg(name: "date", description: "yyyy-MM-dd — the date it's currently on"),
                Arg(name: "new_date", description: "yyyy-MM-dd — the date to move it to"),
                Arg(name: "new_start", description: "new start time, minutes from midnight"),
                Arg(name: "new_end", description: "new end time, minutes from midnight"),
                Arg(name: "scope", description: "\"this_event\" (default) for just this occurrence, or \"future_events\" for a repeating event and everything after it"),
            ]
        ),
        AssistantTool(
            name: "read_date",
            description: "Read the student's classes and calendar events for one specific date — use this instead of read_week when asked what's happening on a particular day.",
            args: [Arg(name: "date", description: "yyyy-MM-dd")]
        ),
        AssistantTool(
            name: "set_class_status",
            description: "Mark a class vacant (cancelled that meeting), online, or back to in-person. This is how to make a class vacant on the calendar.",
            args: [
                Arg(name: "subject_code", description: "the class's subject code, e.g. \"COMP 20073\""),
                Arg(name: "date", description: "yyyy-MM-dd — a date the class actually meets on"),
                Arg(name: "status", description: "\"vacant\", \"online\", or \"regular\""),
                Arg(name: "scope", description: "\"week\" (default) for just that week, or \"term\" for every week"),
                Arg(name: "start", description: "optional, minutes from midnight — only needed if the subject meets more than once that day (e.g. a Lec and a Lab) and it's ambiguous which one is meant"),
            ]
        ),
        AssistantTool(
            name: "set_class_time",
            description: "Move a class to a different start/end time.",
            args: [
                Arg(name: "subject_code", description: "the class's subject code"),
                Arg(name: "date", description: "yyyy-MM-dd — a date the class actually meets on"),
                Arg(name: "start", description: "new start time, minutes from midnight"),
                Arg(name: "end", description: "new end time, minutes from midnight"),
                Arg(name: "scope", description: "\"week\" (default) for just that week, or \"term\" for every week"),
                Arg(name: "current_start", description: "optional, minutes from midnight — disambiguates when the subject meets more than once that day; this is the class's CURRENT start, not the new one"),
            ]
        ),
        AssistantTool(
            name: "read_grades",
            description: "Read the student's posted grades and GPA. Grades cannot be changed by this tool or any other.",
            args: []
        ),
    ]

    static func named(_ name: String) -> AssistantTool? {
        catalog.first { $0.name == name }
    }

    /// The system-prompt block listing every tool and its arguments, e.g.
    /// `- append_note(key, text): Add text to the end of a note...`
    static var promptCatalog: String {
        catalog.map { tool in
            let argList = tool.args.map(\.name).joined(separator: ", ")
            let argNotes = tool.args.map { "  - \($0.name): \($0.description)" }.joined(separator: "\n")
            return "- \(tool.name)(\(argList)): \(tool.description)" + (argNotes.isEmpty ? "" : "\n\(argNotes)")
        }.joined(separator: "\n")
    }

    /// The `tool` field's `enum` constraint for the response JSON schema.
    static var names: [String] { catalog.map(\.name) }
}
