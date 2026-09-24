import Foundation

/// Real mastery, replacing `1 − due/total` (which read 0% for a brand-new
/// deck — nothing due yet isn't the same as nothing learned — and reset every
/// day a card came back due, even one the student aces every time).
enum Mastery {
    /// Share of `cards` that count as mastered: reviewed at least twice,
    /// past a week of retention, and didn't just fail. `reviews` is the
    /// deck's append-only review log (`QuizReviewRecord`); a card with no
    /// matching entry there is judged on its FSRS state alone.
    static func of(cards: [QuizCard], reviews: [QuizReviewRecord] = []) -> Double {
        guard !cards.isEmpty else { return 0 }
        let lastRating = Dictionary(grouping: reviews, by: \.cardID)
            .compactMapValues { $0.max(by: { $0.date < $1.date })?.rating }

        let masteredCount = cards.filter { card in
            card.fsrs.reps >= 2
                && card.fsrs.stability >= 7
                && lastRating[card.id] != .again
        }.count

        return Double(masteredCount) / Double(cards.count)
    }
}
