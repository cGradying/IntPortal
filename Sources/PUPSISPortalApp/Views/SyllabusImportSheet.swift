import SwiftUI
import UniformTypeIdentifiers

/// Get a syllabus in — import a file, paste text, or generate a from-scratch
/// outline; extract it into structured `SyllabusItem`s via `SyllabusExtractor`;
/// review and edit before anything is saved. Same three-step shape as
/// `Views/Quiz/GenerateSheet.swift` (configure → generating → review), scaled
/// down: a syllabus run is 1–3 chunks, not a dozen, so this owns its own
/// `Task` rather than going through a `GenerationCenter`-style background owner.
struct SyllabusImportSheet: View {
    @ObservedObject var syllabus: SyllabusStore
    @ObservedObject var preferences: Preferences
    /// Every subject code currently on the schedule — the picker's choices.
    let subjectCodes: [String]
    let aiModel: String

    @Environment(\.dismiss) private var dismiss

    private enum SourceKind: String, CaseIterable, Identifiable {
        case file, paste, generate
        var id: String { rawValue }
        var label: String {
            switch self {
            case .file: "Import file"
            case .paste: "Paste text"
            case .generate: "Generate from scratch"
            }
        }
    }

    private enum Stage {
        case configure
        case generating(done: Int, total: Int)
        case review(SyllabusExtractor.Result)
        case failed(String)
    }

    @State private var subjectCode: String
    @State private var sourceKind: SourceKind = .file
    @State private var pastedText = ""
    @State private var fileURL: URL?
    @State private var fileError: String?
    @State private var stage: Stage = .configure
    @State private var task: Task<Void, Never>?
    @State private var cancelled = false

    init(syllabus: SyllabusStore, preferences: Preferences, subjectCodes: [String], aiModel: String) {
        self.syllabus = syllabus
        self.preferences = preferences
        self.subjectCodes = subjectCodes
        self.aiModel = aiModel
        _subjectCode = State(initialValue: subjectCodes.first ?? "")
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Add syllabus")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { cancelled = true; task?.cancel(); dismiss() }
                    }
                }
        }
        .frame(minWidth: 460, idealWidth: 520, maxWidth: 900, minHeight: 420, idealHeight: 480, maxHeight: 800)
    }

    @ViewBuilder
    private var content: some View {
        switch stage {
        case .configure: configureForm
        case .generating(let done, let total): generatingView(done: done, total: total)
        case .review(let result): reviewView(result)
        case .failed(let message): failedView(message)
        }
    }

    // MARK: Configure

    private var configureForm: some View {
        Form {
            Section("Subject") {
                if subjectCodes.isEmpty {
                    TextField("Subject code", text: $subjectCode)
                } else {
                    Picker("Subject", selection: $subjectCode) {
                        ForEach(subjectCodes, id: \.self) { Text($0).tag($0) }
                    }
                }
            }
            Section("Source") {
                Picker("From", selection: $sourceKind) {
                    ForEach(SourceKind.allCases) { Text($0.label).tag($0) }
                }
                switch sourceKind {
                case .file:
                    HStack {
                        Button("Choose file…") { pickFile() }
                        if let fileURL { Text(fileURL.lastPathComponent).foregroundStyle(.secondary) }
                    }
                    if let fileError { Text(fileError).foregroundStyle(.red).font(.caption) }
                    Text("PDF, Word, PowerPoint, Markdown, or plain text.")
                        .font(.caption).foregroundStyle(.secondary)
                case .paste:
                    TextEditor(text: $pastedText)
                        .frame(minHeight: 140)
                        .overlay(alignment: .topLeading) {
                            if pastedText.isEmpty {
                                Text("Paste the syllabus text here").foregroundStyle(.tertiary).padding(6)
                                    .allowsHitTesting(false)
                            }
                        }
                case .generate:
                    Text("No real syllabus? The AI drafts a plausible study-guide outline instead, clearly labeled as generated — not the actual course syllabus.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if sourceKind != .generate {
                Section("Term start") {
                    DatePicker("Week 1 begins", selection: $preferences.termStartDate, displayedComponents: .date)
                    Text("Items that only say \u{201C}Week N\u{201D} are dated from here.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section {
                Button("Extract") { start() }.disabled(!canStart)
            }
        }
        .formStyle(.grouped)
    }

    private var canStart: Bool {
        guard !subjectCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        switch sourceKind {
        case .file: return fileURL != nil
        case .paste: return !pastedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .generate: return true
        }
    }

    private func pickFile() {
        let panel = NSOpenPanel()
        let docx = UTType(filenameExtension: "docx") ?? .data
        let pptx = UTType(filenameExtension: "pptx") ?? .data
        let md = UTType(filenameExtension: "md") ?? .plainText
        panel.allowedContentTypes = [.plainText, md, .pdf, docx, pptx]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        fileURL = url
        fileError = nil
    }

    // MARK: Generate

    private func resolveSource() -> SyllabusSource? {
        switch sourceKind {
        case .file:
            guard let fileURL else { return nil }
            do {
                let text = try MaterialImport.text(from: fileURL)
                return .material(text: text, label: fileURL.lastPathComponent)
            } catch {
                fileError = error.localizedDescription
                return nil
            }
        case .paste:
            return .material(text: pastedText, label: "Pasted text")
        case .generate:
            return .fromScratch(description: "\(subjectCode) — student's own course")
        }
    }

    private func start() {
        guard let source = resolveSource() else { return }
        let code = subjectCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let termStart = preferences.termStartDate
        let client = Preferences.localAIClient(modelID: aiModel)
        let chunkSize = preferences.ragChunkSize
        cancelled = false
        stage = .generating(done: 0, total: 0)
        task = Task {
            let result = await SyllabusExtractor.run(
                source: source, subjectCode: code, termStart: termStart, model: aiModel, client: client,
                chunkSize: chunkSize,
                onProgress: { done, total in
                    Task { @MainActor in
                        guard !cancelled else { return }
                        stage = .generating(done: done, total: total)
                    }
                },
                isCancelled: { cancelled }
            )
            await MainActor.run {
                guard !cancelled else { return }
                if result.items.isEmpty {
                    stage = .failed(result.totalChunks == 0
                        ? "Nothing to extract from."
                        : "Extraction failed for all \(result.totalChunks) chunk(s). Check the model in Settings ▸ AI is downloaded and llama.cpp is installed.")
                } else {
                    stage = .review(result)
                }
            }
        }
    }

    private func generatingView(done: Int, total: Int) -> some View {
        VStack(spacing: 16) {
            ProgressView(value: total > 0 ? Double(done) / Double(total) : 0)
                .frame(width: 280)
            Text(total > 0 ? "Extracting chunk \(min(done + 1, total)) of \(total)\u{2026}" : "Preparing\u{2026}")
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func failedView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle").font(.largeTitle).foregroundStyle(.orange)
            Text(message).multilineTextAlignment(.center)
            Button("Try again") { stage = .configure }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Review

    private func reviewView(_ result: SyllabusExtractor.Result) -> some View {
        SyllabusReviewSheet(
            items: result.items, gradingComponents: result.gradingComponents,
            failedChunks: result.failedChunks, totalChunks: result.totalChunks,
            truncatedMaterial: result.truncatedMaterial,
            onSave: { finalItems, finalComponents in
                for item in finalItems { syllabus.addItem(item) }
                if !finalComponents.isEmpty {
                    syllabus.setComponents(finalComponents, for: subjectCode)
                }
                dismiss()
            },
            onBack: { stage = .configure }
        )
    }
}
