// SIS grade-term reader — extracted verbatim from SISScraper.swift
// (termOptionsScript + termSelectFinder). Classifies the page's <select>s by the
// shape of their option labels (YYYY-YYYY = year, sem/summer/mid = semester)
// rather than by element id, which isn't confirmed against the live page.
// Returns { schoolYears, semesters, currentSchoolYear, currentSemester }.
(function () {
    function optionLabels(sel) {
        return Array.prototype.map.call(sel.options, function (o) { return o.textContent.trim(); })
            .filter(function (t) { return t.length > 0; });
    }
    function looksLikeYear(t) { return /\d{4}\s*-\s*\d{4}/.test(t); }
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

    var sels = findTermSelects();
    return {
        schoolYears: sels.year ? optionLabels(sels.year).filter(looksLikeYear) : [],
        semesters: sels.sem ? optionLabels(sels.sem).filter(looksLikeSem) : [],
        currentSchoolYear: selectedLabel(sels.year),
        currentSemester: selectedLabel(sels.sem)
    };
})();
