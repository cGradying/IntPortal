using Microsoft.UI.Xaml;
using Microsoft.Windows.AppNotifications;
using Microsoft.Windows.AppNotifications.Builder;
using PUPSISPortal.Core;

namespace PUPSISPortal.App.Platform;

/// <summary>
/// Class-start reminders as Windows toasts — the counterpart of the mac app's
/// UNUserNotificationCenter reminders. Same limit as mac (see the memory note):
/// this only fires while the app process is running and a timer is ticking, no
/// background/tray-only delivery. A system-tray icon (<see cref="TrayIcon"/>)
/// keeps the process alive when the window is closed, so "running" doesn't
/// strictly mean "window open".
/// </summary>
public static class ToastReminders
{
    /// Register the app's notification identity. Call once, early (before any
    /// window is shown), and <see cref="Unregister"/> on exit.
    public static void Register() => AppNotificationManager.Default.Register();

    public static void Unregister() => AppNotificationManager.Default.Unregister();

    private static void Notify(string title, string body)
    {
        var notification = new AppNotificationBuilder()
            .AddText(title)
            .AddText(body)
            .BuildNotification();
        AppNotificationManager.Default.Show(notification);
    }

    /// <summary>
    /// Ticks once a minute while the window is alive, firing one toast per class
    /// occurrence at <c>NotificationLeadMinutes</c> before it starts. Dedupes by
    /// (class id, date) so a class isn't announced twice in one day.
    /// </summary>
    public sealed class Scheduler
    {
        private readonly DispatcherTimer _timer = new() { Interval = TimeSpan.FromSeconds(30) };
        private readonly HashSet<string> _fired = new();
        private readonly Func<List<ClassSession>> _sessions;
        private readonly Preferences _prefs;

        public Scheduler(Func<List<ClassSession>> sessions, Preferences prefs)
        {
            _sessions = sessions;
            _prefs = prefs;
            _timer.Tick += (_, _) => Check();
        }

        public void Start() => _timer.Start();
        public void Stop() => _timer.Stop();

        private void Check()
        {
            if (!_prefs.NotificationsEnabled) return;

            var now = DateTime.Now;
            var lead = _prefs.NotificationLeadMinutes;
            var today = DateOnly.FromDateTime(now);
            var minutesNow = now.Hour * 60 + now.Minute;

            foreach (var session in _sessions())
            {
                if (session.Day != WeekdayExtensions.FromSystemDayOfWeek(now.DayOfWeek)) continue;

                var minutesUntil = session.Start - minutesNow;
                if (minutesUntil < 0 || minutesUntil > lead) continue;

                var key = $"{session.Id}:{today:O}";
                if (!_fired.Add(key)) continue;

                Notify(
                    $"{session.SubjectCode} in {minutesUntil} min",
                    $"{session.Description} · {ClassSession.Format(session.Start)}");
            }
        }
    }
}
