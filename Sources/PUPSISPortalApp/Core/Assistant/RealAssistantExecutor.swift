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
            answerTemperature: preferences.ragAnswerTemperature,
            answerer: preferences.ragAnswerModel, answerModel: preferences.aiModel
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
        case "move_event": return moveEvent(action)
        case "read_date": return readDate(action)
        case "set_class_status": return setClassStatus(action)
        case "set_class_time": return setClassTime(action)
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

        // Recurrence is opt-in — the model only sends repeat_days when the
        // student actually asked for a recurring event. Omitted (or blank)
        // stays exactly the one-off behavior this tool always had.
        let repeatDays = action.string("repeat_days").map(Self.weekdays(fromCommaList:)) ?? []
        let snapshot = EventSnapshot(
            title: title, calendarID: calendarID, date: date, start: start, end: end,
            repeatDays: repeatDays, repeatsWeekly: !repeatDays.isEmpty
        )
        editor.create(snapshot, inWeekStarting: Weekday.weekStart(containing: date), actionName: "Assistant: Add Event")
        let recurrenceNote = repeatDays.isEmpty ? "" : ", repeating weekly on \(repeatDays.map(\.short).joined(separator: ", "))"
        return AssistantToolResult(action: action, ok: true,
            message: "Added \"\(title)\" on \(dateString), \(ClassSession.format(start))-\(ClassSession.format(end))\(recurrenceNote).")
    }

    /// Parses a comma-separated weekday list like "mon,wed,fri" — `args` can't
    /// carry a real JSON array (`AssistantJSON` deliberately supports only
    /// primitives), so this is the one string that stands in for one.
    /// Unrecognized tokens are dropped rather than failing the whole tool call.
    private static func weekdays(fromCommaList value: String) -> [Weekday] {
        value.split(separator: ",").compactMap { token in
            let code = token.trimmingCharacters(in: .whitespaces).uppercased()
            return Weekday.allCases.first { $0.short == code }
        }
    }

    private func preferredCalendarID() -> String? {
        let configured = preferences.exportCalendarID
        if !configured.isEmpty, calendar.writableCalendars.contains(where: { $0.id == configured }) {
            return configured
        }
        return calendar.writableCalendars.first?.id
    }

    /// Reads one specific date, not a whole week — classes plus that day's
    /// calendar events, vacancy and time exceptions already resolved, via the
    /// same `DayAgenda.timeline` the Today screen draws from. Deliberately
    /// doesn't call `CalendarBridge.load(weekStart:)`, same reasoning as
    /// `readWeek` — a read tool should never move what week the user is
    /// looking at. Uses `CalendarBridge.events(on:calendarIDs:)` instead,
    /// which is read-only with respect to the visible grid.
    private func readDate(_ action: AssistantAction) -> AssistantToolResult {
        guard let dateString = action.string("date"), let date = Self.dateFormat.date(from: dateString) else {
            return AssistantToolResult(action: action, ok: false, message: "Need a valid date (yyyy-MM-dd).")
        }

        let dayEvents = calendar.events(on: date, calendarIDs: preferences.visibleCalendarIDs)
        let entries = DayAgenda.timeline(
            classes: portal.sessions, events: dayEvents, now: date,
            isVacant: { session, occurrence in
                preferences.status(for: session, on: Weekday.weekStart(containing: occurrence)) == .vacant
            },
            time: { session, occurrence in
                preferences.time(for: session, on: Weekday.weekStart(containing: occurrence))
            }
        )
        guard !entries.isEmpty else {
            return AssistantToolResult(action: action, ok: true, message: "Nothing scheduled on \(dateString).")
        }

        let lines = entries.map { "\(ClassSession.format($0.start))-\(ClassSession.format($0.end)) \($0.title)" }
        return AssistantToolResult(
            action: action, ok: true,
            message: Self.truncated((["\(dateString):"] + lines).joined(separator: "\n"))
        )
    }

    /// The one class-lookup every status/time-exception tool shares: which
    /// `ClassSession` a subject code + date names. Zero matches fails closed
    /// with what was searched; more than one (a Lec/Lab pair on the same day)
    /// fails closed asking for the disambiguating `start` unless it was
    /// already given and actually narrows it to exactly one.
    private func findSession(subjectCode: String, on date: Date, disambiguatingStart: Int?) -> (ClassSession?, String?) {
        let day = Weekday.on(date)
        let candidates = portal.sessions.filter { $0.subjectCode == subjectCode && $0.day == day }

        guard !candidates.isEmpty else {
            return (nil, "No class named \"\(subjectCode)\" meets on \(day.short) (\(Self.dateFormat.string(from: date))).")
        }
        guard candidates.count > 1 else {
            return (candidates[0], nil)
        }

        func resolvedStart(_ session: ClassSession) -> Int {
            preferences.time(for: session, on: Weekday.weekStart(containing: date)).start
        }
        guard let disambiguatingStart else {
            let times = candidates.map { ClassSession.format(resolvedStart($0)) }.joined(separator: ", ")
            return (nil, "\"\(subjectCode)\" meets more than once on \(day.short) (\(times)) — give a start time to say which one.")
        }
        guard let match = candidates.first(where: { resolvedStart($0) == disambiguatingStart }) else {
            let times = candidates.map { ClassSession.format(resolvedStart($0)) }.joined(separator: ", ")
            return (nil, "No \"\(subjectCode)\" meeting on \(day.short) starts at \(ClassSession.format(disambiguatingStart)) — it meets at \(times).")
        }
        return (match, nil)
    }

    /// "week" (default) is a this-occurrence exception; "term" is the
    /// recurring default. Anything else falls back to "week" rather than
    /// failing the call over a typo'd scope.
    private func isTermScope(_ action: AssistantAction) -> Bool {
        action.string("scope")?.lowercased() == "term"
    }

    private func setClassStatus(_ action: AssistantAction) -> AssistantToolResult {
        guard let subjectCode = action.string("subject_code") else {
            return AssistantToolResult(action: action, ok: false, message: "No subject_code given.")
        }
        guard let dateString = action.string("date"), let date = Self.dateFormat.date(from: dateString) else {
            return AssistantToolResult(action: action, ok: false, message: "Need a valid date (yyyy-MM-dd).")
        }
        guard let statusString = action.string("status")?.lowercased(), let status = SessionStatus(rawValue: statusString) else {
            return AssistantToolResult(action: action, ok: false, message: "status must be \"vacant\", \"online\", or \"regular\".")
        }
        let (session, error) = findSession(subjectCode: subjectCode, on: date, disambiguatingStart: action.int("start"))
        guard let session else {
            return AssistantToolResult(action: action, ok: false, message: error ?? "Class not found.")
        }

        let termScope = isTermScope(action)
        if termScope {
            preferences.setTermStatus(status, for: session)
        } else {
            preferences.setStatus(status, for: session, on: Weekday.weekStart(containing: date))
        }
        let scopeWord = termScope ? "every week" : "the week of \(dateString)"
        return AssistantToolResult(action: action, ok: true, message: "Marked \(subjectCode) \(status.label.lowercased()) for \(scopeWord).")
    }

    private func setClassTime(_ action: AssistantAction) -> AssistantToolResult {
        guard let subjectCode = action.string("subject_code") else {
            return AssistantToolResult(action: action, ok: false, message: "No subject_code given.")
        }
        guard let dateString = action.string("date"), let date = Self.dateFormat.date(from: dateString) else {
            return AssistantToolResult(action: action, ok: false, message: "Need a valid date (yyyy-MM-dd).")
        }
        guard let start = action.int("start"), let end = action.int("end"), end > start else {
            return AssistantToolResult(action: action, ok: false,
                message: "Need a start and end time in minutes from midnight, with end after start.")
        }
        let (session, error) = findSession(subjectCode: subjectCode, on: date, disambiguatingStart: action.int("current_start"))
        guard let session else {
            return AssistantToolResult(action: action, ok: false, message: error ?? "Class not found.")
        }

        let termScope = isTermScope(action)
        let override = TimeOverride(start: start, end: end)
        if termScope {
            preferences.setTermTime(override, for: session)
        } else {
            preferences.setTime(override, for: session, on: Weekday.weekStart(containing: date))
        }
        let scopeWord = termScope ? "every week" : "that week"
        return AssistantToolResult(action: action, ok: true,
            message: "Moved \(subjectCode) to \(ClassSession.format(start))-\(ClassSession.format(end)) for \(scopeWord).")
    }

    /// Finds an existing calendar event by title on a specific date — not
    /// through the currently-loaded week's `calendar.events`, which may not
    /// include that date at all, but through `CalendarBridge.events(on:calendarIDs:)`,
    /// same as `readDate`. Fails closed on zero or more-than-one match rather
    /// than guessing which event was meant.
    private func moveEvent(_ action: AssistantAction) -> AssistantToolResult {
        guard let title = action.string("title") else {
            return AssistantToolResult(action: action, ok: false, message: "No title given to find the event.")
        }
        guard let dateString = action.string("date"), let date = Self.dateFormat.date(from: dateString) else {
            return AssistantToolResult(action: action, ok: false, message: "Need a valid date (yyyy-MM-dd) for where the event currently is.")
        }
        guard let newDateString = action.string("new_date"), let newDate = Self.dateFormat.date(from: newDateString) else {
            return AssistantToolResult(action: action, ok: false, message: "Need a valid new_date (yyyy-MM-dd).")
        }
        guard let start = action.int("new_start"), let end = action.int("new_end"), end > start else {
            return AssistantToolResult(action: action, ok: false,
                message: "Need new_start and new_end in minutes from midnight, with end after start.")
        }

        let dayEvents = calendar.events(on: date, calendarIDs: preferences.visibleCalendarIDs)
        let matches = dayEvents.filter { $0.title.localizedCaseInsensitiveCompare(title) == .orderedSame }
        guard let match = matches.first, matches.count == 1 else {
            let found = matches.count
            let message = found == 0
                ? "No event named \"\(title)\" found on \(dateString)."
                : "More than one event named \"\(title)\" on \(dateString) — be more specific, or move it by hand."
            return AssistantToolResult(action: action, ok: false, message: message)
        }

        let scope: CalendarBridge.EditScope = action.string("scope")?.lowercased() == "future_events" ? .futureEvents : .thisEvent
        editor.move(match, to: newDate, start: start, end: end, scope: scope, actionName: "Assistant: Move Event")
        return AssistantToolResult(action: action, ok: true,
            message: "Moved \"\(title)\" to \(newDateString), \(ClassSession.format(start))-\(ClassSession.format(end)).")
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
