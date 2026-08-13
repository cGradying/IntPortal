namespace PUPSISPortal.Core;

/// <summary>
/// On-disk cache of the scraped grades, so the Grades page renders before the
/// network answers — the same treatment ScheduleStore gives the schedule, and
/// for the same reason.
///
/// The student's own grades: LocalAppData, directory with owner-only ACL,
/// cleared on sign-out. Uses the shared JsonStore so the JSON layer is testable
/// on non-Windows platforms.
/// </summary>
public static class GradesStore
{
    private const string CurrentFileName = "grades.json";
    private const string HistoryFileName = "grades-history.json";
    private static string? s_testDirectory = null;

    /// <summary>
    /// For testing: override the cache directory. Pass null to use the default.
    /// </summary>
    public static void SetTestDirectory(string? directory)
    {
        s_testDirectory = directory;
    }

    /// <summary>
    /// Save the current term's grade report.
    /// Silently fails if serialization or I/O fails — cache write failures
    /// are not errors worth surfacing to the UI.
    /// </summary>
    public static void Save(GradeReport report)
    {
        JsonStore.Save(report, CurrentFileName, s_testDirectory);
    }

    /// <summary>
    /// Save the full history of grade reports (all scraped terms).
    /// </summary>
    public static void SaveHistory(List<GradeReport> reports)
    {
        JsonStore.Save(reports, HistoryFileName, s_testDirectory);
    }

    /// <summary>
    /// Load the current term's grade report.
    /// Returns null if the file doesn't exist, can't be read, or fails to deserialize.
    /// A missing, unreadable, or stale-format file is not an error worth surfacing —
    /// one refresh rebuilds it.
    /// </summary>
    public static GradeReport? Load()
    {
        return JsonStore.Load<GradeReport>(CurrentFileName, s_testDirectory);
    }

    /// <summary>
    /// Load the full history of grade reports.
    /// Returns an empty list if the file doesn't exist, can't be read, or fails to deserialize.
    /// </summary>
    public static List<GradeReport> LoadHistory()
    {
        return JsonStore.Load<List<GradeReport>>(HistoryFileName, s_testDirectory) ?? new List<GradeReport>();
    }

    /// <summary>
    /// Clears **both** the current-term cache and the history — sign-out has to
    /// take all of the student's grades off disk, not just the visible one.
    /// </summary>
    public static void Delete()
    {
        JsonStore.Delete(CurrentFileName, s_testDirectory);
        JsonStore.Delete(HistoryFileName, s_testDirectory);
    }

    /// <summary>
    /// Fold one term's snapshot into the history: replace any existing entry for
    /// the same term, keep the rest, and return it sorted oldest-first so the
    /// trend never depends on the order terms were scraped in.
    /// </summary>
    public static List<GradeReport> Merged(GradeReport report, List<GradeReport> history)
    {
        var out_list = history
            .Where(r => r.TermLabel != report.TermLabel)
            .ToList();
        out_list.Add(report);
        return out_list.OrderBy(r => r.TermOrder).ToList();
    }
}
