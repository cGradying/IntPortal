using Microsoft.UI.Xaml.Controls;
using Microsoft.Web.WebView2.Core;
using PUPSISPortal.Core;

namespace PUPSISPortal.App.Platform;

/// <summary>
/// The real <see cref="ISisWebView"/>, driving a hidden WinUI <c>WebView2</c>.
/// Ported from the macOS PortalController's WKWebView handling — same quirks:
/// arm the navigation-complete wait BEFORE navigating, and treat a superseded
/// navigation (the -999 equivalent) as normal, not a failure.
///
/// Call on the UI thread — WebView2's Core APIs are single-threaded.
/// Windows-only; not built on mac.
/// </summary>
public sealed class WebView2SisWebView : ISisWebView
{
    private readonly CoreWebView2 _core;
    private readonly TimeSpan _navTimeout;
    private TaskCompletionSource<bool>? _pending;

    public WebView2SisWebView(WebView2 web, TimeSpan? navTimeout = null)
    {
        _core = web.CoreWebView2
                ?? throw new InvalidOperationException("Call EnsureCoreWebView2Async() before constructing.");
        _navTimeout = navTimeout ?? TimeSpan.FromSeconds(25);
        _core.NavigationCompleted += OnNavigationCompleted;
    }

    public async Task NavigateAsync(string url, CancellationToken ct = default)
    {
        // Arm before navigating: a fast NavigationCompleted otherwise resumes nothing.
        var tcs = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);
        _pending = tcs;

        _core.Navigate(url);

        using var timeout = new CancellationTokenSource(_navTimeout);
        await using var _ = timeout.Token.Register(() => tcs.TrySetException(new SisException(SisError.TimedOut)));
        await using var __ = ct.Register(() => tcs.TrySetCanceled(ct));
        await tcs.Task;
    }

    private void OnNavigationCompleted(CoreWebView2 sender, CoreWebView2NavigationCompletedEventArgs e)
    {
        var tcs = _pending;
        _pending = null;
        if (tcs is null) return;

        // A navigation the redirect chain superseded reports Canceled/Aborted —
        // the macOS NSURLErrorCancelled (-999) equivalent. SisSession swallows it.
        if (!e.IsSuccess &&
            e.WebErrorStatus is CoreWebView2WebErrorStatus.OperationCanceled
                              or CoreWebView2WebErrorStatus.ConnectionAborted)
        {
            tcs.TrySetException(new SisException(SisError.Canceled));
        }
        else
        {
            tcs.TrySetResult(true);
        }
    }

    public async Task<string?> EvalJsAsync(string script, CancellationToken ct = default)
    {
        // ExecuteScriptAsync returns the last expression as JSON ("null" for
        // null/undefined). SisSession deserializes it with System.Text.Json.
        var json = await _core.ExecuteScriptAsync(script);
        return json == "null" ? null : json;
    }
}
