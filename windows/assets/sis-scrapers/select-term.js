// SIS grade-term selector — extracted verbatim from SISScraper.swift
// (selectAndSubmitBody + termSelectFinder). Defines a function; the host calls it
// with the two visible labels, e.g.:
//   ExecuteScriptAsync(fileContents + ";pupSelectGradeTerm(" + jsonSy + "," + jsonSem + ");")
// It sets each <select> to the matching option, fires `change`, and submits the
// enclosing form (falling back to a view/show/display button). Returns whether
// both selects were found and set.
//
// Run this INSIDE the host's arm-continuation-before-navigate wait — the submit is
// what triggers navigation, and a fast completion otherwise resumes nothing.
function pupSelectGradeTerm(schoolYear, semester) {
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
    if (!setByLabel(sels.year, schoolYear) || !setByLabel(sels.sem, semester)) return false;

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
}
