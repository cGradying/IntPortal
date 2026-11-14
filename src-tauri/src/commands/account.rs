use crate::*;

#[tauri::command(async)]
pub fn portals() -> Vec<intportal_core::portal::Portal> {
    intportal_core::portal::ALL.clone()
}

#[tauri::command(async)]
pub fn snapshot(state: tauri::State<'_, AppState>) -> Res<Snapshot> {
    snapshot_of(&state)
}

/// Every sign-in goes through here: one credential POST, a live host picked
/// by GET first, at most 3 tries per 15 minutes, and no automatic try after
/// a rejection (`auto`). The count is saved even when the sign-in fails.
pub(crate) async fn guarded_sign_in(
    state: &AppState,
    login: &Login,
    remembered: Option<&str>,
    auto: bool,
) -> Res<(SisClient, Vec<schedule::ScheduleRow>)> {
    let mut ledger = state.ledger.lock().await;
    let r = sign_in_guarded(SisClient::new, &login.into(), remembered, &mut ledger, unix_now() as u64, auto).await;
    if let Ok(json) = serde_json::to_string(&*ledger) {
        let _ = std::fs::write(state.dir.join(GUARD_FILE), json);
    }
    r.map_err(err)
}

#[derive(Serialize)]
pub struct Tries {
    pub(crate) left: usize,
    /// Epoch seconds when a try frees up, if none is left.
    pub(crate) retry_at: Option<u64>,
    /// The SIS turned the saved login down; the student has to edit it.
    pub(crate) rejected: bool,
}

#[tauri::command]
pub async fn tries_left(state: tauri::State<'_, AppState>) -> Res<Tries> {
    let l = state.ledger.lock().await;
    let now = unix_now() as u64;
    Ok(Tries { left: l.tries_left(now), retry_at: l.retry_at(now), rejected: l.rejected() })
}

/// The saved student number, to fill a sign-in form after a rejection
/// (spec 040 C5). Never the password.
#[tauri::command(async)]
pub fn login_hint(portal: String) -> Option<String> {
    match portal.as_str() {
        "sis" => vault::load().map(|l| l.student_number),
        "mabini" => mabini_vault::load().map(|l| l.student_number),
        _ => None,
    }
}

#[tauri::command(async)]
pub fn has_login() -> bool {
    (cfg!(debug_assertions) && DEMO.load(Ordering::Relaxed)) || vault::load().is_some()
}

#[tauri::command]
pub async fn sign_in(state: tauri::State<'_, AppState>, login: Login) -> Res<Snapshot> {
    let (client, rows) = guarded_sign_in(&state, &login, None, false).await?;
    open_account(&state, &login.student_number)?;
    vault::save(&login)?;
    let snap = refresh(&state, &client, Some(rows)).await?;
    *state.client.lock().await = Some(client);
    Ok(snap)
}

/// Background refresh. Signs in again from the keychain when the session is
/// missing or expired.
#[tauri::command]
pub async fn sync(state: tauri::State<'_, AppState>) -> Res<Snapshot> {
    if cfg!(debug_assertions) && DEMO.load(Ordering::Relaxed) {
        tokio::time::sleep(std::time::Duration::from_millis(2200)).await;
        let mut snap = snapshot_of(&state)?;
        snap.last_synced = Some(now_secs());
        state.store.lock().unwrap().save(&snap).map_err(err)?;
        return Ok(snap);
    }
    let mut guard = state.client.lock().await;
    if let Some(client) = guard.as_ref() {
        match refresh(&state, client, None).await {
            Err(e) if e == sis::Error::SignedOut.to_string() => {}
            other => return other,
        }
    }
    let login = vault::load().ok_or("Not signed in")?;
    let remembered = snapshot_of(&state)?.host;
    let (client, rows) = guarded_sign_in(&state, &login, remembered.as_deref(), true).await?;
    let snap = refresh(&state, &client, Some(rows)).await?;
    *guard = Some(client);
    Ok(snap)
}

#[tauri::command]
pub async fn load_history(state: tauri::State<'_, AppState>) -> Res<Snapshot> {
    let guard = state.client.lock().await;
    let client = guard.as_ref().ok_or("Sync first")?;
    let history = client.grade_history().await.map_err(err)?;
    let mut snap = snapshot_of(&state)?;
    snap.history = history;
    state.store.lock().unwrap().save(&snap).map_err(err)?;
    Ok(snap)
}

#[tauri::command]
pub async fn sign_out(state: tauri::State<'_, AppState>) -> Res<()> {
    DEMO.store(false, Ordering::Relaxed);
    *state.client.lock().await = None;
    vault::clear();
    state.store.lock().unwrap().forget_sis().map_err(err)?;
    // eMabini still signed in: the store stays open for its data.
    if mabini_vault::load().is_some() {
        return Ok(());
    }
    // Nobody is signed in now: the landing reads an empty store, and the
    // student's own work waits in their file for the next sign-in.
    let _ = std::fs::remove_file(state.dir.join(CURRENT));
    *state.store.lock().unwrap() = Store::in_memory().map_err(err)?;
    Ok(())
}

/// The campus a student number belongs to, as the student types it.
#[tauri::command(async)]
pub fn campus(student_number: String) -> campus::Resolution {
    campus::resolve(&student_number)
}
