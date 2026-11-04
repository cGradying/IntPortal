//! eMabini, PUP Open University's Moodle learning portal (spec 012,
//! docs/specs/000-sis-data-map.md): sign in, then read courses, deadlines and
//! course grades. `parse` holds the pure readers; this file is the HTTP.
//!
//! The sign-in guard's `Ledger` applies here too (one POST per tap, 3 per 15
//! minutes); the shell keeps a separate ledger per portal.

pub mod parse;

use crate::sis::{host, Error};
use parse::{Course, CourseGrade, Deadline};
use reqwest::redirect::Policy;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

/// Everything read from eMabini in one sync, as kept on the phone.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct MabiniData {
    pub courses: Vec<Course>,
    pub deadlines: Vec<Deadline>,
    pub grades: Vec<CourseGrade>,
    /// Epoch seconds, written by the shell.
    pub last_synced: Option<u64>,
}

const BASE: &str = "https://emabini.pup.edu.ph";

/// One signed-in eMabini session. The cookie jar plus the session key.
pub struct MabiniClient {
    http: reqwest::Client,
    sesskey: String,
}

/// eMabini's login form, fetched with a GET that sends no credentials.
pub struct LoginPage {
    http: reqwest::Client,
    token: String,
}

impl LoginPage {
    pub async fn fetch() -> Result<Self, Error> {
        let http = reqwest::Client::builder()
            .cookie_store(true)
            .redirect(Policy::custom(|a| if host::is_trusted(a.url()) && a.previous().len() < 10 { a.follow() } else { a.stop() }))
            .build()?;
        let page = http.get(format!("{BASE}/login/index.php")).send().await?.error_for_status()?.text().await?;
        let token = parse::login_token(&page).ok_or_else(|| Error::Network("no login form on the eMabini page".into()))?;
        Ok(LoginPage { http, token })
    }

    /// The one credential POST. `student_number` may have dashes and
    /// capitals; eMabini's username is derived from it.
    pub async fn sign_in(self, student_number: &str, password: &str) -> Result<MabiniClient, Error> {
        let LoginPage { http, token } = self;
        let login = format!("{BASE}/login/index.php");
        let username = parse::username(student_number);
        let after = http
            .post(&login)
            .header("Referer", &login)
            .form(&[("anchor", ""), ("logintoken", token.as_str()), ("username", username.as_str()), ("password", password)])
            .send()
            .await?
            .text()
            .await?;
        if parse::has_login_form(&after) {
            return Err(Error::Rejected(
                parse::login_error(&after)
                    .unwrap_or_else(|| "Sign-in didn't go through. Check your student number and password.".into()),
            ));
        }
        let sesskey = parse::sesskey(&after).ok_or_else(|| Error::Network("eMabini gave no session key".into()))?;
        Ok(MabiniClient { http, sesskey })
    }
}

impl MabiniClient {
    async fn call(&self, method: &str, args: Value) -> Result<Value, Error> {
        let url = format!("{BASE}/lib/ajax/service.php?sesskey={}&info={method}", self.sesskey);
        let body = json!([{ "index": 0, "methodname": method, "args": args }]);
        let reply = self.http.post(url).header("Content-Type", "application/json").body(body.to_string()).send().await?.error_for_status()?.text().await?;
        parse::service_data(&reply)
    }

    /// One sync: courses, deadlines from yesterday on, and course grades. A
    /// session that expired fails the whole sync (the caller signs in again);
    /// any other failure keeps what `previous` had for that part.
    pub async fn sync(&self, now: i64, previous: &MabiniData) -> Result<MabiniData, Error> {
        combine(self.courses().await, self.deadlines(now - 86_400, 50).await, self.grades().await, previous, now)
    }

    pub async fn courses(&self) -> Result<Vec<Course>, Error> {
        let args = json!({ "offset": 0, "limit": 0, "classification": "all", "sort": "fullname", "customfieldname": "", "customfieldvalue": "" });
        let data = self.call("core_course_get_enrolled_courses_by_timeline_classification", args).await?;
        Ok(parse::courses(&data))
    }

    /// Action events (assignments, quizzes) due from `from` (epoch seconds), soonest first.
    pub async fn deadlines(&self, from: i64, limit: u32) -> Result<Vec<Deadline>, Error> {
        let data = self.call("core_calendar_get_action_events_by_timesort", json!({ "limitnum": limit, "timesortfrom": from })).await?;
        Ok(parse::deadlines(&data))
    }

    pub async fn grades(&self) -> Result<Vec<CourseGrade>, Error> {
        let page = self.http.get(format!("{BASE}/grade/report/overview/index.php")).send().await?.error_for_status()?.text().await?;
        if parse::has_login_form(&page) {
            return Err(Error::SignedOut);
        }
        Ok(parse::course_grades(&page))
    }
}

/// One sync's three reads into what the phone keeps. Nothing read at all
/// fails like a SIS sync does, rather than stamping old data as fresh.
fn combine(
    courses: Result<Vec<Course>, Error>,
    deadlines: Result<Vec<Deadline>, Error>,
    grades: Result<Vec<CourseGrade>, Error>,
    previous: &MabiniData,
    now: i64,
) -> Result<MabiniData, Error> {
    if [courses.as_ref().err(), deadlines.as_ref().err(), grades.as_ref().err()].contains(&Some(&Error::SignedOut)) {
        return Err(Error::SignedOut);
    }
    let (courses, deadlines, grades) = match (courses, deadlines, grades) {
        (Err(e), Err(_), Err(_)) => return Err(e),
        all => all,
    };
    Ok(MabiniData {
        courses: courses.unwrap_or_else(|_| previous.courses.clone()),
        deadlines: deadlines.unwrap_or_else(|_| previous.deadlines.clone()),
        grades: grades.unwrap_or_else(|_| previous.grades.clone()),
        last_synced: Some(now as u64),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn old() -> MabiniData {
        MabiniData { grades: vec![CourseGrade { course_id: Some(1), name: "OOP".into(), grade: None }], last_synced: Some(500), ..Default::default() }
    }

    #[test]
    fn c128_2_every_fetch_failing_fails_the_sync() {
        let down = || Err::<Vec<()>, _>(Error::Network("down".into()));
        let r = combine(down().map(|_| vec![]), down().map(|_| vec![]), down().map(|_| vec![]), &old(), 1000);
        assert_eq!(r, Err(Error::Network("down".into())), "no fresh last_synced over old data");
    }

    #[test]
    fn one_failed_part_keeps_the_old_part() {
        let r = combine(Ok(vec![]), Ok(vec![]), Err(Error::Network("down".into())), &old(), 1000).unwrap();
        assert_eq!(r.grades, old().grades);
        assert_eq!(r.last_synced, Some(1000));
    }

    #[test]
    fn signed_out_fails_the_sync() {
        assert_eq!(combine(Ok(vec![]), Err(Error::SignedOut), Ok(vec![]), &old(), 1000), Err(Error::SignedOut));
    }
}
