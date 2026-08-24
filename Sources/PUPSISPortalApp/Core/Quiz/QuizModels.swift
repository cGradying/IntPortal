import Foundation

/// A rating on one card review — the four FSRS grades, plus what they mean to
/// the student. `Int` raw value matches the library's own `Grade` ordering
/// (1...4) so `FSRSAdapter` can convert without a lookup table.
enum QuizRating: Int, Codable, CaseIterable, Identifiable {
    case again = 1
    case hard = 2
    case good = 3
    case easy = 4

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .again: "Again"
        case .hard: "Hard"
        case .good: "Good"
        case .easy: "Easy"
        }
    }
}

/// A card's FSRS scheduling state — what `FSRSAdapter` reads and writes.
/// `due` in the past or today means the card is due for study.
struct FSRSState: Codable, Equatable {
    var due: Date
    var stability: Double
    var difficulty: Double
    var reps: Int
    var lapses: Int
    var lastReviewed: Date?

    /// A freshly-generated card, due immediately — new cards are studied on
    /// first sight, not scheduled forward.
    static func new(now: Date = Date()) -> FSRSState {
        FSRSState(due: now, stability: 0, difficulty: 0, reps: 0, lapses: 0, lastReviewed: nil)
    }
}

/// One flashcard. `subject` is recorded on every card (and every
/// `ReviewRecord`) from the start, not added later — it's the field that
/// makes "you're weak on X" possible once review history exists, and it
/// can't be backfilled onto cards that never carried it.
struct QuizCard: Codable, Equatable, Identifiable {
    var id: UUID
    var front: String
    var back: String
    /// Free-text subject/topic label — the RAG topic, a subject code, or
    /// whatever the source material was about. Not validated against the
    /// schedule's subject codes; it's a label, not a foreign key.
    var subject: String
    /// Where this card came from — a vault note key + chunk index, or a
    /// filename for imported material. Shown so a card can be traced back
    /// to what taught it; never emitted by the model itself.
    var citation: String
    var fsrs: FSRSState
    /// Alternate correct phrasings of `front`, for Identification's grading
    /// — generated alongside the card, editable in `CardReviewSheet`. Optional
    /// rather than defaulted to `[]`: Swift's synthesized `Decodable` only
    /// tolerates a *missing key* for an Optional property, not a non-optional
    /// with a default value, so a plain `[String] = []` would fail to decode
    /// every deck already saved before this field existed. Read via
    /// `acceptedAnswers ?? []`, never force-unwrapped.
    var acceptedAnswers: [String]?

    init(
        id: UUID = UUID(), front: String, back: String, subject: String,
        citation: String, fsrs: FSRSState = .new(), acceptedAnswers: [String]? = nil
    ) {
        self.id = id
        self.front = front
        self.back = back
        self.subject = subject
        self.citation = citation
        self.fsrs = fsrs
        self.acceptedAnswers = acceptedAnswers
    }

    /// Normalized for matching across a regenerate — case/whitespace-insensitive
    /// so trivial rephrasing by the model doesn't spuriously look like a new card.
    var normalizedFront: String {
        front.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

/// Where a deck's cards were generated from — kept so "regenerate" and
/// "generate more" know what to ask the model again.
enum QuizSourceKind: String, Codable {
    case vaultTopic
    case material
}

/// A saved deck: metadata + its cards (including their live FSRS state).
/// Lives at `decks/<id>/deck.json`; that folder's `reviews.json` is this
/// deck's review log (see `QuizStore`).
struct QuizDeck: Codable, Equatable, Identifiable {
    var id: UUID
    var name: String
    var sourceKind: QuizSourceKind
    /// The topic typed, or the material's filename/"Pasted text" — reused
    /// verbatim by regenerate.
    var sourceQuery: String
    var created: Date
    var cards: [QuizCard]

    init(
        id: UUID = UUID(), name: String, sourceKind: QuizSourceKind,
        sourceQuery: String, created: Date = Date(), cards: [QuizCard] = []
    ) {
        self.id = id
        self.name = name
        self.sourceKind = sourceKind
        self.sourceQuery = sourceQuery
        self.created = created
        self.cards = cards
    }

    /// Cards due now — what a study session pulls.
    func dueCards(now: Date = Date()) -> [QuizCard] {
        cards.filter { $0.fsrs.due <= now }
    }

}

/// Pure preview of what a regenerate would do — matched by normalized front
/// text, same rule `QuizStore.replaceCards` uses to actually apply it. Lets
/// the confirmation dialog name the count *before* anything is replaced.
func quizRegeneratePreview(old: [QuizCard], new: [QuizCard]) -> (kept: Int, unmatched: Int) {
    let oldFronts = Set(old.map(\.normalizedFront))
    let kept = new.filter { oldFronts.contains($0.normalizedFront) }.count
    return (kept, new.count - kept)
}

/// One completed review — the append-only log a deck's `reviews.json` holds.
/// `subject` is copied from the card at review time (not looked up later) so
/// the log stays meaningful even if the card is edited or deleted afterward.
struct QuizReviewRecord: Codable, Equatable {
    var cardID: UUID
    var subject: String
    var rating: QuizRating
    var date: Date
}
