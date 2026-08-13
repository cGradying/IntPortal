namespace PUPSISPortal.Core.Tests;

/// <summary>
/// Preferences persistence and defaults. Each test gets its own temp directory
/// to avoid interfering with the real settings.
/// </summary>
public class PreferencesTests
{
    private string _testDirectory = null!;

    public PreferencesTests()
    {
        _testDirectory = Path.Combine(Path.GetTempPath(), $"PreferencesTests-{Guid.NewGuid()}");
        Directory.CreateDirectory(_testDirectory);
    }

    private void Cleanup()
    {
        if (Directory.Exists(_testDirectory))
        {
            Directory.Delete(_testDirectory, true);
        }
    }

    [Fact]
    public void TestDefaultsToExpectedValues()
    {
        var prefs = new Preferences(_testDirectory);
        Assert.Equal(ThemeChoice.Auto, prefs.Theme);
        Assert.Empty(prefs.SubjectColors);
        Assert.Empty(prefs.TermStatuses);
    }

    [Fact]
    public void TestThemeSurvivesRelaunch()
    {
        var prefs = new Preferences(_testDirectory);
        prefs.Theme = ThemeChoice.PupMaroon;

        var reloaded = new Preferences(_testDirectory);
        Assert.Equal(ThemeChoice.PupMaroon, reloaded.Theme);

        Cleanup();
    }

    [Fact]
    public void TestCustomColorSurvivesRelaunch()
    {
        var prefs = new Preferences(_testDirectory);
        prefs.SetSubjectColor("COMP 20073", "#FF0000");

        var reloaded = new Preferences(_testDirectory);
        Assert.True(reloaded.HasCustomSubjectColor("COMP 20073"));
        Assert.Equal("#FF0000", reloaded.ColorForSubject("COMP 20073"));

        Cleanup();
    }

    [Fact]
    public void TestResetFallsBackToDefault()
    {
        var prefs = new Preferences(_testDirectory);
        prefs.SetSubjectColor("COMP 20073", "#FF0000");
        prefs.ResetSubjectColor("COMP 20073");

        Assert.False(prefs.HasCustomSubjectColor("COMP 20073"));

        Cleanup();
    }

    // MARK: Online strip colour (per subject)

    [Fact]
    public void TestCustomStripColorWinsAndSurvivesRelaunch()
    {
        var prefs = new Preferences(_testDirectory);
        prefs.SetStripColor("COMP 20073", "#0080FF");

        var reloaded = new Preferences(_testDirectory);
        Assert.True(reloaded.HasCustomStripColor("COMP 20073"));
        Assert.Equal("#0080FF", reloaded.StripColorForSubject("COMP 20073"));

        Cleanup();
    }

    [Fact]
    public void TestResettingAStripColorRemovesIt()
    {
        var prefs = new Preferences(_testDirectory);
        prefs.SetStripColor("COMP 20073", "#FF0000");
        prefs.ResetStripColor("COMP 20073");

        Assert.False(prefs.HasCustomStripColor("COMP 20073"));

        Cleanup();
    }

    /// <summary>
    /// One subject's strip must not leak onto another, and must not touch its
    /// fill colour — separate namespaces.
    /// </summary>
    [Fact]
    public void TestStripColorIsScopedAndSeparateFromTheFill()
    {
        var prefs = new Preferences(_testDirectory);

        prefs.SetStripColor("COMP 20073", "#FF0000");

        Assert.True(prefs.HasCustomStripColor("COMP 20073"));
        Assert.False(prefs.HasCustomSubjectColor("COMP 20073"));

        Cleanup();
    }

    // MARK: Session Status

    private static readonly ClassSession Tuesday = new()
    {
        SubjectCode = "COMP 20073",
        Description = "Data Structures",
        Faculty = "SANTOS, JUAN",
        Day = Weekday.Tuesday,
        Start = 14 * 60,
        End = 16 * 60,
    };

    private static readonly ClassSession Friday = new()
    {
        SubjectCode = "COMP 20073",
        Description = "Data Structures",
        Faculty = "SANTOS, JUAN",
        Day = Weekday.Friday,
        Start = 13 * 60 + 30,
        End = 16 * 60 + 30,
    };

    private static readonly DateTime Week1 = new DateTime(2025, 1, 6); // a Monday
    private static readonly DateTime Week2 = new DateTime(2025, 1, 13); // the next Monday

    [Fact]
    public void TestStatusDefaultsToRegular()
    {
        var prefs = new Preferences(_testDirectory);
        Assert.Equal(SessionStatus.Regular, prefs.Status(Tuesday.Id, Week1));

        Cleanup();
    }

    [Fact]
    public void TestAWeekStatusSurvivesRelaunch()
    {
        var prefs = new Preferences(_testDirectory);
        prefs.SetStatus(Tuesday.Id, Week1, SessionStatus.Online);

        var reloaded = new Preferences(_testDirectory);
        Assert.Equal(SessionStatus.Online, reloaded.Status(Tuesday.Id, Week1));

        Cleanup();
    }

    /// <summary>
    /// The whole point of the fix: a status set in one week must not appear in
    /// another. Keying by session alone was the bug.
    /// </summary>
    [Fact]
    public void TestAWeekStatusDoesNotLeakIntoOtherWeeks()
    {
        var prefs = new Preferences(_testDirectory);
        prefs.SetStatus(Tuesday.Id, Week1, SessionStatus.Online);

        Assert.Equal(SessionStatus.Online, prefs.Status(Tuesday.Id, Week1));
        Assert.Equal(SessionStatus.Regular, prefs.Status(Tuesday.Id, Week2));

        Cleanup();
    }

