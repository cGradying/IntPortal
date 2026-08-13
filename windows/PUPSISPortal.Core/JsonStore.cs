using System.Text.Json;
using System.Security.AccessControl;
using System.Security.Principal;

namespace PUPSISPortal.Core;

/// <summary>
/// Cross-platform JSON serialization with atomic writes and owner-only ACL
/// (on Windows only). Resolves paths under %LOCALAPPDATA%\PUPSISPortal\ by default,
/// or a custom directory if provided.
///
/// The ACL code is guarded by `if (OperatingSystem.IsWindows())` so the JSON
/// layer stays testable on non-Windows platforms.
/// </summary>
public static class JsonStore
{
    private static readonly string DefaultCacheDirectory = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "PUPSISPortal"
    );

    /// <summary>
    /// Save `value` as JSON to `{directory}\{filename}`, atomically
    /// and with owner-only permissions (on Windows).
    /// Silently fails (returns false) if serialization or I/O fails — cache
    /// misses are not errors worth surfacing to the UI.
    /// </summary>
    public static bool Save<T>(T value, string filename, string? directory = null)
    {
        try
        {
            var json = JsonSerializer.Serialize(value, new JsonSerializerOptions { WriteIndented = false });
            var data = System.Text.Encoding.UTF8.GetBytes(json);

            var baseDir = directory ?? DefaultCacheDirectory;
            var path = Path.Combine(baseDir, filename);

            // Ensure directory exists
            if (!Directory.Exists(baseDir))
            {
                Directory.CreateDirectory(baseDir);
                SetOwnerOnlyAcl(baseDir);
            }

            // Write atomically: temp file first, then move
            var tempPath = path + ".tmp";
            File.WriteAllBytes(tempPath, data);
            if (File.Exists(path))
                File.Delete(path);
            File.Move(tempPath, path);

            // Set owner-only ACL on the file
            SetOwnerOnlyAcl(path);
            return true;
        }
        catch
        {
            return false;
        }
    }

    /// <summary>
    /// Load and deserialize JSON from `{directory}\{filename}`.
    /// Returns null if the file doesn't exist, can't be read, or fails to deserialize.
    /// </summary>
    public static T? Load<T>(string filename, string? directory = null)
    {
        try
        {
            var baseDir = directory ?? DefaultCacheDirectory;
            var path = Path.Combine(baseDir, filename);
            if (!File.Exists(path))
                return default;

            var json = File.ReadAllText(path);
            var options = new JsonSerializerOptions { PropertyNameCaseInsensitive = true };
            return JsonSerializer.Deserialize<T>(json, options);
        }
        catch
        {
            return default;
        }
    }

    /// <summary>
    /// Delete the file at `{directory}\{filename}`.
    /// Silently fails if the file doesn't exist or can't be deleted.
    /// </summary>
    public static bool Delete(string filename, string? directory = null)
    {
        try
        {
            var baseDir = directory ?? DefaultCacheDirectory;
            var path = Path.Combine(baseDir, filename);
            if (File.Exists(path))
                File.Delete(path);
            return true;
        }
        catch
        {
            return false;
        }
    }

    /// <summary>
    /// Sets owner-only ACL on a file or directory (Windows only).
    /// On non-Windows platforms, this is a no-op.
    /// The Windows equivalent of chmod 0600 (file) or 0700 (directory).
    /// Silently fails if ACL setting is not supported or throws.
    /// </summary>
    private static void SetOwnerOnlyAcl(string path)
    {
        if (!OperatingSystem.IsWindows())
            return;

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
}
