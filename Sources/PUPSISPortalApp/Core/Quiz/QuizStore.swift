import Foundation

/// Streak state — the one motivational number, deliberately not tied to
/// clearing all due cards (see the plan: "review at least one card").
struct QuizStats: Codable, Equatable {
    var streak: Int = 0
    var lastStudied: Date?
}

/// Every deck lives at `decks/<id>/deck.json`, with that deck's review log
/// alongside it at `decks/<id>/reviews.json` — deleting a deck deletes its
/// folder, so there's never an orphaned review record for a deck that no
/// longer exists. `stats.json` holds the one thing that isn't per-deck: the
/// global streak.
///
/// Same conventions as every other store here (`NotesStore`, `ScheduleStore`):
/// Application Support, dir `0700`, file `0600`, atomic write. An injectable
/// root URL, like `NotesStore`, so tests point it at a temp directory.
@MainActor
final class QuizStore: ObservableObject {
    @Published private(set) var decks: [QuizDeck] = []
    @Published private(set) var stats = QuizStats()
    private let root: URL

    static let defaultRoot: URL = {
        let support = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return support.appendingPathComponent("PUPSISPortal", isDirectory: true)
    }()

    private var decksDir: URL { root.appendingPathComponent("decks", isDirectory: true) }
    private var statsURL: URL { root.appendingPathComponent("stats.json") }
    private func deckDir(_ id: UUID) -> URL { decksDir.appendingPathComponent(id.uuidString, isDirectory: true) }
    private func deckURL(_ id: UUID) -> URL { deckDir(id).appendingPathComponent("deck.json") }
    private func reviewsURL(_ id: UUID) -> URL { deckDir(id).appendingPathComponent("reviews.json") }

    init(root: URL = defaultRoot) {
        self.root = root
        decks = Self.loadDecks(from: decksDir)
        stats = Self.loadStats(from: root.appendingPathComponent("stats.json"))
    }

    // MARK: Deck CRUD

    @discardableResult
    func addDeck(_ deck: QuizDeck) -> QuizDeck {
        decks.append(deck)
        persistDeck(deck)
        return deck
    }

    func update(_ deck: QuizDeck) {
        guard let index = decks.firstIndex(where: { $0.id == deck.id }) else { return }
        decks[index] = deck
        persistDeck(deck)
    }

    func deleteDeck(_ id: UUID) {
        decks.removeAll { $0.id == id }
        try? FileManager.default.removeItem(at: deckDir(id))
    }

    func rename(_ id: UUID, to name: String) {
        guard let index = decks.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        decks[index].name = trimmed
        persistDeck(decks[index])
    }

    // MARK: Cards

    /// Appends cards to an existing deck, skipping any whose normalized
    /// front already exists in it — the generator may hand back duplicates
    /// across chunks or across an append call.
    func appendCards(_ newCards: [QuizCard], to deckID: UUID) {
        guard let index = decks.firstIndex(where: { $0.id == deckID }) else { return }
        let existing = Set(decks[index].cards.map(\.normalizedFront))
        decks[index].cards += newCards.filter { !existing.contains($0.normalizedFront) }
        persistDeck(decks[index])
    }

