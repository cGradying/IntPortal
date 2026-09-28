/// S1 probe: write a throwaway secret to the platform keychain, read it back,
/// delete it. Returns what happened so the UI can show it.
#[tauri::command]
fn keychain_roundtrip() -> Result<String, String> {
    #[cfg(any(target_os = "ios", target_os = "macos"))]
    {
        let entry = keyring::Entry::new("ph.intportal.app.s1", "probe").map_err(|e| e.to_string())?;
        entry.set_password("s1-probe-value").map_err(|e| e.to_string())?;
        let back = entry.get_password().map_err(|e| e.to_string())?;
        entry.delete_credential().map_err(|e| e.to_string())?;
        Ok(format!("keychain ok: read back {} chars", back.len()))
    }
    #[cfg(not(any(target_os = "ios", target_os = "macos")))]
    {
        // ponytail: Android Keystore needs a small Kotlin plugin; S1 only proves the Apple side.
        Err("keychain probe not built for this platform yet".into())
    }
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_notification::init())
        .invoke_handler(tauri::generate_handler![keychain_roundtrip])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
