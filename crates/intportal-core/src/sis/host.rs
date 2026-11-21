//! Which SIS host to try, in what order, and whether a signed-in host is
//! worth keeping (legacy spec 00-sis-host.md). Hosts are not
//! interchangeable: sis1 signs in but never carries the schedule; sis8 does.

use regex::Regex;
use std::sync::LazyLock;

static CANDIDATE: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"^sis\d+\.pup\.edu\.ph$").unwrap());

pub const DEFAULT_ORDER: [&str; 3] = ["sis8.pup.edu.ph", "sis1.pup.edu.ph", "sis2.pup.edu.ph"];

/// How long a portal gets to accept a connection, and to answer one request in full. The SIS is
/// slow and often down; without these a sync waits on a dead host for as long as the phone allows.
pub const CONNECT_TIMEOUT: std::time::Duration = std::time::Duration::from_secs(10);
pub const REQUEST_TIMEOUT: std::time::Duration = std::time::Duration::from_secs(30);

/// Exactly `sisN.pup.edu.ph`, so neither `www.pup.edu.ph` nor a lookalike
/// such as `sis8.pup.edu.ph.evil.com` passes.
pub fn is_candidate(host: &str) -> bool {
    CANDIDATE.is_match(host)
}

/// The credential gate: https on exactly the host the session started on, so a
/// redirect or a form action can't carry the password or the cookies to another
/// `pup.edu.ph` subdomain.
#[cfg(feature = "net")]
pub fn is_trusted(url: &reqwest::Url, host: &str) -> bool {
    url.scheme() == "https" && url.host_str() == Some(host) && url.port().is_none()
}

/// The most of one page the app reads. Real pages are well under 1 MB; a broken
/// or hostile server streaming more would otherwise fill the phone's memory.
#[cfg(feature = "net")]
pub const MAX_BODY: usize = 8 << 20;

/// A response's body as text, at most `MAX_BODY` bytes.
#[cfg(feature = "net")]
pub async fn text(mut resp: reqwest::Response) -> Result<String, super::Error> {
    if resp.content_length().is_some_and(|n| n > MAX_BODY as u64) {
        return Err(super::Error::Network("the page was too big".into()));
    }
    let mut body = Vec::new();
    while let Some(chunk) = resp.chunk().await? {
        if body.len() + chunk.len() > MAX_BODY {
            return Err(super::Error::Network("the page was too big".into()));
        }
        body.extend_from_slice(&chunk);
    }
    Ok(String::from_utf8_lossy(&body).into_owned())
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
        let t = |s: &str| is_trusted(&reqwest::Url::parse(s).unwrap(), "sis8.pup.edu.ph");
        assert!(t("https://sis8.pup.edu.ph/student/"));
        assert!(!t("https://pup.edu.ph/"));
        assert!(!t("https://sis1.pup.edu.ph/student/"));
        assert!(!t("https://mail.pup.edu.ph/student/"));
        assert!(!t("https://sis8.pup.edu.ph:8443/student/"));
        assert!(!t("http://sis8.pup.edu.ph/student/"));
        assert!(!t("https://sis8.pup.edu.ph.evil.com/"));
        assert!(!t("https://notpup.edu.ph/"));
    }

    #[cfg(feature = "net")]
    #[tokio::test]
    async fn text_stops_at_the_cap() {
        let resp = |n: usize| reqwest::Response::from(http::Response::new(vec![b'a'; n]));
        assert_eq!(text(resp(5)).await.unwrap(), "aaaaa");
        assert!(text(resp(MAX_BODY)).await.is_ok());
        assert!(text(resp(MAX_BODY + 1)).await.is_err());
    }

    #[test]
    fn candidate_order() {
        assert_eq!(candidates(None), DEFAULT_ORDER);
        assert_eq!(candidates(Some("sis1.pup.edu.ph")), ["sis1.pup.edu.ph", "sis8.pup.edu.ph", "sis2.pup.edu.ph"]);
        assert_eq!(candidates(Some("sis8.pup.edu.ph")), DEFAULT_ORDER);
        assert_eq!(candidates(Some("www.pup.edu.ph")), DEFAULT_ORDER);
        assert_eq!(candidates(Some("sis5.pup.edu.ph"))[0], "sis5.pup.edu.ph");
    }
}
