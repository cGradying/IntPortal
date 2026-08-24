import Foundation
import FSRS

/// The one file that knows the `SwiftFSRS` package exists. Everything else in
/// `Core/Quiz/` and every view works in `FSRSState`/`QuizRating` — this
/// translates to and from the library's `FSRSCard`/`Rating` at the one seam,
/// so a future Windows port (a C# FSRS package, almost certainly a different
/// API) only has to rewrite this file, not anything that calls into it.
enum FSRSAdapter {
    /// Published FSRS-6 default weights — `FSRSConfiguration()` with every
    /// field nil, which `FSRSParametersGenerator` fills in. No per-user
    /// parameter optimization; see the plan's "deliberately not in v1" list.
    private static let engine = FSRS<LibraryCard>()

    /// A minimal `FSRSCard` conformer, built fresh from `FSRSState` for each
    /// call — the library owns no state between calls, so there's nothing to
    /// keep alive.
    private struct LibraryCard: FSRSCard {
        var due: Date
        var state: State
        var lastReview: Date?
        var stability: Double
        var difficulty: Double
        var scheduledDays: Int
        var learningSteps: Int
        var reps: Int
        var lapses: Int
    }

    private static func libraryCard(from state: FSRSState) -> LibraryCard {
        LibraryCard(
            due: state.due,
            // A card with no reps yet is `.new`; anything reviewed at least
            // once is treated as `.review` — this app doesn't expose FSRS's
            // separate learning/relearning short-term steps, so there's
            // nothing case-specific to preserve between calls.
            state: state.reps == 0 ? .new : .review,
            lastReview: state.lastReviewed,
            stability: state.stability,
            difficulty: state.difficulty,
            scheduledDays: 0,
            learningSteps: 0,
            reps: state.reps,
            lapses: state.lapses
        )
    }

    private static func rating(for grade: QuizRating) -> Rating {
        switch grade {
        case .again: .again
        case .hard: .hard
        case .good: .good
        case .easy: .easy
        }
    }

    /// Applies a review rating to a card's current state, returning its new
    /// scheduled state. Never throws to the caller — a scheduling failure
    /// (only possible on a manual rating, which `QuizRating` doesn't expose)
    /// leaves the card's state unchanged rather than losing the review.
    static func review(_ state: FSRSState, rating grade: QuizRating, now: Date = Date()) -> FSRSState {
        let card = libraryCard(from: state)
        guard let result = try? engine.schedule(card: card, at: now, rating: rating(for: grade)) else {
            return state
        }
        let next = result.card
        return FSRSState(
            due: next.due,
            stability: next.stability,
            difficulty: next.difficulty,
            reps: next.reps,
            lapses: next.lapses,
            lastReviewed: now
        )
    }
}
