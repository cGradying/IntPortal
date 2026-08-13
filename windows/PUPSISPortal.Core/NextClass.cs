namespace PUPSISPortal.Core;

/// <summary>
/// "What's next" — the one glance that makes the app worth opening daily.
///
/// Pure logic on purpose: no Preferences, no views, no clock of its own. The
/// caller supplies `now` and the set of meetings to skip, which is what makes
/// every case here testable at a fixed date.
/// </summary>
public static class NextClass
{
    public record Upcoming
    {
        public required ClassSession Session { get; set; }
        /// <summary>
        /// The concrete DateTime this meeting starts, not just minutes-from-midnight.
        /// </summary>
        public required DateTime Start { get; set; }
        /// <summary>
        /// True while now sits inside the meeting — the banner says "In
        /// session" rather than counting down to something already happening.
        /// </summary>
        public required bool IsNow { get; set; }

        /// <summary>
        /// Whole minutes until it starts; zero once it has.
        /// </summary>
        public int MinutesAway(DateTime from)
        {
            return Math.Max((int)Math.Floor(Start.Subtract(from).TotalMinutes), 0);
        }

        /// <summary>
        /// A short human phrase for how far off it is — shared by the in-window
        /// banner and the menu bar so they never drift apart.
        /// </summary>
        public string Countdown(DateTime now)
        {
            if (IsNow)
                return $"in session until {ClassSession.Format(Session.End)}";

            var minutes = MinutesAway(now);
            if (minutes == 0)
                return "starting now";
            if (minutes < 60)
                return $"in {minutes} min";

            // Same-day logic: check if both dates are on the same day
            if (now.Date == Start.Date)
                return $"at {ClassSession.Format(Session.Start)}";

            return $"{Session.Day.Short()} {ClassSession.Format(Session.Start)}";
        }
    }

    /// <summary>
    /// The next meeting that hasn't finished yet, or null if there are none.
    ///
    /// `isVacant` takes a meeting and the concrete date of the occurrence
    /// being considered, so a caller can apply per-week vacancy that keys to
    /// the right week (this week vs. next) rather than a flat term-wide set —
    /// which is what keeps the menu bar's "up next" in step with the day list
    /// and the grid. Online meetings are deliberately never skipped; you still
    /// have to show up.
    /// </summary>
    public static Upcoming? Next(
        IEnumerable<ClassSession> sessions,
        DateTime now,
        Func<ClassSession, DateTime, bool>? isVacant = null)
    {
        isVacant ??= (_, _) => false;

        var sessionsList = sessions.ToList();
        if (sessionsList.Count == 0)
            return null;

        var thisWeek = WeekdayExtensions.WeekStart(now);
        // Two weeks of candidates, because Sunday evening has to find Monday's
        // first class rather than reporting that the week is over.
        var weekStarts = new[] { thisWeek, thisWeek.AddDays(7) };

        var upcoming = new List<Upcoming>();

        foreach (var weekStart in weekStarts)
        {
            foreach (var session in sessionsList)
            {
                var midnight = session.Day.DateInWeekStarting(weekStart);
                var start = midnight.AddMinutes(session.Start);
                var end = midnight.AddMinutes(session.End);

                if (end <= now)
                    continue;

                if (isVacant(session, start))
                    continue;

                upcoming.Add(new Upcoming
                {
                    Session = session,
                    Start = start,
                    IsNow = start <= now
                });
            }
        }

        return upcoming.Count > 0
            ? upcoming.OrderBy(u => u.Start).First()
            : null;
    }
}
