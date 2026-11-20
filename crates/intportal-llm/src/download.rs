//! Resumable, hash-checked model download. Bytes land in `<file>.part`; a
//! restart continues from its length with an HTTP Range request. Only a file
//! whose SHA-256 matches the pin is renamed into place. A dropped or stalled
//! connection is retried with backoff for as long as the caller wants it
//! (spec 021 C7); each failure is a typed `DlError` with the student's line.
use intportal_ai::models::Model;
use sha2::{Digest, Sha256};
use std::{
    fmt,
    fs::{self, File, OpenOptions},
    io::{Read, Write},
    path::{Path, PathBuf},
    time::Duration,
};

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum DlError {
    /// Pause, Remove or the app asked it to stop; the `.part` stays.
    Paused,
    Offline,
    NoSpace,
    BadHash,
    Http(u16),
    Io(String),
}

impl fmt::Display for DlError {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        f.write_str(match self {
            DlError::Paused => "paused",
            DlError::Offline => "No connection. It carries on when you're back online.",
            DlError::NoSpace => "Storage filled up. Free up some space, then tap Resume.",
            DlError::BadHash => "The file didn't arrive whole, so it was deleted. Tap Resume to fetch it again.",
            DlError::Http(_) => "The download server didn't answer. Tap Resume to try again.",
            DlError::Io(e) => e,
        })
    }
}

impl DlError {
    /// Worth waiting out: the network or the server may come back.
    pub fn transient(&self) -> bool {
        matches!(self, DlError::Offline) || matches!(self, DlError::Http(s) if *s >= 500 || *s == 429)
    }
}

/// ENOSPC is 28 on Linux, Android, macOS and iOS.
fn io(e: std::io::Error) -> DlError {
    if e.raw_os_error() == Some(28) { DlError::NoSpace } else { DlError::Io(e.to_string()) }
}

fn net(e: reqwest::Error) -> DlError {
    match e.status() {
        Some(s) => DlError::Http(s.as_u16()),
        None => DlError::Offline,
    }
}

pub fn download(m: &Model, dir: &Path, on_progress: &mut dyn FnMut(u64, u64) -> bool, on_wait: &mut dyn FnMut(&DlError) -> bool) -> Result<PathBuf, DlError> {
    retrying(|p| fetch(m.url, m.file, m.sha256, m.bytes, dir, p), on_progress, on_wait)
}

/// Backoff between tries: 2 s, 4 s, 8 s … up to 60 s.
pub fn backoff(attempt: u32) -> Duration {
    Duration::from_secs((2u64 << attempt.min(5)).min(60))
}

/// Runs `once` until it ends in something other than a transient error. Before each wait `on_wait`
/// hears why; it returns false to give up (Pause). Progress resets the backoff.
pub fn retrying(mut once: impl FnMut(&mut dyn FnMut(u64, u64) -> bool) -> Result<PathBuf, DlError>, on_progress: &mut dyn FnMut(u64, u64) -> bool, on_wait: &mut dyn FnMut(&DlError) -> bool) -> Result<PathBuf, DlError> {
    let mut attempt = 0;
    loop {
        let mut moved = false;
        let r = once(&mut |d, t| {
            moved = true;
            on_progress(d, t)
        });
        match r {
            Err(e) if e.transient() => {
                if moved {
                    attempt = 0;
                }
                let until = std::time::Instant::now() + backoff(attempt);
                attempt += 1;
                while std::time::Instant::now() < until {
                    if !on_wait(&e) {
                        return Err(DlError::Paused);
                    }
                    std::thread::sleep(Duration::from_millis(250));
                }
            }
            other => return other,
        }
    }
}

