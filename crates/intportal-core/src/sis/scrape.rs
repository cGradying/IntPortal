//! Pure HTML readers for the SIS pages. Both tables are server-rendered, so
//! no JavaScript is needed (S0, #4).

use crate::grades::GradeRow;
use crate::schedule::ScheduleRow;
use regex::Regex;
use scraper::{ElementRef, Html, Selector};
use std::collections::BTreeMap;
use std::sync::LazyLock;

fn sel(s: &str) -> Selector {
    Selector::parse(s).unwrap()
}

fn text(el: ElementRef) -> String {
    el.text().collect::<String>().split_whitespace().collect::<Vec<_>>().join(" ")
}

fn fragment_text(html: &str) -> String {
    text(Html::parse_fragment(html).root_element())
}

/// The login form's action and every field a browser would submit, hidden
/// `csrf_token`s and the `Login` submit value included.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LoginForm {
    pub action: Option<String>,
    pub fields: Vec<(String, String)>,
}

pub fn login_form(html: &str) -> Option<LoginForm> {
    let doc = Html::parse_document(html);
    let form = doc.select(&sel("form")).find(|f| f.select(&sel("#studno")).next().is_some())?;
    let fields = form
        .select(&sel("input[name], select[name], textarea[name]"))
        .filter(|e| !e.value().attr("type").is_some_and(|t| t.eq_ignore_ascii_case("button")))
        .map(|e| (e.value().attr("name").unwrap().to_string(), e.value().attr("value").unwrap_or("").to_string()))
        .collect();
    Some(LoginForm { action: form.value().attr("action").map(String::from), fields })
}

pub fn has_login_form(html: &str) -> bool {
    Html::parse_document(html).select(&sel("#studno")).next().is_some()
}

/// The SIS's own error text (its modal or alert), if the page shows one.
pub fn page_message(html: &str) -> Option<String> {
    let doc = Html::parse_document(html);
    let found = doc.select(&sel(".modal-body, .alert")).map(text).find(|t| !t.is_empty());
    found
}

/// Column index by header name, falling back to a position, so a renamed
/// or reordered column degrades instead of reading the wrong cell.
struct Table {
    headers: Vec<String>,
    rows: Vec<Vec<(String, String)>>,
}

impl Table {
    fn read(html: &str) -> Table {
        let doc = Html::parse_document(html);
        let Some(table) = doc.select(&sel("table")).next() else { return Table { headers: vec![], rows: vec![] } };
        let headers = table.select(&sel("thead th")).map(|th| text(th).to_lowercase()).collect();
        let rows = table
            .select(&sel("tbody tr"))
            .map(|tr| tr.select(&sel("td")).map(|td| (text(td), td.inner_html())).collect())
            .collect();
        Table { headers, rows }
    }

    fn col(&self, name: &str, fallback: usize) -> usize {
        self.headers.iter().position(|h| h == name).unwrap_or(fallback)
    }
}

fn cell(row: &[(String, String)], i: usize) -> String {
    row.get(i).map(|c| c.0.clone()).unwrap_or_default()
}

static BR: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"(?i)<br\s*/?>").unwrap());
static FACULTY_PREFIX: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"(?i)^faculty:\s*").unwrap());

pub fn schedule_rows(html: &str) -> Vec<ScheduleRow> {
    let t = Table::read(html);
    let (code, desc, unit) = (t.col("subject code", 1), t.col("description", 2), t.col("unit", 5));
    t.rows
        .iter()
        .map(|r| {
            // The schedule is the last column; the faculty sits after a <br>.
            let last = r.last().map(|c| c.1.as_str()).unwrap_or("");
            let mut halves = BR.splitn(last, 2);
            let line = fragment_text(halves.next().unwrap_or(""));
            let faculty = halves.next().map(|h| FACULTY_PREFIX.replace(&fragment_text(h), "").into_owned());
            ScheduleRow {
                subject_code: cell(r, code),
                description: cell(r, desc),
                unit: cell(r, unit),
                schedule_line: line,
                faculty: faculty.unwrap_or_default(),
            }
        })
        .collect()
}

