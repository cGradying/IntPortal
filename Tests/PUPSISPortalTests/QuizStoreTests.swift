import XCTest
@testable import PUPSISPortal

/// Deck persistence. Points the store at a temp root so nothing touches the
/// real Application Support folder.
@MainActor
final class QuizStoreTests: XCTestCase {
    private var root: URL!

    override func setUp() {
        super.setUp()
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("quiz-test-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
        super.tearDown()
    }

    private func card(_ front: String, subject: String = "Test") -> QuizCard {
        QuizCard(front: front, back: "back of \(front)", subject: subject, citation: "test")
    }

    /// A deck saved before `acceptedAnswers` existed — the field is entirely
    /// absent from the JSON, not `null`. Confirms the field being Optional
    /// (not a defaulted `[String] = []`) actually does what it's for: every
    /// deck saved before this change must keep loading.
    func testLegacyDeckWithNoAcceptedAnswersKeyStillDecodes() throws {
        let deckID = UUID()
        let cardID = UUID()
        let legacyJSON = """
        {
          "id": "\(deckID.uuidString)",
          "name": "Legacy Deck",
          "sourceKind": "material",
          "sourceQuery": "m",
          "created": 0,
          "cards": [{
            "id": "\(cardID.uuidString)",
            "front": "Q1",
            "back": "A1",
            "subject": "S",
            "citation": "c",
            "fsrs": {"due": 0, "stability": 0, "difficulty": 0, "reps": 0, "lapses": 0}
          }]
        }
        """
        let deckDir = root.appendingPathComponent("decks/\(deckID.uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: deckDir, withIntermediateDirectories: true)
        try legacyJSON.write(to: deckDir.appendingPathComponent("deck.json"), atomically: true, encoding: .utf8)

        let store = QuizStore(root: root)

        XCTAssertEqual(store.decks.count, 1)
        XCTAssertNil(store.decks.first?.cards.first?.acceptedAnswers)
    }

    func testAddDeckRoundTripsThroughANewStoreInstance() {
        let store = QuizStore(root: root)
        let deck = QuizDeck(name: "Photosynthesis", sourceKind: .vaultTopic, sourceQuery: "photosynthesis", cards: [card("Q1")])
        store.addDeck(deck)

        let reloaded = QuizStore(root: root)
        XCTAssertEqual(reloaded.decks.count, 1)
        XCTAssertEqual(reloaded.decks.first?.name, "Photosynthesis")
        XCTAssertEqual(reloaded.decks.first?.cards.first?.front, "Q1")
    }

    func testDeletingADeckRemovesItsReviewLogToo() {
        let store = QuizStore(root: root)
        let deck = store.addDeck(QuizDeck(name: "D", sourceKind: .material, sourceQuery: "m", cards: [card("Q1")]))
        store.recordReview(cardID: deck.cards[0].id, deckID: deck.id, rating: .good)
        XCTAssertEqual(store.reviews(for: deck.id).count, 1)

        store.deleteDeck(deck.id)

        let reloaded = QuizStore(root: root)
        XCTAssertTrue(reloaded.decks.isEmpty)
        // The deck folder (and its reviews.json) is gone — a fresh store for
        // the same id has nothing to read back.
        XCTAssertTrue(reloaded.reviews(for: deck.id).isEmpty)
    }

    func testAppendCardsSkipsDuplicatesByNormalizedFront() {
        let store = QuizStore(root: root)
        let deck = store.addDeck(QuizDeck(name: "D", sourceKind: .material, sourceQuery: "m", cards: [card("What is X?")]))

        store.appendCards([card("  what IS x?  "), card("New one")], to: deck.id)

        let cards = store.decks.first!.cards
        XCTAssertEqual(cards.count, 2)
        XCTAssertTrue(cards.contains { $0.front == "New one" })
    }

    func testRecordReviewUpdatesFSRSStateAndAppendsToTheLog() {
        let store = QuizStore(root: root)
        let deck = store.addDeck(QuizDeck(name: "D", sourceKind: .material, sourceQuery: "m", cards: [card("Q1")]))
        let cardID = deck.cards[0].id
        let dueBefore = store.decks.first!.cards[0].fsrs.due

        store.recordReview(cardID: cardID, deckID: deck.id, rating: .good)

        let updated = store.decks.first!.cards[0]
        XCTAssertEqual(updated.fsrs.reps, 1)
        XCTAssertGreaterThan(updated.fsrs.due, dueBefore)
        XCTAssertEqual(store.reviews(for: deck.id).count, 1)
        XCTAssertEqual(store.reviews(for: deck.id).first?.rating, .good)
        XCTAssertEqual(store.stats.streak, 1)
    }

    /// The whole reason `replaceCards` matches by normalized front instead of
    /// wiping and re-inserting: a regenerated card that still says the same
    /// thing keeps the schedule the student already earned for it.
    func testReplaceCardsPreservesFSRSStateForMatchedFronts() {
        let store = QuizStore(root: root)
        let deck = store.addDeck(QuizDeck(name: "D", sourceKind: .vaultTopic, sourceQuery: "t", cards: [card("Kept question")]))
        store.recordReview(cardID: deck.cards[0].id, deckID: deck.id, rating: .easy)
        let scheduledDue = store.decks.first!.cards[0].fsrs.due

        let result = store.replaceCards(
            [card("Kept question"), card("Brand new question")], in: deck.id
        )

        XCTAssertEqual(result.kept, 1)
        XCTAssertEqual(result.unmatched, 1)
        let kept = store.decks.first!.cards.first { $0.front == "Kept question" }
        XCTAssertEqual(kept?.fsrs.due, scheduledDue)
        let fresh = store.decks.first!.cards.first { $0.front == "Brand new question" }
        XCTAssertEqual(fresh?.fsrs.reps, 0)
    }
}
