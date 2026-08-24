import SwiftUI

/// Generated cards land here before anything is saved — mirrors how the note
/// editor's AI popup gates output behind Replace/Insert instead of writing
/// automatically. Edit or delete a bad card, then Save.
struct CardReviewSheet: View {
    @State private var cards: [QuizCard]
    let failedChunks: Int
    let totalChunks: Int
    /// True when the source material had more chunks than
    /// `CardGenerator.maxChunksPerRun` and the rest was left unused.
    let truncatedMaterial: Bool
    /// The deck being grown/regenerated, for context messaging only.
    let existingDeckName: String?
    /// Non-nil only for a regenerate — (kept, unmatched) computed against the
    /// deck's current cards, so the count is visible before Save commits it.
    let regeneratePreview: (kept: Int, unmatched: Int)?
    let onSave: ([QuizCard]) -> Void
    let onBack: () -> Void

    init(
        cards: [QuizCard], failedChunks: Int, totalChunks: Int, truncatedMaterial: Bool = false,
        existingDeckName: String?, regeneratePreview: (kept: Int, unmatched: Int)?,
        onSave: @escaping ([QuizCard]) -> Void, onBack: @escaping () -> Void
    ) {
        _cards = State(initialValue: cards)
        self.failedChunks = failedChunks
        self.totalChunks = totalChunks
        self.truncatedMaterial = truncatedMaterial
        self.existingDeckName = existingDeckName
        self.regeneratePreview = regeneratePreview
        self.onSave = onSave
        self.onBack = onBack
    }

    var body: some View {
        VStack(spacing: 0) {
            if truncatedMaterial {
                Text("Your material was longer than one generation run covers — only the first part was used.")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.orange.opacity(0.1))
            }
            if failedChunks > 0 {
                Text("\(failedChunks) of \(totalChunks) chunk(s) failed to generate — the \(cards.count) cards below are from the rest.")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.orange.opacity(0.1))
            }
            if let preview = regeneratePreview {
                Text(preview.unmatched > 0
                     ? "\(preview.kept) card(s) keep their study progress; \(preview.unmatched) are new or reworded and start fresh."
                     : "All \(preview.kept) card(s) keep their study progress.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.4))
            }
            List {
                ForEach($cards) { $card in
                    cardRow($card)
                }
            }
            .listStyle(.plain)
            HStack {
                Button("Back") { onBack() }
                Spacer()
                Text("\(cards.count) card(s)").foregroundStyle(.secondary)
                Spacer()
                Button("Save") { onSave(cards) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(cards.isEmpty)
            }
            .padding(12)
        }
    }

    private func cardRow(_ card: Binding<QuizCard>) -> some View {
        CardReviewRow(card: card) {
            cards.removeAll { $0.id == card.wrappedValue.id }
        }
    }
}

/// One card's editable fields, including its accepted-answers chip row —
/// what the model generated as alternate correct phrasings, editable/
/// removable, plus a field to add one by hand. Only meaningful for
/// Identification, but a deck's study mode is picked per-session, not fixed,
/// so this is shown for every card rather than gated on a mode nobody's
/// committed to yet.
private struct CardReviewRow: View {
    @Binding var card: QuizCard
    let onDelete: () -> Void

    @State private var draftAnswer = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Front", text: $card.front, axis: .vertical)
                .font(.body.weight(.medium))
            TextField("Back", text: $card.back, axis: .vertical)
                .foregroundStyle(.secondary)
            acceptedAnswersRow
            HStack {
                TextField("Subject", text: $card.subject)
                    .font(.caption)
                    .textFieldStyle(.plain)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }

    private var acceptedAnswersRow: some View {
        FlowLayout(spacing: 6) {
            ForEach(card.acceptedAnswers ?? [], id: \.self) { answer in
                HStack(spacing: 4) {
                    Text(answer).font(.caption2)
                    Button { removeAnswer(answer) } label: {
                        Image(systemName: "xmark.circle.fill").font(.caption2)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(.tint.opacity(0.14)))
            }
            TextField("+ accepted answer", text: $draftAnswer)
                .textFieldStyle(.plain)
                .font(.caption2)
                .frame(width: 130)
                .onSubmit { addAnswer() }
        }
    }

    private func addAnswer() {
        let trimmed = draftAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var current = card.acceptedAnswers ?? []
        guard !current.contains(trimmed) else { draftAnswer = ""; return }
        current.append(trimmed)
        card.acceptedAnswers = current
        draftAnswer = ""
    }

    private func removeAnswer(_ answer: String) {
        card.acceptedAnswers = (card.acceptedAnswers ?? []).filter { $0 != answer }
    }
}

/// A left-to-right wrapping row — chips need to flow onto a new line rather
/// than clip or scroll horizontally, and SwiftUI has no native wrapping
/// HStack. Minimal `Layout` conformance: measure by greedily packing items
/// until a row overflows the proposed width, then start a new row.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var x: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                totalHeight += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        totalHeight += rowHeight
        return CGSize(width: width.isFinite ? width : x, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