pub fn grades(html: &str) -> (Vec<GradeRow>, BTreeMap<String, String>) {
    let t = Table::read(html);
    let c = |n, f| t.col(n, f);
    let (code, desc, fac, unit, sect, grade, status) = (
        c("subject code", 1),
        c("description", 2),
        c("faculty name", 3),
        c("units", 4),
        c("sect code", 5),
        c("final grade", 6),
        c("grade status", 7),
    );
    let rows = t
        .rows
        .iter()
        .map(|r| GradeRow {
            subject_code: cell(r, code),
            description: cell(r, desc),
            faculty: cell(r, fac),
            unit: cell(r, unit),
            section_code: cell(r, sect),
            final_grade: cell(r, grade),
            grade_status: cell(r, status),
        })
        .collect();

    let doc = Html::parse_document(html);
    let mut summary = BTreeMap::new();
    for dl in doc.select(&sel("dl")) {
        let terms: Vec<String> = dl.select(&sel("dt")).map(text).collect();
        let defs: Vec<String> = dl.select(&sel("dd")).map(text).collect();
        for (k, v) in terms.into_iter().zip(defs) {
            let k = k.trim_end_matches(':').trim().to_string();
            if !k.is_empty() {
                summary.insert(k, v);
            }
        }
    }
    (rows, summary)
}

/// The grades page's term picker: its form, and the School Year and Semester
/// selects found by what their options look like, not by id.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TermPicker {
    pub action: Option<String>,
    pub post: bool,
    /// Every other field the form submits, unchanged.
    pub fields: Vec<(String, String)>,
    pub year_field: String,
    pub semester_field: String,
    /// (value, label), with the selected one first.
    pub years: Vec<(String, String)>,
    pub semesters: Vec<(String, String)>,
}

static YEAR_LABEL: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"\d{4}\s*-\s*\d{4}").unwrap());

fn is_sem(label: &str) -> bool {
    let l = label.to_lowercase();
    l.contains("sem") || l.contains("summer") || l.contains("mid")
}