    /// Replaces a deck's cards after a regenerate, matching new cards to old
    /// on normalized front text so FSRS state (and review history) survives
    /// for every card that still exists. `unmatchedCount` in the return value
    /// is what a confirmation dialog names before this runs — call sites are
    /// expected to have already confirmed with the user.
    @discardableResult
    func replaceCards(_ newCards: [QuizCard], in deckID: UUID) -> (kept: Int, unmatched: Int) {
        guard let index = decks.firstIndex(where: { $0.id == deckID }) else { return (0, newCards.count) }
        let oldByFront = Dictionary(
            decks[index].cards.map { ($0.normalizedFront, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let merged = newCards.map { card -> QuizCard in
            guard let old = oldByFront[card.normalizedFront] else { return card }
            var carried = card
            carried.id = old.id
            carried.fsrs = old.fsrs
            return carried
        }
        decks[index].cards = merged
        persistDeck(decks[index])
        return quizRegeneratePreview(old: Array(oldByFront.values), new: newCards)
    }

    func deleteCard(_ cardID: UUID, from deckID: UUID) {
        guard let index = decks.firstIndex(where: { $0.id == deckID }) else { return }
        decks[index].cards.removeAll { $0.id == cardID }
        persistDeck(decks[index])
    }

    func updateCard(_ card: QuizCard, in deckID: UUID) {
        guard let deckIndex = decks.firstIndex(where: { $0.id == deckID }),
              let cardIndex = decks[deckIndex].cards.firstIndex(where: { $0.id == card.id })
        else { return }
        decks[deckIndex].cards[cardIndex] = card
        persistDeck(decks[deckIndex])
    }

    // MARK: Review

    /// Records one review: updates the card's FSRS state, appends to that
    /// deck's review log, and advances the streak. `now` is injectable for
    /// tests; every other call site uses the real clock.
    func recordReview(cardID: UUID, deckID: UUID, rating: QuizRating, now: Date = Date()) {
        guard let deckIndex = decks.firstIndex(where: { $0.id == deckID }),
              let cardIndex = decks[deckIndex].cards.firstIndex(where: { $0.id == cardID })
        else { return }

        let card = decks[deckIndex].cards[cardIndex]
        decks[deckIndex].cards[cardIndex].fsrs = FSRSAdapter.review(card.fsrs, rating: rating, now: now)
        persistDeck(decks[deckIndex])

        appendReview(
            QuizReviewRecord(cardID: cardID, subject: card.subject, rating: rating, date: now),
            to: deckID
        )

        stats = StudyStats.advance(stats, reviewedAt: now)
        persistStats()
    }

    private func appendReview(_ record: QuizReviewRecord, to deckID: UUID) {
        var log = loadReviews(deckID)
        log.append(record)
        persistReviews(log, deckID: deckID)
    }

    func reviews(for deckID: UUID) -> [QuizReviewRecord] {
        loadReviews(deckID)
    }

    // MARK: Disk

    private func persistDeck(_ deck: QuizDeck) {
        let dir = deckDir(deck.id)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        guard let data = try? JSONEncoder().encode(deck) else { return }
        guard (try? data.write(to: deckURL(deck.id), options: .atomic)) != nil else { return }
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: deckURL(deck.id).path)
    }

    private func loadReviews(_ deckID: UUID) -> [QuizReviewRecord] {
        guard let data = try? Data(contentsOf: reviewsURL(deckID)) else { return [] }
        return (try? JSONDecoder().decode([QuizReviewRecord].self, from: data)) ?? []
    }

    private func persistReviews(_ records: [QuizReviewRecord], deckID: UUID) {
        let dir = deckDir(deckID)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        guard let data = try? JSONEncoder().encode(records) else { return }
        guard (try? data.write(to: reviewsURL(deckID), options: .atomic)) != nil else { return }
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: reviewsURL(deckID).path)
    }

    private func persistStats() {
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        guard let data = try? JSONEncoder().encode(stats) else { return }
        guard (try? data.write(to: statsURL, options: .atomic)) != nil else { return }
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: statsURL.path)
    }

    private static func loadDecks(from decksDir: URL) -> [QuizDeck] {
        guard let entries = try? FileManager.default.contentsOfDirectory(at: decksDir, includingPropertiesForKeys: nil) else {
            return []
        }
        return entries.compactMap { dir -> QuizDeck? in
            let deckURL = dir.appendingPathComponent("deck.json")
            guard let data = try? Data(contentsOf: deckURL) else { return nil }
            return try? JSONDecoder().decode(QuizDeck.self, from: data)
        }.sorted { $0.created > $1.created }
    }

    private static func loadStats(from url: URL) -> QuizStats {
        guard let data = try? Data(contentsOf: url) else { return QuizStats() }
        return (try? JSONDecoder().decode(QuizStats.self, from: data)) ?? QuizStats()
    }
}
