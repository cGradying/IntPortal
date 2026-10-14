//! Pure readers for eMabini (PUP Open University's Moodle). The pages and
//! JSON shapes are in docs/specs/000-sis-data-map.md. Nothing here touches
//! the network, so fixtures test all of it.

use crate::sis::Error;
use regex::Regex;
use scraper::{Html, Selector};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::sync::LazyLock;

fn sel(s: &str) -> Selector {
    Selector::parse(s).unwrap()
}

fn text(el: scraper::ElementRef) -> String {
    el.text().collect::<String>().split_whitespace().collect::<Vec<_>>().join(" ")
}

/// The hidden `logintoken` in the login form; the POST needs it back.
pub fn login_token(html: &str) -> Option<String> {
    Html::parse_document(html).select(&sel("input[name=logintoken]")).next()?.value().attr("value").map(String::from)
}

pub fn has_login_form(html: &str) -> bool {
    Html::parse_document(html).select(&sel("input[name=logintoken]")).next().is_some()
}

/// Moodle's own error text on a failed login, if the page shows one.
pub fn login_error(html: &str) -> Option<String> {
    Html::parse_document(html).select(&sel(".loginerrors, .alert-danger")).map(text).find(|t| !t.is_empty())
}

static SESSKEY: LazyLock<Regex> = LazyLock::new(|| Regex::new(r#""sesskey":"([A-Za-z0-9]+)""#).unwrap());

/// The per-session key every JSON call needs, from the page's inline config.
pub fn sesskey(html: &str) -> Option<String> {
    SESSKEY.captures(html).map(|c| c[1].to_string())
}

/// eMabini's username for a student number: lowercase, dashes removed.
pub fn username(student_number: &str) -> String {
    crate::portal::mabini_username(student_number)
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Course {
    pub id: u64,
    pub fullname: String,
    /// `fullname` split on `_`: `Subject_Term_Section`. Empty when it doesn't fit.
    pub subject: String,
    pub term: String,
    pub section: String,
    pub start: i64,
    pub end: i64,
    /// Percent complete, when the course tracks it.
    pub progress: Option<f64>,
    pub url: String,
}

/// `Subject_First Sem 2627_BSIT 1-A` into its three parts. A name that
/// doesn't have three parts keeps the whole name as the subject.
pub fn split_course_name(fullname: &str) -> (String, String, String) {
    let parts: Vec<&str> = fullname.split('_').map(str::trim).collect();
    match parts[..] {
        [subject, term, section] => (subject.into(), term.into(), section.into()),
        _ => (fullname.trim().into(), String::new(), String::new()),
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Deadline {
    pub id: u64,
    pub name: String,
    pub course_id: u64,
    pub course: String,
    /// Moodle's module, such as `assign` or `quiz`.
    pub kind: String,
    /// Epoch seconds.
    pub due: i64,
    pub overdue: bool,
    pub url: String,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct CourseGrade {
    pub course_id: Option<u64>,
    pub name: String,
    /// `None` while the course shows `-`.
    pub grade: Option<String>,
}

/// The `data` of the first reply from `/lib/ajax/service.php`.
pub fn service_data(body: &str) -> Result<Value, Error> {
    let v: Value = serde_json::from_str(body).map_err(|e| Error::Network(format!("unreadable eMabini reply: {e}")))?;
    let first = v.get(0).ok_or_else(|| Error::Network("empty eMabini reply".into()))?;
    if first["error"].as_bool().unwrap_or(false) || first.get("exception").is_some() {
        let code = first["exception"]["errorcode"].as_str().unwrap_or("");
        return Err(if code == "servicerequireslogin" || code == "invalidsesskey" {
            Error::SignedOut
        } else {
            Error::Network(format!("eMabini refused the request ({code})"))
        });
    }
    Ok(first["data"].clone())
}

pub fn courses(data: &Value) -> Vec<Course> {
    data["courses"]
        .as_array()
        .into_iter()
        .flatten()
        .filter_map(|c| {
            let fullname = c["fullname"].as_str()?.to_string();
            let (subject, term, section) = split_course_name(&fullname);
            Some(Course {
                id: c["id"].as_u64()?,
                fullname,
                subject,
                term,
                section,
                start: c["startdate"].as_i64().unwrap_or(0),
                end: c["enddate"].as_i64().unwrap_or(0),
                progress: c["progress"].as_f64(),
                url: c["viewurl"].as_str().unwrap_or("").into(),
            })
        })
        .collect()
}

pub fn deadlines(data: &Value) -> Vec<Deadline> {
    let mut out: Vec<Deadline> = data["events"]
        .as_array()
        .into_iter()
        .flatten()
        .filter_map(|e| {
            Some(Deadline {
                id: e["id"].as_u64()?,
                name: e["name"].as_str()?.into(),
                course_id: e["course"]["id"].as_u64().unwrap_or(0),
                course: e["course"]["fullname"].as_str().unwrap_or("").into(),
                kind: e["modulename"].as_str().unwrap_or("").into(),
                due: e["timesort"].as_i64()?,
                overdue: e["overdue"].as_bool().unwrap_or(false),
                url: e["url"].as_str().unwrap_or("").into(),
            })
        })
        .collect();
    out.sort_by_key(|d| d.due);
    out
}

static COURSE_ID: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"[?&]id=(\d+)").unwrap());

/// The grades overview table, `#overview-grade`: one row per course.
pub fn course_grades(html: &str) -> Vec<CourseGrade> {
    let doc = Html::parse_document(html);
    let Some(table) = doc.select(&sel("#overview-grade")).next() else { return vec![] };
    table
        .select(&sel("tbody tr"))
        .filter_map(|row| {
            let cells: Vec<_> = row.select(&sel("td")).collect();
            let name = text(*cells.first()?);
            let grade = cells.get(1).map(|c| text(*c)).filter(|g| !g.is_empty() && g != "-");
            let course_id = cells
                .first()?
                .select(&sel("a[href]"))
                .next()
                .and_then(|a| COURSE_ID.captures(a.value().attr("href")?))
                .and_then(|c| c[1].parse().ok());
            (!name.is_empty()).then_some(CourseGrade { course_id, name, grade })
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    const LOGIN: &str = r#"<form action="/login/index.php" method="post"><input type="hidden" name="logintoken" value="TOK123">
        <input name="username" id="username"><input type="password" name="password"></form>"#;

    #[test]
    fn reads_the_login_form() {
        assert_eq!(login_token(LOGIN).as_deref(), Some("TOK123"));
        assert!(has_login_form(LOGIN));
        assert!(!has_login_form("<html><body>Dashboard</body></html>"));
    }

    #[test]
    fn reads_the_failed_login_message() {
        let page = r#"<div class="alert alert-danger loginerrors"> Invalid login, please try again </div>"#;
        assert_eq!(login_error(page).as_deref(), Some("Invalid login, please try again"));
        assert_eq!(login_error(LOGIN), None);
    }

    #[test]
    fn finds_the_sesskey() {
        let page = r#"<script>M.cfg = {"wwwroot":"https:\/\/x","sesskey":"AbC123xyz","themerev":1};</script>"#;
        assert_eq!(sesskey(page).as_deref(), Some("AbC123xyz"));
        assert_eq!(sesskey("<html></html>"), None);
    }

    #[test]
    fn splits_course_names() {
        assert_eq!(
            split_course_name("Mathematics in the Modern World/Matematika sa Makabagong Daigdig_First Sem 2627_BSIT 1-A"),
            ("Mathematics in the Modern World/Matematika sa Makabagong Daigdig".into(), "First Sem 2627".into(), "BSIT 1-A".into())
        );
        assert_eq!(split_course_name("Orientation"), ("Orientation".into(), String::new(), String::new()));
    }

    #[test]
    fn reads_courses() {
        let body = r#"[{"error":false,"data":{"courses":[
            {"id":11,"fullname":"Filipino_First Sem 2627_BSIT 1-A","startdate":100,"enddate":900,"progress":12.5,"viewurl":"https://e/course/view.php?id=11"},
            {"id":12,"fullname":"PE","startdate":0,"enddate":0,"progress":null,"viewurl":""},
            {"fullname":"no id"}]}}]"#;
        let c = courses(&service_data(body).unwrap());
        assert_eq!(c.len(), 2);
        assert_eq!((c[0].id, c[0].subject.as_str(), c[0].term.as_str(), c[0].section.as_str()), (11, "Filipino", "First Sem 2627", "BSIT 1-A"));
        assert_eq!(c[0].progress, Some(12.5));
        assert_eq!(c[1].progress, None);
        assert_eq!(c[1].subject, "PE");
    }

    #[test]
    fn reads_deadlines_soonest_first() {
        let body = r#"[{"error":false,"data":{"events":[
            {"id":2,"name":"PETA 2 is due","modulename":"assign","timesort":2000,"overdue":false,"url":"https://e/mod/assign/view.php?id=2","course":{"id":11,"fullname":"Filipino_x_y"}},
            {"id":1,"name":"PETA 1 is due","modulename":"assign","timesort":1000,"overdue":true,"url":"https://e/mod/assign/view.php?id=1","course":{"id":11,"fullname":"Filipino_x_y"}}]}}]"#;
        let d = deadlines(&service_data(body).unwrap());
        assert_eq!(d.iter().map(|d| d.id).collect::<Vec<_>>(), [1, 2]);
        assert!(d[0].overdue && !d[1].overdue);
        assert_eq!((d[0].kind.as_str(), d[0].course_id), ("assign", 11));
    }

    #[test]
    fn a_session_error_means_signed_out() {
        let expired = r#"[{"error":true,"exception":{"errorcode":"servicerequireslogin","message":"x"}}]"#;
        assert_eq!(service_data(expired), Err(Error::SignedOut));
        assert!(matches!(service_data("not json"), Err(Error::Network(_))));
    }

    #[test]
    fn reads_the_grades_table() {
        let page = r#"<table id="overview-grade"><thead><tr><th>Course name</th><th>Grade</th></tr></thead><tbody>
            <tr><td class="cell c0"><a href="https://e/course/user.php?mode=grade&amp;id=11&amp;user=5">Filipino_First Sem 2627_BSIT 1-A</a></td><td class="cell c1">1.75</td></tr>
            <tr><td class="cell c0"><a href="https://e/course/user.php?mode=grade&amp;id=12&amp;user=5">PE_First Sem 2627_BSIT 1-A</a></td><td class="cell c1">-</td></tr></tbody></table>"#;
        let g = course_grades(page);
        assert_eq!(g.len(), 2);
        assert_eq!((g[0].course_id, g[0].grade.as_deref()), (Some(11), Some("1.75")));
        assert_eq!((g[1].course_id, g[1].grade.as_deref()), (Some(12), None));
        assert!(course_grades("<html></html>").is_empty());
    }
}