pub fn term_picker(html: &str) -> Option<TermPicker> {
    let doc = Html::parse_document(html);
    for form in doc.select(&sel("form")) {
        let mut year = None;
        let mut sem = None;
        for select in form.select(&sel("select[name]")) {
            let mut opts: Vec<(String, String, bool)> = select
                .select(&sel("option"))
                .map(|o| {
                    let label = text(o);
                    (o.value().attr("value").map(String::from).unwrap_or_else(|| label.clone()), label, o.value().attr("selected").is_some())
                })
                .filter(|(_, l, _)| !l.is_empty())
                .collect();
            opts.sort_by_key(|o| !o.2);
            let name = select.value().attr("name").unwrap().to_string();
            let years = opts.iter().filter(|o| YEAR_LABEL.is_match(&o.1)).count();
            let sems = opts.iter().filter(|o| is_sem(&o.1)).count();
            let pairs = |keep: &dyn Fn(&str) -> bool| opts.iter().filter(|o| keep(&o.1)).map(|o| (o.0.clone(), o.1.clone())).collect::<Vec<_>>();
            if years > 0 && years >= sems && year.is_none() {
                year = Some((name, pairs(&|l| YEAR_LABEL.is_match(l))));
            } else if sems > 0 && sem.is_none() {
                sem = Some((name, pairs(&is_sem)));
            }
        }
        let (Some((year_field, years)), Some((semester_field, semesters))) = (year, sem) else { continue };
        let fields = form
            .select(&sel("input[name]"))
            .filter(|e| !e.value().attr("type").is_some_and(|t| t.eq_ignore_ascii_case("button")))
            .map(|e| (e.value().attr("name").unwrap().to_string(), e.value().attr("value").unwrap_or("").to_string()))
            .collect();
        return Some(TermPicker {
            action: form.value().attr("action").map(String::from),
            post: form.value().attr("method").is_some_and(|m| m.eq_ignore_ascii_case("post")),
            fields,
            year_field,
            semester_field,
            years,
            semesters,
        });
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;

    // Shapes copied from the live pages in S0; the data is fake.
    const LOGIN: &str = r#"<html><body>
      <form method="post" action="https://sis8.pup.edu.ph/student/">
        <input type="hidden" name="csrf_token" value="abc">
        <input type="hidden" name="csrf_token" value="abc">
        <input id="studno" name="studno"><select id="SelectMonth" name="SelectMonth"></select>
        <select id="SelectDay" name="SelectDay"></select><select id="SelectYear" name="SelectYear"></select>
        <input id="password" type="password" name="password">
        <input type="submit" name="Login" value="Sign in"><button type="button" name="x">?</button>
      </form></body></html>"#;

    const SCHEDULE: &str = r#"<table><thead><tr><th>#</th><th>Subject Code</th><th>Description</th>
      <th>Lec</th><th>Lab</th><th>Unit</th><th>Schedule</th></tr></thead><tbody>
      <tr><td>1</td><td>COMP 20073</td><td>Data Structures</td><td>2</td><td>1</td><td>3</td>
        <td>1N - BSCS 1-1N - T/F 02:00PM-04:00PM/01:30PM-04:30PM<br><font>Faculty: SANTOS, JUAN</font></td></tr>
      </tbody></table>"#;

    const GRADES: &str = r#"<dl><dt>Scholastic Status:</dt><dd> Regular </dd><dt>GPA</dt><dd>1.25</dd></dl>
      <table><thead><tr><th>#</th><th>Subject Code</th><th>Description</th><th>Faculty Name</th>
      <th>Units</th><th>Sect Code</th><th>Final Grade</th><th>Grade Status</th></tr></thead><tbody>
      <tr><td>1</td><td>COMP 20073</td><td>Data Structures</td><td>SANTOS, JUAN</td><td>3</td><td>1</td><td>1.25</td><td>Passed</td></tr>
      <tr><td>2</td><td>GEED 005</td><td>Purposive Communication</td><td>CRUZ, ANA</td><td>3</td><td>1</td><td></td><td></td></tr>
      </tbody></table>"#;

    #[test]
    fn login_form_submits_like_a_browser() {
        let f = login_form(LOGIN).unwrap();
        assert_eq!(f.action.as_deref(), Some("https://sis8.pup.edu.ph/student/"));
        let names: Vec<&str> = f.fields.iter().map(|(n, _)| n.as_str()).collect();
        assert_eq!(names, ["csrf_token", "csrf_token", "studno", "SelectMonth", "SelectDay", "SelectYear", "password", "Login"]);
        assert!(has_login_form(LOGIN));
        assert!(!has_login_form(SCHEDULE));
    }

    #[test]
    fn schedule_row_splits_line_and_faculty() {
        assert_eq!(
            schedule_rows(SCHEDULE),
            [ScheduleRow {
                subject_code: "COMP 20073".into(),
                description: "Data Structures".into(),
                unit: "3".into(),
                schedule_line: "1N - BSCS 1-1N - T/F 02:00PM-04:00PM/01:30PM-04:30PM".into(),
                faculty: "SANTOS, JUAN".into(),
            }]
        );
    }

    #[test]
    fn grades_rows_and_summary() {
        let (rows, summary) = grades(GRADES);
        assert_eq!(rows.len(), 2);
        assert_eq!(rows[0].final_grade, "1.25");
        assert_eq!(rows[1].final_grade, "");
        assert_eq!(rows[1].unit, "3");
        assert_eq!(summary.get("Scholastic Status").map(String::as_str), Some("Regular"));
        assert_eq!(summary.get("GPA").map(String::as_str), Some("1.25"));
    }

    #[test]
    fn term_picker_finds_selects_by_their_options() {
        let html = r#"<form method="post" action="/student/grades">
          <input type="hidden" name="csrf_token" value="t">
          <select name="sy"><option value="">--</option><option value="2025">2025-2026</option><option value="2026" selected>2026-2027</option></select>
          <select name="sem"><option value="1">First Semester</option><option value="2">Second Semester</option><option value="3">Summer</option></select>
          <input type="submit" name="view" value="View"></form>"#;
        let p = term_picker(html).unwrap();
        assert_eq!((p.year_field.as_str(), p.semester_field.as_str(), p.post), ("sy", "sem", true));
        assert_eq!(p.years, [("2026".into(), "2026-2027".into()), ("2025".into(), "2025-2026".into())]);
        assert_eq!(p.semesters.len(), 3);
        assert_eq!(p.fields, [("csrf_token".into(), "t".into()), ("view".into(), "View".into())]);
        assert_eq!(term_picker(GRADES), None);
    }

    #[test]
    fn missing_table_is_empty_not_a_crash() {
        assert!(schedule_rows("<p>nothing</p>").is_empty());
        assert_eq!(page_message(r#"<div class="modal-body"> Invalid  password </div>"#).as_deref(), Some("Invalid password"));
    }
}
