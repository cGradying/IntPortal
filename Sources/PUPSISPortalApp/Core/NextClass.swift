import Foundation

extension Calendar {
    /// Resolves minutes-from-midnight to a concrete wall-clock `Date` by
    /// setting the hour/minute directly on `day`, rather than adding elapsed
    /// minutes to its midnight. On a DST transition day, adding elapsed
    /// minutes drifts by the DST offset (a class scraped as starting at 8:30
    /// lands at 9:30 or 7:30), while `bySettingHour:minute:` always resolves
    /// to that literal wall-clock time.
    ///
    /// Returns `nil` for a wall-clock time a spring-forward gap skips (e.g.
    /// 2:30 on a day that jumps 2:00→3:00) — no class actually meets at a
    /// time that never happened that day. Callers decide what a `nil` means
    /// for them.
    ///
    /// Neither `bySettingHour:minute:second:of:` nor `date(from:)` actually
    /// fail on a skipped time — every `matchingPolicy`, `.strict` included,
    /// silently normalizes it to some *other* valid moment (the next hour,
    /// sometimes the next day entirely) instead of returning nil. So this
    /// builds the date and round-trips its components back out: if what
    /// comes back isn't the literal day/hour/minute that was asked for, the
    /// requested time never happened and the occurrence is invalid.
    func wallClock(minutes: Int, on day: Date) -> Date? {
        var components = dateComponents([.year, .month, .day], from: day)
        components.hour = minutes / 60
        components.minute = minutes % 60
        components.second = 0

        guard let resolved = date(from: components) else { return nil }
        let actual = dateComponents([.year, .month, .day, .hour, .minute], from: resolved)
        guard actual.year == components.year, actual.month == components.month,
              actual.day == components.day, actual.hour == components.hour,
              actual.minute == components.minute
        else { return nil }

        return resolved
    }
}

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
        /// Resolved minutes-from-midnight for this occurrence — the locally
        /// moved time if one applies, otherwise `session.start`/`.end`. Text
        /// must read off these, never `session.start`/`.end` directly, or a
        /// moved class would show its old SIS time here.
        let startMinutes: Int
        let endMinutes: Int
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
            if isNow { return "in session until \(ClassSession.format(endMinutes))" }

            let minutes = minutesAway(from: now)
            if minutes == 0 { return "starting now" }
            if minutes < 60 { return "in \(minutes) min" }

            return calendar.isDate(start, inSameDayAs: now)
                ? "at \(ClassSession.format(startMinutes))"
                : "\(session.day.short) \(ClassSession.format(startMinutes))"
        }
    }

    /// The next meeting that hasn't finished yet, or `nil` if there are none.
    ///
    /// `isVacant` and `time` both take a meeting **and the concrete date of the
    /// occurrence being considered**, so a caller can apply per-week vacancy
    /// and per-week time moves that key to the right week (this week vs. next)
    /// rather than a flat term-wide set — which is what keeps the menu bar's
    /// "up next" in step with the day list and the grid. Online meetings are
    /// deliberately never skipped; you still have to show up.
    static func next(
        in sessions: [ClassSession],
        at now: Date,
        isVacant: (ClassSession, Date) -> Bool = { _, _ in false },
        time: (ClassSession, Date) -> (Int, Int) = { s, _ in (s.start, s.end) },
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
                let (startMinutes, endMinutes) = time(session, midnight)
                // A skipped spring-forward occurrence is dropped here — no
                // class actually meets at a time that never happened that day.
                guard let start = calendar.wallClock(minutes: startMinutes, on: midnight),
                      let end = calendar.wallClock(minutes: endMinutes, on: midnight),
                      end > now
                else { return nil }

                // Checked per occurrence, so a class vacant only this week is
                // still a candidate next week.
                guard !isVacant(session, start) else { return nil }

                return Upcoming(
                    session: session, start: start,
                    startMinutes: startMinutes, endMinutes: endMinutes,
                    isNow: start <= now
                )
            }
        }

        return upcoming.min { $0.start < $1.start }
    }
}
