import WebKit

/// Pulls structured rows out of the SIS pages.
///
/// Both the Schedule and Grades pages are a single server-rendered `<table>`.
/// Selects the plain `table` element rather than `table.tbldsp` — that class is
/// added asynchronously by the site's DataTables plugin and is sometimes still
/// absent right after the page finishes loading. The row data itself is
/// server-rendered and always present.
enum SISScraper {
    static func scrapeSchedule(from webView: WKWebView) async throws -> [[String: String]] {
        let result = try await webView.evaluateJavaScript(scheduleScript)
        return result as? [[String: String]] ?? []
    }

    static func scrapeGrades(from webView: WKWebView) async throws -> (rows: [[String: String]], summary: [String: String]) {
        let result = try await webView.evaluateJavaScript(gradesScript) as? [String: Any]
        return (
            result?["rows"] as? [[String: String]] ?? [],
            result?["summary"] as? [String: String] ?? [:]
        )
    }

    /// Shared table walk, reused by both page scripts. Maps each header cell to
    /// its column index by name, with a positional fallback, so a reordered or
    /// renamed column degrades gracefully instead of reading the wrong cell.
    ///
    /// `columns` is `{ outputKey: [candidateHeaderName, fallbackIndex] }`.
    private static let tableWalker = """
    function walkTable(columns, mapRow) {
        var table = document.querySelector('table');
        if (!table) return [];

        var headers = Array.prototype.map.call(
            table.querySelectorAll('thead th'),
            function (th) { return th.textContent.trim().toLowerCase(); }
        );
        function columnIndex(name, fallback) {
            var i = headers.indexOf(name);
            return i >= 0 ? i : fallback;
        }
        var index = {};
        Object.keys(columns).forEach(function (key) {
            index[key] = columnIndex(columns[key][0], columns[key][1]);
        });

        var scratch = document.createElement('div');
        function textOf(html) { scratch.innerHTML = html || ''; return scratch.textContent.trim(); }

        return Array.prototype.map.call(table.querySelectorAll('tbody tr'), function (row) {
            var cells = Array.prototype.slice.call(row.querySelectorAll('td'));
            function cellText(i) { return cells[i] ? cells[i].textContent.trim() : ''; }
            function cellHTML(i) { return cells[i] ? cells[i].innerHTML : ''; }
            return mapRow(cells, index, cellText, cellHTML, textOf);
        });
    }
    """

    private static let scheduleScript = """
    (function () {
        \(tableWalker)
        return walkTable(
            { code: ['subject code', 1], desc: ['description', 2], unit: ['unit', 5] },
            function (cells, index, cellText, cellHTML, textOf) {
                // Schedule is always the last column; faculty sits after a <br>
                // inside a <font> tag, so split there instead of regexing the
                // flattened text.
                var parts = cellHTML(cells.length - 1) || '';
                var halves = parts.split(/<br\\s*\\/?>/i);
                var faculty = halves.length > 1
                    ? textOf(halves.slice(1).join(' ')).replace(/^Faculty:\\s*/i, '').trim()
                    : '';
                return {
                    subjectCode: cellText(index.code),
                    description: cellText(index.desc),
                    unit: cellText(index.unit),
                    scheduleLine: textOf(halves[0]),
                    faculty: faculty
                };
            }
        );
    })();
    """

    /// The Grades table shares the schedule's shape: `#, Subject Code,
    /// Description, Faculty Name, Units, Sect Code, Final Grade, Grade Status`.
    /// Grade cells are empty until the school posts them — that empty string is
    /// the expected value, not a scrape failure.
    ///
    /// The `<dl>` summary (Admission Status, Scholastic Status, GPA) is walked
    /// separately into label → value, keeping whatever the live page lists
    /// rather than hard-coding the labels.
    private static let gradesScript = """
    (function () {
        \(tableWalker)
        var rows = walkTable(
            {
                code: ['subject code', 1], desc: ['description', 2],
                faculty: ['faculty name', 3], unit: ['units', 4],
                section: ['sect code', 5], grade: ['final grade', 6],
                status: ['grade status', 7]
            },
            function (cells, index, cellText) {
                return {
                    subjectCode: cellText(index.code),
                    description: cellText(index.desc),
                    faculty: cellText(index.faculty),
                    unit: cellText(index.unit),
                    sectionCode: cellText(index.section),
                    finalGrade: cellText(index.grade),
                    gradeStatus: cellText(index.status)
                };
            }
        );

        var summary = {};
        Array.prototype.forEach.call(document.querySelectorAll('dl'), function (dl) {
            var terms = dl.querySelectorAll('dt');
            var defs = dl.querySelectorAll('dd');
            for (var i = 0; i < terms.length && i < defs.length; i++) {
                var key = terms[i].textContent.trim().replace(/:$/, '');
                if (key) summary[key] = defs[i].textContent.trim();
            }
        });

        return { rows: rows, summary: summary };
    })();
    """
}
