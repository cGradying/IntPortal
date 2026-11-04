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

/// Threads for llama.cpp's matrix work on a phone with `cores` cores: four at most (more do not help a
/// phone and spin against each other), and always one core left for the UI. llama.cpp's own default is
/// four, which on a 4-core phone leaves the UI thread and the WebView renderer to fight the model.
pub fn threads_for(cores: usize) -> i32 {
    cores.saturating_sub(1).clamp(1, 4) as i32
}

/// Makes the calling thread (and the threads llama.cpp starts from it) yield to the UI on Android.
/// Raising the nice value is allowed to any app; lowering it again is not, so call this only on a
/// thread made for the model. Elsewhere it does nothing.
pub fn lower_priority() {
    #[cfg(target_os = "android")]
    // SAFETY: setpriority only reads its arguments. who = 0 is the calling thread on Linux.
    unsafe {
        libc::setpriority(libc::PRIO_PROCESS, 0, 10);
    }
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
    fn model_threads_leave_a_core_for_the_ui_and_stop_at_four() {
        assert_eq!([0, 1, 2, 4, 6, 8, 12].map(threads_for), [1, 1, 1, 3, 4, 4, 4]);
    }

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
