using System.Diagnostics;
using System.Net;
using System.Net.Sockets;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace PUPSISPortal.App.Platform;

/// <summary>
/// Google OAuth for a public (PKCE) client on Windows — the loopback-redirect
/// counterpart of macOS's GoogleAuth.swift (which uses ASWebAuthenticationSession
/// and a reversed-client-ID URL scheme). Windows has no scheme-registration-free
/// equivalent for an unpackaged exe, so this follows Google's other documented
/// installed-app flow instead: bind an ephemeral 127.0.0.1 port, send the user to
/// it in their default browser, and catch the redirect with a one-shot
/// <see cref="HttpListener"/>. Same PKCE math, same token endpoint, same refresh-
/// token-in-the-credential-vault storage.
///
/// ponytail: while the OAuth consent screen is in "testing" mode, Google expires
/// the refresh token after ~7 days — same caveat as the mac app; not worth
/// automating for a personal project.
/// </summary>
public sealed class GoogleAuthWindows
{
    private const string Scope = "https://www.googleapis.com/auth/calendar";
    private static readonly HttpClient Http = new();

    private string? _accessToken;
    private DateTime _accessExpiry = DateTime.MinValue;

    public bool IsConnected => GoogleTokenVaultStore.Load() != null;

    public sealed class AuthException : Exception
    {
        public AuthException(string message) : base(message) { }
    }

    /// <summary>
    /// Runs the full consent round-trip: opens the system browser, waits for the
    /// loopback redirect, exchanges the code, and stores the refresh token.
    /// </summary>
    public async Task ConnectAsync(string clientId, CancellationToken ct = default)
    {
        var id = clientId.Trim();
        if (id.Length == 0) throw new AuthException("Enter your Google OAuth client ID first.");

        var port = FreeLoopbackPort();
        var redirect = $"http://127.0.0.1:{port}/";
        var verifier = RandomString(64);
        var challenge = Challenge(verifier);
        var state = RandomString(32);

        var authUrl = "https://accounts.google.com/o/oauth2/v2/auth?" + FormEncode(new()
        {
            ["client_id"] = id,
            ["redirect_uri"] = redirect,
            ["response_type"] = "code",
            ["scope"] = Scope,
            ["code_challenge"] = challenge,
            ["code_challenge_method"] = "S256",
            ["state"] = state,
            ["access_type"] = "offline",
            ["prompt"] = "consent",
        });

        using var listener = new HttpListener();
        listener.Prefixes.Add(redirect);
        listener.Start();

        Process.Start(new ProcessStartInfo(authUrl) { UseShellExecute = true });

        HttpListenerContext context;
        using (ct.Register(listener.Stop))
        {
            try { context = await listener.GetContextAsync(); }
            catch (Exception) when (ct.IsCancellationRequested) { throw new AuthException("Google sign-in was cancelled."); }
        }

        var query = context.Request.QueryString;
        await RespondAsync(context, query["error"] == null);

        if (query["state"] != state)
            throw new AuthException("Sign-in response didn't match the request.");
        var code = query["code"];
        if (code is null)
            throw new AuthException(query["error"] ?? "No authorization code returned.");

        var token = await PostTokenAsync(new()
        {
            ["grant_type"] = "authorization_code",
            ["code"] = code,
            ["code_verifier"] = verifier,
            ["client_id"] = id,
            ["redirect_uri"] = redirect,
        }, ct);

        if (token.RefreshToken is { } refresh)
            GoogleTokenVaultStore.Save(refresh);
        _accessToken = token.AccessToken;
        _accessExpiry = DateTime.UtcNow.AddSeconds(token.ExpiresIn);
    }

    public void Disconnect()
    {
        GoogleTokenVaultStore.Delete();
        _accessToken = null;
        _accessExpiry = DateTime.MinValue;
    }

