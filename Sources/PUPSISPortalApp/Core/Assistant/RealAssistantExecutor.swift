import Foundation

/// The assistant's real hands: every case here goes through the same store
/// methods the UI itself uses (`NotesStore.setText`, `EventEditor.create`,
/// …) — never a raw file write, never a direct EventKit call. That's what
/// keeps undo, persistence, and validation identical to a human doing it by
/// hand through the app.
///
/// v1 scope only: notes read+write, calendar read + add-only, grades
/// read-only. There is deliberately no case for anything else — an unknown
/// tool name (from a hallucinating model, or a future catalog entry this
/// executor hasn't caught up to) fails closed with a message, never a crash.
@MainActor
final class RealAssistantExecutor: AssistantExecutor {
    private let notesStore: NotesStore
    private let editor: EventEditor
    private let calendar: CalendarBridge
    private let portal: PortalController
    private let preferences: Preferences
    /// The note the user currently has open, if any — resolved fresh on every
    /// call rather than captured once, since it can change mid-conversation.
    private let openNoteKey: () -> String?
    /// The retrieval + grounded-answer pipeline behind `search_notes`/
    /// `ask_notes` — shared with the `/rag` slash command, see its own doc
    /// comment for why. Built from the same injectable pieces
    /// (`llamaCppClient`/`ensureServerRunning`/`ollamaClient`) this
    /// initializer always took, so existing tests construct it exactly as
    /// before.
    private let ragQuery: RAGQuery

    /// Tool-result strings are fed back to the model in `.auto` mode and shown
    /// in the confirm-row UI — capped so one enormous note can't blow out
    /// either.
    private static let resultCharLimit = 4000

    init(
        notes: NotesStore,
        editor: EventEditor,
        calendar: CalendarBridge,
        portal: PortalController,
        preferences: Preferences,
        openNoteKey: @escaping () -> String?,
        llamaCppClient: LlamaCppClient = LlamaCppClient(),
        ensureServerRunning: @escaping () async -> Bool = { await LlamaServerManager.shared.ensureRunning() },
        ollamaClient: OllamaClient = OllamaClient()
    ) {
        self.notesStore = notes
        self.editor = editor
        self.calendar = calendar
        self.portal = portal
        self.preferences = preferences
        self.openNoteKey = openNoteKey
        self.ragQuery = RAGQuery(
            notes: notes, ollamaClient: ollamaClient, llamaCppClient: llamaCppClient,
            ensureServerRunning: ensureServerRunning,
            embedModel: preferences.ragEmbedModel, chunkSize: preferences.ragChunkSize,
            similarityFloor: preferences.ragSimilarityFloor, contextBudget: preferences.ragContextBudget,
            answerTemperature: preferences.ragAnswerTemperature
        )
    }

    func execute(_ action: AssistantAction) async -> AssistantToolResult {
        switch action.tool {
        case "read_note": return readNote(action)
        case "list_notes": return listNotes(action)
        case "search_notes": return await searchNotes(action)
        case "ask_notes": return await askNotes(action)
        case "append_note": return appendNote(action)
        case "create_note": return createNote(action)
        case "read_week": return readWeek(action)
        case "add_event": return addEvent(action)
        case "read_grades": return readGrades(action)
        default:
            return AssistantToolResult(action: action, ok: false, message: "Unknown tool '\(action.tool)'.")
        }
    }

    // MARK: Notes

    private func resolvedKey(_ action: AssistantAction) -> String? {
        action.string("key") ?? openNoteKey()
    }

    private func readNote(_ action: AssistantAction) -> AssistantToolResult {
        guard let key = resolvedKey(action) else {
            return AssistantToolResult(action: action, ok: false, message: "No note is open and no key was given.")
        }
        let text = notesStore.text(for: key)
        guard !text.isEmpty else {
            return AssistantToolResult(action: action, ok: true, message: "That note is empty.")
        }
        return AssistantToolResult(action: action, ok: true, message: Self.truncated(text))
    }

