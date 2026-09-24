import Foundation

/// Spec 11 upgrade 4: how many cards come due each of the next 7 days, for
/// the dithered bars drawn under each deck.
enum DueForecast {
    /// 7 counts by `fsrs.due`, bucket 0 starting on `day`'s calendar day.
    /// Bucket 0 also catches anything already overdue (due before today),
    /// same as `QuizDeck.dueCards` — "due today" already means "due" to
    /// every other read of this data, so the forecast shouldn't disagree.
    /// Boundaries come from `calendar.date(byAdding:)`, never `+86400`, so a
    /// DST transition inside the window can't shift a bucket by an hour and
    /// land a card's day-of-due on the wrong side of it.
    static func next7(cards: [QuizCard], from day: Date, calendar: Calendar = .current) -> [Int] {
        let start = calendar.startOfDay(for: day)
        return (0..<7).map { offset in
            guard
                let bucketStart = calendar.date(byAdding: .day, value: offset, to: start),
                let bucketEnd = calendar.date(byAdding: .day, value: 1, to: bucketStart)
            else { return 0 }

            return cards.filter { card in
                offset == 0
                    ? card.fsrs.due < bucketEnd
                    : card.fsrs.due >= bucketStart && card.fsrs.due < bucketEnd
            }.count
        }
    }
}
