using Microsoft.UI.Xaml;
using PUPSISPortal.App.Platform;
using PUPSISPortal.Core;

namespace PUPSISPortal.App;

/// <summary>
/// Stage 3–5 shell: Mica ground + custom titlebar, a minimal sign-in, and the
/// week-grid calendar rendered from the ported <see cref="SisSession"/>. The
/// session is real (Core, tested on mac); the driver and UI are Windows-only.
/// </summary>
public sealed partial class MainWindow : Window
{
    private SisSession? _session;

    public MainWindow()
    {
        InitializeComponent();
        ExtendsContentIntoTitleBar = true;
        SetTitleBar(AppTitleBar);
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
        Calendar.Visibility = Visibility.Visible;
        Calendar.Show(_session.Sessions);
    }

    private static int ToInt(double value) => double.IsNaN(value) ? 0 : (int)value;
}
