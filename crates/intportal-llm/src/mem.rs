/// Bytes the app may still allocate before the system kills it, or None
/// where the platform gives no answer.
#[cfg(target_os = "ios")]
pub fn available() -> Option<u64> {
    extern "C" {
        fn os_proc_available_memory() -> usize;
    }
    Some(unsafe { os_proc_available_memory() } as u64)
}

#[cfg(target_os = "android")]
pub fn available() -> Option<u64> {
    parse_mem_available(&std::fs::read_to_string("/proc/meminfo").ok()?)
}

#[cfg(not(any(target_os = "ios", target_os = "android")))]
pub fn available() -> Option<u64> {
    None
}

/// `MemAvailable:  1234 kB` in /proc/meminfo, as bytes.
pub fn parse_mem_available(meminfo: &str) -> Option<u64> {
    let line = meminfo.lines().find(|l| l.starts_with("MemAvailable:"))?;
    Some(line.split_whitespace().nth(1)?.parse::<u64>().ok()? * 1024)
}

#[cfg(test)]
mod tests {
    #[test]
    fn reads_mem_available_in_bytes() {
        let m = "MemTotal:  8000000 kB\nMemFree: 100 kB\nMemAvailable:    2048 kB\n";
        assert_eq!(super::parse_mem_available(m), Some(2_097_152));
        assert_eq!(super::parse_mem_available("MemTotal: 1 kB"), None);
    }
}
