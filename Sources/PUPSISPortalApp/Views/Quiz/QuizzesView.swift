import SwiftUI

/// Quizzes' full-width face of Notebook: a deck browser that opens into
/// either a study session or the generate flow.
///
/// A deliberate, scoped departure from the rest of the app's restraint —
/// see the Quizzes surface brief. Where every other screen spends subject
/// color as a rare accent, this one spends it across whole category
/// sections and stat-card tiles; where every other screen avoids anything
/// dashboard-shaped, this one leans into real progress rings and a featured
/// strip. Every number shown is derived from the store — nothing here is
/// invented to look impressive.
struct QuizzesView: View {
    @ObservedObject var store: QuizStore
    @ObservedObject var center: GenerationCenter
    @ObservedObject var preferences: Preferences
    @ObservedObject var notes: NotesStore
    let aiModel: String
    @Environment(\.palette) private var palette
    @Environment(\.typography) private var typography

    struct GrowthRequest: Identifiable {
        let id = UUID()
        let deck: QuizDeck
        let mode: GenerateSheet.GrowthMode
    }

    /// Reopening a job the banner shows — reconstructs `existing` from the
    /// job's own target so a resumed append/regenerate sheet has the deck
    /// it needs without re-deriving it from anywhere else.
    private struct Resume: Identifiable {
        let id: UUID
        let existing: (deck: QuizDeck, mode: GenerateSheet.GrowthMode)?
    }

    @State private var pickingModeFor: QuizDeck?
    @State private var studying: (deck: QuizDeck, mode: QuizMode)?
    @State private var generatingNew = false
    @State private var growing: GrowthRequest?
    @State private var resuming: Resume?
    @State private var pendingDelete: QuizDeck?
    @State private var renaming: QuizDeck?
    @State private var renameText = ""

