import SwiftUI

/// `front` shown with either its real `back` or another card's back
/// (`QuizQuestion.build(.trueFalse, ...)`), 50/50 — judge True or False. A
/// wrong answer gets an AI explanation; a correct one auto-advances after a
/// brief pause.
struct TrueFalseSession: View {
    @ObservedObject var store: QuizStore
    @ObservedObject var preferences: Preferences
    let deck: QuizDeck
    let onDone: () -> Void

    @State private var queue: [QuizCard] = []
    @State private var index = 0
    @State private var question: QuizQuestion?
    @State private var answered: Bool?
    @State private var explanation: String?
    @State private var explaining = false
    @State private var explanationCache: [UUID: String] = [:]
    @State private var pressed: Bool?
    @State private var correctThisSession = 0
    @Environment(\.palette) private var palette
    @Environment(\.typography) private var typography
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 20) {
            QuizSessionHeader(
                title: deck.name, position: index + 1, total: queue.count, correct: correctThisSession,
                ringColor: index < queue.count ? palette.color(for: queue[index].subject) : palette.accent, onDone: onDone
            )

            if queue.isEmpty {
                QuizEmptyState(message: "Nothing due in this deck.")
            } else if case .trueFalse(let card, let statement, let isActuallyTrue) = question {
                Spacer()
                content(card: card, statement: statement, isActuallyTrue: isActuallyTrue)
                Spacer()
            } else {
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
        question = QuizQuestion.build(.trueFalse, card: queue[index], deck: deck.cards)
        answered = nil
        explanation = nil
    }

    private func content(card: QuizCard, statement: String, isActuallyTrue: Bool) -> some View {
        VStack(spacing: 20) {
            Text(card.front)
                .font(typography.detailTitle)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text(statement)
                .font(typography.screenTitle)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            if let answered {
                PixelBadge(kind: answered ? .correct : .incorrect, key: card.id)
                    .frame(width: 28, height: 28)
                if !answered {
                    wrongAnswerPanel(card: card, statement: statement, isActuallyTrue: isActuallyTrue)
                } else if reduceMotion {
                    // Auto-advance skipped under Reduce Motion (WCAG's
                    // "Timing Adjustable") — this is the way forward instead.
                    Button("Next") { advance() }
                }
            } else {
                HStack(spacing: 16) {
                    tfButton("False", card: card, isActuallyTrue: isActuallyTrue, said: false)
                    tfButton("True", card: card, isActuallyTrue: isActuallyTrue, said: true)
                }
            }
        }
        .padding(32)
        .frame(maxWidth: 480)
        .background(RoundedRectangle(cornerRadius: 16).fill(palette.color(for: card.subject).opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(palette.color(for: card.subject).opacity(0.25)))
        .cardGenerationTransition(key: card.id)
    }

    @ViewBuilder
    private func tfButton(_ label: String, card: QuizCard, isActuallyTrue: Bool, said: Bool) -> some View {
        let pressGesture = DragGesture(minimumDistance: 0)
            .onChanged { _ in pressed = said }
            .onEnded { _ in pressed = nil }
        if said {
            Button(label) { answer(said, card: card, isActuallyTrue: isActuallyTrue) }
                .buttonStyle(.borderedProminent)
                .tint(palette.color(for: card.subject))
                .scaleEffect(pressed == said ? 0.94 : 1)
                .animation(Motion.hover(reduced: reduceMotion), value: pressed)
                .simultaneousGesture(pressGesture)
        } else {
            Button(label) { answer(said, card: card, isActuallyTrue: isActuallyTrue) }
                .buttonStyle(.bordered)
                .scaleEffect(pressed == said ? 0.94 : 1)
                .animation(Motion.hover(reduced: reduceMotion), value: pressed)
                .simultaneousGesture(pressGesture)
        }
    }

    private func answer(_ said: Bool, card: QuizCard, isActuallyTrue: Bool) {
        let correct = said == isActuallyTrue
        answered = correct
        store.recordReview(cardID: card.id, deckID: deck.id, rating: correct ? .good : .again)
        if correct {
            correctThisSession += 1
            guard !reduceMotion else { return }
            Task {
                try? await Task.sleep(nanoseconds: 600_000_000)
                if answered == true { advance() }
            }
        }
    }

    @ViewBuilder
    private func wrongAnswerPanel(card: QuizCard, statement: String, isActuallyTrue: Bool) -> some View {
        VStack(spacing: 8) {
            if let explanation {
                Text(explanation).font(typography.footer).foregroundStyle(.secondary).multilineTextAlignment(.center)
            } else if explaining {
                ProgressView().controlSize(.small)
            } else {
                Button("Why?") {
                    Task { await fetchExplanationIfNeeded(card: card, shownStatement: statement, isActuallyTrue: isActuallyTrue) }
                }
                .buttonStyle(.borderless)
                .font(typography.footer)
            }
            Button("Next") { advance() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.space, modifiers: [])
        }
    }

    private func fetchExplanationIfNeeded(card: QuizCard, shownStatement: String, isActuallyTrue: Bool) async {
        explanation = explanationCache[card.id]
        guard explanation == nil, preferences.aiEnabled, !preferences.aiModel.isEmpty else { return }
        // The "question" here is really the shown statement plus whether it
        // was true — feed that as the front/answer pair so the explanation
        // addresses what was actually judged, not the card's original front.
        let judgmentCard = QuizCard(
            front: "True or false: \(shownStatement)",
            back: isActuallyTrue ? "True" : "False",
            subject: card.subject, citation: card.citation
        )
        explaining = true
        let text = await AnswerExplainer.explain(
            card: judgmentCard, studentAnswered: isActuallyTrue ? "False" : "True",
            model: preferences.aiModel, client: Preferences.localAIClient(modelID: preferences.aiModel)
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
