using System.Text.Json;

namespace PUPSISPortal.Core.Tests;

/// <summary>
/// The pure Google event builder — summary/RRULE/tag/skip rules — without the
/// network. The REST calls themselves are verified by running the app.
/// </summary>
public class GoogleCalendarClientTests
{
    private static readonly DateTime WeekStart = new DateTime(2026, 8, 3, 0, 0, 0, DateTimeKind.Utc);
    private static readonly DateTime TermEnd = new DateTime(2026, 8, 31, 0, 0, 0, DateTimeKind.Utc);

    private static ClassSession Session(string code, Weekday day, int start, int end)
    {
        return new ClassSession
        {
            SubjectCode = code,
            Description = "Desc",
            Faculty = "SANTOS, JUAN",
            Day = day,
            Start = start,
            End = end,
        };
    }

    private static GoogleEvent? Event(ClassSession session, SessionStatus status)
    {
        return GoogleCalendarClient.Event(session, status, WeekStart, TermEnd, TimeZoneInfo.Utc);
    }

    [Fact]
    public void TestRegularClassBuildsATaggedRecurringEvent()
    {
        var e = Event(Session("PHYS", Weekday.Thursday, 13 * 60, 15 * 60), SessionStatus.Regular);
        Assert.NotNull(e);
        Assert.Equal("PHYS", e.Summary);
        Assert.Null(e.Location);
        Assert.Contains("2026-08-06", e.Start.DateTime);
        Assert.Contains("13:00", e.Start.DateTime);
        Assert.Contains("2026-08-06", e.End.DateTime);
        Assert.Contains("15:00", e.End.DateTime);
        Assert.Contains("RRULE:FREQ=WEEKLY;UNTIL=20260831T235959Z;BYDAY=TH", e.Recurrence);
        Assert.Equal(GoogleCalendarClient.TagValue, e.ExtendedProperties.Private[GoogleCalendarClient.TagKey]);
    }

    [Fact]
    public void TestVacantClassIsSkipped()
    {
        var e = Event(Session("SKIP", Weekday.Monday, 8 * 60, 10 * 60), SessionStatus.Vacant);
        Assert.Null(e);
    }

    [Fact]
    public void TestOnlineClassIsMarked()
    {
        var e = Event(Session("CS", Weekday.Monday, 8 * 60, 10 * 60), SessionStatus.Online);
        Assert.NotNull(e);
        Assert.Equal("CS (Online)", e.Summary);
        Assert.Equal("Online", e.Location);
    }

    /// <summary>
    /// The exported body must be valid JSON with the tag nested under
    /// extendedProperties.private, which is how a re-export finds its own events.
    /// </summary>
    [Fact]
    public void TestEncodesToJSONWithPrivateTag()
    {
        var e = Event(Session("MATH", Weekday.Monday, 8 * 60, 10 * 60), SessionStatus.Regular);
        Assert.NotNull(e);

        var json = JsonSerializer.Serialize(e);
        var doc = JsonDocument.Parse(json);
        var root = doc.RootElement;

        var ext = root.GetProperty("extendedProperties");
        var priv = ext.GetProperty("private");
        Assert.Equal("1", priv.GetProperty("pupsisportal").GetString());
    }
}