/// One try. `on_progress(done, total)` returns false to pause; the `.part` stays for the next try.
pub fn fetch(url: &str, file: &str, sha256: &str, bytes: u64, dir: &Path, on_progress: &mut dyn FnMut(u64, u64) -> bool) -> Result<PathBuf, DlError> {
    fs::create_dir_all(dir).map_err(io)?;
    let (done, part) = (dir.join(file), dir.join(format!("{file}.part")));
    if done.metadata().map(|m| m.len() == bytes).unwrap_or(false) {
        return Ok(done);
    }
    let mut have = part.metadata().map(|m| m.len()).unwrap_or(0);
    if have > bytes {
        let _ = fs::remove_file(&part);
        have = 0;
    }
    if have < bytes {
        // The blocking client applies the timeout to each read: a stalled one (a network switch, a dead Wi-Fi) errors after 30 s and is retried.
        let client = reqwest::blocking::Client::builder().https_only(!cfg!(test)).connect_timeout(Duration::from_secs(15)).timeout(Duration::from_secs(30)).build().map_err(net)?;
        let mut req = client.get(url);
        if have > 0 {
            req = req.header("Range", format!("bytes={have}-"));
        }
        let mut resp = req.send().map_err(net)?;
        let append = match resp.status().as_u16() {
            // Only a range that starts where the part ends is appended; any other is started over.
            206 if resumes_at(resp.headers().get(reqwest::header::CONTENT_RANGE).and_then(|v| v.to_str().ok()), have) => true,
            206 => {
                drop(resp);
                let _ = fs::remove_file(&part);
                return Err(DlError::Offline);
            }
            200 => false, // the server ignored Range: start over
            s => return Err(DlError::Http(s)),
        };
        let mut out = if append { OpenOptions::new().append(true).open(&part) } else { File::create(&part) }.map_err(io)?;
        if !append {
            have = 0;
        }
        let mut buf = vec![0u8; 256 * 1024];
        loop {
            let n = resp.read(&mut buf).map_err(|_| DlError::Offline)?;
            if n == 0 {
                break;
            }
            have += n as u64;
            if have > bytes {
                // More than the pinned size: not the file we want, and it would fill the phone.
                drop(out);
                let _ = fs::remove_file(&part);
                return Err(DlError::BadHash);
            }
            out.write_all(&buf[..n]).map_err(io)?;
            if !on_progress(have, bytes) {
                return Err(DlError::Paused);
            }
        }
        out.sync_all().map_err(io)?;
        if have < bytes {
            return Err(DlError::Offline); // the server closed early: resume from here
        }
    }
    finish(&part, &done, sha256)
}

/// Whether a 206 answer's `Content-Range` starts at `have`.
fn resumes_at(content_range: Option<&str>, have: u64) -> bool {
    content_range.is_some_and(|v| v.starts_with(&format!("bytes {have}-")))
}

/// Checks a whole `.part` against the pin and renames it into place; a bad one is deleted.
pub fn finish(part: &Path, done: &Path, sha256: &str) -> Result<PathBuf, DlError> {
    if sha_of(part).map_err(DlError::Io)? != sha256 {
        let _ = fs::remove_file(part);
        return Err(DlError::BadHash);
    }
    fs::rename(part, done).map_err(io)?;
    Ok(done.to_path_buf())
}

