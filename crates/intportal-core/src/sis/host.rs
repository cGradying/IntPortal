//! Which SIS host to try, in what order, and whether a signed-in host is
//! worth keeping (legacy spec 00-sis-host.md). Hosts are not
//! interchangeable: sis1 signs in but never carries the schedule; sis8 does.

use regex::Regex;
use std::sync::LazyLock;

static CANDIDATE: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"^sis\d+\.pup\.edu\.ph$").unwrap());

pub const DEFAULT_ORDER: [&str; 3] = ["sis8.pup.edu.ph", "sis1.pup.edu.ph", "sis2.pup.edu.ph"];

/// Exactly `sisN.pup.edu.ph`, so neither `www.pup.edu.ph` nor a lookalike
/// such as `sis8.pup.edu.ph.evil.com` passes.
pub fn is_candidate(host: &str) -> bool {
    CANDIDATE.is_match(host)
}

/// The credential gate: only https `pup.edu.ph` or its subdomains.
pub fn is_trusted(url: &reqwest::Url) -> bool {
    url.scheme() == "https" && url.host_str().is_some_and(|h| h == "pup.edu.ph" || h.ends_with(".pup.edu.ph"))
}

/// The remembered host first if it is still a candidate, then the default order.
pub fn candidates(remembered: Option<&str>) -> Vec<String> {
    let mut order: Vec<String> = remembered.filter(|h| is_candidate(h)).map(String::from).into_iter().collect();
    for h in DEFAULT_ORDER {
        if !order.iter().any(|o| o == h) {
            order.push(h.into());
        }
    }
    order
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Attempt {
    Rejected,
    Failed,
    SignedInEmpty,
    SignedInWithRows,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Decision {
    Keep,
    Next,
    /// Bad credentials: sending them to a second server helps nothing.
    Stop,
}

pub fn decide(attempt: Attempt) -> Decision {
    match attempt {
        Attempt::Rejected => Decision::Stop,
        Attempt::Failed | Attempt::SignedInEmpty => Decision::Next,
        Attempt::SignedInWithRows => Decision::Keep,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn candidate_hosts() {
        for h in ["sis1.pup.edu.ph", "sis2.pup.edu.ph", "sis8.pup.edu.ph", "sis23.pup.edu.ph"] {
            assert!(is_candidate(h), "{h}");
        }
        for h in ["www.pup.edu.ph", "sis8.pup.edu.ph.evil.com", "", "pup.edu.ph", "sis.pup.edu.ph"] {
            assert!(!is_candidate(h), "{h}");
        }
    }

    #[test]
    fn trusted_urls() {
        let t = |s: &str| is_trusted(&reqwest::Url::parse(s).unwrap());
        assert!(t("https://sis8.pup.edu.ph/student/"));
        assert!(t("https://pup.edu.ph/"));
        assert!(!t("http://sis8.pup.edu.ph/student/"));
        assert!(!t("https://sis8.pup.edu.ph.evil.com/"));
        assert!(!t("https://notpup.edu.ph/"));
    }

    #[test]
    fn candidate_order() {
        assert_eq!(candidates(None), DEFAULT_ORDER);
        assert_eq!(candidates(Some("sis1.pup.edu.ph")), ["sis1.pup.edu.ph", "sis8.pup.edu.ph", "sis2.pup.edu.ph"]);
        assert_eq!(candidates(Some("sis8.pup.edu.ph")), DEFAULT_ORDER);
        assert_eq!(candidates(Some("www.pup.edu.ph")), DEFAULT_ORDER);
        assert_eq!(candidates(Some("sis5.pup.edu.ph"))[0], "sis5.pup.edu.ph");
    }

    #[test]
    fn decisions() {
        assert_eq!(decide(Attempt::Rejected), Decision::Stop);
        assert_eq!(decide(Attempt::Failed), Decision::Next);
        assert_eq!(decide(Attempt::SignedInEmpty), Decision::Next);
        assert_eq!(decide(Attempt::SignedInWithRows), Decision::Keep);
    }
}
