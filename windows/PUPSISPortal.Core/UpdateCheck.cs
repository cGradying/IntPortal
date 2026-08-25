using System.Text.Json;

namespace PUPSISPortal.Core;

/// <summary>
/// A newer release than the one currently running, if there is one.
/// </summary>
public record UpdateInfo(string Version, string Url);

/// <summary>
/// The in-app "update available" nudge: checks GitHub's public releases API for
/// something newer than the running version and links out to it. No self-update
/// — the user still downloads and installs by hand, same as today. No personal
/// data leaves the machine; it's an anonymous GET against this project's own
/// public releases endpoint.
///
/// The HTTP call is injectable so the interesting part — deciding whether a
/// fetched release is actually newer — is unit-tested here without a network
/// call, the same DI-via-delegate shape <see cref="GoogleCalendarClient"/> uses.
/// </summary>
public class UpdateChecker
{
    private const string ReleasesUrl =
        "https://api.github.com/repos/cGradying/IntPortal/releases/latest";

    private static readonly HttpClient DefaultHttp = new();
    private readonly Func<Task<string>> _fetchJson;

    public UpdateChecker(Func<Task<string>>? fetchJson = null)
    {
        _fetchJson = fetchJson ?? DefaultFetch;
    }

    private static async Task<string> DefaultFetch()
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, ReleasesUrl);
        // GitHub's API 403s an unauthenticated request with no User-Agent.
        request.Headers.UserAgent.ParseAdd("PUPSISPortal-UpdateCheck");
        var response = await DefaultHttp.SendAsync(request);
        response.EnsureSuccessStatusCode();
        return await response.Content.ReadAsStringAsync();
    }

    /// <summary>
    /// The latest release, if it's newer than <paramref name="currentVersion"/>;
    /// null if it isn't, or if the check fails for any reason (offline, GitHub
    /// down, unexpected payload) — a failed check is silence, never an error the
    /// user has to deal with.
    /// </summary>
    public async Task<UpdateInfo?> CheckAsync(string currentVersion)
    {
        string json;
        try { json = await _fetchJson(); }
        catch { return null; }

        try
        {
            using var doc = JsonDocument.Parse(json);
            var root = doc.RootElement;
            var tag = root.TryGetProperty("tag_name", out var t) ? t.GetString() : null;
            var url = root.TryGetProperty("html_url", out var u) ? u.GetString() : null;
            if (string.IsNullOrEmpty(tag) || string.IsNullOrEmpty(url))
                return null;

            var latest = tag.TrimStart('v', 'V');
            return IsNewer(latest, currentVersion) ? new UpdateInfo(latest, url) : null;
        }
        catch (JsonException)
        {
            return null;
        }
    }

    /// <summary>
    /// True if <paramref name="latest"/> is strictly newer than
    /// <paramref name="current"/>. Compares up to four dot-separated segments
    /// (covers both "1.1.2" tags and a 4-part <c>&lt;Version&gt;</c> like
    /// "1.1.2.0"); a missing or non-numeric segment reads as 0 rather than
    /// throwing, so an unexpected tag format just fails closed ("not newer")
    /// instead of crashing the check.
    /// </summary>
    public static bool IsNewer(string latest, string current)
    {
        var l = ParseVersion(latest);
        var c = ParseVersion(current);
        for (var i = 0; i < 4; i++)
        {
            if (l[i] != c[i])
                return l[i] > c[i];
        }
        return false;
    }

    private static int[] ParseVersion(string version)
    {
        var parts = version.Trim().TrimStart('v', 'V').Split('.');
        var result = new int[4];
        for (var i = 0; i < 4 && i < parts.Length; i++)
            result[i] = int.TryParse(parts[i], out var n) ? n : 0;
        return result;
    }
}
