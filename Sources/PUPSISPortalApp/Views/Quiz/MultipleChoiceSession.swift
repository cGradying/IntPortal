import SwiftUI

/// `front` shown, four tappable options — the correct `back` plus three
/// sibling cards' backs (`QuizQuestion.build(.multipleChoice, ...)`). No AI
/// call for the options themselves: the deck's own other cards are the wrong
/// answers, so they're never nonsense. A wrong pick gets an AI explanation
/// (falls back to nothing extra if Ollama's unavailable); a correct one
/// auto-advances after a brief pause.
struct MultipleChoiceSession: View {
    @ObservedObject var store: QuizStore
    @ObservedObject var preferences: Preferences
    let deck: QuizDeck
    let onDone: () -> Void

    @State private var queue: [QuizCard] = []
    @State private var index = 0
    @State private var question: QuizQuestion?
    @State private var picked: String?
    @State private var explanation: String?
    @State private var explaining = false
    @State private var explanationCache: [UUID: String] = [:]
    @State private var correctThisSession = 0
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 20) {
            QuizSessionHeader(
                title: deck.name, position: index + 1, total: queue.count, correct: correctThisSession,
                ringColor: index < queue.count ? palette.color(for: queue[index].subject) : .accentColor, onDone: onDone
            )

            if queue.isEmpty {
                QuizEmptyState(message: "Nothing due in this deck.")
            } else if case .multipleChoice(let card, let options) = question, index < queue.count {
                Spacer()
                content(card: card, options: options)
                Spacer()
            } else if index >= queue.count, !queue.isEmpty {
                QuizCompleteState(onDone: onDone)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { start() }
    }

    private func start() {
        queue = deck.dueCards()
        buildQuestion()
    }

    private func buildQuestion() {
        guard index < queue.count else { question = nil; return }
        question = QuizQuestion.build(.multipleChoice, card: queue[index], deck: deck.cards)
        picked = nil
        explanation = nil
    }

    private func content(card: QuizCard, options: [String]) -> some View {
        VStack(spacing: 20) {
            Text(card.front)
                .font(.title2.weight(.medium))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            VStack(spacing: 8) {
                ForEach(options, id: \.self) { option in
                    optionRow(option, card: card)
                }
            }
            .frame(maxWidth: 420)
            if let picked {
                let correct = picked == card.back
                PixelBadge(kind: correct ? .correct : .incorrect, key: card.id)
                    .frame(width: 28, height: 28)
                if !correct {
                    wrongAnswerPanel(card: card, picked: picked)
                } else if reduceMotion {
                    // Auto-advance skipped under Reduce Motion (WCAG's
                    // "Timing Adjustable") — this is the way forward instead.
                    Button("Next") { advance() }
                }
            }
        }
        .cardGenerationTransition(key: card.id)
    }

    private func optionRow(_ option: String, card: QuizCard) -> some View {
        let isCorrect = option == card.back
        let isPicked = option == picked
        return Button {
            guard picked == nil else { return }
            pick(option, card: card, isCorrect: isCorrect)
        } label: {
            Text(option)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(rowColor(isCorrect: isCorrect, isPicked: isPicked, subject: card.subject))
                )
        }
        .buttonStyle(.plain)
        .disabled(picked != nil)
        .scaleEffect(isPicked ? 1.02 : 1)
        .animation(Motion.selection(reduced: reduceMotion), value: picked)
        // Correctness here was color-only (green/red fill) — nothing for a
        // screen reader to announce once an option resolves.
        .accessibilityValue(picked == nil ? "" : isCorrect ? "Correct" : isPicked ? "Incorrect" : "")
    }

    private func rowColor(isCorrect: Bool, isPicked: Bool, subject: String) -> Color {
        guard picked != nil else { return palette.color(for: subject).opacity(0.12) }
        if isCorrect { return .green.opacity(0.25) }
        if isPicked { return .red.opacity(0.25) }
        return palette.color(for: subject).opacity(0.12)
    }

    private func pick(_ option: String, card: QuizCard, isCorrect: Bool) {
        picked = option
        store.recordReview(cardID: card.id, deckID: deck.id, rating: isCorrect ? .good : .again)
        if isCorrect {
            correctThisSession += 1
            guard !reduceMotion else { return }
            Task {
                try? await Task.sleep(nanoseconds: 600_000_000)
                if picked == option { advance() }
            }
        }
    }

    @ViewBuilder
    private func wrongAnswerPanel(card: QuizCard, picked: String) -> some View {
        VStack(spacing: 8) {
            if let explanation {
                Text(explanation).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            } else if explaining {
                ProgressView().controlSize(.small)
            } else {
                Button("Why?") { Task { await fetchExplanationIfNeeded(card: card, picked: picked) } }
                    .buttonStyle(.borderless)
                    .font(.caption)
            }
            Button("Next") { advance() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.space, modifiers: [])
        }
    }

    private func fetchExplanationIfNeeded(card: QuizCard, picked: String) async {
        explanation = explanationCache[card.id]
        guard explanation == nil, preferences.aiEnabled, !preferences.aiModel.isEmpty else { return }
        explaining = true
        let text = await AnswerExplainer.explain(
            card: card, studentAnswered: picked, model: preferences.aiModel, client: LlamaCppClient()
        )
        explaining = false
        guard let text else { return }
        explanationCache[card.id] = text
        explanation = text
    }

    private func advance() {
        index += 1
        buildQuestion()
    }
}
