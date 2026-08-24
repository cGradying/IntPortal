import XCTest
@testable import PUPSISPortal

final class QuizModeSupportTests: XCTestCase {
    private func card(_ front: String, _ back: String) -> QuizCard {
        QuizCard(front: front, back: back, subject: "S", citation: "c")
    }

    // MARK: pickDistractors

    func testPickDistractorsExcludesTheCardsOwnBack() {
        let target = card("Q", "correct answer")
        let deck = [target, card("Q2", "wrong 1"), card("Q3", "wrong 2"), card("Q4", "wrong 3")]

        let distractors = QuizModeSupport.pickDistractors(for: target, in: deck)

        XCTAssertFalse(distractors.contains("correct answer"))
        XCTAssertEqual(distractors.count, 3)
    }

    func testPickDistractorsNeverReturnsDuplicateBacks() {
        let target = card("Q", "correct")
        let deck = [target, card("Q2", "same"), card("Q3", "same"), card("Q4", "different")]

        let distractors = QuizModeSupport.pickDistractors(for: target, in: deck, count: 3)

        XCTAssertEqual(Set(distractors).count, distractors.count)
    }

    func testPickDistractorsReturnsFewerThanRequestedWhenTheDeckIsSmall() {
        let target = card("Q", "correct")
        let deck = [target, card("Q2", "only other")]

        let distractors = QuizModeSupport.pickDistractors(for: target, in: deck, count: 3)

        XCTAssertEqual(distractors, ["only other"])
    }

    // MARK: pickFalseStatement

    func testPickFalseStatementReturnsNilOnASingleCardDeck() {
        let only = card("Q", "A")
        XCTAssertNil(QuizModeSupport.pickFalseStatement(for: only, in: [only]))
    }

    func testPickFalseStatementNeverReturnsTheCardsOwnBack() {
        let target = card("Q", "correct")
        let deck = [target, card("Q2", "other")]

        for _ in 0..<20 {
            XCTAssertEqual(QuizModeSupport.pickFalseStatement(for: target, in: deck), "other")
        }
    }

    // MARK: matchingSet

    func testMatchingSetNeverExceedsTheDeckSize() {
        let deck = (0..<3).map { card("Q\($0)", "A\($0)") }
        XCTAssertEqual(QuizModeSupport.matchingSet(from: deck, count: 6).count, 3)
    }

    func testMatchingSetRespectsTheRequestedCountOnALargerDeck() {
        let deck = (0..<10).map { card("Q\($0)", "A\($0)") }
        XCTAssertEqual(QuizModeSupport.matchingSet(from: deck, count: 6).count, 6)
    }

    // MARK: isCorrectIdentification

    func testIdentificationIgnoresCaseAndSurroundingWhitespace() {
        let target = card("photosynthesis", "back")
        XCTAssertTrue(QuizModeSupport.isCorrectIdentification(typed: "  Photosynthesis  ", card: target))
    }

    func testIdentificationRejectsATypo() {
        let target = card("Photosynthesis", "back")
        XCTAssertFalse(QuizModeSupport.isCorrectIdentification(typed: "Photosynthessi", card: target))
    }

    /// The whole point of `acceptedAnswers`: a genuinely correct answer
    /// phrased differently than `front` still counts.
    func testIdentificationAcceptsAnAlternatePhrasingNotJustFront() {
        var target = card("Photosynthesis", "back")
        target.acceptedAnswers = ["the process of photosynthesis"]

        XCTAssertTrue(QuizModeSupport.isCorrectIdentification(typed: "The Process Of Photosynthesis", card: target))
        XCTAssertTrue(QuizModeSupport.isCorrectIdentification(typed: "photosynthesis", card: target))
        XCTAssertFalse(QuizModeSupport.isCorrectIdentification(typed: "respiration", card: target))
    }

    func testIdentificationWithNoAcceptedAnswersOnlyMatchesFront() {
        let target = card("Photosynthesis", "back")
        XCTAssertNil(target.acceptedAnswers)
        XCTAssertFalse(QuizModeSupport.isCorrectIdentification(typed: "the process of photosynthesis", card: target))
    }

    // MARK: QuizMode.minCards

    func testMinCardsGatesMultipleChoiceAndMatchingButNotFlashcardsOrIdentification() {
        XCTAssertEqual(QuizMode.flashcard.minCards, 1)
        XCTAssertEqual(QuizMode.identification.minCards, 1)
        XCTAssertEqual(QuizMode.multipleChoice.minCards, 4)
        XCTAssertEqual(QuizMode.trueFalse.minCards, 4)
        XCTAssertEqual(QuizMode.matching.minCards, 4)
    }

    // MARK: QuizQuestion.build

    func testMultipleChoiceOptionsAlwaysContainTheCardsOwnBackExactlyOnce() {
        let target = card("Q", "correct")
        let deck = [target, card("Q2", "w1"), card("Q3", "w2"), card("Q4", "w3")]

        guard case .multipleChoice(let builtCard, let options) = QuizQuestion.build(.multipleChoice, card: target, deck: deck) else {
            return XCTFail("expected .multipleChoice")
        }
        XCTAssertEqual(builtCard.id, target.id)
        XCTAssertEqual(options.filter { $0 == "correct" }.count, 1)
        XCTAssertEqual(options.count, 4)
    }

    func testTrueFalseIsActuallyTrueMatchesWhetherTheStatementIsTheCardsOwnBack() {
        let target = card("Q", "correct")
        let deck = [target, card("Q2", "other")]

        for _ in 0..<20 {
            guard case .trueFalse(_, let statement, let isActuallyTrue) = QuizQuestion.build(.trueFalse, card: target, deck: deck) else {
                return XCTFail("expected .trueFalse")
            }
            XCTAssertEqual(isActuallyTrue, statement == "correct")
        }
    }

    func testMatchingRoundNeverExceedsTheRequestedCount() {
        let deck = (0..<10).map { card("Q\($0)", "A\($0)") }
        guard case .matching(let round) = QuizQuestion.build(.matching, card: deck[0], deck: deck) else {
            return XCTFail("expected .matching")
        }
        XCTAssertLessThanOrEqual(round.count, 6)
    }
}
