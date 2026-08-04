import WebKit

/// Generic scraping helpers for the SIS's DataTables tables and `<dl>` summary
/// blocks — keyed off class/tag, not the DataTables-generated ids (those
/// change per page load), so one script covers Schedule, Grades, and any
/// future `tbldsp` table without per-page column hardcoding.
enum SISScraper {
    private static let tableScript = """
    (function () {
        var table = document.querySelector('table.tbldsp');
        if (!table) return [];
        var headers = Array.from(table.querySelectorAll('thead th')).map(function (th) {
            return th.textContent.trim();
        });
        var rows = Array.from(table.querySelectorAll('tbody tr'));
        return rows.map(function (row) {
            var cells = Array.from(row.querySelectorAll('td'));
            var obj = {};
            headers.forEach(function (header, i) {
                obj[header] = cells[i] ? cells[i].textContent.trim() : '';
            });
            return obj;
        });
    })();
    """

    private static let summaryScript = """
    (function () {
        var lists = Array.from(document.querySelectorAll('dl'));
        var obj = {};
        lists.forEach(function (dl) {
            var dt = dl.querySelector('dt');
            var dd = dl.querySelector('dd');
            if (dt && dd) obj[dt.textContent.trim()] = dd.textContent.trim();
        });
        return obj;
    })();
    """

    static func scrapeTable(from webView: WKWebView) async throws -> [[String: String]] {
        let result = try await webView.evaluateJavaScript(tableScript)
        return result as? [[String: String]] ?? []
    }

    static func scrapeSummary(from webView: WKWebView) async throws -> [String: String] {
        let result = try await webView.evaluateJavaScript(summaryScript)
        return result as? [String: String] ?? [:]
    }
}
