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

impl MabiniClient {
    /// Signs in with one credential POST. `student_number` may have dashes
    /// and capitals; eMabini's username is derived from it.
    pub async fn sign_in(student_number: &str, password: &str) -> Result<Self, Error> {
        let http = reqwest::Client::builder()
            .cookie_store(true)
            .redirect(Policy::custom(|a| if host::is_trusted(a.url()) && a.previous().len() < 10 { a.follow() } else { a.stop() }))
            .build()?;
        let login = format!("{BASE}/login/index.php");
        let page = http.get(&login).send().await?.error_for_status()?.text().await?;
        let token = parse::login_token(&page).ok_or_else(|| Error::Network("no login form on the eMabini page".into()))?;
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
        fn keep<T: Clone>(r: Result<Vec<T>, Error>, old: &[T]) -> Result<Vec<T>, Error> {
            match r {
                Err(Error::SignedOut) => Err(Error::SignedOut),
                Err(_) => Ok(old.to_vec()),
                Ok(v) => Ok(v),
            }
        }
        Ok(MabiniData {
            courses: keep(self.courses().await, &previous.courses)?,
            deadlines: keep(self.deadlines(now - 86_400, 50).await, &previous.deadlines)?,
            grades: keep(self.grades().await, &previous.grades)?,
            last_synced: Some(now as u64),
        })
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
