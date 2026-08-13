namespace PUPSISPortal.Core;

/// <summary>
/// Abstract webview interface that SisSession relies on.
/// This allows testing without WebView2, and eventual WebView2 driver
/// to inject navigation timing and JavaScript execution.
///
/// A real WebView2 driver arms a continuation before triggering navigation,
/// then completes it when the navigation event fires — see the Swift
/// CLAUDE.md quirk: "Arm the continuation before triggering navigation".
/// </summary>
public interface ISisWebView
{
    /// <summary>
    /// Begin navigation to a URL.
    /// A real implementation arms the navigation-complete event or continuation
    /// before kicking off the load, so a fast completion still resumes.
    /// </summary>
    Task NavigateAsync(string url, CancellationToken ct = default);

    /// <summary>
    /// Execute JavaScript and return its result as a JSON string — exactly what
    /// WebView2's <c>ExecuteScriptAsync</c> yields (a string result comes back
    /// JSON-quoted, an object/array as its JSON text). Returns null if the script
    /// returned null/undefined. The orchestration deserializes with System.Text.Json.
    /// </summary>
    Task<string?> EvalJsAsync(string script, CancellationToken ct = default);
}
