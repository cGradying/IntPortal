using System.Text.Json;

namespace PUPSISPortal.Core;

/// <summary>Where sign-in currently stands.</summary>
public enum LoginStatus { Idle, LoggingIn, Success, Failed }

/// <summary>
/// The JS the session runs, injected so it's testable. In the app these are the
/// verbatim assets under <c>windows/assets/sis-scrapers/</c> plus the two inline
/// probes; in tests they're sentinels a fake <see cref="ISisWebView"/> matches on.
/// <see cref="Login"/> may contain a <c>%ARGS%</c> placeholder for the credential
/// arguments.
/// </summary>
public sealed record SisScripts(
    string Login,
    string Probe,
    string PathName,
    string Schedule,
    string Grades,
    string TermOptions);

/// <summary>
/// The headless SIS session brain, ported from the macOS <c>PortalController</c>
/// but decoupled from any webview: it drives sign-in and scraping through
/// <see cref="ISisWebView"/>, so the login/DOM-poll/single-flight logic is unit
/// tested here with a fake. The real WebView2 driver (which arms navigation
/// completion, swallows superseded-navigation cancels, etc.) lives in the WinUI
/// app and is verified on Windows.
///
/// The SIS quirks are preserved deliberately — see CLAUDE.md: sign-in is detected
/// by polling the DOM (login form gone = in, validation modal = rejected), NOT by
/// URL; a failed refresh never blanks a cached schedule; one operation is in
/// flight at a time.
/// </summary>
public sealed class SisSession
{
    private const string Base = "https://sis8.pup.edu.ph/student";
    public const string LoginUrl = Base + "/";
    public const string ScheduleUrl = Base + "/schedule";
    public const string GradesUrl = Base + "/grades";

    private const string GenericFailure =
        "Sign-in didn't go through — check your student number, birthdate, and password.";

    private static readonly JsonSerializerOptions JsonOpts = new() { PropertyNameCaseInsensitive = true };

    private readonly ISisWebView _web;
    private readonly SisScripts _scripts;
    private readonly TimeSpan _signInTimeout;
    private readonly TimeSpan _pageTimeout;
    private readonly TimeSpan _pollInterval;

    // Single-flight guard: 0 = free, 1 = an operation is running. The original
    // "wrong password" bug was two concurrent sign-ins corrupting shared state.
    private int _inFlight;

    public LoginStatus Status { get; private set; } = LoginStatus.Idle;
    public string? StatusMessage { get; private set; }
    public List<ClassSession> Sessions { get; private set; } = new();
    public DateTime? LastUpdated { get; private set; }
    public string? RefreshError { get; private set; }
    public GradeReport? Grades { get; private set; }
    public string? GradesError { get; private set; }

    public SisSession(
        ISisWebView web,
        SisScripts scripts,
        TimeSpan? signInTimeout = null,
        TimeSpan? pageTimeout = null,
        TimeSpan? pollInterval = null)
    {
        _web = web;
        _scripts = scripts;
        _signInTimeout = signInTimeout ?? TimeSpan.FromSeconds(25);
        _pageTimeout = pageTimeout ?? TimeSpan.FromSeconds(12);
        _pollInterval = pollInterval ?? TimeSpan.FromMilliseconds(300);

        // Load caches up front so the first frame already has a calendar/grades,
        // exactly like the Swift init.
        var cached = ScheduleStore.Load();
        if (cached != null) { Sessions = cached.Sessions; LastUpdated = cached.LastUpdated; }
        Grades = GradesStore.Load();
    }

    /// <summary>
    /// Sign in, then load the schedule and grades. Single-flight: a second call
    /// while one is running returns immediately rather than corrupting state.
    /// </summary>
    public async Task SignInAsync(Credentials credentials, CancellationToken ct = default)
    {
        if (Interlocked.CompareExchange(ref _inFlight, 1, 0) != 0)
            return; // already signing in / loading — ignore the re-entrant call

        try
        {
            Status = LoginStatus.LoggingIn;
            StatusMessage = null;
            try
            {
                await NavigateSwallowingCancel(LoginUrl, ct);

                // Fire fill+submit and DON'T await navigation: sign-in runs a
                // redirect chain and a validation error shows a modal with no
                // navigation at all. Poll the DOM for the real outcome instead.
                await _web.EvalJsAsync(BuildLoginScript(credentials), ct);

                var (success, message) = await AwaitSignInOutcome(ct);
                if (!success) { Report(message); return; }

                Status = LoginStatus.Success;
                await LoadScheduleCore(ct);
                await LoadGradesCore(ct);
            }
            catch (Exception ex)
            {
                Report(ex.Message);
            }
        }
        finally
        {
            Interlocked.Exchange(ref _inFlight, 0);
        }
    }

