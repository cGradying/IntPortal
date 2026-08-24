import SwiftUI

/// One study session: due cards only (per FSRS), one at a time. Built around
/// active recall — the question shows alone with a coaching line, a
/// deliberate "Show answer" action reveals the back (no tap-anywhere flip,
/// which invites peeking before you've actually tried), then rate to
/// schedule the next appearance. Needs no AI and works with Ollama stopped —
/// generation and studying are fully separate paths.
struct StudySession: View {
    @ObservedObject var store: QuizStore
    let deck: QuizDeck
    let onDone: () -> Void
    @Environment(\.palette) private var palette

    /// Snapshotted once at appear — cards rated during this session drop out
    /// of `deck.dueCards()` immediately, which would otherwise yank the
    /// queue out from under whatever's currently showing.
    @State private var queue: [QuizCard] = []
    @State private var index = 0
    @State private var revealed = false
    @State private var correctThisSession = 0

    var body: some View {
        VStack(spacing: 20) {
            QuizSessionHeader(
                title: deck.name, position: index + 1, total: queue.count, correct: correctThisSession,
                ringColor: index < queue.count ? subjectColor : .accentColor, onDone: onDone
            )

            if queue.isEmpty {
                QuizEmptyState(message: "Nothing due in this deck.")
            } else if index < queue.count {
                Spacer()
                card
                Spacer()
                controls
                    .padding(.bottom, 24)
            } else {
                QuizCompleteState(onDone: onDone)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { queue = deck.dueCards() }
    }

    private var current: QuizCard { queue[index] }
    private var subjectColor: Color { palette.color(for: current.subject) }

    private var card: some View {
        VStack(spacing: 16) {
            Text(current.front)
                .font(.title2.weight(.medium))
                .multilineTextAlignment(.center)
            if revealed {
                Divider().frame(width: 200)
                Text(current.back)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .cardGenerationTransition(key: "\(current.id)-back")
            } else {
                Label("Think of the answer, then check", systemImage: "brain")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(32)
        .frame(maxWidth: 480)
        .background(RoundedRectangle(cornerRadius: 16).fill(subjectColor.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(subjectColor.opacity(0.25)))
        .cardGenerationTransition(key: current.id)
    }

    @ViewBuilder
    private var controls: some View {
        if revealed {
            HStack(spacing: 10) {
                ForEach(QuizRating.allCases) { rating in
                    Button(rating.label) { rate(rating) }
                        .buttonStyle(.bordered)
                }
            }
        } else {
            Button("Show answer") { revealed = true }
                .buttonStyle(.borderedProminent)
                .tint(subjectColor)
                .keyboardShortcut(.space, modifiers: [])
        }
    }

    private func rate(_ rating: QuizRating) {
        store.recordReview(cardID: current.id, deckID: deck.id, rating: rating)
        if rating != .again { correctThisSession += 1 }
        revealed = false
        index += 1
    }
}