    private func listNotes(_ action: AssistantAction) -> AssistantToolResult {
        let vaultNames = Self.fileNames(in: notesStore.vault)
        let subjectAndDayKeys = notesStore.notes.keys
            .filter { $0.hasPrefix("class:") || $0.hasPrefix("day:") }
            .sorted()

        var lines: [String] = []
        if !vaultNames.isEmpty { lines.append("Vault: " + vaultNames.sorted().joined(separator: ", ")) }
        if !subjectAndDayKeys.isEmpty { lines.append("Class/day notes: " + subjectAndDayKeys.joined(separator: ", ")) }
        guard !lines.isEmpty else {
            return AssistantToolResult(action: action, ok: true, message: "No notes exist yet.")
        }
        return AssistantToolResult(action: action, ok: true, message: Self.truncated(lines.joined(separator: "\n")))
    }

    private static func fileNames(in nodes: [VaultNode]) -> [String] {
        nodes.flatMap { node -> [String] in
            node.isFolder ? fileNames(in: node.children ?? []) : [node.name]
        }
    }

    /// Retrieval half of "RAG over your notes" — delegates to `RAGQuery`
    /// (embeddings first, term-matching fallback; see its own doc comment).
    /// Only notes the user has left in the RAG (`NotesStore.ragIncludedKeys`)
    /// are ever searched — the right-click "Include in AI search" toggle.
    private func searchNotes(_ action: AssistantAction) async -> AssistantToolResult {
        guard let query = action.string("query") else {
            return AssistantToolResult(action: action, ok: false, message: "No search query given.")
        }
        let hits = await ragQuery.search(query)
        guard !hits.isEmpty else {
            return AssistantToolResult(action: action, ok: true, message: "No notes matched \"\(query)\".")
        }
        let lines = hits.map { "\($0.name): …\($0.text.prefix(160))…" }
        return AssistantToolResult(
            action: action, ok: true,
            message: Self.truncated(lines.joined(separator: "\n")),
            sources: Self.uniqueNames(hits)
        )
    }

    private static func uniqueNames(_ hits: [NoteChunk]) -> [String] {
        var seen = Set<String>()
        return hits.map(\.name).filter { seen.insert($0).inserted }
    }

    /// Generation half of RAG over the notes vault — delegates to `RAGQuery`,
    /// translating its two expected failure modes (nothing matched / server
    /// unavailable) into the `ok: true`/`ok: false` split the model and the
    /// confirm-row UI expect.
    private func askNotes(_ action: AssistantAction) async -> AssistantToolResult {
        guard let query = action.string("query") else {
            return AssistantToolResult(action: action, ok: false, message: "No question given.")
        }
        do {
            let answer = try await ragQuery.ask(query)
            return AssistantToolResult(action: action, ok: true, message: answer.text, sources: answer.sources)
        } catch let error as RAGQuery.QueryError {
            let ok = error == .noMatch(query)
            return AssistantToolResult(action: action, ok: ok, message: error.localizedDescription)
        } catch {
            return AssistantToolResult(action: action, ok: false, message: error.localizedDescription)
        }
    }

    /// The one place the spike's near-miss (an empty argument silently
    /// deleting a note via `NotesStore.setText`) is actually blocked —
    /// `AssistantAction.string(_:)` already treats whitespace-only as absent.
    private func appendNote(_ action: AssistantAction) -> AssistantToolResult {
        guard let key = resolvedKey(action) else {
            return AssistantToolResult(action: action, ok: false, message: "No note is open and no key was given.")
        }
        guard let text = action.string("text") else {
            return AssistantToolResult(action: action, ok: false, message: "No text given — nothing was added.")
        }
        let existing = notesStore.text(for: key)
        let combined = existing.isEmpty ? text : existing + "\n\n" + text
        notesStore.setText(combined, for: key)
        return AssistantToolResult(action: action, ok: true, message: "Added to \(displayName(for: key)).")
    }

    private func createNote(_ action: AssistantAction) -> AssistantToolResult {
        let name = action.string("name") ?? "Untitled"
        let key = notesStore.addFile(name: name, to: nil)
        if let text = action.string("text") {
            notesStore.setText(text, for: key)
        }
        return AssistantToolResult(action: action, ok: true, message: "Created note \"\(name)\".")
    }

    private func displayName(for key: String) -> String {
        if key.hasPrefix("class:") { return String(key.dropFirst("class:".count)) }
        if key.hasPrefix("vault:") { return notesStore.vaultName(forKey: key) ?? "the note" }
        return key
    }

    // MARK: Calendar