    public Task LoadScheduleAsync(CancellationToken ct = default) => LoadScheduleCore(ct);
    public Task LoadGradesAsync(CancellationToken ct = default) => LoadGradesCore(ct);

    // ponytail: loadGradeHistory (the term-by-term backfill) needs an
    // eval-and-wait-for-the-navigation-it-triggers primitive that the 2-method
    // interface doesn't expose, and it's unverified even in Swift (no posted
    // grades to test against). Deferred to the WinUI/WebView2 stage where the
    // driver can arm navigation around the term-select submit.

    private async Task LoadScheduleCore(CancellationToken ct)
    {
        try
        {
            await NavigateSwallowingCancel(ScheduleUrl, ct);

            var rows = await AwaitPageRows(
                "/schedule",
                async () => Deserialize<List<Dictionary<string, string>>>(
                    await _web.EvalJsAsync(_scripts.Schedule, ct)),
                r => r.Count == 0,
                ct);

            var scraped = rows.SelectMany(ScheduleParser.Parse).ToList();
            var now = DateTime.Now;

            // A scrape that parses to nothing while we already hold a schedule is
            // almost always a hiccup, not a real empty term — never blank a good
            // cache on it.
            if (scraped.Count == 0 && Sessions.Count > 0)
            {
                RefreshError = "No classes found on the SIS schedule page — kept your last schedule.";
                return;
            }

            Sessions = scraped;
            LastUpdated = now;
            RefreshError = null;
            ScheduleStore.Save(scraped, now);
        }
        catch (Exception ex)
        {
            Report($"Couldn't refresh your schedule: {ex.Message}");
        }
    }

    private async Task LoadGradesCore(CancellationToken ct)
    {
        try
        {
            await NavigateSwallowingCancel(GradesUrl, ct);

            var scraped = await AwaitPageRows(
                "/grades",
                async () => Deserialize<GradesScrape>(await _web.EvalJsAsync(_scripts.Grades, ct)),
                g => g.Rows.Count == 0,
                ct);

            var opts = Deserialize<TermOpts>(await _web.EvalJsAsync(_scripts.TermOptions, ct));

            var report = new GradeReport
            {
                LastUpdated = DateTime.Now,
                Subjects = GradesParser.Parse(scraped.Rows),
                Summary = scraped.Summary,
                SchoolYear = opts?.CurrentSchoolYear,
                Semester = opts?.CurrentSemester,
            };

            // Same protection as the schedule: an empty parse must not wipe grades
            // we already hold.
            if (report.Subjects.Count == 0 && Grades is { Subjects.Count: > 0 })
            {
                GradesError = "No grades found on the SIS page — kept your last grades.";
                return;
            }

            Grades = report;
            GradesError = null;
            GradesStore.Save(report);

            // Fold the current term into history — but only when it's actually
            // identified and has posted grades, or a monthly refresh piles up
            // duplicate untagged points.
            if (report.HasPostedGrades && report.SchoolYear != null)
            {
                var history = GradesStore.Merged(report, GradesStore.LoadHistory());
                GradesStore.SaveHistory(history);
            }
        }
        catch (Exception ex)
        {
            // Own error channel: a grades failure never disturbs the schedule.
            GradesError = $"Couldn't refresh your grades: {ex.Message}";
        }
    }

