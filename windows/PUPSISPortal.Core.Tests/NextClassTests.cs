using Xunit;

namespace PUPSISPortal.Core.Tests;

/// <summary>
/// Fixed dates throughout — "next class" is the one feature whose whole job is
/// being right about the current moment, so nothing here may read the clock.
/// </summary>
public class NextClassTests
{
    /// <summary>
    /// Create a DateTime with explicit timezone (Manila/Asia timezone for testing).
    /// 2026-08-03 is a Monday; 2026-08-09 the Sunday that closes that week.
    /// </summary>
    private DateTime Date(string iso, int hour, int minute = 0)
    {
        var parts = iso.Split('-');
        var (year, month, day) = (int.Parse(parts[0]), int.Parse(parts[1]), int.Parse(parts[2]));
        // Create in UTC then we'll handle timezone conversion if needed
        return new DateTime(year, month, day, hour, minute, 0, DateTimeKind.Utc);
    }

    private ClassSession Session(string code, Weekday day, int start, int end)
    {
        return new ClassSession
        {
            SubjectCode = code,
            Description = "Test Subject",
            Faculty = "SANTOS, JUAN",
            Day = day,
            Start = start,
            End = end
        };
    }

    private List<ClassSession> Week => new()
    {
        Session("COMP 20073", Weekday.Monday, 8 * 60, 10 * 60),
        Session("GEED 005", Weekday.Monday, 14 * 60, 16 * 60),
        Session("COMP 20073", Weekday.Friday, 13 * 60 + 30, 16 * 60 + 30),
    };

    [Fact]
    public void TestBetweenClassesPicksTheNextOneNotThePast()
    {
        var upcoming = NextClass.Next(Week, Date("2026-08-03", 11));

        Assert.NotNull(upcoming);
        Assert.Equal("GEED 005", upcoming.Session.SubjectCode);
        Assert.False(upcoming.IsNow);
        Assert.Equal(Date("2026-08-03", 14), upcoming.Start);
    }

    /// <summary>
    /// A class already running is what you want to see, not the one after it.
    /// </summary>
    [Fact]
    public void TestDuringAClassReportsItAsInSession()
    {
        var upcoming = NextClass.Next(Week, Date("2026-08-03", 9));

        Assert.NotNull(upcoming);
        Assert.Equal("COMP 20073", upcoming.Session.SubjectCode);
        Assert.True(upcoming.IsNow);
    }

    /// <summary>
    /// The moment a class ends it stops being the answer.
    /// </summary>
    [Fact]
    public void TestAClassThatJustEndedIsNotTheNextOne()
    {
        var upcoming = NextClass.Next(Week, Date("2026-08-03", 10));

        Assert.NotNull(upcoming);
        Assert.Equal("GEED 005", upcoming.Session.SubjectCode);
    }

    /// <summary>
    /// Sunday night must find Monday's first class rather than reporting that
    /// the week is over — the schedule repeats, so there is always a next one.
    /// </summary>
    [Fact]
    public void TestAfterTheLastClassOfTheWeekWrapsIntoTheNext()
    {
        var upcoming = NextClass.Next(Week, Date("2026-08-09", 20));

        Assert.NotNull(upcoming);
        Assert.Equal("COMP 20073", upcoming.Session.SubjectCode);
        Assert.Equal(Weekday.Monday, upcoming.Session.Day);
        Assert.Equal(Date("2026-08-10", 8), upcoming.Start);
    }

    [Fact]
    public void TestVacantMeetingsAreSkipped()
    {
        var vacant = Week[1].Id; // Monday's GEED 005
        var upcoming = NextClass.Next(
            Week,
            Date("2026-08-03", 11),
            (s, _) => s.Id == vacant
        );

        Assert.NotNull(upcoming);
        Assert.Equal("COMP 20073", upcoming.Session.SubjectCode);
        Assert.Equal(Weekday.Friday, upcoming.Session.Day);
    }

