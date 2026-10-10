//! Resumable, hash-checked model download. Bytes land in `<file>.part`; a
//! restart continues from its length with an HTTP Range request. Only a file
//! whose SHA-256 matches the pin is renamed into place.
use intportal_ai::models::Model;
use sha2::{Digest, Sha256};
use std::{
    fs::{self, File, OpenOptions},
    io::{Read, Write},
    path::{Path, PathBuf},
};

pub fn download(m: &Model, dir: &Path, on_progress: &mut dyn FnMut(u64, u64) -> bool) -> Result<PathBuf, String> {
    fetch(m.url, m.file, m.sha256, m.bytes, dir, on_progress)
}

/// `on_progress(done, total)` returns false to pause; the `.part` stays for the next try.
pub fn fetch(url: &str, file: &str, sha256: &str, bytes: u64, dir: &Path, on_progress: &mut dyn FnMut(u64, u64) -> bool) -> Result<PathBuf, String> {
    fs::create_dir_all(dir).map_err(|e| e.to_string())?;
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
        let mut req = reqwest::blocking::Client::new().get(url);
        if have > 0 {
            req = req.header("Range", format!("bytes={have}-"));
        }
        let mut resp = req.send().map_err(|e| e.to_string())?;
        let status = resp.status().as_u16();
        let append = match status {
            206 => true,
            200 => false, // the server ignored Range: start over
            s => return Err(format!("download failed: HTTP {s}")),
        };
        let mut out = if append { OpenOptions::new().append(true).open(&part) } else { File::create(&part) }.map_err(|e| e.to_string())?;
        if !append {
            have = 0;
        }
        let mut buf = vec![0u8; 256 * 1024];
        loop {
            let n = resp.read(&mut buf).map_err(|e| e.to_string())?;
            if n == 0 {
                break;
            }
            out.write_all(&buf[..n]).map_err(|e| e.to_string())?;
            have += n as u64;
            if !on_progress(have, bytes) {
                return Err("paused".into());
            }
        }
        out.sync_all().map_err(|e| e.to_string())?;
    }
    if sha_of(&part)? != sha256 {
        let _ = fs::remove_file(&part);
        return Err("the downloaded file failed its check and was deleted; try again".into());
    }
    fs::rename(&part, &done).map_err(|e| e.to_string())?;
    Ok(done)
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
        let l = TcpListener::bind("127.0.0.1:0").unwrap();
        let url = format!("http://{}/m.gguf", l.local_addr().unwrap());
        std::thread::spawn(move || {
            for _ in 0..n {
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
                let head = if start > 0 { "206 Partial Content" } else { "200 OK" };
                let _ = write!(s, "HTTP/1.1 {head}\r\nContent-Length: {}\r\nConnection: close\r\n\r\n", body.len() - start);
                let _ = s.write_all(&body[start..]);
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
        assert_eq!(r, Err("paused".into()));
        let part = fs::metadata(dir.join("m.gguf.part")).unwrap().len();
        assert!(part > 0 && part < body.len() as u64);
        let path = fetch(&url, "m.gguf", &sha(&body), body.len() as u64, &dir, &mut |_, _| true).unwrap();
        assert_eq!(fs::read(path).unwrap(), body);
        assert!(!dir.join("m.gguf.part").exists());
    }

    #[test]
    fn a_wrong_hash_deletes_the_part_file() {
        let body = vec![7u8; 1000];
        let (url, dir) = (serve(body.clone(), 1), tmp("badsha"));
        let r = fetch(&url, "m.gguf", &sha(b"something else"), 1000, &dir, &mut |_, _| true);
        assert!(r.unwrap_err().contains("failed its check"));
        assert!(!dir.join("m.gguf.part").exists() && !dir.join("m.gguf").exists());
    }
}
