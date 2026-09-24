import Foundation

/// Spec 11 upgrade 7 (the list half — the heatmap grid itself is a drawing
/// concern, not modeled here): "Weak on," the cards actually worth
/// reviewing again.
enum WeakList {
    struct Entry: Equatable {
        var deckID: UUID
        var deckName: String
        var cardFront: String
        var againCount: Int
    }

    /// Top 3 cards by how many times they were rated Again in the last 30
    /// days, across every deck. `reviews` is each deck's review log, keyed
    /// by deck id (`QuizStore`'s own `reviews.json` per deck). Ties keep
    /// `decks`' order — `sorted(by:)` is stable — so identical counts don't
    /// reshuffle between calls.
    static func top3(
        decks: [QuizDeck], reviews: [UUID: [QuizReviewRecord]],
        now: Date = Date(), calendar: Calendar = .current
    ) -> [Entry] {
        guard let cutoff = calendar.date(byAdding: .day, value: -30, to: now) else { return [] }

        var entries: [Entry] = []
        for deck in decks {
            let recentAgains = (reviews[deck.id] ?? []).filter { $0.rating == .again && $0.date >= cutoff }
            let counts = Dictionary(grouping: recentAgains, by: \.cardID).mapValues(\.count)
            for card in deck.cards {
                guard let count = counts[card.id] else { continue }
                entries.append(Entry(deckID: deck.id, deckName: deck.name, cardFront: card.front, againCount: count))
            }
        }

        return Array(entries.sorted { $0.againCount > $1.againCount }.prefix(3))
    }
}