    /// <summary>
    /// The term default applies to every week that has no exception of its own.
    /// </summary>
    [Fact]
    public void TestTermStatusAppliesToEveryWeekWithoutAnException()
    {
        var prefs = new Preferences(_testDirectory);
        prefs.SetTermStatus(Tuesday.Id, SessionStatus.Online);

        Assert.Equal(SessionStatus.Online, prefs.Status(Tuesday.Id, Week1));
        Assert.Equal(SessionStatus.Online, prefs.Status(Tuesday.Id, Week2));

        Cleanup();
    }

    /// <summary>
    /// A one-week exception wins over the term default, and only for its week.
    /// </summary>
    [Fact]
    public void TestAWeekExceptionOverridesTheTermDefault()
    {
        var prefs = new Preferences(_testDirectory);
        prefs.SetTermStatus(Tuesday.Id, SessionStatus.Online);
        prefs.SetStatus(Tuesday.Id, Week1, SessionStatus.Vacant);

        Assert.Equal(SessionStatus.Vacant, prefs.Status(Tuesday.Id, Week1));
        Assert.Equal(SessionStatus.Online, prefs.Status(Tuesday.Id, Week2));

        Cleanup();
    }

    /// <summary>
    /// A week status equal to the term default isn't a real exception, so it
    /// shouldn't be stored.
    /// </summary>
    [Fact]
    public void TestAWeekStatusMatchingTheTermDefaultStoresNothing()
    {
        var prefs = new Preferences(_testDirectory);
        prefs.SetTermStatus(Tuesday.Id, SessionStatus.Online);
        prefs.SetStatus(Tuesday.Id, Week1, SessionStatus.Online);

        Assert.Empty(prefs.OccurrenceStatuses);

        Cleanup();
    }

    /// <summary>
    /// Status is per meeting, not per subject — same course, two days, one of
    /// them online. Keying this by subject code would be the obvious bug.
    /// </summary>
    [Fact]
    public void TestStatusIsScopedToOneMeetingNotTheWholeSubject()
    {
        var prefs = new Preferences(_testDirectory);
        prefs.SetStatus(Tuesday.Id, Week1, SessionStatus.Vacant);

        Assert.Equal(SessionStatus.Vacant, prefs.Status(Tuesday.Id, Week1));
        Assert.Equal(SessionStatus.Regular, prefs.Status(Friday.Id, Week1));

        Cleanup();
    }

    /// <summary>
    /// Reminders and next-class honour term-vacant only — a one-week vacancy
    /// can't be dropped from a weekly-recurring trigger.
    /// </summary>
    [Fact]
    public void TestVacantSessionIDsReflectTermVacantNotAOneWeekVacant()
    {
        var prefs = new Preferences(_testDirectory);

        prefs.SetStatus(Tuesday.Id, Week1, SessionStatus.Vacant);
        Assert.Empty(prefs.VacantSessionIds);

        prefs.SetTermStatus(Tuesday.Id, SessionStatus.Vacant);
        Assert.Contains(Tuesday.Id, prefs.VacantSessionIds);

        Cleanup();
    }

    [Fact]
    public void TestTermEndDefaultsToAboutASemesterOut()
    {
        var prefs = new Preferences(_testDirectory);
        var end = prefs.TermEndDate;

        // Should be roughly 4 months out
        var monthDiff = (end.Year - DateTime.Now.Year) * 12 + (end.Month - DateTime.Now.Month);
        Assert.True(monthDiff >= 3 && monthDiff <= 5);

        Cleanup();
    }

    [Fact]
    public void TestTermEndSurvivesRelaunch()
    {
        var chosen = new DateTime(2026, 12, 15);
        var prefs = new Preferences(_testDirectory);
        prefs.TermEndDate = chosen;

        var reloaded = new Preferences(_testDirectory);
        Assert.Equal(chosen, reloaded.TermEndDate);

        Cleanup();
    }

    /// <summary>
    /// Event colours are keyed by run, so recolouring one day of a connected run
    /// recolours all of it rather than breaking the bar in half.
    /// </summary>
    [Fact]
    public void TestEventColoursAreKeyedByRunAndSurviveRelaunch()
    {
        var run = "event-Study-840-960";
        var prefs = new Preferences(_testDirectory);
        prefs.SetEventColor(run, "#00FF00");

        var reloaded = new Preferences(_testDirectory);
        Assert.True(reloaded.HasCustomEventColor(run));
        Assert.Equal("#00FF00", reloaded.ColorForEvent(run));

        Cleanup();
    }

    [Fact]
    public void TestResettingAnEventColourFallsBackToDefault()
    {
        var prefs = new Preferences(_testDirectory);
        var run = "event-Study-840-960";

        prefs.SetEventColor(run, "#FF0000");
        prefs.ResetEventColor(run);

        Assert.False(prefs.HasCustomEventColor(run));

        Cleanup();
    }

    /// <summary>
    /// Subject colours and event colours are separate namespaces — a class and
    /// an event with the same name must not share a swatch.
    /// </summary>
    [Fact]
    public void TestEventColoursDoNotLeakIntoSubjectColours()
    {
        var prefs = new Preferences(_testDirectory);
        prefs.SetEventColor("COMP 20073", "#FF0000");

        Assert.False(prefs.HasCustomSubjectColor("COMP 20073"));

        Cleanup();
    }

    /// <summary>
    /// One subject's override must not leak onto another.
    /// </summary>
    [Fact]
    public void TestOverridesAreScopedToOneSubject()
    {
        var prefs = new Preferences(_testDirectory);
        prefs.SetSubjectColor("COMP 20073", "#FF0000");

        Assert.False(prefs.HasCustomSubjectColor("GEED 005"));

        Cleanup();
    }
}
