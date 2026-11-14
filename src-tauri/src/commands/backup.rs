use crate::*;

/// The backup file's text (spec 047 C9). `themes` is the webview's saved themes.
/// Holds the sync lock, so a refresh can't save over a backup being read.
#[tauri::command]
pub async fn backup_make(state: tauri::State<'_, AppState>, themes: Vec<serde_json::Value>) -> Res<String> {
    let _sync = state.client.lock().await;
    let who = open_student(&state).ok_or("Sign in first, then back up.")?;
    let mut salt = [0u8; 16];
    getrandom::fill(&mut salt).map_err(|_| "Couldn't make the backup.")?;
    let now = SystemTime::now().duration_since(UNIX_EPOCH).map_or(0, |d| d.as_secs() as i64);
    let b = Backup::make(&state.store.lock().unwrap(), &who, salt, themes, now).map_err(|_| "Couldn't make the backup.")?;
    let text = serde_json::to_string(&b).map_err(|_| "Couldn't make the backup.")?;
    // A file restore would refuse isn't made (C9): say why instead.
    if text.len() > backup::MAX_BYTES {
        return Err(format!("Your photos make this backup too big to restore here; it's {} MB. Remove some photos and try again.", text.len().div_ceil(1024 * 1024)));
    }
    Ok(text)
}

/// Reads a backup and says what it holds; refuses a damaged, newer or other student's file (C10).
#[tauri::command(async)]
pub fn backup_preview(state: tauri::State<'_, AppState>, text: String) -> Res<backup::Preview> {
    let b = Backup::parse(&text).map_err(err)?;
    b.check(open_student(&state).as_deref()).map_err(err)?;
    Ok(b.preview())
}

/// Replaces the student's notes, decks and the rest with the file's, or changes nothing.
/// Returns the file's themes for the webview to save. Holds the sync lock (a refresh
/// saves a whole snapshot and would revert it) and the AI index lock.
#[tauri::command]
pub async fn backup_restore(state: tauri::State<'_, AppState>, ai: tauri::State<'_, ai::AiState>, text: String) -> Res<Vec<serde_json::Value>> {
    let _sync = state.client.lock().await;
    let b = Backup::parse(&text).map_err(err)?;
    b.check(open_student(&state).as_deref()).map_err(err)?;
    ai::while_idle(&ai, || state.store.lock().unwrap().restore(&b).map_err(|_| "Couldn't restore that backup, so nothing changed.".to_string()))??;
    Ok(b.themes)
}

/// Bytes taken by notes, photos, decks and the rest (C11).
#[tauri::command(async)]
pub fn space_used(state: tauri::State<'_, AppState>) -> Res<store::Space> {
    state.store.lock().unwrap().space().map_err(err)
}

/// Everything on this phone, the student's own notes and decks included.
#[tauri::command(async)]
pub fn erase_everything(state: tauri::State<'_, AppState>) -> Res<()> {
    state.store.lock().unwrap().wipe().map_err(err)?;
    let _ = std::fs::remove_dir_all(state.dir.join(PHOTO_TMP));
    Ok(())
}