    /// Deliberately doesn't call `CalendarBridge.load(weekStart:)` for an
    /// arbitrary requested week — that mutates the `@Published events` the
    /// visible `CalendarView` is bound to, so a *read* tool changing what
    /// week the user is looking at would be a surprising side effect. Classes
    /// are weekly-recurring so they're accurate regardless of week; calendar
    /// events are only reported for whatever week is already loaded.
    private func readWeek(_ action: AssistantAction) -> AssistantToolResult {
        // Term-level resolution only — a recurring move, never a this-week-only
        // exception, since this listing is explicitly labelled "every week".
        func termTime(_ session: ClassSession) -> (Int, Int) {
            preferences.termTimes[session.id].map { ($0.start, $0.end) } ?? (session.start, session.end)
        }
        let classLines = portal.sessions
            .sorted { ($0.day.rawValue, $0.start) < ($1.day.rawValue, $1.start) }
            .map { session -> String in
                let (start, end) = termTime(session)
                return "\(session.day.short) \(session.subjectCode) \(ClassSession.format(start))-\(ClassSession.format(end))"
            }

        let eventLines = calendar.events
            .filter { if case .calendarEvent = $0.source { return true } else { return false } }
            .sorted { ($0.day.rawValue, $0.start) < ($1.day.rawValue, $1.start) }
            .map { "\($0.day.short) \($0.title) \(ClassSession.format($0.start))-\(ClassSession.format($0.end))" }

        var lines = ["Classes (every week):"]
        lines += classLines.isEmpty ? ["none"] : classLines
        lines.append("")
        lines.append("Calendar events (currently loaded week):")
        lines += eventLines.isEmpty ? ["none"] : eventLines

        return AssistantToolResult(action: action, ok: true, message: Self.truncated(lines.joined(separator: "\n")))
    }

    private static let dateFormat: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.calendar = Calendar(identifier: .gregorian)
        return formatter
    }()

    private func addEvent(_ action: AssistantAction) -> AssistantToolResult {
        let title = action.string("title") ?? "New event"

        guard let dateString = action.string("date"), let date = Self.dateFormat.date(from: dateString) else {
            return AssistantToolResult(action: action, ok: false, message: "Need a valid date (yyyy-MM-dd).")
        }
        guard let start = action.int("start"), let end = action.int("end"), end > start else {
            return AssistantToolResult(action: action, ok: false,
                message: "Need a start and end time in minutes from midnight, with end after start.")
        }
        guard let calendarID = preferredCalendarID() else {
            return AssistantToolResult(action: action, ok: false, message: "No writable calendar is available to add to.")
        }

        let snapshot = EventSnapshot(title: title, calendarID: calendarID, date: date, start: start, end: end, repeatDays: [])
        editor.create(snapshot, inWeekStarting: Weekday.weekStart(containing: date), actionName: "Assistant: Add Event")
        return AssistantToolResult(action: action, ok: true,
            message: "Added \"\(title)\" on \(dateString), \(ClassSession.format(start))-\(ClassSession.format(end)).")
    }

    private func preferredCalendarID() -> String? {
        let configured = preferences.exportCalendarID
        if !configured.isEmpty, calendar.writableCalendars.contains(where: { $0.id == configured }) {
            return configured
        }
        return calendar.writableCalendars.first?.id
    }

    // MARK: Grades (read-only — no other case here ever writes one)

    private func readGrades(_ action: AssistantAction) -> AssistantToolResult {
        guard let report = portal.grades else {
            return AssistantToolResult(action: action, ok: true, message: "No grades loaded yet.")
        }
        guard report.hasPostedGrades else {
            return AssistantToolResult(action: action, ok: true, message: "No grades posted yet for this term.")
        }
        var lines = report.subjects.map { "\($0.subjectCode): \($0.finalGrade.isEmpty ? "ungraded" : $0.finalGrade)" }
        if let gpa = report.computedGPA {
            lines.append("GPA: \(String(format: "%.2f", gpa))")
        }
        return AssistantToolResult(action: action, ok: true, message: Self.truncated(lines.joined(separator: "\n")))
    }

    private static func truncated(_ text: String) -> String {
        text.count > resultCharLimit ? String(text.prefix(resultCharLimit)) + "\n[...truncated]" : text
    }
}
