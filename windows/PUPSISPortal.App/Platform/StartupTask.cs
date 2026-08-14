using Microsoft.Win32;

namespace PUPSISPortal.App.Platform;

/// <summary>
/// "Start with Windows", via the per-user Run registry key. The app is
/// unpackaged (<c>WindowsPackageType=None</c> in the csproj), so the MSIX-only
/// <c>Windows.ApplicationModel.StartupTask</c> API isn't available — this is
/// the same mechanism every unpackaged Win32 app uses, and needs no admin
/// rights (HKCU, not HKLM).
/// </summary>
public static class StartupTask
{
    private const string KeyPath = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string ValueName = "PUPSISPortal";

    public static bool IsEnabled
    {
        get
        {
            using var key = Registry.CurrentUser.OpenSubKey(KeyPath, writable: false);
            return key?.GetValue(ValueName) != null;
        }
    }

    public static void SetEnabled(bool enabled)
    {
        using var key = Registry.CurrentUser.CreateSubKey(KeyPath, writable: true);
        if (enabled)
            key.SetValue(ValueName, $"\"{Environment.ProcessPath}\"");
        else
            key.DeleteValue(ValueName, throwOnMissingValue: false);
    }
}
