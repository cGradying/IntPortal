using PUPSISPortal.Core;

namespace PUPSISPortal.Core.Tests;

/// <summary>
/// Cases are the real schedule lines scraped from the live SIS page.
/// </summary>
public class ScheduleParserTests
{
    private static List<ClassSession> Parse(string line)
    {
        return ScheduleParser.Parse(new Dictionary<string, string>
        {
            { "subjectCode", "TEST 001" },
            { "description", "Test Subject" },
            { "faculty", "SANTOS, JUAN" },
            { "scheduleLine", line },
        });
    }

    [Fact]
    public void TwoDaysPairWithTheirOwnTimes()
    {
        var sessions = Parse("1N - BSCS 1-1N - T/F 02:00PM-04:00PM/01:30PM-04:30PM");
        Assert.Equal(2, sessions.Count);
        Assert.Equal(Weekday.Tuesday, sessions[0].Day);
        Assert.Equal(14 * 60, sessions[0].Start);
        Assert.Equal(16 * 60, sessions[0].End);
        Assert.Equal(Weekday.Friday, sessions[1].Day);
        Assert.Equal(13 * 60 + 30, sessions[1].Start);
        Assert.Equal(16 * 60 + 30, sessions[1].End);
    }

    [Fact]
    public void SameDayTwiceBecomesTwoBlocks()
    {
        var sessions = Parse("1N - BSCS 1-1N - SUN/SUN 08:00AM-12:00PM/01:00PM-06:00PM");
        Assert.Equal(2, sessions.Count);
        Assert.True(sessions.All(s => s.Day == Weekday.Sunday));
        Assert.Equal(8 * 60, sessions[0].Start);
        Assert.Equal(12 * 60, sessions[0].End);
        Assert.Equal(13 * 60, sessions[1].Start);
        Assert.Equal(18 * 60, sessions[1].End);
    }

    [Fact]
    public void SingleDaySingleRange()
    {
        var sessions = Parse("1N - BSCS 1-1N - S 07:30AM-10:30AM");
        Assert.Single(sessions);
        Assert.Equal(Weekday.Saturday, sessions[0].Day);
        Assert.Equal(7 * 60 + 30, sessions[0].Start);
        Assert.Equal(10 * 60 + 30, sessions[0].End);
    }

    /// <summary>
    /// `TH` and `SUN` must win over the single-letter `T`/`S` codes.
    /// </summary>
    [Fact]
    public void MultiLetterDayCodesArentSwallowed()
    {
        var th = Parse("1N - X - TH 09:00AM-11:00AM");
        Assert.NotEmpty(th);
        Assert.Equal(Weekday.Thursday, th.First().Day);

        var sun = Parse("1N - X - SUN 09:00AM-11:00AM");
        Assert.NotEmpty(sun);
        Assert.Equal(Weekday.Sunday, sun.First().Day);
    }

    [Fact]
    public void NoonAndMidnightBoundaries()
    {
        var noon = Parse("1N - X - M 12:00PM-01:00PM");
        Assert.NotEmpty(noon);
        Assert.Equal(12 * 60, noon.First().Start);
        Assert.Equal(13 * 60, noon.First().End);

        var earlyMorning = Parse("1N - X - M 12:30AM-01:30AM");
        Assert.NotEmpty(earlyMorning);
        Assert.Equal(30, earlyMorning.First().Start);
        Assert.Equal(90, earlyMorning.First().End);
    }

    [Fact]
    public void UnparseableRowsAreSkippedNotCrashed()
    {
        Assert.Empty(Parse(""));
        Assert.Empty(Parse("1N - BSCS 1-1N - TBA"));
        Assert.Empty(Parse("no times here at all"));
    }
}

/// <summary>
/// DayOfWeek numbers weekdays from Sunday = 0, this enum counts from Monday = 1.
/// Getting the shift wrong puts the now-line in the wrong column.
/// </summary>
public class WeekdayTests
{
    private static Weekday GetWeekday(int year, int month, int day)
    {
        var date = new DateTime(year, month, day, 12, 0, 0);
        return WeekdayExtensions.On(date);
    }