    /// <summary>
    /// Skipping is per meeting, not per subject: COMP 20073 meets twice, and
    /// marking Monday vacant must leave Friday alone.
    /// </summary>
    [Fact]
    public void TestSkippingOneMeetingLeavesTheSubjectsOtherMeeting()
    {
        var mondayComp = Week[0].Id;
        var upcoming = NextClass.Next(
            Week,
            Date("2026-08-03", 7),
            (s, _) => s.Id == mondayComp
        );

        Assert.NotNull(upcoming);
        Assert.Equal("GEED 005", upcoming.Session.SubjectCode);
    }

    /// <summary>
    /// Per-occurrence vacancy: a class vacant only this week is skipped now
    /// but must still surface as next week's candidate — the reason isVacant
    /// takes the occurrence date rather than a flat set of ids.
    /// </summary>
    [Fact]
    public void TestThisWeekOnlyVacancyStillSurfacesNextWeek()
    {
        var only = new[] { Session("COMP 20073", Weekday.Monday, 8 * 60, 10 * 60) };
        var thisMonday = Date("2026-08-03", 7);
        var nextMonday = Date("2026-08-10", 8);

        var upcoming = NextClass.Next(
            only,
            thisMonday,
            (_, occurrence) => occurrence < nextMonday
        );

        // This week's Monday is vacant, so the answer is next week's occurrence.
        Assert.NotNull(upcoming);
        Assert.Equal("COMP 20073", upcoming.Session.SubjectCode);
        Assert.Equal(nextMonday, upcoming.Start);
    }

    [Fact]
    public void TestNoSessionsMeansNoAnswerRatherThanACrash()
    {
        var result = NextClass.Next(new List<ClassSession>(), Date("2026-08-03", 11));
        Assert.Null(result);
    }

    /// <summary>
    /// Every meeting marked vacant is the same as having none.
    /// </summary>
    [Fact]
    public void TestSkippingEverythingReturnsNil()
    {
        var all = new HashSet<string>(Week.Select(s => s.Id));
        var result = NextClass.Next(
            Week,
            Date("2026-08-03", 7),
            (s, _) => all.Contains(s.Id)
        );
        Assert.Null(result);
    }

    [Fact]
    public void TestMinutesAwayCountsDownInWholeMinutes()
    {
        var now = Date("2026-08-03", 13, 35);
        var upcoming = NextClass.Next(Week, now);

        Assert.NotNull(upcoming);
        Assert.Equal(25, upcoming.MinutesAway(now));
    }

    /// <summary>
    /// Once it's started the countdown is zero, not negative.
    /// </summary>
    [Fact]
    public void TestMinutesAwayNeverGoesNegative()
    {
        var now = Date("2026-08-03", 9);
        var upcoming = NextClass.Next(Week, now);

        Assert.NotNull(upcoming);
        Assert.Equal(0, upcoming.MinutesAway(now));
    }

    // MARK: Countdown phrasing (shared by the banner and the menu bar)

    [Fact]
    public void TestCountdownReadsInSessionWhileAClassRuns()
    {
        var now = Date("2026-08-03", 9);
        var upcoming = NextClass.Next(Week, now);

        Assert.NotNull(upcoming);
        var phrase = upcoming.Countdown(now);
        Assert.Equal("in session until 10AM", phrase);
    }

    [Fact]
    public void TestCountdownUnderAnHourIsMinutes()
    {
        var now = Date("2026-08-03", 13, 35);
        var upcoming = NextClass.Next(Week, now);

        Assert.NotNull(upcoming);
        var phrase = upcoming.Countdown(now);
        Assert.Equal("in 25 min", phrase);
    }

    [Fact]
    public void TestCountdownSameDayButOverAnHourIsAClockTime()
    {
        var now = Date("2026-08-03", 11);
        var upcoming = NextClass.Next(Week, now);

        Assert.NotNull(upcoming);
        var phrase = upcoming.Countdown(now);
        Assert.Equal("at 2PM", phrase);
    }

    [Fact]
    public void TestCountdownOnAnotherDayCarriesTheDay()
    {
        var now = Date("2026-08-03", 17);
        var upcoming = NextClass.Next(Week, now);

        Assert.NotNull(upcoming);
        var phrase = upcoming.Countdown(now);
        Assert.Equal("FRI 1:30PM", phrase);
    }
}
