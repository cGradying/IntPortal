use super::host;
use super::scrape;
use super::{Credentials, Error};
use crate::grades::{GradeReport, GradeRow};
use crate::schedule::ScheduleRow;
use reqwest::redirect::Policy;
use std::collections::BTreeMap;

/// One signed-in session on one SIS host. The cookie jar is the session.
pub struct SisClient {
    http: reqwest::Client,
    host: String,
}

impl SisClient {
    pub fn new(host: &str) -> Result<Self, Error> {
        if !host::is_candidate(host) {
            return Err(Error::UntrustedHost(host.into()));
        }
        let http = reqwest::Client::builder()
            .cookie_store(true)
            .redirect(Policy::custom(|a| {
                if host::is_trusted(a.url()) && a.previous().len() < 10 {
                    a.follow()
                } else {
                    a.stop()
                }
            }))
            .build()?;
        Ok(SisClient { http, host: host.into() })
    }

    pub fn host(&self) -> &str {
        &self.host
    }

    fn url(&self, path: &str) -> String {
        format!("https://{}/student/{path}", self.host)
    }

    async fn get(&self, path: &str) -> Result<String, Error> {
        Ok(self.http.get(self.url(path)).send().await?.error_for_status()?.text().await?)
    }

    /// A plain GET: is this host up and serving the login form? Sends no
    /// credentials, so it can be repeated freely.
    pub async fn probe(&self) -> Result<(), Error> {
        let page = self.get("").await?;
        if scrape::has_login_form(&page) {
            Ok(())
        } else {
            Err(Error::Network("no login form on the SIS page".into()))
        }
    }

    /// Signed in means the login form is gone after the POST. The old app's
    /// logout-link marker matches nothing on the live site (#4).
    pub async fn sign_in(&self, c: &Credentials) -> Result<(), Error> {
        let page = self.get("").await?;
        let form = scrape::login_form(&page).ok_or_else(|| Error::Network("no login form on the SIS page".into()))?;
        let action = reqwest::Url::parse(&self.url(""))
            .and_then(|base| base.join(form.action.as_deref().unwrap_or("")))
            .map_err(|e| Error::Network(e.to_string()))?;
        if !host::is_trusted(&action) {
            return Err(Error::UntrustedHost(action.to_string()));
        }

        let values = [
            ("studno", c.student_number.clone()),
            ("SelectMonth", c.birth_month.to_string()),
            ("SelectDay", c.birth_day.to_string()),
            ("SelectYear", c.birth_year.to_string()),
            ("password", c.password.clone()),
        ];
        let mut fields = form.fields;
        for (name, value) in values {
            match fields.iter_mut().find(|(n, _)| n == name) {
                Some(f) => f.1 = value,
                None => fields.push((name.into(), value)),
            }
        }

        let after = self.http.post(action).header("Referer", self.url("")).form(&fields).send().await?.text().await?;
        if scrape::has_login_form(&after) {
            let msg = scrape::page_message(&after)
                .unwrap_or_else(|| "Sign-in didn't go through. Check your student number, birthdate and password.".into());
            return Err(Error::Rejected(msg));
        }
        Ok(())
    }

    pub async fn schedule(&self) -> Result<Vec<ScheduleRow>, Error> {
        let page = self.get("schedule").await?;
        if scrape::has_login_form(&page) {
            return Err(Error::SignedOut);
        }
        Ok(scrape::schedule_rows(&page))
    }

    pub async fn grades(&self) -> Result<(Vec<GradeRow>, BTreeMap<String, String>), Error> {
        let page = self.get("grades").await?;
        if scrape::has_login_form(&page) {
            return Err(Error::SignedOut);
        }
        Ok(scrape::grades(&page))
    }
}

impl SisClient {
    /// Every past term's grades, oldest first. A term that fails or has no
    /// posted grades is skipped, never fatal to the rest.
    pub async fn grade_history(&self) -> Result<Vec<GradeReport>, Error> {
        let page = self.get("grades").await?;
        if scrape::has_login_form(&page) {
            return Err(Error::SignedOut);
        }
        let Some(p) = scrape::term_picker(&page) else { return Ok(vec![]) };
        let action = reqwest::Url::parse(&self.url("grades"))
            .and_then(|base| base.join(p.action.as_deref().unwrap_or("")))
            .map_err(|e| Error::Network(e.to_string()))?;
        if !host::is_trusted(&action) {
            return Err(Error::UntrustedHost(action.to_string()));
        }
        let mut out = vec![];
        for (year, year_label) in &p.years {
            for (sem, sem_label) in &p.semesters {
                let mut fields = p.fields.clone();
                fields.push((p.year_field.clone(), year.clone()));
                fields.push((p.semester_field.clone(), sem.clone()));
                let req = if p.post { self.http.post(action.clone()).form(&fields) } else { self.http.get(action.clone()).query(&fields) };
                let Ok(resp) = req.send().await else { continue };
                let Ok(html) = resp.text().await else { continue };
                let (rows, summary) = scrape::grades(&html);
                let report = GradeReport {
                    subjects: crate::grades::parse(&rows),
                    summary,
                    school_year: Some(year_label.clone()),
                    semester: Some(sem_label.clone()),
                };
                if report.has_posted_grades() {
                    out.push(report);
                }
            }
        }
        out.sort_by_key(|r| r.term_order());
        Ok(out)
    }
}

impl super::guard::Sis for SisClient {
    async fn probe(&self) -> Result<(), Error> {
        SisClient::probe(self).await
    }
    async fn sign_in(&self, c: &Credentials) -> Result<(), Error> {
        SisClient::sign_in(self, c).await
    }
    async fn schedule(&self) -> Result<Vec<ScheduleRow>, Error> {
        SisClient::schedule(self).await
    }
}