    /// <summary>
    /// Poll until the login form disappears (signed in) or a validation modal
    /// appears (rejected). Polling — not watching navigations — is what survives
    /// the redirect chain and the no-navigation error case.
    /// </summary>
    private async Task<(bool Success, string Message)> AwaitSignInOutcome(CancellationToken ct)
    {
        var deadline = DateTime.UtcNow + _signInTimeout;
        while (DateTime.UtcNow < deadline)
        {
            var probe = Deserialize<Probe>(await _web.EvalJsAsync(_scripts.Probe, ct));
            if (probe != null)
            {
                if (!probe.StillOnLoginForm) return (true, "");
                if (!string.IsNullOrEmpty(probe.Message)) return (false, probe.Message);
            }
            await Task.Delay(_pollInterval, ct);
        }
        return (false, GenericFailure);
    }

    /// <summary>
    /// Poll until the path matches AND the scrape yields rows — one navigation
    /// completion is not proof the right page is loaded, and DataTables may not
    /// have filled the body yet. Reaching the page and finding nothing is a real
    /// answer (an empty term); never reaching it is a timeout.
    /// </summary>
    private async Task<T> AwaitPageRows<T>(
        string suffix,
        Func<Task<T?>> scrapeOnce,
        Func<T, bool> isEmpty,
        CancellationToken ct) where T : class
    {
        var deadline = DateTime.UtcNow + _pageTimeout;
        var reachedPage = false;
        T? last = null;

        while (DateTime.UtcNow < deadline)
        {
            if (await IsOnPage(suffix, ct))
            {
                reachedPage = true;
                T? scraped = null;
                try { scraped = await scrapeOnce(); } catch { scraped = null; }
                if (scraped != null)
                {
                    last = scraped;
                    if (!isEmpty(scraped)) return scraped;
                }
            }
            await Task.Delay(_pollInterval, ct);
        }

        if (reachedPage && last != null) return last;
        throw new SisException(SisError.TimedOut);
    }

    private async Task<bool> IsOnPage(string suffix, CancellationToken ct)
    {
        var path = Deserialize<string>(await _web.EvalJsAsync(_scripts.PathName, ct)) ?? "";
        return path.EndsWith(suffix, StringComparison.Ordinal);
    }

    /// <summary>
    /// A failed refresh must never replace a schedule we already have — a cached
    /// calendar beats an error screen. With nothing cached, the error takes the
    /// whole view. Falls back to Idle (not LoggingIn) so Retry isn't a no-op.
    /// </summary>
    private void Report(string message)
    {
        if (Sessions.Count == 0)
        {
            Status = LoginStatus.Failed;
            StatusMessage = message;
        }
        else
        {
            RefreshError = message;
            Status = LoginStatus.Idle;
        }
    }

    /// <summary>
    /// A superseded navigation during the post-login redirect chain is normal
    /// (the macOS equivalent is NSURLErrorCancelled / -999), not a failure. The
    /// real driver swallows it; we also tolerate it here so the polling loops
    /// carry on rather than surfacing it.
    /// </summary>
    private async Task NavigateSwallowingCancel(string url, CancellationToken ct)
    {
        try { await _web.NavigateAsync(url, ct); }
        catch (SisException e) when (e.Error == SisError.Canceled) { /* expected during redirects */ }
    }

    private string BuildLoginScript(Credentials c)
    {
        static string Js(string value) => JsonSerializer.Serialize(value);
        var args = string.Join(", ", new[]
        {
            Js(c.StudentNumber),
            Js(c.BirthMonth.ToString()),
            Js(c.BirthDay.ToString()),
            Js(c.BirthYear.ToString()),
            Js(c.Password),
        });
        return _scripts.Login.Replace("%ARGS%", args);
    }

    private static T? Deserialize<T>(string? json) where T : class
    {
        if (string.IsNullOrEmpty(json)) return null;
        try { return JsonSerializer.Deserialize<T>(json, JsonOpts); }
        catch { return null; }
    }

    private sealed record Probe
    {
        public bool StillOnLoginForm { get; init; }
        public string Message { get; init; } = "";
    }

    private sealed class GradesScrape
    {
        public List<Dictionary<string, string>> Rows { get; set; } = new();
        public Dictionary<string, string> Summary { get; set; } = new();
    }

    private sealed class TermOpts
    {
        public string? CurrentSchoolYear { get; set; }
        public string? CurrentSemester { get; set; }
    }
}
