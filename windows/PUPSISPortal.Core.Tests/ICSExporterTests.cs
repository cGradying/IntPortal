namespace PUPSISPortal.Core.Tests;

/// <summary>
/// The .ics builder. Pure string output, so it's checked here rather than by
/// importing into a live calendar. Fake subjects — never a real schedule.
/// </summary>
public class ICSExporterTests
{
    // 2026-08-03 is a Monday.
    private static readonly DateTime WeekStart = new DateTime(2026, 8, 3, 0, 0, 0, DateTimeKind.Utc);
    private static readonly DateTime TermEnd = new DateTime(2026, 8, 31, 0, 0, 0, DateTimeKind.Utc);
    private static readonly DateTime Now = new DateTime(2026, 8, 1, 0, 0, 0, DateTimeKind.Utc);

    private static ClassSession Session(string code, Weekday day, int start, int end,
        string description = "Test Subject", string faculty = "SANTOS, JUAN")
    {
        return new ClassSession
        {
            SubjectCode = code,
            Description = description,
            Faculty = faculty,
            Day = day,
            Start = start,
            End = end,
        };
    }

    private static string Ics(List<ClassSession> sessions,
        Func<ClassSession, SessionStatus>? status = null)
    {
        return ICSExporter.Ics(sessions, WeekStart, TermEnd, status, Now);
    }

    private static int EventCount(string text)
    {
        return text.Split("BEGIN:VEVENT").Length - 1;
    }

    // MARK: Structure

    [Fact]
    public void TestWrapsEventsInACalendar()
    {
        var text = Ics(new List<ClassSession> { Session("MATH", Weekday.Monday, 8 * 60, 10 * 60) });
        Assert.StartsWith("BEGIN:VCALENDAR", text);
        Assert.Contains("VERSION:2.0", text);
        Assert.Contains("END:VCALENDAR", text);
        Assert.EndsWith("\r\n", text);
        Assert.Equal(1, EventCount(text));
    }

    [Fact]
    public void TestOneEventPerSession()
    {
        var text = Ics(new List<ClassSession>
        {
            Session("MATH", Weekday.Monday, 8 * 60, 10 * 60),
            Session("PHYS", Weekday.Thursday, 13 * 60, 15 * 60),
        });
        Assert.Equal(2, EventCount(text));
    }

    /// <summary>
    /// Weekly repeat, ending on the term-end day, on the class's own weekday.
    /// </summary>
    [Fact]
    public void TestWeeklyRuleWithByDayAndUntil()
    {
        var text = Ics(new List<ClassSession> { Session("PHYS", Weekday.Thursday, 13 * 60, 15 * 60) });
        Assert.Contains("RRULE:FREQ=WEEKLY;UNTIL=20260831T235959;BYDAY=TH", text);
        // First occurrence is Thursday of the given week (Aug 6) at 1PM.
        Assert.Contains("DTSTART:20260806T130000", text);
        Assert.Contains("DTEND:20260806T150000", text);
    }

    [Fact]
    public void TestEveryWeekdayMapsToItsByDayCode()
    {
        var pairs = new (Weekday, string)[]
        {
            (Weekday.Monday, "MO"), (Weekday.Tuesday, "TU"), (Weekday.Wednesday, "WE"),
            (Weekday.Thursday, "TH"), (Weekday.Friday, "FR"), (Weekday.Saturday, "SA"),
            (Weekday.Sunday, "SU"),
        };

        foreach (var (day, code) in pairs)
        {
            var text = Ics(new List<ClassSession> { Session("X", day, 9 * 60, 10 * 60) });
            Assert.Contains($"BYDAY={code}", text);
        }
    }

    // MARK: Status

    [Fact]
    public void TestVacantClassesAreSkipped()
    {
        var vacant = Session("SKIP", Weekday.Monday, 8 * 60, 10 * 60);
        var kept = Session("KEEP", Weekday.Tuesday, 8 * 60, 10 * 60);
        var text = Ics(new List<ClassSession> { vacant, kept },
            s => s.SubjectCode == "SKIP" ? SessionStatus.Vacant : SessionStatus.Regular);

        Assert.Equal(1, EventCount(text));
        Assert.DoesNotContain("SUMMARY:SKIP", text);
        Assert.Contains("SUMMARY:KEEP", text);
    }

    [Fact]
    public void TestOnlineClassesAreMarked()
    {
        var text = Ics(new List<ClassSession> { Session("CS", Weekday.Monday, 8 * 60, 10 * 60) },
            _ => SessionStatus.Online);

        Assert.Contains("SUMMARY:CS (Online)", text);
        Assert.Contains("LOCATION:Online", text);
    }

    [Fact]
    public void TestInPersonClassesHaveNoLocation()
    {
        var text = Ics(new List<ClassSession> { Session("CS", Weekday.Monday, 8 * 60, 10 * 60) });
        Assert.DoesNotContain("LOCATION:", text);
    }

    // MARK: Escaping

    [Fact]
    public void TestSpecialCharactersAreEscaped()
    {
        var text = Ics(new List<ClassSession>
        {
            Session("ENG", Weekday.Monday, 8 * 60, 10 * 60, "Reading, Writing; Speaking", "")
        });

        Assert.Contains("DESCRIPTION:Reading\\, Writing\\; Speaking", text);
    }

    [Fact]
    public void TestFacultyJoinedIntoDescription()
    {
        var text = Ics(new List<ClassSession>
        {
            Session("ENG", Weekday.Monday, 8 * 60, 10 * 60, "English", "REYES\\, MARIA")
        });

        // Backslash and comma both escaped, newline between description and faculty.
        Assert.Contains("DESCRIPTION:English\\nREYES\\\\\\, MARIA", text);
    }
}
