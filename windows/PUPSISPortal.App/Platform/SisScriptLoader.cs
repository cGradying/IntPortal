using PUPSISPortal.Core;

namespace PUPSISPortal.App.Platform;

/// <summary>
/// Builds the <see cref="SisScripts"/> the session runs: the extracted scraper
/// assets (shipped beside the exe) plus the two inline probes that were inline
/// in the macOS PortalController.
/// </summary>
public static class SisScriptLoader
{
    private const string PathName = "document.location.pathname";

    // Success = the login form is gone; a validation modal = rejected. Never a URL check.
    private const string Probe = """
        (function () {
            var modal = document.querySelector('.modal.show .modal-body, .modal[style*="block"] .modal-body');
            return {
                stillOnLoginForm: !!document.getElementById('studno'),
                message: modal ? modal.textContent.trim() : ''
            };
        })();
        """;

    public static SisScripts Load()
    {
        static string Asset(string name) =>
            File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "Assets", "sis-scrapers", name));

        return new SisScripts(
            Login: Asset("login.js"),          // ends with (%ARGS%); SisSession fills it
            Probe: Probe,
            PathName: PathName,
            Schedule: Asset("schedule.js"),
            Grades: Asset("grades.js"),
            TermOptions: Asset("term-options.js"));
    }
}