    [Fact]
    public void EveryDayOfAKnownWeekMaps()
    {
        // 2026-08-03 is a Monday.
        Assert.Equal(Weekday.Monday, GetWeekday(2026, 8, 3));
        Assert.Equal(Weekday.Tuesday, GetWeekday(2026, 8, 4));
        Assert.Equal(Weekday.Wednesday, GetWeekday(2026, 8, 5));
        Assert.Equal(Weekday.Thursday, GetWeekday(2026, 8, 6));
        Assert.Equal(Weekday.Friday, GetWeekday(2026, 8, 7));
        Assert.Equal(Weekday.Saturday, GetWeekday(2026, 8, 8));
        Assert.Equal(Weekday.Sunday, GetWeekday(2026, 8, 9));
    }

    /// <summary>
    /// The week should always start on Monday regardless of the system's locale.
    /// </summary>
    [Fact]
    public void WeekStartIsMondayRegardlessOfLocale()
    {
        var monday = new DateTime(2026, 8, 3); // Monday
        var wednesday = new DateTime(2026, 8, 5);
        var sunday = new DateTime(2026, 8, 9);

        var startFromMonday = WeekdayExtensions.WeekStart(monday);
        var startFromWednesday = WeekdayExtensions.WeekStart(wednesday);
        var startFromSunday = WeekdayExtensions.WeekStart(sunday);

        Assert.Equal(monday.Date, startFromMonday);
        Assert.Equal(monday.Date, startFromWednesday);
        Assert.Equal(monday.Date, startFromSunday);
    }

    /// <summary>
    /// Sunday belongs to the week that started six days earlier, not the one
    /// about to begin.
    /// </summary>
    [Fact]
    public void SundayClosesTheWeekRatherThanOpeningTheNext()
    {
        var sunday = new DateTime(2026, 8, 9);
        var monday = new DateTime(2026, 8, 3);

        var start = WeekdayExtensions.WeekStart(sunday);
        Assert.Equal(monday.Date, start);

        var sundayInWeek = Weekday.Sunday.DateInWeekStarting(start);
        Assert.Equal(sunday.Date, sundayInWeek.Date);
    }

    [Fact]
    public void EachWeekdayLandsOnItsOwnDate()
    {
        var start = new DateTime(2026, 8, 3); // Monday
        var dates = new List<DateTime>();
        foreach (Weekday day in Enum.GetValues(typeof(Weekday)))
        {
            dates.Add(day.DateInWeekStarting(start));
        }

        // All dates should be unique
        Assert.Equal(dates.Count, new HashSet<DateTime>(dates).Count);

        // First should be Monday (2026-08-03)
        Assert.Equal(new DateTime(2026, 8, 3), dates.First());

        // Last should be Sunday (2026-08-09)
        Assert.Equal(new DateTime(2026, 8, 9), dates.Last());
    }
}

/// <summary>
/// ClassSession.NextMeetingDate — drives the class-note Add-date menu's
/// "Next class" default.
/// </summary>
public class ClassSessionNextMeetingTests
{
    private static DateTime DateOnly(int year, int month, int day) => new DateTime(year, month, day);

    private static ClassSession Session(string subject, Weekday day) =>
        new ClassSession
        {
            SubjectCode = subject,
            Description = "",
            Faculty = "",
            Day = day,
            Start = 480,
            End = 600
        };

    /// <summary>
    /// Subject meets Sunday; asking from Saturday (the 15th) should land on
    /// Sunday the 16th, not today.
    /// </summary>
    [Fact]
    public void WrapsForwardToTheNextScheduledWeekday()
    {
        var sessions = new List<ClassSession> { Session("COMP1", Weekday.Sunday) };
        var saturday = DateOnly(2026, 8, 15);

        var next = WeekdayExtensions.NextMeetingDate("COMP1", sessions, saturday);

        Assert.Equal(DateOnly(2026, 8, 16), next);
    }

    /// <summary>
    /// Asking on the meeting day itself returns that same day, not a week out.
    /// </summary>
    [Fact]
    public void ReturnsTodayWhenTodayIsAMeetingDay()
    {
        var sessions = new List<ClassSession> { Session("COMP1", Weekday.Sunday) };
        var sunday = DateOnly(2026, 8, 16);

        var next = WeekdayExtensions.NextMeetingDate("COMP1", sessions, sunday);

        Assert.Equal(sunday, next);
    }

    [Fact]
    public void NilForASubjectNotOnTheSchedule()
    {
        var sessions = new List<ClassSession> { Session("COMP1", Weekday.Sunday) };

        var next = WeekdayExtensions.NextMeetingDate("MATH1", sessions, DateOnly(2026, 8, 15));

        Assert.Null(next);
    }
}
