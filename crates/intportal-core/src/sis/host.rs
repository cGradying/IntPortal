//! Which SIS host to try, in what order, and whether a signed-in host is
//! worth keeping (legacy spec 00-sis-host.md). Hosts are not
//! interchangeable: sis1 signs in but never carries the schedule; sis8 does.

use regex::Regex;
use std::sync::LazyLock;

static CANDIDATE: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"^sis\d+\.pup\.edu\.ph$").unwrap());

/// Every host from sis1 to sis8, so a student whose schedule isn't on the
/// first host is found on another. sis8 goes first because it carries the
/// schedule; the order of the rest is the old spec's three, then the others.
pub const DEFAULT_ORDER: [&str; 8] = [
    "sis8.pup.edu.ph",
    "sis1.pup.edu.ph",
    "sis2.pup.edu.ph",
    "sis3.pup.edu.ph",
    "sis4.pup.edu.ph",
    "sis5.pup.edu.ph",
    "sis6.pup.edu.ph",
    "sis7.pup.edu.ph",
];

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
    fn every_host_from_sis1_to_sis8_is_tried_once() {
        let mut all: Vec<&str> = DEFAULT_ORDER.to_vec();
        assert_eq!(all[0], "sis8.pup.edu.ph", "the host known to carry the schedule goes first");
        all.sort_unstable();
        let expected: Vec<String> = (1..=8).map(|n| format!("sis{n}.pup.edu.ph")).collect();
        assert_eq!(all, expected);
    }

    #[test]
    fn candidate_order() {
        assert_eq!(candidates(None), DEFAULT_ORDER);
        assert_eq!(candidates(Some("sis8.pup.edu.ph")), DEFAULT_ORDER);
        assert_eq!(candidates(Some("www.pup.edu.ph")), DEFAULT_ORDER);
        // The remembered host moves to the front and appears once; the rest keep their order.
        let from_sis5 = candidates(Some("sis5.pup.edu.ph"));
        assert_eq!(from_sis5[0], "sis5.pup.edu.ph");
        assert_eq!(from_sis5.len(), 8);
        assert_eq!(&from_sis5[1..4], ["sis8.pup.edu.ph", "sis1.pup.edu.ph", "sis2.pup.edu.ph"]);
        // A remembered host outside sis1 to sis8 is still tried first, ahead of all eight.
        let from_sis23 = candidates(Some("sis23.pup.edu.ph"));
        assert_eq!(from_sis23[0], "sis23.pup.edu.ph");
        assert_eq!(from_sis23.len(), 9);
    }

    #[test]
    fn decisions() {
        assert_eq!(decide(Attempt::Rejected), Decision::Stop);
        assert_eq!(decide(Attempt::Failed), Decision::Next);
        assert_eq!(decide(Attempt::SignedInEmpty), Decision::Next);
        assert_eq!(decide(Attempt::SignedInWithRows), Decision::Keep);
    }
}
