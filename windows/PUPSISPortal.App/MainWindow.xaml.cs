using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using PUPSISPortal.App.Platform;
using PUPSISPortal.Core;

namespace PUPSISPortal.App;

/// <summary>
/// Stage 3–5 shell: Mica ground + custom titlebar, a minimal sign-in, and the
/// week-grid calendar rendered from the ported <see cref="SisSession"/>. The
/// session is real (Core, tested on mac); the driver and UI are Windows-only.
/// Stage 8 adds the integrations flyout (.ics/Google/startup), toast reminders,
/// and the tray icon.
/// </summary>
public sealed partial class MainWindow : Window
{
    private SisSession? _session;
    private readonly Preferences _prefs = new();
    private readonly GoogleAuthWindows _google = new();
    private readonly TrayIcon _tray;
    private readonly UpdateChecker _updateChecker = new();
    private ToastReminders.Scheduler? _reminders;
    private string? _updateUrl;

    public MainWindow()
    {
        InitializeComponent();
        ExtendsContentIntoTitleBar = true;
        SetTitleBar(AppTitleBar);
        Notes.OwnerWindow = this;

        _tray = new TrayIcon(this);
        _tray.OpenRequested += () => { AppWindow.Show(); Activate(); };
        _tray.ExitRequested += () => { _tray.Dispose(); Application.Current.Exit(); };
        _tray.Show();

        // Closing the window keeps reminders/the tray alive instead of exiting —
        // "Exit" from the tray menu is the real quit.
        AppWindow.Closing += (_, args) =>
        {
            args.Cancel = true;
            AppWindow.Hide();
        };

        StartupMenuItem.IsChecked = StartupTask.IsEnabled;

        _ = InitAsync();
    }

    private async Task InitAsync()
    {
        await Web.EnsureCoreWebView2Async();
        _session = new SisSession(new WebView2SisWebView(Web), SisScriptLoader.Load());

        // Cached schedule shows immediately, even before any network.
        if (_session.Sessions.Count > 0) ShowCalendar();

        var saved = PasswordVaultCredentialStore.Load();
        if (saved is not null) await RunSignIn(saved);

        _ = CheckForUpdateAsync();
    }

    /// <summary>
    /// The update nudge — checks once at startup, independent of sign-in state.
    /// Silent on failure/no-update (<see cref="UpdateChecker.CheckAsync"/> never
    /// throws); this only ever shows the bar, never an error.
    /// </summary>
    private async Task CheckForUpdateAsync()
    {
        var current = System.Reflection.Assembly.GetExecutingAssembly().GetName().Version?.ToString() ?? "0.0.0.0";
        var update = await _updateChecker.CheckAsync(current);
        if (update is null) return;

        _updateUrl = update.Url;
        UpdateBar.Message = $"PUPSISPortal {update.Version} is out — you're on {current}.";
        UpdateBar.IsOpen = true;
    }

