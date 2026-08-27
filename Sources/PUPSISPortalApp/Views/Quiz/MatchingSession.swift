import SwiftUI

/// A round of up to 6 due cards at a time — fronts and backs in two
/// independently shuffled columns, tap a front then a back to pair them.
/// A card that took a wrong attempt before its match records `.again`
/// instead of `.good`, so guessing your way to a match still shows up as
/// something to review sooner.
struct MatchingSession: View {
    @ObservedObject var store: QuizStore
    let deck: QuizDeck
    let onDone: () -> Void

    @State private var pool: [QuizCard] = []
    @State private var round: [QuizCard] = []
    @State private var leftOrder: [QuizCard] = []
    @State private var rightOrder: [QuizCard] = []
    @State private var matchedIDs: Set<UUID> = []
    @State private var mistakes: [UUID: Int] = [:]
    @State private var selectedFront: QuizCard?
    @State private var wrongFlash: (front: UUID, back: UUID)?
    @State private var roundKey = UUID()
    @State private var totalDue = 0
    @State private var correctThisSession = 0
    @Environment(\.palette) private var palette
    @Environment(\.typography) private var typography
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 20) {
            QuizSessionHeader(
                title: deck.name, position: max(totalDue - pool.count - round.count + matchedIDs.count, 0),
                total: totalDue, correct: correctThisSession, ringColor: palette.accent, onDone: onDone
            )

            if totalDue == 0 {
                QuizEmptyState(message: "Nothing due in this deck.")
            } else if !round.isEmpty {
                Spacer()
                board
                Spacer()
            } else {
                QuizCompleteState(onDone: onDone)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { start() }
    }

    private func start() {
        pool = deck.dueCards().shuffled()
        totalDue = pool.count
        nextRound()
    }

    private func nextRound() {
        // `QuizQuestion.build` needs a `card:` argument every other mode
        // actually uses; matching doesn't have one to give it (a round is
        // built from the pool, not "around" one card), so this calls the
        // same underlying helper directly rather than forcing an unused
        // placeholder card through the shared API.
        round = QuizModeSupport.matchingSet(from: pool, count: 6)
        pool.removeAll { card in round.contains { $0.id == card.id } }
        leftOrder = round.shuffled()
        rightOrder = round.shuffled()
        matchedIDs = []
        mistakes = [:]
        selectedFront = nil
        roundKey = UUID()
    }

    private var board: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(spacing: 8) {
                ForEach(leftOrder) { card in
                    tile(text: card.front, id: card.id, isFront: true)
                }
            }
            VStack(spacing: 8) {
                ForEach(rightOrder) { card in
                    tile(text: card.back, id: card.id, isFront: false)
                }
            }
        }
        .frame(maxWidth: 640)
        .cardGenerationTransition(key: roundKey)
        .onChange(of: matchedIDs) { _, matched in
            if matched.count == round.count { round = []; if !pool.isEmpty { nextRound() } }
        }
    }

    private func tile(text: String, id: UUID, isFront: Bool) -> some View {
        let matched = matchedIDs.contains(id)
        let selected = isFront && selectedFront?.id == id
        let flashingWrong = isFront ? wrongFlash?.front == id : wrongFlash?.back == id
        let subjectColor = palette.color(for: round.first { $0.id == id }?.subject ?? "")
        // A real Button, not .onTapGesture — this was mouse-only and
        // unreachable by keyboard/VoiceOver, the app's primary navigation
        // aside, the only fully mouse-locked interaction in the app.
        return Button { tap(id: id, isFront: isFront) } label: {
            Text(text)
                .font(typography.detailBody)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8).fill(
                        matched ? Color.quizSuccess.opacity(0.2)
                            : flashingWrong ? Color.quizDanger.opacity(0.3)
                            : selected ? subjectColor.opacity(0.28)
                            : subjectColor.opacity(0.12)
                    )
                )
                .opacity(matched ? 0.35 : 1)
        }
        .buttonStyle(.plain)
        .animation(Motion.arrival(reduced: reduceMotion), value: matched)
        .animation(Motion.hover(reduced: reduceMotion), value: flashingWrong)
        .animation(Motion.selection(reduced: reduceMotion), value: selected)
        .disabled(matched)
        .accessibilityValue(matched ? "Matched" : flashingWrong == true ? "Incorrect" : "")
    }

    private func tap(id: UUID, isFront: Bool) {
        guard !matchedIDs.contains(id) else { return }
        if isFront {
            selectedFront = round.first { $0.id == id }
            return
        }
        guard let front = selectedFront else { return }
        if front.id == id {
            matchedIDs.insert(id)
            let rating: QuizRating = (mistakes[id] ?? 0) == 0 ? .good : .again
            store.recordReview(cardID: id, deckID: deck.id, rating: rating)
            if rating == .good { correctThisSession += 1 }
            selectedFront = nil
        } else {
            mistakes[front.id, default: 0] += 1
            wrongFlash = (front.id, id)
            Task {
                try? await Task.sleep(nanoseconds: 350_000_000)
                wrongFlash = nil
            }
            selectedFront = nil
        }
    }
}
