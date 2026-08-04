import WebKit

/// Pulls the schedule rows out of the SIS page.
///
/// Selects the plain `table` element rather than `table.tbldsp` — that class
/// is added asynchronously by the site's DataTables plugin and is sometimes
/// still absent right after the page finishes loading. The row data itself is
/// server-rendered and always present.
enum SISScraper {
    private static let scheduleScript = """
    (function () {
        var table = document.querySelector('table');
        if (!table) return [];

        var headers = Array.from(table.querySelectorAll('thead th')).map(function (th) {
            return th.textContent.trim().toLowerCase();
        });
        function columnIndex(name, fallback) {
            var i = headers.indexOf(name);
            return i >= 0 ? i : fallback;
        }
        var codeIndex = columnIndex('subject code', 1);
        var descIndex = columnIndex('description', 2);
        var unitIndex = columnIndex('unit', 5);

        var scratch = document.createElement('div');
        function textOf(html) {
            scratch.innerHTML = html || '';
            return scratch.textContent.trim();
        }

        return Array.from(table.querySelectorAll('tbody tr')).map(function (row) {
            var cells = Array.from(row.querySelectorAll('td'));
            function cellText(i) { return cells[i] ? cells[i].textContent.trim() : ''; }

            // Schedule is always the last column; faculty sits after a <br>
            // inside a <font> tag, so split there instead of regexing the
            // flattened text.
            var parts = (cells[cells.length - 1] || {}).innerHTML || '';
            var halves = parts.split(/<br\\s*\\/?>/i);
            var faculty = halves.length > 1
                ? textOf(halves.slice(1).join(' ')).replace(/^Faculty:\\s*/i, '').trim()
                : '';

            return {
                subjectCode: cellText(codeIndex),
                description: cellText(descIndex),
                unit: cellText(unitIndex),
                scheduleLine: textOf(halves[0]),
                faculty: faculty
            };
        });
    })();
    """

    static func scrapeSchedule(from webView: WKWebView) async throws -> [[String: String]] {
        let result = try await webView.evaluateJavaScript(scheduleScript)
        return result as? [[String: String]] ?? []
    }
}
