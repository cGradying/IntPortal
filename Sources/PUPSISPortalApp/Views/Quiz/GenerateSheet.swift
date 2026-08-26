import SwiftUI
import UniformTypeIdentifiers

/// Generate a new deck, or grow an existing one. One sheet covers all three
/// (new / append / regenerate) because they share the same source picker and
/// review-before-save step — only what "Save" does at the end differs.
///
/// Generation itself runs in `GenerationCenter`, not here — "Send to
/// background" only means something if the work survives this sheet being
/// dismissed. This view starts a job, watches it, and shows the review step
/// once it finishes; `QuizzesView`'s banner is what lets the user come back
/// to a job after backgrounding it.
struct GenerateSheet: View {
    enum GrowthMode { case append, regenerate }

    @ObservedObject var store: QuizStore
    @ObservedObject var center: GenerationCenter
    @ObservedObject var preferences: Preferences
    @ObservedObject var notes: NotesStore
    let aiModel: String
    /// nil for a brand-new deck; set when growing an existing one.
    let existing: (deck: QuizDeck, mode: GrowthMode)?
    /// Set when reopening a job that was sent to background from a since-
    /// dismissed sheet — skips straight to whatever state that job is in
    /// instead of showing the configure form again.
    var resumeJobID: UUID? = nil

    @Environment(\.dismiss) private var dismiss

    private enum SourceKind: String, CaseIterable, Identifiable {
        case topic, paste, file
        var id: String { rawValue }
        var label: String {
            switch self {
            case .topic: "Vault topic"
            case .paste: "Paste material"
            case .file: "Import file"
            }
        }
    }

    @State private var sourceKind: SourceKind = .topic
    @State private var topic = ""
    @State private var pastedText = ""
    @State private var fileURL: URL?
    @State private var fileError: String?
    @State private var deckName = ""
    @State private var jobID: UUID?
    @State private var configError: String?

