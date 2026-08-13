namespace PUPSISPortal.Core;

/// <summary>
/// Errors from the SIS session orchestration.
/// </summary>
public enum SisError
{
    /// <summary>
    /// Navigation or scraping took too long. The SIS is slow or the connection is unstable.
    /// </summary>
    TimedOut,

    /// <summary>
    /// Sign-in failed: wrong credentials or server rejected the submission.
    /// </summary>
    SignInFailed,

    /// <summary>
    /// A navigation or operation was canceled (e.g., superseded by another navigation
    /// during the post-login redirect chain).
    /// </summary>
    Canceled,

    /// <summary>
    /// A network error occurred (DNS, connection refused, etc.).
    /// </summary>
    NetworkError,

    /// <summary>
    /// The page didn't load as expected or the scraper couldn't find required elements.
    /// </summary>
    PageNotReady,
}

/// <summary>
/// Exception thrown by SisSession operations.
/// </summary>
public class SisException : Exception
{
    public SisError Error { get; }

    public SisException(SisError error, string? message = null)
        : base(message ?? GetDefaultMessage(error))
    {
        Error = error;
    }

    private static string GetDefaultMessage(SisError error) => error switch
    {
        SisError.TimedOut => "The SIS took too long to respond. Check your connection and try again.",
        SisError.SignInFailed => "Sign-in didn't go through — check your student number, birthdate, and password.",
        SisError.Canceled => "Navigation was canceled.",
        SisError.NetworkError => "Network error. Check your connection.",
        SisError.PageNotReady => "The page didn't load as expected.",
        _ => "An error occurred.",
    };
}
