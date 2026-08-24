import Foundation

/// A way to study a deck. Picked per session (`QuizModePicker`), never stored
/// on the deck — the same cards support all of them. No SwiftUI, no store
/// access, same as the rest of `Core/Quiz/`.
enum QuizMode: String, CaseIterable, Identifiable {
    case flashcard
    case identification
    case multipleChoice
    case trueFalse
    case matching

    var id: String { rawValue }

    var label: String {
        switch self {
        case .flashcard: "Flashcards"
        case .identification: "Identification"
        case .multipleChoice: "Multiple Choice"
        case .trueFalse: "True or False"
        case .matching: "Matching"
        }
    }

    var symbol: String {
        switch self {
        case .flashcard: "rectangle.on.rectangle"
        case .identification: "text.cursor"
        case .multipleChoice: "checklist"
        case .trueFalse: "checkmark.circle.trianglebadge.exclamationmark"
        case .matching: "arrow.left.arrow.right"
        }
    }

    /// Multiple choice needs 3 distractors + the correct answer; matching
    /// needs enough cards for a round to feel like more than one pair.
    /// Flashcards/identification work on a single card, so 1.
    var minCards: Int {
        switch self {
        case .flashcard, .identification: 1
        case .multipleChoice, .trueFalse: 4
        case .matching: 4
        }
    }
}

/// Pure helpers every non-flashcard mode uses to build a round from a deck's
/// own cards — no AI call, no schema, nothing `CardGenerator` needs to know
/// about. Distractors and the "false" half of a true/false round are sibling
/// cards' real backs, not invented text, so they're never nonsense.
enum QuizModeSupport {
    /// Up to `count` other cards' backs, excluding `card`'s own — the wrong
    /// options for a multiple-choice round. Deduped so two cards that happen
    /// to share a back (a near-duplicate the review sheet let through) don't
    /// show the same wrong answer twice.
    static func pickDistractors(for card: QuizCard, in deck: [QuizCard], count: Int = 3) -> [String] {
        var seen = Set([card.back.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()])
        var picked: [String] = []
        for sibling in deck.shuffled() {
            guard sibling.id != card.id else { continue }
            let key = sibling.back.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            picked.append(sibling.back)
            if picked.count == count { break }
        }
        return picked
    }

    /// A wrong statement for the false half of a true/false round — another
    /// card's real back. `nil` on a deck too small to have a sibling (also
    /// gated by `QuizMode.minCards`, but kept nil-safe for direct callers/tests).
    static func pickFalseStatement(for card: QuizCard, in deck: [QuizCard]) -> String? {
        deck.filter { $0.id != card.id }.randomElement()?.back
    }

    /// A random subset of `count` cards (or the whole deck if smaller) for
    /// one matching round.
    static func matchingSet(from deck: [QuizCard], count: Int = 6) -> [QuizCard] {
        Array(deck.shuffled().prefix(min(count, deck.count)))
    }

    /// Case/whitespace-insensitive exact match — identification's grading
    /// rule. A genuine typo counts wrong; predictable beats forgiving here,
    /// since a fuzzy match risks crediting a wrong-but-close answer. Checked
    /// against `card.front` **and** every `acceptedAnswers` entry, so a
    /// genuinely correct but differently-phrased answer isn't marked wrong
    /// just because it doesn't match the one string the model happened to
    /// generate as the front.
    static func isCorrectIdentification(typed: String, card: QuizCard) -> Bool {
        let normalizedTyped = normalize(typed)
        let candidates = [card.front] + (card.acceptedAnswers ?? [])
        return candidates.contains { normalize($0) == normalizedTyped }
    }

    private static func normalize(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

/// What a mode needs to render one round and grade the answer — one typed
/// shape instead of each session view building (and re-shuffling, and
/// re-picking-siblings) its own private `Round` struct. `MultipleChoiceSession`
/// and `TrueFalseSession` ask `build` for the next question; `MatchingSession`
/// keeps its own tile-by-tile interaction (there's no single "the current
/// question" to hand back for a whole round of pairs), so `.matching` here is
/// only the initial round selection.
enum QuizQuestion {
    case flashcard(card: QuizCard)
    case identification(card: QuizCard)
    /// `options` is shuffled and always contains `card.back` exactly once.
    case multipleChoice(card: QuizCard, options: [String])
    case trueFalse(card: QuizCard, statement: String, isActuallyTrue: Bool)
    case matching(round: [QuizCard])

    /// Builds the question for `card` under `mode`, using `deck` for modes
    /// that need sibling cards. `deck` should be the deck's full card list
    /// (not just the due queue) — a due queue of one card would otherwise
    /// starve multiple-choice/true-false of distractors mid-session.
    static func build(_ mode: QuizMode, card: QuizCard, deck: [QuizCard]) -> QuizQuestion {
        switch mode {
        case .flashcard:
            return .flashcard(card: card)
        case .identification:
            return .identification(card: card)
        case .multipleChoice:
            var options = QuizModeSupport.pickDistractors(for: card, in: deck) + [card.back]
            options.shuffle()
            return .multipleChoice(card: card, options: options)
        case .trueFalse:
            let falseStatement = QuizModeSupport.pickFalseStatement(for: card, in: deck)
            // Falls back to the real statement (always "true") if the deck's
            // too small for a sibling — `QuizMode.minCards` keeps this mode
            // off that small a deck anyway; nil-safety costs nothing here.
            let showFalse = Bool.random() && falseStatement != nil
            return .trueFalse(
                card: card, statement: showFalse ? falseStatement! : card.back, isActuallyTrue: !showFalse
            )
        case .matching:
            return .matching(round: QuizModeSupport.matchingSet(from: deck))
        }
    }
}
