use crate::*;

/// One eMabini credential POST, under the same rules as the SIS: 3 tries per
/// 15 minutes, none by itself after a rejection (`auto`). The count is saved
/// even when the sign-in fails.
pub(crate) async fn guarded_mabini_sign_in(state: &AppState, login: &MabiniLogin, auto: bool) -> Res<MabiniClient> {
    let mut ledger = state.mabini_ledger.lock().await;
    let r = sis::post_once(&mut ledger, unix_now() as u64, auto, LoginPage::fetch(), |page| page.sign_in(&login.student_number, &login.password)).await;
    if let Ok(json) = serde_json::to_string(&*ledger) {
        let _ = std::fs::write(state.dir.join(MABINI_GUARD_FILE), json);
    }
    r.map_err(err)
}

pub(crate) async fn mabini_refresh(state: &AppState, client: &MabiniClient) -> Res<MabiniData> {
    let previous = state.store.lock().unwrap().mabini().map_err(err)?;
    let data = client.sync(unix_now(), &previous).await.map_err(err)?;
    state.store.lock().unwrap().save_mabini(&data).map_err(err)?;
    Ok(data)
}

/// The store eMabini data goes in: the SIS student's when one is signed in
/// (another number is refused), else the typed student's (`Some`, to open).
pub(crate) fn mabini_account<'a>(sis_number: Option<&str>, typed: &'a str) -> Res<Option<&'a str>> {
    match sis_number {
        Some(n) if account_file(n) == account_file(typed) => Ok(None),
        Some(_) => Err("That isn't the student number signed in to the SIS on this phone. Use your own eMabini login, or sign out of the SIS first.".into()),
        None => Ok(Some(typed)),
    }
}

#[tauri::command]
pub async fn mabini_sign_in(state: tauri::State<'_, AppState>, login: MabiniLogin) -> Res<MabiniData> {
    let open = mabini_account(vault::load().as_ref().map(|l| l.student_number.as_str()), &login.student_number)?;
    let client = guarded_mabini_sign_in(&state, &login, false).await?;
    if let Some(n) = open {
        open_account(&state, n)?;
    }
    mabini_vault::save(&login)?;
    let data = mabini_refresh(&state, &client).await?;
    *state.mabini.lock().await = Some(client);
    Ok(data)
}

/// Background refresh of eMabini. Signs in again from the keychain only when
/// the session expired, and never after a rejection.
#[tauri::command]
pub async fn mabini_sync(state: tauri::State<'_, AppState>) -> Res<MabiniData> {
    if cfg!(debug_assertions) && DEMO.load(Ordering::Relaxed) {
        tokio::time::sleep(std::time::Duration::from_millis(1200)).await;
        return state.store.lock().unwrap().mabini().map_err(err);
    }
    let mut guard = state.mabini.lock().await;
    if let Some(client) = guard.as_ref() {
        match mabini_refresh(&state, client).await {
            Err(e) if e == sis::Error::SignedOut.to_string() => {}
            other => return other,
        }
    }
    let login = mabini_vault::load().ok_or("Not signed in to Mabini")?;
    let client = guarded_mabini_sign_in(&state, &login, true).await?;
    let data = mabini_refresh(&state, &client).await?;
    *guard = Some(client);
    Ok(data)
}

/// What the last eMabini sync kept, without touching the network.
#[tauri::command(async)]
pub fn mabini_data(state: tauri::State<'_, AppState>) -> Res<MabiniData> {
    state.store.lock().unwrap().mabini().map_err(err)
}

#[tauri::command(async)]
pub fn has_mabini_login() -> bool {
    (cfg!(debug_assertions) && DEMO.load(Ordering::Relaxed)) || mabini_vault::load().is_some()
}

#[tauri::command]
pub async fn mabini_tries_left(state: tauri::State<'_, AppState>) -> Res<Tries> {
    let l = state.mabini_ledger.lock().await;
    let now = unix_now() as u64;
    Ok(Tries { left: l.tries_left(now), retry_at: l.retry_at(now), rejected: l.rejected() })
}

#[tauri::command]
pub async fn mabini_sign_out(state: tauri::State<'_, AppState>) -> Res<()> {
    *state.mabini.lock().await = None;
    mabini_vault::clear();
    state.store.lock().unwrap().forget_mabini().map_err(err)?;
    // No SIS login either: nobody is signed in, so detach the store like sign_out does.
    if vault::load().is_none() {
        let _ = std::fs::remove_file(state.dir.join(CURRENT));
        *state.store.lock().unwrap() = Store::in_memory().map_err(err)?;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn c128_1_mabini_attaches_only_to_the_signed_in_student() {
        assert_eq!(mabini_account(Some("2024-00001-MN-0"), "2024-00001-mn-0"), Ok(None), "same student: keep the open store");
        assert!(mabini_account(Some("2024-00001-MN-0"), "2024-00002-MN-0").is_err(), "another student's number is refused");
        assert_eq!(mabini_account(None, "2024-00002-MN-0"), Ok(Some("2024-00002-MN-0")), "eMabini alone opens that student's store");
    }
}
