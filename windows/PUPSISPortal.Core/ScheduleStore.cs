namespace PUPSISPortal.Core;

/// <summary>
/// On-disk cache of the scraped schedule, so a launch can render before the
/// network answers — and keep rendering when it never does.
///
/// The student's own class schedule: LocalAppData, directory with owner-only ACL,
/// cleared on sign-out.
/// </summary>
public static class ScheduleStore
{
    private const string FileName = "schedule.json";
    private static string? s_testDirectory = null;

    /// <summary>
    /// For testing: override the cache directory. Pass null to use the default.
    /// </summary>
    public static void SetTestDirectory(string? directory)
    {
        s_testDirectory = directory;
    }

    /// <summary>
    /// Save `sessions` and `lastUpdated` to the cache.
    /// Silently fails if serialization or I/O fails — no need to surface
    /// cache write failures to the UI.
    /// </summary>
    public static void Save(List<ClassSession> sessions, DateTime? lastUpdated = null)
    {
        var payload = new CachedSchedule
        {
            LastUpdated = lastUpdated ?? DateTime.UtcNow,
            Sessions = sessions
        };
        JsonStore.Save(payload, FileName, s_testDirectory);
    }

    /// <summary>
    /// Load the cached schedule from disk.
    /// Returns null if the file doesn't exist, can't be read, or fails to deserialize.
    /// A missing, unreadable, or stale-format file is not an error worth surfacing —
    /// one refresh rebuilds it.
    /// </summary>
    public static CachedSchedule? Load()
    {
        return JsonStore.Load<CachedSchedule>(FileName, s_testDirectory);
    }

    /// <summary>
    /// Delete the cache file from disk.
    /// Silently fails if the file doesn't exist or can't be deleted.
    /// </summary>
    public static void Delete()
    {
        JsonStore.Delete(FileName, s_testDirectory);
    }
}
