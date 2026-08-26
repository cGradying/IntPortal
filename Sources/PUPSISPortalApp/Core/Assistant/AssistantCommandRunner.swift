import Foundation

/// Runs a parsed `AssistantCommand` against the real stores. Deliberately not
/// `AssistantExecutor` — commands never go through the model's tool-picking
/// loop at all, so there's no `AssistantAction` to produce, just a reply and
/// (for `/read`) a note to pin.
@MainActor
struct AssistantCommandRunner {
    /// A note pinned into the conversation by `/read` — shown as a chip in the
    /// panel header and rendered into the system prompt until unpinned or a
    /// different `/read` replaces it.
    struct PinnedNote: Equatable {
        let name: String
        let text: String
    }

    struct Outcome {
        let reply: String
        var pin: PinnedNote?
        /// True for `/create` — lets the panel show a distinct confirmation
        /// styling later if that's ever wanted; unused today beyond that.
        var wroteNote: Bool = false
        /// Note names `/rag` actually answered from — mirrors
        /// `AssistantToolResult.sources`, rendered the same way in the panel.
        var sources: [String] = []
    }

    private let notes: NotesStore
    private let openNoteKey: () -> String?
    private let client: OllamaClient
    private let model: String
    private let ragQuery: RAGQuery
    /// `/think` writes here directly — a UI setting, not a tool call.
    private let preferences: Preferences
    /// `/date`, `/vacant`, `/online`, `/regular` all delegate to this rather
    /// than duplicating any calendar logic — they just build the same
    /// `AssistantAction` the model's tool-picking would, deterministically.
    private let executor: RealAssistantExecutor

    init(
        notes: NotesStore,
        openNoteKey: @escaping () -> String?,
        model: String,
        preferences: Preferences,
        executor: RealAssistantExecutor,
        client: OllamaClient = OllamaClient(),
        ragQuery: RAGQuery? = nil
    ) {
        self.notes = notes
        self.openNoteKey = openNoteKey
        self.model = model
        self.client = client
        self.executor = executor
        self.preferences = preferences
        self.ragQuery = ragQuery ?? RAGQuery(
            notes: notes,
            embedModel: preferences.ragEmbedModel, chunkSize: preferences.ragChunkSize,
            similarityFloor: preferences.ragSimilarityFloor, contextBudget: preferences.ragContextBudget,
            answerTemperature: preferences.ragAnswerTemperature,
            answerer: preferences.ragAnswerModel, answerModel: preferences.aiModel
        )
    }

    func run(_ command: AssistantCommand) async -> Outcome {
        switch command {
        case .read(let name): return read(name)
        case .summary(let name): return await summary(name)
        case .create(let prompt): return await create(prompt)
        case .rag(let prompt): return await rag(prompt)
        case .date(let dateString): return await readDate(dateString)
        case .classStatus(let subject, let dateString, let status): return await setClassStatus(subject, dateString, status)
        case .week(let weekStart): return await readWeek(weekStart)
        case .grades: return await readGrades()
        case .notes: return await listNotes()
        case .find(let query): return await find(query)
        case .event(let title, let date, let start, let end): return await addEvent(title, date, start, end)
        case .move(let title, let date, let newDate, let newStart, let newEnd): return await moveEvent(title, date, newDate, newStart, newEnd)
        case .think(let level):
            preferences.aiThinking = level
            return Outcome(reply: "Thinking set to \(level.label). \(level.explanation)", pin: nil)
        case .help: return Outcome(reply: AssistantCommand.helpText, pin: nil)
        case .unknown(let word):
            return Outcome(reply: "Unknown command /\(word).\n\n\(AssistantCommand.helpText)", pin: nil)
        }
    }

    /// Always actually searches the vault — no model in the loop deciding
    /// whether to bother, see the doc comment on `AssistantCommand.rag`.
    private func rag(_ prompt: String) async -> Outcome {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return Outcome(reply: #"Ask something, e.g. `/rag "what does my Sapiens note say about the agricultural revolution?"`."#, pin: nil)
        }
        do {
            let answer = try await ragQuery.ask(trimmed)
            return Outcome(reply: answer.text, pin: nil, sources: answer.sources)
        } catch {
            return Outcome(reply: error.localizedDescription, pin: nil)
        }
    }

    private func readDate(_ dateString: String) async -> Outcome {
        let trimmed = dateString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return Outcome(reply: #"Give a date, e.g. `/date 2026-08-30`."#, pin: nil)
        }
        let result = await executor.execute(AssistantAction(tool: "read_date", args: ["date": .string(trimmed)]))
        return Outcome(reply: result.message, pin: nil)
    }

