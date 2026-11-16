use crate::*;

/// Look around first, in every build: a fake week and term so every screen
/// can be seen without an SIS account. The data is `intportal_core::demo`.
#[tauri::command(async)]
pub fn demo(state: tauri::State<'_, AppState>, today: Date) -> Res<Snapshot> {
    DEMO.store(true, Ordering::Relaxed);
    open_account(&state, "demo")?;
    let snap = intportal_core::demo::sis(snapshot_of(&state)?, today, now_secs());
    state.store.lock().unwrap().save(&snap).map_err(err)?;
    state.store.lock().unwrap().save_mabini(&intportal_core::demo::mabini(unix_now())).map_err(err)?;
    Ok(snap)
}
