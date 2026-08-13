using System.Text.Json;
using System.Security.AccessControl;
using System.Security.Principal;

namespace PUPSISPortal.Core;

/// <summary>
/// On-disk cache of the scraped grades, so the Grades page renders before the
/// network answers — the same treatment ScheduleStore gives the schedule, and
/// for the same reason.
///
/// The student's own grades: AppData/Local, directory with owner-only ACL,
/// cleared on sign-out.
/// </summary>
[System.Runtime.Versioning.SupportedOSPlatform("windows")]
public static class GradesStore
{
    private static readonly string Directory;
    public static readonly string FileUrl;
    /// <summary>
    /// Past terms, backfilled from the grades page's SY/Semester dropdowns.
    /// Same treatment as the current term — the student's own data, owner-only ACL.
    /// </summary>
    public static readonly string HistoryUrl;

    static GradesStore()
    {
        var appData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        Directory = Path.Combine(appData, "PUPSISPortal");
        FileUrl = Path.Combine(Directory, "grades.json");
        HistoryUrl = Path.Combine(Directory, "grades-history.json");
    }

    public static void Save(GradeReport report, string? path = null)
    {
        Write(report, path ?? FileUrl);
    }

    public static void SaveHistory(List<GradeReport> reports, string? path = null)
    {
        Write(reports, path ?? HistoryUrl);
    }

    private static void Write<T>(T value, string path)
    {
        try
        {
            var json = JsonSerializer.Serialize(value, new JsonSerializerOptions { WriteIndented = false });
            var data = System.Text.Encoding.UTF8.GetBytes(json);

            // Ensure directory exists
            var dirPath = Path.GetDirectoryName(path);
            if (dirPath != null && !System.IO.Directory.Exists(dirPath))
            {
                System.IO.Directory.CreateDirectory(dirPath);
                // Set owner-only ACL (replaces inherited permissions)
                SetOwnerOnlyAcl(dirPath);
            }

            // Write atomically by writing to temp file first, then moving
            var tempPath = path + ".tmp";
            System.IO.File.WriteAllBytes(tempPath, data);
            if (System.IO.File.Exists(path))
                System.IO.File.Delete(path);
            System.IO.File.Move(tempPath, path);

            // Set owner-only ACL on the file
            SetOwnerOnlyAcl(path);
        }
        catch
        {
            // Silent fail: no usable cache is not an error worth surfacing
        }
    }

    /// <summary>
    /// Sets NTFS ACL to owner-only (the Windows equivalent of chmod 0600/0700).
    /// Removes all inherited permissions and grants full control only to the current user.
    /// </summary>
    private static void SetOwnerOnlyAcl(string path)
    {
        try
        {
            var fileInfo = new FileInfo(path);
            if (!fileInfo.Exists)
            {
                var dirInfo = new DirectoryInfo(path);
                if (!dirInfo.Exists)
                    return;

                var dirSecurity = dirInfo.GetAccessControl();
                dirSecurity.SetAccessRuleProtection(true, false);
                // Clear all existing rules
                foreach (var rule in dirSecurity.GetAccessRules(true, true, typeof(SecurityIdentifier)))
                {
                    if (rule is FileSystemAccessRule fsRule)
                        dirSecurity.RemoveAccessRule(fsRule);
                }

                var currentUser = WindowsIdentity.GetCurrent().User;
                if (currentUser != null)
                {
                    dirSecurity.AddAccessRule(new FileSystemAccessRule(
                        currentUser,
                        FileSystemRights.FullControl,
                        InheritanceFlags.ContainerInherit | InheritanceFlags.ObjectInherit,
                        PropagationFlags.None,
                        AccessControlType.Allow));
                }

                dirInfo.SetAccessControl(dirSecurity);
            }
            else
            {
                var fileSecurity = fileInfo.GetAccessControl();
                fileSecurity.SetAccessRuleProtection(true, false);
                // Clear all existing rules
                foreach (var rule in fileSecurity.GetAccessRules(true, true, typeof(SecurityIdentifier)))
                {
                    if (rule is FileSystemAccessRule fsRule)
                        fileSecurity.RemoveAccessRule(fsRule);
                }

                var currentUser = WindowsIdentity.GetCurrent().User;
                if (currentUser != null)
                {
                    fileSecurity.AddAccessRule(new FileSystemAccessRule(
                        currentUser,
                        FileSystemRights.FullControl,
                        InheritanceFlags.None,
                        PropagationFlags.None,
                        AccessControlType.Allow));
                }

                fileInfo.SetAccessControl(fileSecurity);
            }
        }
        catch
        {
            // Silent fail: ACL setting is best-effort, not critical
        }
    }

    /// <summary>
    /// null for "no usable cache" — a missing, unreadable, or stale-format file
    /// is not an error worth surfacing; one refresh rebuilds it.
    /// </summary>
    public static GradeReport? Load(string? path = null)
    {
        try
        {
            var json = System.IO.File.ReadAllText(path ?? FileUrl);
            return JsonSerializer.Deserialize<GradeReport>(json);
        }
        catch
        {
            return null;
        }
    }

    public static List<GradeReport> LoadHistory(string? path = null)
    {
        try
        {
            var json = System.IO.File.ReadAllText(path ?? HistoryUrl);
            return JsonSerializer.Deserialize<List<GradeReport>>(json) ?? new List<GradeReport>();
        }
        catch
        {
            return new List<GradeReport>();
        }
    }

    /// <summary>
    /// Clears **both** the current-term cache and the history — sign-out has to
    /// take all of the student's grades off disk, not just the visible one.
    /// </summary>
    public static void Delete()
    {
        try
        {
            System.IO.File.Delete(FileUrl);
        }
        catch { }

        try
        {
            System.IO.File.Delete(HistoryUrl);
        }
        catch { }
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
