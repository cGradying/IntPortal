//! The login guard. A student was locked out of their SIS account by too
//! many login requests, so signing in is one credential POST per tap, on a
//! host a plain GET has shown to be up, at most 3 per 15 minutes, and never
//! again by itself after a rejected password (spec 011, C11 to C16). The
//! numbers and the refusal text come from the portal (spec 050 C1, C5).

use super::{host, Credentials, Error};
use crate::portal::{Limits, Portal, SIS};
use crate::schedule::ScheduleRow;
use serde::{Deserialize, Serialize};

/// What the guard needs from a SIS host; `SisClient` is the real one.
#[allow(async_fn_in_trait)] // only used with concrete types, so `Send` is checked at the call site
pub trait Sis {
    /// A GET of the login page. Sends no credentials.
    async fn probe(&self) -> Result<(), Error>;
    /// The one credential POST.
    async fn sign_in(&self, c: &Credentials) -> Result<(), Error>;
    async fn schedule(&self) -> Result<Vec<ScheduleRow>, Error>;
}

/// Sign-in attempts in the last 15 minutes, and whether the SIS turned the
/// saved login down. Kept on the phone, outside any student's store, so a
/// restart doesn't reset it.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Ledger {
    attempts: Vec<u64>,
    rejected: bool,
    /// When the saved ledger was found unreadable: no tries for one window
    /// from then, rather than a fresh count (050 C2).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    broken_at: Option<u64>,
    #[serde(skip, default = "sis_limits")]
    limits: Limits,
    #[serde(skip, default = "sis_again")]
    again: &'static str,
}

fn sis_limits() -> Limits {
    SIS.limits
}

fn sis_again() -> &'static str {
    SIS.rejected_again
}

impl Default for Ledger {
    fn default() -> Self {
        Ledger::new(&SIS)
    }
}

impl Ledger {
    pub fn new(portal: &Portal) -> Ledger {
        Ledger { attempts: vec![], rejected: false, broken_at: None, limits: portal.limits, again: portal.rejected_again }
    }

    /// The ledger saved on the phone, `None` when there is no file yet. A file
    /// that doesn't parse fails closed: no tries until a window passes.
    pub fn load(saved: Option<&str>, now: u64, portal: &Portal) -> Ledger {
        let fresh = Ledger::new(portal);
        match saved.map(serde_json::from_str::<Ledger>) {
            None => fresh,
            Some(Ok(l)) => Ledger { limits: portal.limits, again: portal.rejected_again, ..l },
            Some(Err(_)) => Ledger { broken_at: Some(now), ..fresh },
        }
    }

    fn window(&self) -> u64 {
        u64::from(self.limits.window_secs)
    }

    fn live(&self, now: u64) -> impl Iterator<Item = &u64> {
        let w = self.window();
        self.attempts.iter().filter(move |&&a| a + w > now)
    }

    fn broken_until(&self, now: u64) -> Option<u64> {
        self.broken_at.map(|b| b + self.window()).filter(|&until| until > now)
    }

    pub fn tries_left(&self, now: u64) -> usize {
        if self.broken_until(now).is_some() {
            return 0;
        }
        usize::from(self.limits.attempts).saturating_sub(self.live(now).count())
    }

    /// When the next try frees up, if none is left now (epoch seconds).
    pub fn retry_at(&self, now: u64) -> Option<u64> {
        if self.tries_left(now) > 0 {
            return None;
        }
        let oldest = self.live(now).min().map(|a| a + self.window());
        self.broken_until(now).max(oldest)
    }

    /// Whether the SIS turned the saved login down and it hasn't been edited since.
    pub fn rejected(&self) -> bool {
        self.rejected
    }

    fn precheck(&mut self, auto: bool) -> Result<(), Error> {
        if auto && self.rejected {
            return Err(Error::Rejected(self.again.into()));
        }
        Ok(())
    }

    /// Remembers whether the portal turned the login down. Only a sign-in that went
    /// through clears it: a tap that never reached the portal, or a dropped answer,
    /// leaves the rejected login rejected, so a background sync can't send it again
    /// and add to the portal's own failed-login count.
    fn record<T>(&mut self, result: &Result<T, Error>) {
        match result {
            Ok(_) => self.rejected = false,
            Err(Error::Rejected(_)) => self.rejected = true,
            Err(_) => {}
        }
    }

    fn spend(&mut self, now: u64) -> Result<(), Error> {
        if let Some(retry_at) = self.retry_at(now) {
            return Err(Error::TooManyTries { retry_at });
        }
        let w = self.window();
        self.attempts.retain(|&a| a + w > now);
        self.attempts.push(now);
        self.broken_at = None;
        Ok(())
    }

