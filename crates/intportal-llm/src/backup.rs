//! Keeps the models folder out of iCloud and device backups: 0.4 to 1.1 GB the
//! student can download again. This is what `NSURLIsExcludedFromBackupKey`
//! writes, as an extended attribute, so no Objective-C is needed.

/// Apple's binary plist for the string "com.apple.backupd".
#[cfg(any(target_os = "macos", target_os = "ios"))]
const BACKUPD: [u8; 61] = [
    98, 112, 108, 105, 115, 116, 48, 48, 95, 16, 17, 99, 111, 109, 46, 97, 112, 112, 108, 101, 46, 98, 97, 99, 107, 117, 112, 100, 8, 0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 28,
];
#[cfg(any(target_os = "macos", target_os = "ios"))]
const ATTR: &[u8] = b"com.apple.metadata:com_apple_backup_excludeItem\0";

/// Excludes `path` (a file or folder) from backup. On Android the folder
/// should be under `getNoBackupFilesDir()` instead, and this does nothing.
pub fn exclude(path: &std::path::Path) -> Result<(), String> {
    #[cfg(any(target_os = "macos", target_os = "ios"))]
    {
        use std::os::unix::ffi::OsStrExt;
        let p = std::ffi::CString::new(path.as_os_str().as_bytes()).map_err(|e| e.to_string())?;
        let rc = unsafe { libc::setxattr(p.as_ptr(), ATTR.as_ptr().cast(), BACKUPD.as_ptr().cast(), BACKUPD.len(), 0, 0) };
        if rc != 0 {
            return Err(std::io::Error::last_os_error().to_string());
        }
    }
    let _ = path;
    Ok(())
}

#[cfg(all(test, target_os = "macos"))]
mod tests {
    #[test]
    fn sets_the_exclude_attribute() {
        let dir = std::env::temp_dir().join(format!("intportal-bk-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        super::exclude(&dir).unwrap();
        let out = std::process::Command::new("xattr").arg("-l").arg(&dir).output().unwrap();
        assert!(String::from_utf8_lossy(&out.stdout).contains("com_apple_backup_excludeItem"));
        std::fs::remove_dir_all(&dir).unwrap();
    }
}