    /// <summary>
    /// A valid access token, refreshing from the stored refresh token when the
    /// cached one has expired. Pass this as <c>GoogleCalendarClient</c>'s token
    /// provider.
    /// </summary>
    public async Task<string> ValidAccessTokenAsync(string clientId)
    {
        if (_accessToken is { } cached && _accessExpiry - DateTime.UtcNow > TimeSpan.FromSeconds(60))
            return cached;

        var refresh = GoogleTokenVaultStore.Load() ?? throw new AuthException("Connect your Google account first.");
        var id = clientId.Trim();
        if (id.Length == 0) throw new AuthException("Enter your Google OAuth client ID first.");

        var token = await PostTokenAsync(new()
        {
            ["grant_type"] = "refresh_token",
            ["refresh_token"] = refresh,
            ["client_id"] = id,
        }, default);

        _accessToken = token.AccessToken;
        _accessExpiry = DateTime.UtcNow.AddSeconds(token.ExpiresIn);
        return token.AccessToken;
    }

    // MARK: Token endpoint

    private sealed record TokenResponse(string AccessToken, double ExpiresIn, string? RefreshToken);

    private static async Task<TokenResponse> PostTokenAsync(Dictionary<string, string> fields, CancellationToken ct)
    {
        using var content = new StringContent(FormEncode(fields), Encoding.UTF8, "application/x-www-form-urlencoded");
        using var response = await Http.PostAsync("https://oauth2.googleapis.com/token", content, ct);
        var body = await response.Content.ReadAsStringAsync(ct);
        if (!response.IsSuccessStatusCode)
            throw new AuthException(GoogleError(body));

        using var doc = JsonDocument.Parse(body);
        var root = doc.RootElement;
        return new TokenResponse(
            root.GetProperty("access_token").GetString()!,
            root.GetProperty("expires_in").GetDouble(),
            root.TryGetProperty("refresh_token", out var r) ? r.GetString() : null);
    }

    private static string GoogleError(string body)
    {
        try
        {
            using var doc = JsonDocument.Parse(body);
            var root = doc.RootElement;
            var desc = root.TryGetProperty("error_description", out var d) ? d.GetString() : null;
            var err = root.TryGetProperty("error", out var e) ? e.GetString() : null;
            return desc ?? err ?? "Google rejected the request.";
        }
        catch
        {
            return "Google rejected the request.";
        }
    }

    // MARK: Loopback listener detail

    private static async Task RespondAsync(HttpListenerContext context, bool ok)
    {
        var html = ok
            ? "<html><body style='font-family:sans-serif;padding:2em'>Signed in — you can close this window.</body></html>"
            : "<html><body style='font-family:sans-serif;padding:2em'>Sign-in failed — you can close this window.</body></html>";
        var bytes = Encoding.UTF8.GetBytes(html);
        context.Response.ContentType = "text/html";
        context.Response.ContentLength64 = bytes.Length;
        await context.Response.OutputStream.WriteAsync(bytes);
        context.Response.OutputStream.Close();
    }

    /// <summary>
    /// Binds an ephemeral TCP port then releases it immediately, handing the
    /// number to <c>HttpListener</c>, which can't request port 0 itself.
    /// ponytail: a tiny race window between release and HttpListener.Start() —
    /// negligible on a loopback address for an interactive, user-initiated flow.
    /// </summary>
    private static int FreeLoopbackPort()
    {
        var listener = new TcpListener(IPAddress.Loopback, 0);
        listener.Start();
        var port = ((IPEndPoint)listener.LocalEndpoint).Port;
        listener.Stop();
        return port;
    }

    // MARK: PKCE / helpers

    private static string Challenge(string verifier) => Base64Url(SHA256.HashData(Encoding.UTF8.GetBytes(verifier)));

    private static string RandomString(int bytes) => Base64Url(RandomNumberGenerator.GetBytes(bytes));

    private static string Base64Url(byte[] data) =>
        Convert.ToBase64String(data).Replace("+", "-").Replace("/", "_").Replace("=", "");

    private static string FormEncode(Dictionary<string, string> fields) =>
        string.Join("&", fields.Select(kv => $"{Uri.EscapeDataString(kv.Key)}={Uri.EscapeDataString(kv.Value)}"));
}
