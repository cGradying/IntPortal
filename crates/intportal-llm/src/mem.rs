/// Bytes the app may still allocate before the system kills it, or None
/// where the platform gives no answer.
#[cfg(all(target_os = "ios", not(target_abi = "sim")))]
pub fn available() -> Option<u64> {
    extern "C" {
        fn os_proc_available_memory() -> usize;
    }
    // 0 means the system gave no answer, not that nothing is free.
    Some(unsafe { os_proc_available_memory() } as u64).filter(|&n| n > 0)
}

#[cfg(target_os = "android")]
pub fn available() -> Option<u64> {
    parse_mem_available(&std::fs::read_to_string("/proc/meminfo").ok()?)
}

// The simulator has no per-app limit and reports 0, so it gets no gate.
#[cfg(not(any(all(target_os = "ios", not(target_abi = "sim")), target_os = "android")))]
pub fn available() -> Option<u64> {
    None
}

/// The phone's total RAM, where the platform says (Android; iOS and the Mac give no figure, they are not small phones).
#[cfg(target_os = "android")]
pub fn total() -> Option<u64> {
    parse_meminfo(&std::fs::read_to_string("/proc/meminfo").ok()?, "MemTotal:")
}

#[cfg(not(target_os = "android"))]
pub fn total() -> Option<u64> {
    None
}

/// `MemAvailable:  1234 kB` in /proc/meminfo, as bytes.
pub fn parse_mem_available(meminfo: &str) -> Option<u64> {
    parse_meminfo(meminfo, "MemAvailable:")
}

fn parse_meminfo(meminfo: &str, field: &str) -> Option<u64> {
    let line = meminfo.lines().find(|l| l.starts_with(field))?;
    Some(line.split_whitespace().nth(1)?.parse::<u64>().ok()? * 1024)
}

#[cfg(test)]
mod tests {
    #[test]
    fn reads_mem_available_in_bytes() {
        let m = "MemTotal:  8000000 kB\nMemFree: 100 kB\nMemAvailable:    2048 kB\n";
        assert_eq!(super::parse_mem_available(m), Some(2_097_152));
        assert_eq!(super::parse_mem_available("MemTotal: 1 kB"), None);
        assert_eq!(super::parse_meminfo(m, "MemTotal:"), Some(8_192_000_000));
    }
}
