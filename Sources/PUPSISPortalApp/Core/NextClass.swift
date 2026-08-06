import Foundation

/// "What's next" — the one glance that makes the app worth opening daily.
///
/// Pure logic on purpose: no `Preferences`, no views, no clock of its own. The
/// caller supplies `now` and the set of meetings to skip, which is what makes
/// every case here testable at a fixed date.
enum NextClass {
    struct Upcoming: Equatable {
        let session: ClassSession
        /// The concrete `Date` this meeting starts, not just minutes-from-midnight.
        let start: Date
        /// True while `now` sits inside the meeting — the banner says "In
        /// session" rather than counting down to something already happening.
        let isNow: Bool

        /// Whole minutes until it starts; zero once it has.
        func minutesAway(from now: Date) -> Int {
            max(Int(start.timeIntervalSince(now) / 60), 0)
        }
    }

    /// The next meeting that hasn't finished yet, or `nil` if there are none.
    ///
    /// `skipping` takes `ClassSession.id`s the user marked vacant. Online ones
    /// are deliberately *not* skipped — you still have to show up.
    static func next(
        in sessions: [ClassSession],
        at now: Date,
        skipping vacant: Set<String> = [],
        calendar: Calendar = .current
    ) -> Upcoming? {
        let live = sessions.filter { !vacant.contains($0.id) }
        guard !live.isEmpty else { return nil }

        let thisWeek = Weekday.weekStart(containing: now, calendar: calendar)
        // Two weeks of candidates, because Sunday evening has to find Monday's
        // first class rather than reporting that the week is over.
        let weekStarts = [thisWeek, calendar.date(byAdding: .day, value: 7, to: thisWeek)]
            .compactMap { $0 }

        let upcoming = weekStarts.flatMap { weekStart in
            live.compactMap { session -> Upcoming? in
                let midnight = session.day.date(inWeekStarting: weekStart, calendar: calendar)
                // Added as minutes rather than a raw interval so a DST shift
                // moves the class with the clock instead of an hour off it.
                guard let start = calendar.date(byAdding: .minute, value: session.start, to: midnight),
                      let end = calendar.date(byAdding: .minute, value: session.end, to: midnight),
                      end > now
                else { return nil }

                return Upcoming(session: session, start: start, isNow: start <= now)
            }
        }

        return upcoming.min { $0.start < $1.start }
    }
}
