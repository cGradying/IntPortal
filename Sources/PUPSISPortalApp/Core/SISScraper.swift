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

    /// The grades page's two `<select>`s: available school years and semesters,
    /// plus whichever is currently showing. Found by the shape of their options
    /// (a `YYYY-YYYY` year, a "Semester"/"Summer" label) rather than by element
    /// id — the ids aren't confirmed against the live page, and this degrades to
    /// empty lists rather than reading the wrong control.
    static func gradeTermOptions(from webView: WKWebView) async throws -> GradeTermOptions {
        let result = try await webView.evaluateJavaScript(termOptionsScript) as? [String: Any]
        return GradeTermOptions(
            schoolYears: result?["schoolYears"] as? [String] ?? [],
            semesters: result?["semesters"] as? [String] ?? [],
            currentSchoolYear: result?["currentSchoolYear"] as? String,
            currentSemester: result?["currentSemester"] as? String
        )
    }

    /// Fire-and-forget JS that selects a term by its visible labels and submits,
    /// so the next navigation shows that term. Run it *inside* the controller's
    /// arm-continuation-before-navigate wait — the submit is what triggers the
    /// navigation, and a fast `didFinish` otherwise resumes nothing.
    static func selectGradeTermScript(schoolYear: String, semester: String) -> String {
        "(function(){\(selectAndSubmitBody)})(\(jsString(schoolYear)), \(jsString(semester)));"
    }

    /// The available terms on the grades page, as visible labels.
    struct GradeTermOptions {
        let schoolYears: [String]
        let semesters: [String]
        let currentSchoolYear: String?
        let currentSemester: String?

        /// Every school-year × semester combination, current term first so a
        /// refresh re-confirms what's on screen before wandering into history.
        var combinations: [(schoolYear: String, semester: String)] {
            var out: [(schoolYear: String, semester: String)] = []
            for sy in schoolYears {
                for sem in semesters { out.append((schoolYear: sy, semester: sem)) }
            }
            guard let sy = currentSchoolYear, let sem = currentSemester else { return out }
            let isCurrent: ((schoolYear: String, semester: String)) -> Bool = {
                $0.schoolYear == sy && $0.semester == sem
            }
            return out.filter(isCurrent) + out.filter { !isCurrent($0) }
        }
    }

    /// A JS string literal from a Swift string, quotes and backslashes escaped.
    private static func jsString(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\""
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

    /// Classifies the page's `<select>`s by what their options look like: a
    /// school-year select carries `YYYY-YYYY` labels, a semester select carries
    /// "sem"/"summer" labels. Shared by reading and setting so both agree on
    /// which control is which without depending on ids that aren't confirmed.
    private static let termSelectFinder = """
    function optionLabels(sel) {
        return Array.prototype.map.call(sel.options, function (o) { return o.textContent.trim(); })
            .filter(function (t) { return t.length > 0; });
    }
    function looksLikeYear(t) { return /\\d{4}\\s*-\\s*\\d{4}/.test(t); }
    function looksLikeSem(t) { var s = t.toLowerCase(); return s.indexOf('sem') >= 0 || s.indexOf('summer') >= 0 || s.indexOf('mid') >= 0; }
    function classifySelect(sel) {
        var labels = optionLabels(sel);
        if (labels.length === 0) return null;
        var years = labels.filter(looksLikeYear).length;
        var sems = labels.filter(looksLikeSem).length;
        if (years >= sems && years > 0) return 'year';
        if (sems > 0) return 'sem';
        return null;
    }
    function findTermSelects() {
        var selects = Array.prototype.slice.call(document.querySelectorAll('select'));
        var yearSel = null, semSel = null;
        selects.forEach(function (sel) {
            var kind = classifySelect(sel);
            if (kind === 'year' && !yearSel) yearSel = sel;
            else if (kind === 'sem' && !semSel) semSel = sel;
        });
        return { year: yearSel, sem: semSel };
    }
    function selectedLabel(sel) {
        return sel && sel.selectedIndex >= 0 ? sel.options[sel.selectedIndex].textContent.trim() : null;
    }
    """

    private static let termOptionsScript = """
    (function () {
        \(termSelectFinder)
        var sels = findTermSelects();
        return {
            schoolYears: sels.year ? optionLabels(sels.year).filter(looksLikeYear) : [],
            semesters: sels.sem ? optionLabels(sels.sem).filter(looksLikeSem) : [],
            currentSchoolYear: selectedLabel(sels.year),
            currentSemester: selectedLabel(sels.sem)
        };
    })();
    """

    /// Body of `selectGradeTerm` — takes the two labels as arguments, sets each
    /// select to the matching option, fires `change`, and submits the enclosing
    /// form (falling back to a "view"/"show" button). Returns whether both
    /// selects were found and set.
    private static let selectAndSubmitBody = """
        \(termSelectFinder)
        var sels = findTermSelects();
        if (!sels.year || !sels.sem) return false;
        function setByLabel(sel, label) {
            for (var i = 0; i < sel.options.length; i++) {
                if (sel.options[i].textContent.trim() === label) {
                    sel.selectedIndex = i;
                    sel.dispatchEvent(new Event('change', { bubbles: true }));
                    return true;
                }
            }
            return false;
        }
        var syArg = arguments[0], semArg = arguments[1];
        if (!setByLabel(sels.year, syArg) || !setByLabel(sels.sem, semArg)) return false;

        var form = sels.year.form || sels.sem.form;
        var button = document.querySelector('button, input[type=submit]');
        var labelText = button ? (button.textContent || button.value || '').toLowerCase() : '';
        if (button && (labelText.indexOf('view') >= 0 || labelText.indexOf('show') >= 0 || labelText.indexOf('display') >= 0)) {
            button.click();
        } else if (form) {
            form.submit();
        } else {
            return false;
        }
        return true;
    """
}
