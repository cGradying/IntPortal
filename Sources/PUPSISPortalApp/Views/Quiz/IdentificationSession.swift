import SwiftUI

/// Description shown, student types the term. Graded case/whitespace-
/// insensitively (`QuizModeSupport.isCorrectIdentification`) — a genuine
/// typo counts wrong on purpose; see the mode picker's grading note.
/// Correct answers auto-advance after a brief pause; wrong answers get an
/// AI explanation (falls back to just the answer if Ollama's unavailable).
struct IdentificationSession: View {
    @ObservedObject var store: QuizStore
    @ObservedObject var preferences: Preferences
    let deck: QuizDeck
    let onDone: () -> Void

    @State private var queue: [QuizCard] = []
    @State private var index = 0
    @State private var typed = ""
    @State private var graded: Bool?
    @State private var explanation: String?
    @State private var explaining = false
    @State private var explanationCache: [UUID: String] = [:]
    @State private var correctThisSession = 0
    @FocusState private var fieldFocused: Bool
    @Environment(\.palette) private var palette
    @Environment(\.typography) private var typography
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 20) {
            QuizSessionHeader(
                title: deck.name, position: index + 1, total: queue.count, correct: correctThisSession,
                ringColor: index < queue.count ? subjectColor : palette.accent, onDone: onDone
            )

            if queue.isEmpty {
                QuizEmptyState(message: "Nothing due in this deck.")
            } else if index < queue.count {
                Spacer()
                card
                Spacer()
                controls.padding(.bottom, 24)
            } else {
                QuizCompleteState(onDone: onDone)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { queue = deck.dueCards() }
    }

    private var current: QuizCard { queue[index] }
    private var subjectColor: Color { palette.color(for: current.subject) }
    private var fieldPulseColor: Color {
        switch graded {
        case true: subjectColor
        case false: .red
        case nil: .clear
        }
    }

    private var card: some View {
        VStack(spacing: 16) {
            Text(current.back)
                .font(typography.screenTitle)
                .multilineTextAlignment(.center)
            TextField("Type the term", text: $typed)
                .textFieldStyle(.roundedBorder)
                .frame(width: 280)
                .disabled(graded != nil)
                .focused($fieldFocused)
                .onSubmit { if graded == nil { grade() } }
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(fieldPulseColor, lineWidth: 2)
                        .opacity(graded == nil ? 0 : 1)
                )
                .animation(Motion.selection(reduced: reduceMotion), value: graded)
            if let graded {
                PixelBadge(kind: graded ? .correct : .incorrect, key: current.id)
                    .frame(width: 28, height: 28)
                if !graded {
                    wrongAnswerPanel
                } else if reduceMotion {
                    // The auto-advance timer is skipped under Reduce Motion
                    // (WCAG's "Timing Adjustable" — content disappearing on
                    // a fixed clock nobody can extend), so this is the only
                    // way forward on a correct answer in that case.
                    Button("Next") { advance() }
                }
            }
        }
        .padding(32)
        .frame(maxWidth: 480)
        .background(RoundedRectangle(cornerRadius: 16).fill(subjectColor.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(subjectColor.opacity(0.25)))
        .cardGenerationTransition(key: current.id)
        .onAppear { fieldFocused = true }
    }

    @ViewBuilder
    private var wrongAnswerPanel: some View {
        VStack(spacing: 6) {
            Text("Answer: \(current.front)").font(typography.detailBody)
            if let explanation {
                Text(explanation).font(typography.footer).foregroundStyle(.secondary).multilineTextAlignment(.center)
            } else if explaining {
                ProgressView().controlSize(.small)
            } else {
                Button("Why?") { Task { await fetchExplanationIfNeeded() } }
                    .buttonStyle(.borderless)
                    .font(typography.footer)
            }
        }
    }

    @ViewBuilder
    private var controls: some View {
        if graded == nil {
            Button("Check") { grade() }
                .buttonStyle(.borderedProminent)
                .disabled(typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } else if graded == false {
            Button("Next") { advance() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.space, modifiers: [])
        }
    }

    private func grade() {
        let correct = QuizModeSupport.isCorrectIdentification(typed: typed, card: current)
        graded = correct
        store.recordReview(cardID: current.id, deckID: deck.id, rating: correct ? .good : .again)
        if correct {
            correctThisSession += 1
            guard !reduceMotion else { return }
            Task {
                try? await Task.sleep(nanoseconds: 600_000_000)
                if graded == true { advance() }
            }
        }
    }

    private func fetchExplanationIfNeeded() async {
        explanation = explanationCache[current.id]
        guard explanation == nil, preferences.aiEnabled, !preferences.aiModel.isEmpty else { return }
        explaining = true
        let text = await AnswerExplainer.explain(
            card: current, studentAnswered: typed, model: preferences.aiModel, client: Preferences.localAIClient(modelID: preferences.aiModel)
        )
        explaining = false
        guard let text else { return }
        explanationCache[current.id] = text
        explanation = text
    }

    private func advance() {
        graded = nil
        typed = ""
        explanation = nil
        index += 1
        fieldFocused = true
    }
}
