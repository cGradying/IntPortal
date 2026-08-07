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

        /// A short human phrase for how far off it is — shared by the in-window
        /// banner and the menu bar so they never drift apart.
        func countdown(now: Date, calendar: Calendar = .current) -> String {
            if isNow { return "in session until \(ClassSession.format(session.end))" }

            let minutes = minutesAway(from: now)
            if minutes == 0 { return "starting now" }
            if minutes < 60 { return "in \(minutes) min" }

            return calendar.isDate(start, inSameDayAs: now)
                ? "at \(ClassSession.format(session.start))"
                : "\(session.day.short) \(ClassSession.format(session.start))"
        }
    }

    /// The next meeting that hasn't finished yet, or `nil` if there are none.
    ///
    /// `isVacant` takes a meeting **and the concrete date of the occurrence
    /// being considered**, so a caller can apply per-week vacancy that keys to
    /// the right week (this week vs. next) rather than a flat term-wide set —
    /// which is what keeps the menu bar's "up next" in step with the day list
    /// and the grid. Online meetings are deliberately never skipped; you still
    /// have to show up.
    static func next(
        in sessions: [ClassSession],
        at now: Date,
        isVacant: (ClassSession, Date) -> Bool = { _, _ in false },
        calendar: Calendar = .current
    ) -> Upcoming? {
        guard !sessions.isEmpty else { return nil }

        let thisWeek = Weekday.weekStart(containing: now, calendar: calendar)
        // Two weeks of candidates, because Sunday evening has to find Monday's
        // first class rather than reporting that the week is over.
        let weekStarts = [thisWeek, calendar.date(byAdding: .day, value: 7, to: thisWeek)]
            .compactMap { $0 }

        let upcoming = weekStarts.flatMap { weekStart in
            sessions.compactMap { session -> Upcoming? in
                let midnight = session.day.date(inWeekStarting: weekStart, calendar: calendar)
                // Added as minutes rather than a raw interval so a DST shift
                // moves the class with the clock instead of an hour off it.
                guard let start = calendar.date(byAdding: .minute, value: session.start, to: midnight),
                      let end = calendar.date(byAdding: .minute, value: session.end, to: midnight),
                      end > now
                else { return nil }

                // Checked per occurrence, so a class vacant only this week is
                // still a candidate next week.
                guard !isVacant(session, start) else { return nil }

                return Upcoming(session: session, start: start, isNow: start <= now)
            }
        }

        return upcoming.min { $0.start < $1.start }
    }
}