    private void OnViewUpdate(object sender, RoutedEventArgs e)
    {
        if (_updateUrl is null) return;
        _ = System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(_updateUrl) { UseShellExecute = true });
    }

    private async void OnSignIn(object sender, RoutedEventArgs e)
    {
        if (_session is null) return;

        var creds = new Credentials
        {
            StudentNumber = StudNo.Text.Trim(),
            BirthMonth = ToInt(BMonth.Value),
            BirthDay = ToInt(BDay.Value),
            BirthYear = ToInt(BYear.Value),
            Password = Pwd.Password,
        };
        PasswordVaultCredentialStore.Save(creds);
        await RunSignIn(creds);
    }

    private async Task RunSignIn(Credentials creds)
    {
        if (_session is null) return;

        Status.Text = "Signing in…";
        SignInButton.IsEnabled = false;
        await _session.SignInAsync(creds);
        SignInButton.IsEnabled = true;

        if (_session.Status == LoginStatus.Success || _session.Sessions.Count > 0)
        {
            ShowCalendar();
            Status.Text = _session.RefreshError ?? "";
        }
        else
        {
            Status.Text = _session.StatusMessage ?? "Sign-in failed.";
        }
    }

    private void ShowCalendar()
    {
        if (_session is null) return;
        SignInPanel.Visibility = Visibility.Collapsed;
        NavButtons.Visibility = Visibility.Visible;
        MoreButton.Visibility = Visibility.Visible;
        Calendar.Show(_session.Sessions);
        ShowScreen(Calendar);

        GoogleMenuItem.Text = _google.IsConnected ? "Disconnect Google Calendar" : "Connect Google Calendar…";

        if (_reminders is null)
        {
            _reminders = new ToastReminders.Scheduler(() => _session.Sessions, _prefs);
            _reminders.Start();
        }
    }

    // MARK: Screen switcher

    private void OnNavCalendar(object sender, RoutedEventArgs e) => ShowScreen(Calendar);
    private void OnNavNotes(object sender, RoutedEventArgs e) => ShowScreen(Notes);
    private void OnNavGrades(object sender, RoutedEventArgs e)
    {
        ShowScreen(Grades);
        if (_session is not null) _ = Grades.LoadAsync(_session);
    }

    private void ShowScreen(FrameworkElement shown)
    {
        foreach (var screen in new FrameworkElement[] { Calendar, Notes, Grades })
            screen.Visibility = screen == shown ? Visibility.Visible : Visibility.Collapsed;
    }

    // MARK: Integrations flyout

    private async void OnExportIcs(object sender, RoutedEventArgs e)
    {
        if (_session is null) return;
        var picker = new Windows.Storage.Pickers.FileSavePicker();
        picker.FileTypeChoices.Add("Calendar", new List<string> { ".ics" });
        picker.SuggestedFileName = "PUPSISPortal";
        WinRT.Interop.InitializeWithWindow.Initialize(picker, WinRT.Interop.WindowNative.GetWindowHandle(this));

        var file = await picker.PickSaveFileAsync();
        if (file is null) return;

        var weekStart = WeekdayExtensions.WeekStart(DateTime.Now);
        var ics = ICSExporter.Ics(_session.Sessions, weekStart, _prefs.TermEndDate,
            s => _prefs.Status(s.Id, weekStart));
        await Windows.Storage.FileIO.WriteTextAsync(file, ics);
        Status.Text = "Exported .ics.";
    }

    private async void OnGoogleConnect(object sender, RoutedEventArgs e)
    {
        if (_google.IsConnected)
        {
            _google.Disconnect();
            GoogleMenuItem.Text = "Connect Google Calendar…";
            return;
        }

        var box = new TextBox { Header = "Google OAuth client ID", Text = _prefs.GoogleClientId };
        var dialog = new ContentDialog
        {
            Title = "Connect Google Calendar",
            Content = box,
            PrimaryButtonText = "Connect",
            CloseButtonText = "Cancel",
            DefaultButton = ContentDialogButton.Primary,
            XamlRoot = Content.XamlRoot,
        };
        if (await dialog.ShowAsync() != ContentDialogResult.Primary) return;

        _prefs.GoogleClientId = box.Text.Trim();
        try
        {
            await _google.ConnectAsync(_prefs.GoogleClientId);
            GoogleMenuItem.Text = "Disconnect Google Calendar";
            Status.Text = "Google Calendar connected.";
        }
        catch (GoogleAuthWindows.AuthException ex)
        {
            Status.Text = ex.Message;
        }
    }

    private async void OnGoogleExport(object sender, RoutedEventArgs e)
    {
        if (_session is null) return;
        if (!_google.IsConnected) { Status.Text = "Connect your Google account first."; return; }

        var client = new GoogleCalendarClient(() => _google.ValidAccessTokenAsync(_prefs.GoogleClientId));

        var calendarId = _prefs.GoogleCalendarId;
        if (string.IsNullOrEmpty(calendarId))
        {
            List<GoogleCalendar> calendars;
            try { calendars = await client.ListCalendarsAsync(); }
            catch (GoogleCalendarClient.ClientException ex) { Status.Text = ex.Message; return; }

            var combo = new ComboBox { HorizontalAlignment = HorizontalAlignment.Stretch };
            foreach (var cal in calendars) combo.Items.Add(cal.Summary);
            if (combo.Items.Count > 0) combo.SelectedIndex = 0;

            var dialog = new ContentDialog
            {
                Title = "Which calendar?",
                Content = combo,
                PrimaryButtonText = "Export",
                CloseButtonText = "Cancel",
                DefaultButton = ContentDialogButton.Primary,
                XamlRoot = Content.XamlRoot,
            };
            if (await dialog.ShowAsync() != ContentDialogResult.Primary || combo.SelectedIndex < 0) return;

            calendarId = calendars[combo.SelectedIndex].Id;
            _prefs.GoogleCalendarId = calendarId;
        }

        try
        {
            var weekStart = WeekdayExtensions.WeekStart(DateTime.Now);
            Status.Text = await client.ExportClassesAsync(
                _session.Sessions, weekStart, _prefs.TermEndDate, calendarId,
                s => _prefs.Status(s.Id, weekStart));
        }
        catch (GoogleCalendarClient.ClientException ex)
        {
            Status.Text = ex.Message;
        }
    }

    private void OnToggleStartup(object sender, RoutedEventArgs e) =>
        StartupTask.SetEnabled(StartupMenuItem.IsChecked);

    private static int ToInt(double value) => double.IsNaN(value) ? 0 : (int)value;
}
