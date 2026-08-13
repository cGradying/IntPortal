using Xunit;

namespace PUPSISPortal.Core.Tests;

/// <summary>
/// The shared "today at a glance" reading behind the Today screen and the menu
/// bar. Fixed clock, fake subjects — never a real schedule.
/// </summary>
public class DayAgendaTests
{
    /// <summary>
    /// A meeting on `day`, minutes-from-midnight.
    /// </summary>
    private ClassSession Session(string code, Weekday day, int start, int end)
    {
        return new ClassSession
        {
            SubjectCode = code,
            Description = "Test",
            Faculty = "SANTOS, JUAN",
            Day = day,
            Start = start,
            End = end
        };
    }

    /// <summary>
    /// A fixed DateTime on a known weekday at a given minute-of-day.
    /// Uses UTC for reproducibility: 2026-08-03 is a Monday.
    /// </summary>
    private DateTime Date(Weekday weekday, int minute)
    {
        var baseDate = new DateTime(2026, 8, 3, 0, 0, 0, DateTimeKind.Utc); // Monday
        var offset = (int)weekday - 1; // Monday = 1, so offset = 0
        var date = baseDate.AddDays(offset);
        var hour = minute / 60;
        var min = minute % 60;
        return date.AddHours(hour).AddMinutes(min);
    }

    private DayAgenda Agenda(
        IEnumerable<ClassSession> sessions,
        DateTime now,
        HashSet<string>? vacant = null)
    {
        vacant ??= new HashSet<string>();
        return DayAgenda.Make(sessions, now, (s, _) => vacant.Contains(s.Id));
    }

    // MARK: Phase

    [Fact]
    public void TestPhaseClassifiesPastNowUpcoming()
    {
        var sessions = new[]
        {
            Session("PAST", Weekday.Wednesday, 8 * 60, 9 * 60),
            Session("NOW", Weekday.Wednesday, 10 * 60, 11 * 60),
            Session("SOON", Weekday.Wednesday, 13 * 60, 14 * 60),
        };
        var result = Agenda(sessions, Date(Weekday.Wednesday, 10 * 60 + 30));

        var phases = result.Items.Select(i => i.Phase).ToList();
        Assert.Equal(new[] { ClassPhase.Past, ClassPhase.InSession, ClassPhase.Upcoming }, phases);

        var codes = result.Items.Select(i => i.Session.SubjectCode).ToList();
        Assert.Equal(new[] { "PAST", "NOW", "SOON" }, codes);
    }

    // MARK: Vacancy + sort

    [Fact]
    public void TestVacantIsDroppedAndItemsSortByStart()
    {
        var out_ = Session("OUT", Weekday.Wednesday, 9 * 60, 10 * 60);
        var sessions = new[]
        {
            Session("LATE", Weekday.Wednesday, 15 * 60, 16 * 60),
            out_,
            Session("EARLY", Weekday.Wednesday, 8 * 60, 9 * 60),
        };
        var result = Agenda(
            sessions,
            Date(Weekday.Wednesday, 7 * 60),
            new HashSet<string> { out_.Id }
        );

        var codes = result.Items.Select(i => i.Session.SubjectCode).ToList();
        Assert.Equal(new[] { "EARLY", "LATE" }, codes);
    }

    [Fact]
    public void TestRemainingExcludesFinishedClasses()
    {
        var sessions = new[]
        {
            Session("DONE", Weekday.Wednesday, 8 * 60, 9 * 60),
            Session("LEFT", Weekday.Wednesday, 14 * 60, 15 * 60),
        };
        var result = Agenda(sessions, Date(Weekday.Wednesday, 12 * 60));

        var codes = result.Remaining.Select(i => i.Session.SubjectCode).ToList();
        Assert.Equal(new[] { "LEFT" }, codes);
    }

    // MARK: Tomorrow

    [Fact]
    public void TestTomorrowFirstPicksEarliestNextDay()
    {
        var sessions = new[]
        {
            Session("TUE_LATE", Weekday.Thursday, 15 * 60, 16 * 60),
            Session("TUE_EARLY", Weekday.Thursday, 8 * 60, 9 * 60),
        };
        var result = Agenda(sessions, Date(Weekday.Wednesday, 20 * 60));

        Assert.Equal("TUE_EARLY", result.TomorrowFirst?.SubjectCode);
    }

    /// <summary>
    /// Sunday evening must look ahead to Monday — the week rolls over.
    /// </summary>
    [Fact]
    public void TestSundayEveningLooksAheadToMonday()
    {
        var monday = Session("MON", Weekday.Monday, 7 * 60, 8 * 60);
        var result = Agenda(new[] { monday }, Date(Weekday.Sunday, 21 * 60));

        Assert.Equal("MON", result.TomorrowFirst?.SubjectCode);
    }