    /// Spends a try and keeps it on the phone before any credential is sent:
    /// a try that can't be saved is not made (050 C3).
    fn spend_saved(&mut self, now: u64, save: &mut impl FnMut(&Ledger) -> Result<(), String>) -> Result<(), Error> {
        self.spend(now)?;
        save(self).map_err(|_| Error::LedgerUnsaved)
    }
}

/// For a portal with one host (eMabini): `page` is the GET of its login
/// form, and a try is spent only once it answered, right before the one
/// credential POST. `auto` and `save` as in `sign_in_guarded`.
pub async fn post_once<P, T, Fut: std::future::Future<Output = Result<T, Error>>>(
    ledger: &mut Ledger,
    now: u64,
    auto: bool,
    mut save: impl FnMut(&Ledger) -> Result<(), String>,
    page: impl std::future::Future<Output = Result<P, Error>>,
    post: impl FnOnce(P) -> Fut,
) -> Result<T, Error> {
    ledger.precheck(auto)?;
    let page = page.await?;
    ledger.spend_saved(now, &mut save)?;
    let r = post(page).await;
    ledger.record(&r);
    let _ = save(ledger); // the try is already counted; the result's own error matters more
    r
}

/// Picks a live host with GETs, then makes exactly one credential POST on it.
///
/// `auto` is true for a background sign-in from the saved login (sync); it
/// refuses to run after a rejection. A tap on Sign in passes false, which
/// clears that rejection first. `save` writes the ledger to the phone; it runs
/// once before the POST (no POST if it fails) and once after.
pub async fn sign_in_guarded<C: Sis>(
    make: impl Fn(&str) -> Result<C, Error>,
    c: &Credentials,
    remembered: Option<&str>,
    ledger: &mut Ledger,
    now: u64,
    auto: bool,
    mut save: impl FnMut(&Ledger) -> Result<(), String>,
) -> Result<(C, Vec<ScheduleRow>), Error> {
    ledger.precheck(auto)?;
    let mut down = Error::Network("no SIS server answered".into());
    let mut live = None;
    for h in host::candidates(remembered) {
        let client = make(&h)?;
        match client.probe().await {
            Ok(()) => {
                live = Some(client);
                break;
            }
            Err(e) => down = e,
        }
    }
    let client = live.ok_or(down)?;
    ledger.spend_saved(now, &mut save)?;
    let signed_in = client.sign_in(c).await;
    ledger.record(&signed_in);
    let _ = save(ledger);
    signed_in?;
    // Signed in with no schedule (011 C10, C15): a tap keeps this one session and lets the
    // student in; a background sync refuses it, so it never wipes the schedule it has.
    match client.schedule().await? {
        rows if rows.is_empty() && auto => Err(Error::NoSchedule),
        rows => Ok((client, rows)),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::cell::RefCell;
    use std::rc::Rc;

    #[derive(Default)]
    struct Log {
        probes: Vec<String>,
        posts: Vec<String>,
    }

    struct Fake {
        host: String,
        up: bool,
        reject: bool,
        post_fails: bool,
        rows: usize,
        log: Rc<RefCell<Log>>,
    }

    impl Sis for Fake {
        async fn probe(&self) -> Result<(), Error> {
            self.log.borrow_mut().probes.push(self.host.clone());
            if self.up { Ok(()) } else { Err(Error::Network("down".into())) }
        }
        async fn sign_in(&self, _: &Credentials) -> Result<(), Error> {
            self.log.borrow_mut().posts.push(self.host.clone());
            if self.reject {
                Err(Error::Rejected("bad".into()))
            } else if self.post_fails {
                Err(Error::Network("dropped".into()))
            } else {
                Ok(())
            }
        }
        async fn schedule(&self) -> Result<Vec<ScheduleRow>, Error> {
            Ok(vec![ScheduleRow::default(); self.rows])
        }
    }

    fn creds() -> Credentials {
        Credentials { student_number: "2024-00001-MN-0".into(), birth_month: 1, birth_day: 2, birth_year: 2005, password: "x".into() }
    }

    /// Hosts in `down` don't answer the probe.
    fn run(down: &[&str], reject: bool, post_fails: bool, rows: usize, ledger: &mut Ledger, now: u64, auto: bool) -> (Result<usize, Error>, Log) {
        let log = Rc::new(RefCell::new(Log::default()));
        let l = log.clone();
        let down: Vec<String> = down.iter().map(|s| s.to_string()).collect();
        let make = move |h: &str| Ok(Fake { host: h.into(), up: !down.iter().any(|d| d == h), reject, post_fails, rows, log: l.clone() });
        let r = pollster(sign_in_guarded(make, &creds(), None, ledger, now, auto, |_| Ok(()))).map(|(_, rows)| rows.len());
        let log = Rc::try_unwrap(log).ok().unwrap().into_inner();
        (r, log)
    }

    fn pollster<F: std::future::Future>(f: F) -> F::Output {
        tokio::runtime::Builder::new_current_thread().build().unwrap().block_on(f)
    }

    #[test]
    fn one_post_on_the_first_live_host() {
        let mut l = Ledger::default();
        let (r, log) = run(&["sis8.pup.edu.ph"], false, false, 3, &mut l, 1000, false);
        assert_eq!(r, Ok(3));
        assert_eq!(log.probes, ["sis8.pup.edu.ph", "sis1.pup.edu.ph"]);
        assert_eq!(log.posts, ["sis1.pup.edu.ph"]);
    }

    #[test]
    fn no_host_up_posts_nothing_and_spends_nothing() {
        let mut l = Ledger::default();
        let (r, log) = run(&["sis8.pup.edu.ph", "sis1.pup.edu.ph", "sis2.pup.edu.ph"], false, false, 3, &mut l, 1000, false);
        assert!(matches!(r, Err(Error::Network(_))));
        assert!(log.posts.is_empty());
        assert_eq!(l.tries_left(1000), 3);
    }

    #[test]
    fn c10_empty_schedule_lets_a_tap_in_and_is_not_retried_on_another_host() {
        let mut l = Ledger::default();
        let (r, log) = run(&[], false, false, 0, &mut l, 1000, false);
        assert_eq!(r, Ok(0), "a tap gets the open session, with no rows");
        assert_eq!(log.posts.len(), 1);
    }

    #[test]
    fn c10_a_sync_never_adopts_an_empty_schedule() {
        let mut l = Ledger::default();
        let (r, log) = run(&[], false, false, 0, &mut l, 1000, true);
        assert_eq!(r, Err(Error::NoSchedule));
        assert_eq!(log.posts.len(), 1);
    }

    #[test]
    fn a_dropped_post_is_not_retried_and_still_counts() {
        let mut l = Ledger::default();
        let (r, log) = run(&[], false, true, 3, &mut l, 1000, false);
        assert!(matches!(r, Err(Error::Network(_))));
        assert_eq!(log.posts.len(), 1);
        assert_eq!(l.tries_left(1000), 2);
    }

    #[test]
    fn a_rejection_stops_sync_until_the_login_is_edited() {
        let mut l = Ledger::default();
        let (r, _) = run(&[], true, false, 3, &mut l, 1000, false);
        assert!(matches!(r, Err(Error::Rejected(_))));
        assert!(l.rejected());
        let (r, log) = run(&[], false, false, 3, &mut l, 1100, true);
        assert_eq!(r, Err(Error::Rejected(SIS.rejected_again.into())));
        assert!(log.probes.is_empty() && log.posts.is_empty());
        // The student edits the login and taps Sign in: allowed again.
        let (r, _) = run(&[], false, false, 3, &mut l, 1200, false);
        assert_eq!(r, Ok(3));
        assert!(!l.rejected());
    }

    #[test]
    fn three_tries_per_fifteen_minutes() {
        let mut l = Ledger::default();
        for t in [1000, 1100, 1200] {
            assert_eq!(run(&[], false, false, 3, &mut l, t, false).0, Ok(3));
        }
        assert_eq!(l.tries_left(1200), 0);
        let (r, log) = run(&[], false, false, 3, &mut l, 1300, false);
        assert_eq!(r, Err(Error::TooManyTries { retry_at: 1000 + 900 }));
        assert!(log.posts.is_empty());
        // The oldest try ages out of the window.
        assert_eq!(run(&[], false, false, 3, &mut l, 1000 + 900, false).0, Ok(3));
    }

    #[test]
    fn the_ledger_survives_a_restart() {
        let mut l = Ledger::default();
        let _ = run(&[], true, false, 3, &mut l, 1000, false);
        let back: Ledger = serde_json::from_str(&serde_json::to_string(&l).unwrap()).unwrap();
        assert_eq!(back, l);
        assert_eq!(back.tries_left(1000), 2);
    }

    fn once(l: &mut Ledger, now: u64, auto: bool, page_up: bool, post: Result<(), Error>) -> (Result<(), Error>, usize) {
        let posts = RefCell::new(0);
        let r = pollster(post_once(
            l,
            now,
            auto,
            |_| Ok(()),
            async move { if page_up { Ok(()) } else { Err(Error::Network("down".into())) } },
            |()| async {
                *posts.borrow_mut() += 1;
                post
            },
        ));
        (r, posts.into_inner())
    }

    #[test]
    fn post_once_guards_a_single_host_portal() {
        let mut l = Ledger::default();
        assert_eq!(once(&mut l, 1000, false, true, Err(Error::Rejected("bad".into()))), (Err(Error::Rejected("bad".into())), 1));
        assert!(l.rejected());
        assert_eq!(once(&mut l, 1100, true, true, Ok(())), (Err(Error::Rejected(SIS.rejected_again.into())), 0));
        assert_eq!(l.tries_left(1100), 2, "a refused auto try spends nothing");
        assert_eq!(once(&mut l, 1200, false, true, Ok(())), (Ok(()), 1));
        assert!(!l.rejected(), "the tap cleared it and a success leaves it clear");
    }

    #[test]
    fn a_tap_that_never_signs_in_keeps_the_rejection() {
        let mut l = Ledger::default();
        let _ = once(&mut l, 1000, false, true, Err(Error::Rejected("bad".into())));
        // The tap finds the portal down, then its answer is lost: still rejected either way.
        assert!(matches!(once(&mut l, 1100, false, false, Ok(())).0, Err(Error::Network(_))));
        assert!(l.rejected());
        assert!(matches!(once(&mut l, 1200, false, true, Err(Error::Network("dropped".into()))).0, Err(Error::Network(_))));
        assert!(l.rejected());
        // So the background sync still sends nothing.
        assert_eq!(once(&mut l, 1300, true, true, Ok(())), (Err(Error::Rejected(SIS.rejected_again.into())), 0));
    }

    #[test]
    fn c128_3_page_down_spends_no_try() {
        let mut l = Ledger::default();
        for now in [1000, 1001, 1002, 1003] {
            assert_eq!(once(&mut l, now, true, false, Ok(())), (Err(Error::Network("down".into())), 0));
        }
        assert_eq!(l.tries_left(1003), 3, "no credential was sent, so no try is spent");
    }

    #[test]
    fn post_once_stops_at_the_limit_without_posting() {
        let mut l = Ledger::default();
        for now in [1000, 1001, 1002] {
            assert_eq!(once(&mut l, now, false, true, Err(Error::Network("dropped".into()))).1, 1);
        }
        assert_eq!(once(&mut l, 1003, false, true, Ok(())), (Err(Error::TooManyTries { retry_at: 1900 }), 0));
    }

    #[test]
    fn c1_the_numbers_come_from_the_portal() {
        let p = Portal { limits: Limits { attempts: 1, window_secs: 60 }, ..SIS };
        let mut l = Ledger::new(&p);
        assert_eq!(l.tries_left(1000), 1);
        let _ = run(&[], false, true, 3, &mut l, 1000, false);
        assert_eq!(l.retry_at(1000), Some(1060));
    }

    #[test]
    fn c2_a_broken_ledger_fails_closed_for_one_window() {
        let l = Ledger::load(Some("{not json"), 5000, &SIS);
        assert_eq!(l.tries_left(5000), 0);
        assert_eq!(l.retry_at(5000), Some(5900));
        assert_eq!(l.tries_left(5900), 3, "a full window later it counts again");
        let saved = serde_json::to_string(&l).unwrap();
        assert_eq!(Ledger::load(Some(&saved), 5100, &SIS).tries_left(5100), 0, "a restart keeps it closed");
        assert_eq!(Ledger::load(None, 5000, &SIS).tries_left(5000), 3, "no file yet is a fresh ledger");
    }

    #[test]
    fn c3_a_try_that_cant_be_saved_sends_nothing() {
        let log = Rc::new(RefCell::new(Log::default()));
        let l2 = log.clone();
        let make = move |h: &str| Ok(Fake { host: h.into(), up: true, reject: false, post_fails: false, rows: 3, log: l2.clone() });
        let mut l = Ledger::default();
        let r = pollster(sign_in_guarded(make, &creds(), None, &mut l, 1000, false, |_| Err("disk full".into())));
        assert_eq!(r.map(|_| ()), Err(Error::LedgerUnsaved));
        assert!(log.borrow().posts.is_empty());
        let mut posts = 0;
        let r = pollster(post_once(&mut Ledger::default(), 1000, false, |_| Err("disk full".into()), async { Ok(()) }, |()| {
            posts += 1;
            async { Ok(()) }
        }));
        assert_eq!(r, Err(Error::LedgerUnsaved));
        assert_eq!(posts, 0);
    }

    #[test]
    fn c5_the_refusal_names_the_portal() {
        let mut l = Ledger::new(&crate::portal::MABINI);
        let _ = once(&mut l, 1000, false, true, Err(Error::Rejected("bad".into())));
        let (r, _) = once(&mut l, 1100, true, true, Ok(()));
        assert_eq!(r, Err(Error::Rejected(crate::portal::MABINI.rejected_again.into())));
        assert!(!crate::portal::MABINI.rejected_again.contains("birthdate"));
    }
}