    var body: some View {
        Group {
            if let studying, let live = store.decks.first(where: { $0.id == studying.deck.id }) {
                session(mode: studying.mode, deck: live)
            } else {
                browser
            }
        }
        .sheet(item: $pickingModeFor) { deck in
            QuizModePicker(
                deck: deck,
                onPick: { mode in pickingModeFor = nil; studying = (deck, mode) },
                onCancel: { pickingModeFor = nil }
            )
        }
        .sheet(isPresented: $generatingNew) {
            GenerateSheet(store: store, center: center, preferences: preferences, notes: notes, aiModel: aiModel, existing: nil)
        }
        .sheet(item: $growing) { request in
            GenerateSheet(
                store: store, center: center, preferences: preferences, notes: notes, aiModel: aiModel,
                existing: (deck: request.deck, mode: request.mode)
            )
        }
        .sheet(item: $resuming) { resume in
            GenerateSheet(
                store: store, center: center, preferences: preferences, notes: notes, aiModel: aiModel,
                existing: resume.existing, resumeJobID: resume.id
            )
        }
        .alert("Rename deck", isPresented: renamePresented, presenting: renaming) { deck in
            TextField("Name", text: $renameText)
            Button("OK") { store.rename(deck.id, to: renameText); renaming = nil }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
        .confirmationDialog(
            "Delete \u{201C}\(pendingDelete?.name ?? "")\u{201D}?",
            isPresented: deletePresented, presenting: pendingDelete
        ) { deck in
            Button("Delete", role: .destructive) { store.deleteDeck(deck.id) }
        } message: { _ in
            Text("This deletes the deck and its review history.")
        }
    }

    @ViewBuilder
    private func session(mode: QuizMode, deck: QuizDeck) -> some View {
        let done = { studying = nil }
        switch mode {
        case .flashcard: StudySession(store: store, deck: deck, onDone: done)
        case .identification: IdentificationSession(store: store, preferences: preferences, deck: deck, onDone: done)
        case .multipleChoice: MultipleChoiceSession(store: store, preferences: preferences, deck: deck, onDone: done)
        case .trueFalse: TrueFalseSession(store: store, preferences: preferences, deck: deck, onDone: done)
        case .matching: MatchingSession(store: store, deck: deck, onDone: done)
        }
    }

    private var renamePresented: Binding<Bool> {
        Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })
    }
    private var deletePresented: Binding<Bool> {
        Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
    }

    private var browser: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                if !center.jobs.isEmpty {
                    VStack(spacing: 6) { ForEach(center.jobs) { jobBanner($0) } }
                }
                if store.decks.isEmpty {
                    Text("No decks yet — generate one from a topic or your own material.")
                        .foregroundStyle(.secondary)
                        .padding(.top, 40)
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    if let featured = mostUrgentDeck {
                        featuredStrip(featured)
                    }
                    ForEach(categories, id: \.name) { category in
                        categorySection(category)
                    }
                }
            }
            .padding(20)
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Category dashboard

    private struct Category {
        let name: String
        let decks: [QuizDeck]
        var dueTotal: Int { decks.reduce(0) { $0 + $1.dueCards().count } }
    }

    /// Groups every deck by `sourceQuery` — the topic typed or material
    /// filename it was generated from — so a regenerated or "generate more"
    /// deck clusters with its siblings under the material that produced
    /// them. Sorted so the category with the most due work leads — the
    /// browser reads "what needs me" top to bottom.
    private var categories: [Category] {
        let grouped = Dictionary(grouping: store.decks) { $0.sourceQuery }
        return grouped
            .map { Category(name: $0.key, decks: $0.value) }
            .sorted { $0.dueTotal != $1.dueTotal ? $0.dueTotal > $1.dueTotal : $0.name < $1.name }
    }

    /// The single deck with the most cards due right now — real data, not a
    /// recommendation engine. `nil` when nothing anywhere is due.
    private var mostUrgentDeck: QuizDeck? {
        store.decks.filter { $0.dueCards().count > 0 }.max { $0.dueCards().count < $1.dueCards().count }
    }

    private func featuredStrip(_ deck: QuizDeck) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Continue studying").font(typography.detailMeta).foregroundStyle(.secondary)
            deckTile(deck, featured: true)
        }
    }

    private func categorySection(_ category: Category) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle().fill(palette.accent).frame(width: 8, height: 8)
                Text(category.name).font(typography.detailTitle).lineLimit(1).truncationMode(.tail)
                Spacer()
                Text(category.dueTotal > 0
                     ? "\(category.decks.count) deck\(category.decks.count == 1 ? "" : "s") · \(category.dueTotal) due today"
                     : "\(category.decks.count) deck\(category.decks.count == 1 ? "" : "s") · all caught up")
                    .font(.caption).foregroundStyle(.secondary)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                ForEach(category.decks) { deck in
                    deckTile(deck, featured: false)
                }
            }
        }
    }

    private func deckTile(_ deck: QuizDeck, featured: Bool) -> some View {
        DeckStatCard(deck: deck, color: palette.accent, featured: featured) {
            pickingModeFor = deck
        }
        .contextMenu {
            Button("Generate more…") { growing = GrowthRequest(deck: deck, mode: .append) }
            Button("Regenerate…") { growing = GrowthRequest(deck: deck, mode: .regenerate) }
            Divider()
            Button("Rename") { renameText = deck.name; renaming = deck }
            Button("Delete", role: .destructive) { pendingDelete = deck }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Quizzes").font(.title2.weight(.semibold))
                if store.stats.streak > 0 {
                    HStack(spacing: 4) {
                        PixelBadge(kind: .streak, key: "streak-\(store.stats.streak)")
                            .frame(width: 16, height: 18)
                        Text("\(store.stats.streak) day streak")
                            .font(.callout)
                            .foregroundStyle(.orange)
                    }
                }
            }
            Spacer()
            Button {
                guard !preferences.aiModel.isEmpty else { return }
                generatingNew = true
            } label: {
                Label("Generate deck", systemImage: "sparkles")
            }
            .disabled(!preferences.aiEnabled || preferences.aiModel.isEmpty)
            .help(preferences.aiEnabled && !preferences.aiModel.isEmpty
                  ? "Generate a new deck" : "Turn on IntAssis and pick a model in Settings first")
        }
    }

    /// A backgrounded generation job — in progress, ready to review, or
    /// failed. Tapping a ready/failed one reopens `GenerateSheet` right at
    /// that result via `resumeJobID`.
    private func jobBanner(_ job: GenerationCenter.Job) -> some View {
        HStack(spacing: 8) {
            if job.result != nil {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("\u{201C}\(job.label)\u{201D} ready — \(job.result?.cards.count ?? 0) cards to review")
            } else if job.failure != nil {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text("\u{201C}\(job.label)\u{201D} failed to generate")
            } else {
                ProgressView().controlSize(.small)
                Text("Generating \u{201C}\(job.label)\u{201D}\u{2026} \(job.total > 0 ? "\(job.done)/\(job.total)" : "")")
            }
            Spacer()
            if job.finished {
                Button("Review") { resuming = Resume(id: job.id, existing: existingFor(job)) }
                Button("Dismiss") { center.dismiss(job.id) }
            } else {
                Button("Cancel") { center.cancel(job.id) }
            }
        }
        .font(.callout)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.5)))
    }

    private func existingFor(_ job: GenerationCenter.Job) -> (deck: QuizDeck, mode: GenerateSheet.GrowthMode)? {
        switch job.target {
        case .new: return nil
        case .append(let deckID):
            guard let deck = store.decks.first(where: { $0.id == deckID }) else { return nil }
            return (deck, .append)
        case .regenerate(let deckID):
            guard let deck = store.decks.first(where: { $0.id == deckID }) else { return nil }
            return (deck, .regenerate)
        }
    }

}
