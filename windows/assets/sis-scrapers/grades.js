// SIS grades scraper — extracted verbatim from SISScraper.swift (gradesScript).
// Returns { rows: [...], summary: {label: value} }. Grade cells are empty until
// the school posts them — that empty string is expected, not a failure.
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
