//! llama.cpp behind the `Llm` trait. Linux gets a stub that returns an error,
//! so callers need no `cfg`.

#[cfg(any(target_os = "macos", target_os = "ios", target_os = "android"))]
mod llama;
#[cfg(any(target_os = "macos", target_os = "ios", target_os = "android"))]
pub use llama::Llama;

#[cfg(not(any(target_os = "macos", target_os = "ios", target_os = "android")))]
mod stub;
#[cfg(not(any(target_os = "macos", target_os = "ios", target_os = "android")))]
pub use stub::Llama;

pub mod download;
pub mod mem;
pub mod backup;

/// Where a model runs. CPU only is for the simulator and for tests.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Device {
    Gpu,
    Cpu,
}

/// Takes the printable UTF-8 prefix of `buf` and leaves a split multi-byte
/// character for the next token. Invalid bytes become U+FFFD.
pub fn take_utf8(buf: &mut Vec<u8>) -> String {
    match std::str::from_utf8(buf) {
        Ok(s) => {
            let out = s.to_string();
            buf.clear();
            out
        }
        Err(e) if e.error_len().is_none() => {
            let n = e.valid_up_to();
            let out = String::from_utf8_lossy(&buf[..n]).into_owned();
            buf.drain(..n);
            out
        }
        Err(_) => {
            let out = String::from_utf8_lossy(buf).into_owned();
            buf.clear();
            out
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn holds_back_a_split_character() {
        let bytes = "ñ".as_bytes(); // 0xC3 0xB1
        let mut buf = vec![b'a', bytes[0]];
        assert_eq!(take_utf8(&mut buf), "a");
        buf.push(bytes[1]);
        assert_eq!(take_utf8(&mut buf), "ñ");
        assert!(buf.is_empty());
    }

    #[test]
    fn replaces_invalid_bytes() {
        let mut buf = vec![0xFF, b'x'];
        assert_eq!(take_utf8(&mut buf), "\u{FFFD}x");
    }
}