    private func setClassStatus(_ subject: String, _ dateString: String, _ status: String) async -> Outcome {
        let subject = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        let dateString = dateString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !subject.isEmpty, !dateString.isEmpty else {
            return Outcome(reply: #"Give a subject and a date, e.g. `/\#(status) "COMP 20073" 2026-08-30`."#, pin: nil)
        }
        let action = AssistantAction(tool: "set_class_status", args: [
            "subject_code": .string(subject), "date": .string(dateString), "status": .string(status),
        ])
        let result = await executor.execute(action)
        return Outcome(reply: result.message, pin: nil)
    }

    private func readWeek(_ weekStart: String) async -> Outcome {
        let trimmed = weekStart.trimmingCharacters(in: .whitespacesAndNewlines)
        var args: [String: AssistantJSON] = [:]
        if !trimmed.isEmpty { args["weekStart"] = .string(trimmed) }
        let result = await executor.execute(AssistantAction(tool: "read_week", args: args))
        return Outcome(reply: result.message, pin: nil)
    }

    private func readGrades() async -> Outcome {
        let result = await executor.execute(AssistantAction(tool: "read_grades"))
        return Outcome(reply: result.message, pin: nil)
    }

    private func listNotes() async -> Outcome {
        let result = await executor.execute(AssistantAction(tool: "list_notes"))
        return Outcome(reply: result.message, pin: nil)
    }

    /// Just the matches — `/rag` above is the synthesized-answer sibling.
    private func find(_ query: String) async -> Outcome {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return Outcome(reply: #"Give something to search for, e.g. `/find "photosynthesis"`."#, pin: nil)
        }
        let result = await executor.execute(AssistantAction(tool: "search_notes", args: ["query": .string(trimmed)]))
        return Outcome(reply: result.message, pin: nil, sources: result.sources)
    }

    private func addEvent(_ title: String, _ date: String, _ start: String, _ end: String) async -> Outcome {
        guard !title.isEmpty, !date.isEmpty, !start.isEmpty, !end.isEmpty else {
            return Outcome(reply: #"Give a title, date, start, and end, e.g. `/event "Study group" 2026-08-30 780 900`."#, pin: nil)
        }
        let action = AssistantAction(tool: "add_event", args: [
            "title": .string(title), "date": .string(date), "start": .string(start), "end": .string(end),
        ])
        let result = await executor.execute(action)
        return Outcome(reply: result.message, pin: nil)
    }

    private func moveEvent(_ title: String, _ date: String, _ newDate: String, _ newStart: String, _ newEnd: String) async -> Outcome {
        guard !title.isEmpty, !date.isEmpty, !newDate.isEmpty, !newStart.isEmpty, !newEnd.isEmpty else {
            return Outcome(reply: #"Give a title, its current date, and the new date/start/end, e.g. `/move "Study group" 2026-08-30 2026-08-31 780 900`."#, pin: nil)
        }
        let action = AssistantAction(tool: "move_event", args: [
            "title": .string(title), "date": .string(date),
            "new_date": .string(newDate), "new_start": .string(newStart), "new_end": .string(newEnd),
        ])
        let result = await executor.execute(action)
        return Outcome(reply: result.message, pin: nil)
    }

    private func read(_ name: String?) -> Outcome {
        guard let key = resolvedKey(for: name) else {
            return notFound(name)
        }
        let text = notes.text(for: key)
        guard !text.isEmpty else {
            return Outcome(reply: "\(displayName(key)) is empty.", pin: nil)
        }
        let pin = PinnedNote(name: displayName(key), text: text)
        return Outcome(reply: "Pinned \"\(pin.name)\" — ask away.", pin: pin)
    }

    private func summary(_ name: String) async -> Outcome {
        guard let key = resolvedKey(for: name) else { return notFound(name) }
        let text = notes.text(for: key)
        guard !text.isEmpty else {
            return Outcome(reply: "\(displayName(key)) is empty — nothing to summarize.", pin: nil)
        }
        do {
            let summary = try await client.generate(
                model: model, selection: text, instruction: Self.summarizeInstruction
            )
            return Outcome(reply: summary, pin: nil)
        } catch {
            return Outcome(reply: error.localizedDescription, pin: nil)
        }
    }

    private func create(_ prompt: String) async -> Outcome {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return Outcome(reply: "Say what the note should be about, e.g. `/create photosynthesis basics`.", pin: nil)
        }
        do {
            let text = try await client.generate(model: model, selection: trimmed, instruction: Self.createInstruction)
            let name = String(trimmed.prefix(60))
            let key = notes.addFile(name: name, to: nil)
            notes.setText(text, for: key)
            return Outcome(reply: "Created \"\(name)\".", pin: nil, wroteNote: true)
        } catch {
            return Outcome(reply: error.localizedDescription, pin: nil)
        }
    }

    private func resolvedKey(for name: String?) -> String? {
        guard let name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return openNoteKey()
        }
        return notes.key(forName: name)
    }

    private func notFound(_ name: String?) -> Outcome {
        guard let name, !name.isEmpty else {
            return Outcome(reply: "No note is open and no name was given.", pin: nil)
        }
        let names = notes.noteNames()
        let list = names.isEmpty ? "There are no notes yet." : "Notes you have: " + names.joined(separator: ", ")
        return Outcome(reply: "No note named \"\(name)\". \(list)", pin: nil)
    }

    private func displayName(_ key: String) -> String {
        if key.hasPrefix("class:") { return String(key.dropFirst("class:".count)) }
        if key.hasPrefix("vault:") { return notes.vaultName(forKey: key) ?? "the note" }
        return key
    }

    // MARK: House-style instructions

    static let summarizeInstruction = """
    Summarize the following note for a student, in a few short sentences. \
    Reply with the summary only — no preamble, no restating the request.
    """

    static let createInstruction = """
    Write a new study note in Markdown for the topic below. Reply with the \
    note's body only — no title line, no preamble.
    """
}
