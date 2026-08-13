// SIS schedule scraper — extracted verbatim from the macOS app's SISScraper.swift
// (scheduleScript). Runs in WebView2 via ExecuteScriptAsync; returns a JSON array
// of { subjectCode, description, unit, scheduleLine, faculty }.
//
// Selects the plain `table`, NOT `table.tbldsp` — that class is added async by the
// site's DataTables plugin and is sometimes absent when the scrape runs. Faculty
// sits after a <br> inside a <font> tag; split there, don't regex flattened text.
(function () {
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

    return walkTable(
        { code: ['subject code', 1], desc: ['description', 2], unit: ['unit', 5] },
        function (cells, index, cellText, cellHTML, textOf) {
            // Schedule is always the last column; faculty sits after a <br> inside
            // a <font> tag, so split there instead of regexing the flattened text.
            var parts = cellHTML(cells.length - 1) || '';
            var halves = parts.split(/<br\s*\/?>/i);
            var faculty = halves.length > 1
                ? textOf(halves.slice(1).join(' ')).replace(/^Faculty:\s*/i, '').trim()
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