fn sha_of(path: &Path) -> Result<String, String> {
    let mut f = File::open(path).map_err(|e| e.to_string())?;
    let (mut h, mut buf) = (Sha256::new(), vec![0u8; 256 * 1024]);
    loop {
        let n = f.read(&mut buf).map_err(|e| e.to_string())?;
        if n == 0 {
            return Ok(h.finalize().iter().map(|b| format!("{b:02x}")).collect());
        }
        h.update(&buf[..n]);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::{
        io::{BufRead, BufReader},
        net::TcpListener,
    };

    /// Serves `body` for `n` connections, honouring `Range: bytes=N-`.
    fn serve(body: Vec<u8>, n: usize) -> String {
        serve_with(body, n, None, 0)
    }

    /// Like `serve`; `status` answers every request with that code instead, and the first `cut`
    /// connections send only half of what they promise and hang up.
    fn serve_with(body: Vec<u8>, n: usize, status: Option<u16>, cut: usize) -> String {
        let l = TcpListener::bind("127.0.0.1:0").unwrap();
        let url = format!("http://{}/m.gguf", l.local_addr().unwrap());
        std::thread::spawn(move || {
            for i in 0..n {
                let (mut s, _) = l.accept().unwrap();
                let mut start = 0usize;
                for line in BufReader::new(&s).lines() {
                    let line = line.unwrap();
                    if line.is_empty() {
                        break;
                    }
                    if let Some(r) = line.to_lowercase().strip_prefix("range: bytes=") {
                        start = r.trim_end_matches('-').parse().unwrap();
                    }
                }
                if let Some(code) = status {
                    let _ = write!(s, "HTTP/1.1 {code} Nope\r\nContent-Length: 0\r\nConnection: close\r\n\r\n");
                    continue;
                }
                let head = if start > 0 { format!("206 Partial Content\r\nContent-Range: bytes {start}-{}/{}", body.len() - 1, body.len()) } else { "200 OK".into() };
                let _ = write!(s, "HTTP/1.1 {head}\r\nContent-Length: {}\r\nConnection: close\r\n\r\n", body.len() - start);
                let rest = &body[start..];
                let _ = s.write_all(if i < cut { &rest[..rest.len() / 2] } else { rest });
            }
        });
        url
    }

    fn sha(b: &[u8]) -> String {
        Sha256::digest(b).iter().map(|x| format!("{x:02x}")).collect()
    }

    fn tmp(name: &str) -> PathBuf {
        let d = std::env::temp_dir().join(format!("intportal-dl-{name}-{}", std::process::id()));
        let _ = fs::remove_dir_all(&d);
        d
    }

    #[test]
    fn a_resume_appends_and_the_hash_is_checked() {
        let body: Vec<u8> = (0..600_000u32).map(|i| (i % 251) as u8).collect();
        let (url, dir) = (serve(body.clone(), 2), tmp("resume"));
        let r = fetch(&url, "m.gguf", &sha(&body), body.len() as u64, &dir, &mut |done, _| done < 300_000);
        assert_eq!(r, Err(DlError::Paused));
        let part = fs::metadata(dir.join("m.gguf.part")).unwrap().len();
        assert!(part > 0 && part < body.len() as u64);
        let path = fetch(&url, "m.gguf", &sha(&body), body.len() as u64, &dir, &mut |_, _| true).unwrap();
        assert_eq!(fs::read(path).unwrap(), body);
        assert!(!dir.join("m.gguf.part").exists());
    }

    #[test]
    fn a_resume_must_start_where_the_part_ends() {
        assert!(resumes_at(Some("bytes 300-999/1000"), 300));
        assert!(!resumes_at(Some("bytes 0-999/1000"), 300));
        assert!(!resumes_at(Some("bytes 3000-3999/4000"), 300));
        assert!(!resumes_at(None, 300));
    }

    #[test]
    fn a_body_longer_than_the_pin_stops_and_is_deleted() {
        let body = vec![7u8; 600_000];
        let (url, dir) = (serve(body, 1), tmp("toolong"));
        let r = fetch(&url, "m.gguf", &sha(b"x"), 1000, &dir, &mut |_, _| true);
        assert_eq!(r.unwrap_err(), DlError::BadHash);
        assert!(!dir.join("m.gguf.part").exists());
    }

    #[test]
    fn a_wrong_hash_deletes_the_part_file() {
        let body = vec![7u8; 1000];
        let (url, dir) = (serve(body.clone(), 1), tmp("badsha"));
        let r = fetch(&url, "m.gguf", &sha(b"something else"), 1000, &dir, &mut |_, _| true);
        assert_eq!(r.unwrap_err(), DlError::BadHash);
        assert!(!dir.join("m.gguf.part").exists() && !dir.join("m.gguf").exists());
    }

    #[test]
    fn a_connection_that_drops_is_resumed_without_a_tap() {
        let body: Vec<u8> = (0..400_000u32).map(|i| (i % 241) as u8).collect();
        let (url, dir) = (serve_with(body.clone(), 2, None, 1), tmp("drop"));
        let mut waits = 0;
        let path = retrying(|p| fetch(&url, "m.gguf", &sha(&body), body.len() as u64, &dir, p), &mut |_, _| true, &mut |e| {
            assert_eq!(*e, DlError::Offline);
            waits += 1;
            true
        })
        .unwrap();
        assert_eq!(fs::read(path).unwrap(), body);
        assert!(waits > 0, "it waited, then resumed");
    }

    #[test]
    fn a_missing_file_is_not_retried_and_a_busy_server_is_until_pause() {
        let (url, dir) = (serve_with(vec![1; 10], 1, Some(404), 0), tmp("404"));
        let r = retrying(|p| fetch(&url, "m.gguf", "x", 10, &dir, p), &mut |_, _| true, &mut |_| panic!("404 is not worth waiting for"));
        assert_eq!(r, Err(DlError::Http(404)));
        let (url, dir) = (serve_with(vec![1; 10], 1, Some(503), 0), tmp("503"));
        let r = retrying(|p| fetch(&url, "m.gguf", "x", 10, &dir, p), &mut |_, _| true, &mut |e| {
            assert!(e.transient());
            false // the student paused while it waited
        });
        assert_eq!(r, Err(DlError::Paused));
    }

    #[test]
    fn errors_read_as_the_students_lines_and_backoff_caps_at_a_minute() {
        assert!(DlError::NoSpace.to_string().starts_with("Storage filled up"));
        assert_eq!(io(std::io::Error::from_raw_os_error(28)), DlError::NoSpace);
        assert_eq!([0, 1, 2, 9].map(|a| backoff(a).as_secs()), [2, 4, 8, 60]);
    }
}
