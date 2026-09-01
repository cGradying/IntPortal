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
        /// JSON Schema primitive type — every argument in this catalog is
        /// either a string or a whole number, so this is the whole vocabulary
        /// `argsSchema` needs, not a general JSON Schema type system.
        var type: String = "string"
        /// Whether the model must supply this argument — an optional one
        /// (documented in `description` as "omitted"/"optional") is left out
        /// of `argsSchema`'s `required` list, not made nullable.
        var required: Bool = true
    }

    let name: String
    /// One line, written for the model: what it does and when to use it.
    let description: String
    /// Argument name → one-line description, `type`, and `required` — used
    /// both for the system prompt (`promptCatalog`) and, since Granite can
    /// actually follow a tight schema (unlike the sub-3B models this catalog
    /// was first tuned against), the response schema's per-tool validation
    /// (`argsSchema`).
    let args: [Arg]

    /// v1 scope, per the plan: notes read+write, calendar read + write
    /// (add/move an event, mark a class vacant/online, move a class's time),
    /// grades read-only. No delete or rename tool exists anywhere in this
    /// catalog — that's deliberate, not an oversight to fill in later.
    static let catalog: [AssistantTool] = [
        AssistantTool(
            name: "read_note",
            description: "Read a note's text.",
            args: [Arg(name: "key", description: "note key, or omitted for the currently open note", required: false)]
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
            description: "Answer a question by searching the student's notes and having the assistant model synthesize a grounded answer from what's found — not just a list of matches like search_notes. Use this when the student wants an actual answer synthesized from their notes, not just to see what matched.",
            args: [Arg(name: "query", description: "the question to answer from the student's notes")]
        ),
        AssistantTool(
            name: "append_note",
            description: "Add text to the end of a note, keeping what's already there.",
            args: [
                Arg(name: "key", description: "note key, or omitted for the currently open note", required: false),
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
            args: [Arg(name: "weekStart", description: "yyyy-MM-dd, or omitted for the current week", required: false)]
        ),
        AssistantTool(
            name: "add_event",
            description: "Add a new calendar event, optionally repeating weekly. Cannot rename or delete existing events.",
            args: [
                Arg(name: "title", description: "event title"),
                Arg(name: "date", description: "yyyy-MM-dd — for a repeating event, the first occurrence"),
                Arg(name: "start", description: "start time, minutes from midnight", type: "integer"),
                Arg(name: "end", description: "end time, minutes from midnight", type: "integer"),
                Arg(name: "repeat_days", description: "optional — only when the student actually asked for a recurring event: comma-separated weekdays, e.g. \"mon,wed,fri\". Omit for a one-off event.", required: false),
            ]
        ),
        AssistantTool(
            name: "move_event",
            description: "Move an existing calendar event to a new date and/or time. Cannot rename or delete it.",
            args: [
                Arg(name: "title", description: "the event's current title, to find it"),
                Arg(name: "date", description: "yyyy-MM-dd — the date it's currently on"),
                Arg(name: "new_date", description: "yyyy-MM-dd — the date to move it to"),
                Arg(name: "new_start", description: "new start time, minutes from midnight", type: "integer"),
                Arg(name: "new_end", description: "new end time, minutes from midnight", type: "integer"),
                Arg(name: "scope", description: "\"this_event\" (default) for just this occurrence, or \"future_events\" for a repeating event and everything after it", required: false),
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
                Arg(name: "scope", description: "\"week\" (default) for just that week, or \"term\" for every week", required: false),
                Arg(name: "start", description: "optional, minutes from midnight — only needed if the subject meets more than once that day (e.g. a Lec and a Lab) and it's ambiguous which one is meant", type: "integer", required: false),
            ]
        ),
        AssistantTool(
            name: "set_class_time",
            description: "Move a class to a different start/end time.",
            args: [
                Arg(name: "subject_code", description: "the class's subject code"),
                Arg(name: "date", description: "yyyy-MM-dd — a date the class actually meets on"),
                Arg(name: "start", description: "new start time, minutes from midnight", type: "integer"),
                Arg(name: "end", description: "new end time, minutes from midnight", type: "integer"),
                Arg(name: "scope", description: "\"week\" (default) for just that week, or \"term\" for every week", required: false),
                Arg(name: "current_start", description: "optional, minutes from midnight — disambiguates when the subject meets more than once that day; this is the class's CURRENT start, not the new one", type: "integer", required: false),
            ]
        ),
        AssistantTool(
            name: "read_grades",
            description: "Read the student's posted grades and GPA. Grades cannot be changed by this tool or any other.",
            args: []
        ),
        AssistantTool(
            name: "read_syllabus",
            description: "Read the student's syllabus items for a subject, or every subject if omitted.",
            args: [Arg(name: "subject_code", description: "e.g. \"COMP 20073\", or omitted for every subject", required: false)]
        ),
        AssistantTool(
            name: "add_syllabus_item",
            description: "Add one syllabus item — a week's topic, a quiz, an exam, or a project deadline. When structuring a pasted syllabus or generating one from scratch, call this once per item — several times in the same turn to add a whole syllabus at once.",
            args: [
                Arg(name: "subject_code", description: "e.g. \"COMP 20073\""),
                Arg(name: "topic", description: "what the item is, e.g. \"Chain rule\" or \"Midterm exam\""),
                Arg(name: "type", description: "\"lecture\", \"quiz\", \"exam\", or \"project\""),
                Arg(name: "date", description: "yyyy-MM-dd, or omitted if no real date is known for it yet", required: false),
                Arg(name: "week", description: "week number within the term, or omitted", type: "integer", required: false),
            ]
        ),
        AssistantTool(
            name: "set_syllabus_item_status",
            description: "Mark a syllabus item done, or clear that back to automatic (date-derived) status. Cannot rename or delete the item.",
            args: [
                Arg(name: "subject_code", description: "the item's subject code"),
                Arg(name: "topic", description: "the item's topic, to find it — must match an existing item exactly"),
                Arg(name: "done", description: "\"true\" to mark it done, \"false\" to un-mark it and go back to automatic status"),
            ]
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

    /// One `oneOf` branch per tool — `{tool: <const name>, args: {...}}` with
    /// that tool's real argument shape — derived straight from `catalog`, so
    /// it can never drift from `promptCatalog`/`names` the way a hand-written
    /// parallel schema could. Ollama's `format` degrades models below ~3B
    /// badly against a schema this tight (the original reason `args` stayed
    /// generic); Granite is what this is built for.
    static var argsSchema: [String: Any] {
        [
            "oneOf": catalog.map { tool -> [String: Any] in
                var properties: [String: Any] = [:]
                for arg in tool.args { properties[arg.name] = ["type": arg.type] }
                let required = tool.args.filter(\.required).map(\.name)
                var argsSchema: [String: Any] = ["type": "object", "properties": properties]
                if !required.isEmpty { argsSchema["required"] = required }
                return [
                    "type": "object",
                    "properties": [
                        "tool": ["const": tool.name],
                        "args": argsSchema,
                    ],
                    "required": ["tool"],
                ]
            },
        ]
    }
}
