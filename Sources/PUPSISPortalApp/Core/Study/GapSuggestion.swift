import Foundation

/// A stretch of free time today, minutes-from-midnight — the same shape
/// `DayAgenda.AgendaEntry.start`/`.end` already use. Lifted out on its own so
/// this file doesn't have to import anything view-facing just to talk about
/// "a gap"; the Today screen builds these from its own merged timeline.
struct StudyGap: Equatable {
    var start: Int
    var end: Int
}

/// Spec 11 upgrade 1: what to study, and for how long, in a free block of
/// the day.
enum GapSuggestion {
    struct Suggestion: Equatable {
        var deck: QuizDeck
        var dueCount: Int
        var minutes: Int
        var mode: QuizMode
        var examDate: Date?
    }

    /// Picks the gap `now` falls in (or the next one still ahead), then the
    /// deck with the most cards due for it — ties go to whichever deck's
    /// linked exam (`examDates`, keyed by deck id, already resolved by
    /// `ExamLink` upstream) is soonest. Minutes are `min(due × 2, gap
    /// remaining)`. Always suggests Flashcards, the one mode every deck
    /// supports regardless of size.
    static func make(
        gaps: [StudyGap], decks: [QuizDeck], now: Date,
        examDates: [UUID: Date] = [:], calendar: Calendar = .current
    ) -> Suggestion? {
        let nowMinutes = minutesSinceMidnight(now, calendar: calendar)
        guard let gap = gaps.filter({ $0.end > nowMinutes }).min(by: { $0.start < $1.start }) else {
            return nil
        }
        let remaining = gap.end - max(gap.start, nowMinutes)
        guard remaining > 0 else { return nil }

        let candidates = decks.compactMap { deck -> (deck: QuizDeck, due: Int)? in
            let due = deck.dueCards(now: now).count
            return due > 0 ? (deck, due) : nil
        }
        guard let maxDue = candidates.map(\.due).max() else { return nil }
        guard let winner = candidates
            .filter({ $0.due == maxDue })
            .min(by: { (examDates[$0.deck.id] ?? .distantFuture) < (examDates[$1.deck.id] ?? .distantFuture) })
        else { return nil }

        return Suggestion(
            deck: winner.deck,
            dueCount: winner.due,
            minutes: min(winner.due * 2, remaining),
            mode: .flashcard,
            examDate: examDates[winner.deck.id]
        )
    }

    private static func minutesSinceMidnight(_ date: Date, calendar: Calendar) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
}
