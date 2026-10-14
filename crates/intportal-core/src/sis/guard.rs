//! The login guard. A student was locked out of their SIS account by too
//! many login requests, so signing in is one credential POST per tap, on a
//! host a plain GET has shown to be up, at most 3 per 15 minutes, and never
//! again by itself after a rejected password (spec 011, C11 to C16).

use super::{host, Credentials, Error};
use crate::schedule::ScheduleRow;
use serde::{Deserialize, Serialize};

// ponytail: same numbers as `portal::Limits` for SIS; read them from there once the registry lands.
pub const MAX_ATTEMPTS: usize = 3;
pub const WINDOW_SECS: u64 = 15 * 60;

pub const REJECTED_AGAIN: &str = "The SIS turned your login down. Update your student number, birthdate or password to try again.";

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
#[derive(Debug, Default, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Ledger {
    attempts: Vec<u64>,
    rejected: bool,
}

impl Ledger {
    fn live(&self, now: u64) -> impl Iterator<Item = &u64> {
        self.attempts.iter().filter(move |&&a| a + WINDOW_SECS > now)
    }

    pub fn tries_left(&self, now: u64) -> usize {
        MAX_ATTEMPTS.saturating_sub(self.live(now).count())
    }

    /// When the next try frees up, if none is left now (epoch seconds).
    pub fn retry_at(&self, now: u64) -> Option<u64> {
        if self.tries_left(now) > 0 {
            return None;
        }
        self.live(now).min().map(|a| a + WINDOW_SECS)
    }

    /// Whether the SIS turned the saved login down and it hasn't been edited since.
    pub fn rejected(&self) -> bool {
        self.rejected
    }

    fn precheck(&mut self, auto: bool) -> Result<(), Error> {
        if auto && self.rejected {
            return Err(Error::Rejected(REJECTED_AGAIN.into()));
        }
        if !auto {
            self.rejected = false;
        }
        Ok(())
    }

    /// For a portal with one host and nothing to probe (eMabini): the same
    /// rules around its one credential POST. `auto` as in `sign_in_guarded`.
    /// Call `record` with the POST's result afterwards.
    pub fn begin(&mut self, now: u64, auto: bool) -> Result<(), Error> {
        self.precheck(auto)?;
        self.spend(now)
    }

    /// Remembers whether the portal turned the login down.
    pub fn record<T>(&mut self, result: &Result<T, Error>) {
        if let Err(e) = result {
            self.rejected = matches!(e, Error::Rejected(_));
        }
    }

    fn spend(&mut self, now: u64) -> Result<(), Error> {
        if let Some(retry_at) = self.retry_at(now) {
            return Err(Error::TooManyTries { retry_at });
        }
        self.attempts.retain(|&a| a + WINDOW_SECS > now);
        self.attempts.push(now);
        Ok(())
    }
}

/// Picks a live host with GETs, then makes exactly one credential POST on it.
///
/// `auto` is true for a background sign-in from the saved login (sync); it
/// refuses to run after a rejection. A tap on Sign in passes false, which
/// clears that rejection first. The caller saves `ledger` afterwards, win or
/// lose.
pub async fn sign_in_guarded<C: Sis>(
    make: impl Fn(&str) -> Result<C, Error>,
    c: &Credentials,
    remembered: Option<&str>,
    ledger: &mut Ledger,
    now: u64,
    auto: bool,
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
    ledger.spend(now)?;
    let signed_in = client.sign_in(c).await;
    ledger.record(&signed_in);
    signed_in?;
    match client.schedule().await? {
        rows if rows.is_empty() => Err(Error::NoSchedule),
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
        let r = pollster(sign_in_guarded(make, &creds(), None, ledger, now, auto)).map(|(_, rows)| rows.len());
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
    fn empty_schedule_is_not_retried_on_another_host() {
        let mut l = Ledger::default();
        let (r, log) = run(&[], false, false, 0, &mut l, 1000, false);
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
        assert_eq!(r, Err(Error::Rejected(REJECTED_AGAIN.into())));
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
        assert_eq!(r, Err(Error::TooManyTries { retry_at: 1000 + WINDOW_SECS }));
        assert!(log.posts.is_empty());
        // The oldest try ages out of the window.
        assert_eq!(run(&[], false, false, 3, &mut l, 1000 + WINDOW_SECS, false).0, Ok(3));
    }

    #[test]
    fn the_ledger_survives_a_restart() {
        let mut l = Ledger::default();
        let _ = run(&[], true, false, 3, &mut l, 1000, false);
        let back: Ledger = serde_json::from_str(&serde_json::to_string(&l).unwrap()).unwrap();
        assert_eq!(back, l);
        assert_eq!(back.tries_left(1000), 2);
    }

    #[test]
    fn begin_and_record_guard_a_single_host_portal() {
        let mut l = Ledger::default();
        l.begin(1000, false).unwrap();
        l.record::<()>(&Err(Error::Rejected("bad".into())));
        assert!(l.rejected());
        assert_eq!(l.begin(1100, true), Err(Error::Rejected(REJECTED_AGAIN.into())));
        assert_eq!(l.tries_left(1100), 2, "a refused auto try spends nothing");
        l.begin(1200, false).unwrap();
        l.record(&Ok(()));
        assert!(!l.rejected(), "the tap cleared it and a success leaves it clear");
    }
}
