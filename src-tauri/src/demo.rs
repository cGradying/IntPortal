use crate::*;

/// Look around first, in every build: a fake week and term so every screen
/// can be seen without an SIS account. The data is `intportal_core::demo`.
#[tauri::command(async)]
pub fn demo(state: tauri::State<'_, AppState>, today: Date) -> Res<Snapshot> {
    // Look around lives in memory: no file on the phone, so a real student's data never
    // syncs into it, and it never inherits the old single store. Not while a portal is signed in.
    if vault::load().is_some() || mabini_vault::load().is_some() {
        return Err("Sign out first to look around.".into());
    }
    DEMO.store(true, Ordering::Relaxed);
    *state.store.lock().unwrap() = Store::in_memory().map_err(err)?;
    let snap = intportal_core::demo::sis(snapshot_of(&state)?, today, now_secs());
    state.store.lock().unwrap().save(&snap).map_err(err)?;
    state.store.lock().unwrap().save_mabini(&intportal_core::demo::mabini(unix_now())).map_err(err)?;
    Ok(snap)
}
