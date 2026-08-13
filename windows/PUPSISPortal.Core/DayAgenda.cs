namespace PUPSISPortal.Core;

/// <summary>
/// Where a class sits relative to right now.
/// </summary>
public enum ClassPhase
{
    Past,
    InSession,
    Upcoming,
}

/// <summary>
/// "What does today look like right now" — the shared reading behind both the
/// Today screen and the menu bar. Pure on purpose: no Preferences, no views,
/// no clock of its own. Vacancy arrives as a closure taking the class and its
/// occurrence date, so each caller applies its own per-week rule and tomorrow
/// keys to the right week (which can be next week) without this type depending
/// on Preferences.
/// </summary>
public record DayAgenda
{
    public record Item(ClassSession Session, ClassPhase Phase)
    {
        public string Id => Session.Id;
    }

    /// <summary>
    /// Today's non-vacant classes, sorted by start, each tagged with its phase.
    /// </summary>
    public required List<Item> Items { get; set; }

    /// <summary>
    /// The first non-vacant class tomorrow, or null.
    /// </summary>
    public ClassSession? TomorrowFirst { get; set; }

    /// <summary>
    /// Today's classes that haven't finished — what the menu bar shows, so the
    /// scarce space reads as "now and what's left", not the whole past day.
    /// </summary>
    public List<Item> Remaining => Items.Where(i => i.Phase != ClassPhase.Past).ToList();

    public static DayAgenda Make(
        IEnumerable<ClassSession> sessions,
        DateTime now,
        Func<ClassSession, DateTime, bool> isVacant)
    {
        var today = WeekdayExtensions.On(now);
        var nowMinutes = NowLine.Minutes(now);

        var sessionsList = sessions.ToList();
        var items = sessionsList
            .Where(s => s.Day == today && !isVacant(s, now))
            .OrderBy(s => s.Start)
            .Select(session =>
            {
                var phase = session.End <= nowMinutes ? ClassPhase.Past
                    : session.Start <= nowMinutes ? ClassPhase.InSession
                    : ClassPhase.Upcoming;
                return new Item(session, phase);
            })
            .ToList();

        var tomorrowDate = now.AddDays(1);
        var tomorrowDay = WeekdayExtensions.On(tomorrowDate);
        var tomorrowFirst = sessionsList
            .Where(s => s.Day == tomorrowDay && !isVacant(s, tomorrowDate))
            .OrderBy(s => s.Start)
            .FirstOrDefault();

        return new DayAgenda { Items = items, TomorrowFirst = tomorrowFirst };
    }

    // MARK: Merged timeline (classes + custom calendar events)

    /// <summary>
    /// A single row in the Today timeline — a class or a calendar event, flattened
    /// to the same shape so free time can be read across both.
    /// </summary>
    public record AgendaEntry
    {
        public enum KindType { Klass, Event }

        public required string Id { get; set; }
        /// <summary>
        /// Minutes from midnight.
        /// </summary>
        public required int Start { get; set; }
        public required int End { get; set; }
        public required string Title { get; set; }
        public required string Subtitle { get; set; }
        public required KindType Kind { get; set; }
        public required ClassPhase Phase { get; set; }

        public ClassSession? Session { get; set; }
    }

    /// <summary>
    /// Today's non-vacant classes merged with today's calendar events, sorted by
    /// start and phase-tagged — so the Today screen can draw one timeline and its
    /// free stretches span classes and the user's own events, not just classes.
    /// </summary>
    public static List<AgendaEntry> Timeline(
        IEnumerable<ClassSession> classes,
        IEnumerable<DayBlock> events,
        DateTime now,
        Func<ClassSession, DateTime, bool> isVacant)
    {
        var today = WeekdayExtensions.On(now);
        var nowMinutes = NowLine.Minutes(now);

        ClassPhase Phase(int start, int end) =>
            end <= nowMinutes ? ClassPhase.Past
            : start <= nowMinutes ? ClassPhase.InSession
            : ClassPhase.Upcoming;

        var classList = classes.ToList();
        var classEntries = classList
            .Where(s => s.Day == today && !isVacant(s, now))
            .Select(session => new AgendaEntry
            {
                Id = $"class-{session.Id}",
                Start = session.Start,
                End = session.End,
                Title = session.SubjectCode,
                Subtitle = session.Description,
                Kind = AgendaEntry.KindType.Klass,
                Phase = Phase(session.Start, session.End),
                Session = session,
            })
            .ToList();

        var eventList = events.ToList();
        var eventEntries = eventList
            .Where(b => b.Day == today)
            .Select(block => new AgendaEntry
            {
                Id = block.Id,
                Start = block.Start,
                End = block.End,
                Title = block.Title,
                Subtitle = block.Subtitle,
                Kind = AgendaEntry.KindType.Event,
                Phase = Phase(block.Start, block.End),
            })
            .ToList();

        return (classEntries.Concat(eventEntries).OrderBy(e => e.Start)).ToList();
    }

    /// <summary>
    /// Free minutes still ahead today — the ≥15-minute gaps the timeline draws
    /// between consecutive entries, counting only gaps that haven't passed.
    /// Overlapping entries contribute nothing (a negative gap is dropped).
    /// </summary>
    public static int RemainingFreeMinutes(IEnumerable<AgendaEntry> entries, int nowMinutes)
    {
        var entryList = entries.ToList();
        var total = 0;

        for (int i = 0; i < entryList.Count - 1; i++)
        {
            var gap = entryList[i + 1].Start - entryList[i].End;
            if (gap >= 15 && entryList[i + 1].Start > nowMinutes)
            {
                total += gap;
            }
        }

        return total;
    }

    public DayAgenda() { }
}

/// <summary>
/// Helper to extract minutes from midnight from a DateTime.
/// </summary>
public static class NowLine
{
    public static int Minutes(DateTime now)
    {
        return now.Hour * 60 + now.Minute;
    }
}
