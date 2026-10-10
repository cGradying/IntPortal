//! Talking to PUP's SIS over plain HTTP (spike S0, #4): sign in with a form
//! POST, then read the server-rendered schedule and grades tables.

mod client;
pub mod guard;
pub mod host;
pub mod scrape;

pub use client::SisClient;
pub use guard::{sign_in_guarded, Ledger};

/// The student's own SIS login. `Debug` never prints the password.
#[derive(Clone)]
pub struct Credentials {
    pub student_number: String,
    pub birth_month: u8,
    pub birth_day: u8,
    pub birth_year: u16,
    pub password: String,
}

impl std::fmt::Debug for Credentials {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("Credentials").field("student_number", &self.student_number).finish_non_exhaustive()
    }
}

#[derive(Debug, thiserror::Error, PartialEq, Eq)]
pub enum Error {
    /// The SIS turned the credentials down. Never retried on another host.
    #[error("{0}")]
    Rejected(String),
    #[error("couldn't reach the SIS: {0}")]
    Network(String),
    /// A page came back as the login form: the session expired.
    #[error("the SIS session expired")]
    SignedOut,
    /// Every host signed in but none had schedule rows.
    #[error("signed in, but no SIS server had your schedule")]
    NoSchedule,
    /// The 3-per-15-minutes limit is used up. `retry_at` is epoch seconds.
    #[error("too many sign-in tries; try again later")]
    TooManyTries { retry_at: u64 },
    #[error("refusing to talk to {0}: not a PUP SIS host")]
    UntrustedHost(String),
}

impl From<reqwest::Error> for Error {
    fn from(e: reqwest::Error) -> Self {
        Error::Network(e.without_url().to_string())
    }
}
