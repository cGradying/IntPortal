using System.Diagnostics;
using System.Text.Json;
using Xunit;

namespace PUPSISPortal.Core.Tests;

/// <summary>
/// The session orchestration, driven through a fake ISisWebView (no network, no
/// real credentials). Covers the SIS quirks that each cost real debugging on the
/// macOS app: DOM-poll sign-in detection, timeouts, single-flight, and a failed
/// refresh never blanking a cached schedule.
/// </summary>
public class SisSessionTests : IDisposable
{
    private readonly string _dir;

    public SisSessionTests()
    {
        _dir = Path.Combine(Path.GetTempPath(), $"SisSessionTests-{Guid.NewGuid()}");
        Directory.CreateDirectory(_dir);
        ScheduleStore.SetTestDirectory(_dir);
        GradesStore.SetTestDirectory(_dir);
    }

    public void Dispose()
    {
        ScheduleStore.SetTestDirectory(null);
        GradesStore.SetTestDirectory(null);
        if (Directory.Exists(_dir)) Directory.Delete(_dir, recursive: true);
    }

    // ---- helpers -------------------------------------------------------------

    private static readonly SisScripts Scripts =
        new("LOGIN", "PROBE", "PATH", "SCHED", "GRADESJS", "TERMOPTS");

    private static SisSession Make(FakeSisWebView web, TimeSpan? signIn = null) =>
        new(web, Scripts,
            signInTimeout: signIn ?? TimeSpan.FromSeconds(2),
            pageTimeout: TimeSpan.FromMilliseconds(500),
            pollInterval: TimeSpan.FromMilliseconds(5));

    private static Credentials Creds() => new()
    {
        StudentNumber = "2020-00000-MN-0",
        BirthMonth = 1,
        BirthDay = 1,
        BirthYear = 2000,
        Password = "secret",
    };

    private static ClassSession Sample() => new()
    {
        SubjectCode = "COMP 20073",
        Description = "Data Structures",
        Faculty = "SANTOS, JUAN",
        Day = Weekday.Monday,
        Start = 480,
        End = 570,
    };

    private const string ScheduleRows =
        "[{\"subjectCode\":\"COMP 20073\",\"description\":\"Data Structures\",\"unit\":\"3\"," +
        "\"scheduleLine\":\"M 08:00AM-09:30AM\",\"faculty\":\"SANTOS, JUAN\"}]";

    private const string GradesRows =
        "{\"rows\":[{\"subjectCode\":\"COMP 20073\",\"description\":\"Data Structures\"," +
        "\"faculty\":\"SANTOS, JUAN\",\"unit\":\"3\",\"sectionCode\":\"D\"," +
        "\"finalGrade\":\"1.25\",\"gradeStatus\":\"OK\"}],\"summary\":{}}";

    // ---- tests ---------------------------------------------------------------

    [Fact]
    public async Task CorrectPassword_SignsIn_AndParsesSchedule()
    {
        var web = new FakeSisWebView();
        var probeCalls = 0;
        web.Eval = script => script switch
        {
            "LOGIN" => null,
            // Redirect chain: the login form lingers for a couple of polls, then clears.
            "PROBE" => (++probeCalls >= 2)
                ? "{\"stillOnLoginForm\":false,\"message\":\"\"}"
                : "{\"stillOnLoginForm\":true,\"message\":\"\"}",
            "SCHED" => ScheduleRows,
            "GRADESJS" => GradesRows,
            "TERMOPTS" => "{\"currentSchoolYear\":null,\"currentSemester\":null}",
            _ => null,
        };

        var session = Make(web);
        await session.SignInAsync(Creds());

        Assert.Equal(LoginStatus.Success, session.Status);
        Assert.Single(session.Sessions);
        Assert.Equal("COMP 20073", session.Sessions[0].SubjectCode);
        Assert.Equal(Weekday.Monday, session.Sessions[0].Day);
        Assert.NotNull(session.Grades);
        Assert.Single(session.Grades!.Subjects);
    }