    private var job: GenerationCenter.Job? {
        jobID.flatMap { id in center.jobs.first { $0.id == id } }
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(existing == nil ? "Generate deck" : (existing!.mode == .append ? "Generate more" : "Regenerate deck"))
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            if let jobID { center.cancel(jobID) }
                            dismiss()
                        }
                    }
                }
        }
        // A fixed .frame(width:height:) locks a sheet at that exact size —
        // macOS only offers the drag-to-resize edge when the content's own
        // frame is flexible. min/ideal/max gives the same starting size but
        // lets the user actually resize it, which a deck full of cards to
        // review genuinely benefits from.
        .frame(minWidth: 460, idealWidth: 520, maxWidth: 900, minHeight: 420, idealHeight: 480, maxHeight: 800)
        .onAppear {
            guard jobID == nil, let resumeJobID else { return }
            jobID = resumeJobID
        }
    }

    @ViewBuilder
    private var content: some View {
        if let job {
            if let result = job.result {
                CardReviewSheet(
                    cards: result.cards, failedChunks: result.failedChunks, totalChunks: result.totalChunks,
                    truncatedMaterial: result.truncatedMaterial,
                    existingDeckName: existing?.deck.name,
                    regeneratePreview: existing?.mode == .regenerate
                        ? quizRegeneratePreview(old: existing!.deck.cards, new: result.cards) : nil,
                    onSave: { finalCards in save(finalCards); center.dismiss(job.id) },
                    onBack: { center.dismiss(job.id); jobID = nil }
                )
            } else if let failure = job.failure {
                failedView(failure) { center.dismiss(job.id); jobID = nil }
            } else {
                generatingView(job)
            }
        } else if let configError {
            failedView(configError) { self.configError = nil }
        } else {
            configureForm
        }
    }

    // MARK: Configure

    private var configureForm: some View {
        Form {
            if existing?.mode == .regenerate {
                Section {
                    Text("Regenerates \u{201C}\(existing!.deck.name)\u{201D} from its original source: \(existing!.deck.sourceQuery)")
                        .foregroundStyle(.secondary)
                }
            } else {
                Section("Source") {
                    Picker("From", selection: $sourceKind) {
                        ForEach(SourceKind.allCases) { Text($0.label).tag($0) }
                    }
                    switch sourceKind {
                    case .topic:
                        TextField("Topic, e.g. \"thermodynamics\"", text: $topic)
                    case .paste:
                        TextEditor(text: $pastedText)
                            .frame(minHeight: 140)
                            .overlay(alignment: .topLeading) {
                                if pastedText.isEmpty {
                                    Text("Paste study material here").foregroundStyle(.tertiary).padding(6)
                                        .allowsHitTesting(false)
                                }
                            }
                    case .file:
                        HStack {
                            Button("Choose file…") { pickFile() }
                            if let fileURL { Text(fileURL.lastPathComponent).foregroundStyle(.secondary) }
                        }
                        if let fileError { Text(fileError).foregroundStyle(.red).font(.caption) }
                    }
                }
                if existing == nil {
                    Section("Deck name") {
                        TextField("Auto-named from the source if left blank", text: $deckName)
                    }
                }
            }
            Section {
                Button(existing?.mode == .regenerate ? "Regenerate" : "Generate") { startGeneration() }
                    .disabled(!canGenerate)
            }
        }
        .formStyle(.grouped)
    }

    private var canGenerate: Bool {
        guard existing?.mode != .regenerate else { return true }
        switch sourceKind {
        case .topic: return !topic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .paste: return !pastedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .file: return fileURL != nil
        }
    }

    private func pickFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText, UTType(filenameExtension: "md") ?? .plainText, .pdf]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        fileURL = url
        fileError = nil
    }

    // MARK: Generate

    private func resolveSource() -> QuizSource? {
        if existing?.mode == .regenerate, let deck = existing?.deck {
            switch deck.sourceKind {
            case .vaultTopic: return .vaultTopic(deck.sourceQuery)
            case .material:
                // The original pasted/imported text isn't retained on disk —
                // only the label is. Regenerate can't replay it.
                return nil
            }
        }
        switch sourceKind {
        case .topic:
            return .vaultTopic(topic.trimmingCharacters(in: .whitespacesAndNewlines))
        case .paste:
            return .material(text: pastedText, label: "Pasted text")
        case .file:
            guard let fileURL else { return nil }
            do {
                let text = try MaterialImport.text(from: fileURL)
                return .material(text: text, label: fileURL.lastPathComponent)
            } catch {
                fileError = error.localizedDescription
                return nil
            }
        }
    }

    private func startGeneration() {
        guard let source = resolveSource() else {
            if existing?.mode == .regenerate {
                configError = "This deck was generated from material that isn't kept on disk — only vault-topic decks can be regenerated. Use \u{201C}Generate more\u{201D} with new material instead."
            }
            return
        }
        if deckName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            deckName = defaultDeckName(for: source)
        }
        let ragQuery = sourceKind == .topic || existing?.mode == .regenerate ? RAGQuery(notes: notes) : nil
        let target: GenerationCenter.Target = existing.map {
            $0.mode == .append ? .append(deckID: $0.deck.id) : .regenerate(deckID: $0.deck.id)
        } ?? .new(name: deckName, sourceKind: sourceKindForNewDeck, sourceQuery: sourceQueryForNewDeck)
        jobID = center.start(
            label: deckName, source: source, model: aiModel, client: LlamaCppClient(),
            ragQuery: ragQuery, chunkSize: preferences.ragChunkSize, target: target
        )
    }

    private func defaultDeckName(for source: QuizSource) -> String {
        switch source {
        case .vaultTopic(let topic): return String(topic.prefix(60))
        case .material(_, let label): return String(label.prefix(60))
        }
    }

    private func generatingView(_ job: GenerationCenter.Job) -> some View {
        VStack(spacing: 16) {
            ProgressView(value: job.total > 0 ? Double(job.done) / Double(job.total) : 0)
                .frame(width: 280)
            Text(job.total > 0 ? "Generating from chunk \(min(job.done + 1, job.total)) of \(job.total)\u{2026}" : "Preparing\u{2026}")
                .foregroundStyle(.secondary)
            Button("Send to background") { dismiss() }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func failedView(_ message: String, dismissAction: @escaping () -> Void) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle").font(.largeTitle).foregroundStyle(.orange)
            Text(message).multilineTextAlignment(.center)
            Button("Try again") { dismissAction() }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Save

    private func save(_ cards: [QuizCard]) {
        guard let existing else {
            // Read the deck's identity from the job's target, not local form
            // state — a resumed (backgrounded, sheet re-opened) job has none
            // of that state, only what it was started with.
            let (name, kind, query): (String, QuizSourceKind, String)
            if case .new(let n, let k, let q) = job?.target {
                (name, kind, query) = (n, k, q)
            } else {
                (name, kind, query) = (
                    deckName.isEmpty ? "Untitled deck" : deckName,
                    sourceKindForNewDeck, sourceQueryForNewDeck
                )
            }
            store.addDeck(QuizDeck(name: name, sourceKind: kind, sourceQuery: query, cards: cards))
            dismiss()
            return
        }
        switch existing.mode {
        case .append:
            store.appendCards(cards, to: existing.deck.id)
        case .regenerate:
            store.replaceCards(cards, in: existing.deck.id)
        }
        dismiss()
    }

    private var sourceKindForNewDeck: QuizSourceKind {
        sourceKind == .topic ? .vaultTopic : .material
    }
    private var sourceQueryForNewDeck: String {
        switch sourceKind {
        case .topic: return topic.trimmingCharacters(in: .whitespacesAndNewlines)
        case .paste: return "Pasted text"
        case .file: return fileURL?.lastPathComponent ?? "Imported file"
        }
    }
}