    [Fact]
    public void TestEmptyDayHasNoItemsButStillFindsTomorrow()
    {
        var sessions = new[] { Session("TMRW", Weekday.Thursday, 9 * 60, 10 * 60) };
        var result = Agenda(sessions, Date(Weekday.Wednesday, 10 * 60));

        Assert.Empty(result.Items);
        Assert.Equal("TMRW", result.TomorrowFirst?.SubjectCode);
    }

    // MARK: Merged timeline (classes + custom events)

    private DayBlock Event(string title, Weekday day, int start, int end)
    {
        return new DayBlock(
            id: $"{title}-{start}",
            day: day,
            start: start,
            end: end,
            title: title,
            subtitle: $"{start}–{end}"
        );
    }

    private List<DayAgenda.AgendaEntry> Timeline(
        IEnumerable<ClassSession> classes,
        IEnumerable<DayBlock> events,
        DateTime now,
        HashSet<string>? vacant = null)
    {
        vacant ??= new HashSet<string>();
        return DayAgenda.Timeline(classes, events, now, (s, _) => vacant.Contains(s.Id));
    }

    /// <summary>
    /// Classes and events interleave in start order, not classes-then-events.
    /// </summary>
    [Fact]
    public void TestTimelineMergesAndOrdersByStart()
    {
        var math = Session("MATH", Weekday.Monday, 8 * 60, 10 * 60);
        var phys = Session("PHYS", Weekday.Monday, 14 * 60, 16 * 60);
        var lunch = Event("LUNCH", Weekday.Monday, 12 * 60, 13 * 60);

        var entries = Timeline(new[] { math, phys }, new[] { lunch }, Date(Weekday.Monday, 9 * 60));
        var titles = entries.Select(e => e.Title).ToList();
        Assert.Equal(new[] { "MATH", "LUNCH", "PHYS" }, titles);
    }

    [Fact]
    public void TestTimelineTagsPhaseAcrossBoth()
    {
        var math = Session("MATH", Weekday.Monday, 8 * 60, 10 * 60);
        var lunch = Event("LUNCH", Weekday.Monday, 12 * 60, 13 * 60);

        var entries = Timeline(new[] { math }, new[] { lunch }, Date(Weekday.Monday, 9 * 60));
        var mathEntry = entries.First(e => e.Title == "MATH");
        var lunchEntry = entries.First(e => e.Title == "LUNCH");

        Assert.Equal(ClassPhase.InSession, mathEntry.Phase);
        Assert.Equal(ClassPhase.Upcoming, lunchEntry.Phase);
    }

    /// <summary>
    /// Events on another day, and vacant classes, are left out.
    /// </summary>
    [Fact]
    public void TestTimelineFiltersOtherDaysAndVacant()
    {
        var math = Session("MATH", Weekday.Monday, 8 * 60, 10 * 60);
        var tomorrowEvent = Event("TMRW", Weekday.Tuesday, 9 * 60, 10 * 60);
        var now = Date(Weekday.Monday, 7 * 60);

        var entries = Timeline(
            new[] { math },
            new[] { tomorrowEvent },
            now,
            new HashSet<string> { math.Id }
        );
        Assert.Empty(entries);
    }

    /// <summary>
    /// Free time ahead sums the ≥15-minute gaps between entries that haven't passed.
    /// </summary>
    [Fact]
    public void TestRemainingFreeMinutesCountsGapsAhead()
    {
        var math = Session("MATH", Weekday.Monday, 8 * 60, 10 * 60);
        var phys = Session("PHYS", Weekday.Monday, 14 * 60, 16 * 60);
        var lunch = Event("LUNCH", Weekday.Monday, 12 * 60, 13 * 60);
        var entries = Timeline(
            new[] { math, phys },
            new[] { lunch },
            Date(Weekday.Monday, 9 * 60)
        );

        // 10:00→12:00 (120) + 13:00→14:00 (60) = 180, both still ahead of 9:00.
        var free = DayAgenda.RemainingFreeMinutes(entries, 9 * 60);
        Assert.Equal(180, free);
    }

    [Fact]
    public void TestRemainingFreeMinutesSkipsPassedGaps()
    {
        var math = Session("MATH", Weekday.Monday, 8 * 60, 10 * 60);
        var phys = Session("PHYS", Weekday.Monday, 14 * 60, 16 * 60);
        var lunch = Event("LUNCH", Weekday.Monday, 12 * 60, 13 * 60);
        var entries = Timeline(
            new[] { math, phys },
            new[] { lunch },
            Date(Weekday.Monday, 13 * 60 + 20)
        );

        // At 1:20PM the 10:00→12:00 gap has passed (its next entry, LUNCH at 12:00,
        // is behind now); only 13:00→14:00 (60, PHYS still ahead) counts.
        var free = DayAgenda.RemainingFreeMinutes(entries, 13 * 60 + 20);
        Assert.Equal(60, free);
    }
}