    [Fact]
    public async Task WrongPassword_ReportsRejected_WithoutHanging()
    {
        var web = new FakeSisWebView
        {
            Eval = script => script == "PROBE"
                ? "{\"stillOnLoginForm\":true,\"message\":\"Invalid student number or password.\"}"
                : null,
        };

        var session = Make(web);
        await session.SignInAsync(Creds());

        Assert.Equal(LoginStatus.Failed, session.Status);
        Assert.Contains("Invalid", session.StatusMessage);
        Assert.Empty(session.Sessions);
    }

    [Fact]
    public async Task StalledSignIn_TimesOut_DoesNotHang()
    {
        // Login form never clears and no modal appears — the classic no-navigation
        // stall. The armed poll must give up on its own.
        var web = new FakeSisWebView
        {
            Eval = script => script == "PROBE" ? "{\"stillOnLoginForm\":true,\"message\":\"\"}" : null,
        };

        var session = Make(web, signIn: TimeSpan.FromMilliseconds(80));
        var sw = Stopwatch.StartNew();
        await session.SignInAsync(Creds());
        sw.Stop();

        Assert.Equal(LoginStatus.Failed, session.Status);
        Assert.Contains("Sign-in didn't go through", session.StatusMessage);
        Assert.True(sw.ElapsedMilliseconds < 3000, "sign-in should time out, not hang");
    }

    [Fact]
    public async Task ConcurrentSignIns_AreSingleFlight()
    {
        var web = new FakeSisWebView();
        var gate = new TaskCompletionSource();
        // Hold the first sign-in at the login navigation until we release the gate.
        web.NavHook = async (url, _) => { if (url == SisSession.LoginUrl) await gate.Task; };
        web.Eval = script => script switch
        {
            "PROBE" => "{\"stillOnLoginForm\":false,\"message\":\"\"}",
            "SCHED" => "[]",
            "GRADESJS" => "{\"rows\":[],\"summary\":{}}",
            "TERMOPTS" => "{}",
            _ => null,
        };

        var session = Make(web);
        var first = session.SignInAsync(Creds());   // parks at the login nav
        await Task.Delay(50);
        var second = session.SignInAsync(Creds());   // must be dropped by single-flight
        await second;

        Assert.Equal(1, web.NavCount); // the second call never navigated

        gate.SetResult();
        await first;
    }

    [Fact]
    public async Task FailedRefresh_KeepsCachedSchedule()
    {
        // A schedule is already cached (as if from a previous session).
        ScheduleStore.Save(new List<ClassSession> { Sample() }, DateTime.Now);

        var web = new FakeSisWebView
        {
            Eval = script => script == "SCHED" ? "[]" : null, // scrape comes back empty
        };

        var session = Make(web);
        Assert.Single(session.Sessions); // loaded the cache at construction

        await session.LoadScheduleAsync();

        Assert.NotNull(session.RefreshError);
        Assert.Single(session.Sessions);                 // cache preserved
        Assert.Equal("COMP 20073", session.Sessions[0].SubjectCode);
    }

    // ---- fake ----------------------------------------------------------------

    private sealed class FakeSisWebView : ISisWebView
    {
        public string CurrentPath = "/student/";
        public int NavCount;
        public Func<string, string?> Eval = _ => null;
        public Func<string, CancellationToken, Task>? NavHook;

        public Task NavigateAsync(string url, CancellationToken ct = default)
        {
            NavCount++;
            CurrentPath = url.EndsWith("/schedule") ? "/student/schedule"
                        : url.EndsWith("/grades") ? "/student/grades"
                        : "/student/";
            return NavHook?.Invoke(url, ct) ?? Task.CompletedTask;
        }

        public Task<string?> EvalJsAsync(string script, CancellationToken ct = default)
        {
            if (script == "PATH")
                return Task.FromResult<string?>(JsonSerializer.Serialize(CurrentPath));
            return Task.FromResult(Eval(script));
        }
    }
}
