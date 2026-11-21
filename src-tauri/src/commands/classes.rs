use crate::*;
use intportal_core::own_class::{self, OwnClass};

/// Adds the student's own class, or replaces the own class whose code was `was` (spec 060 C1 to C4).
#[tauri::command(async)]
pub fn save_class(state: tauri::State<'_, AppState>, was: Option<String>, class: OwnClass) -> Res<Snapshot> {
    let store = state.store.lock().unwrap();
    let mut snap = store.load().map_err(err)?;
    own_class::save(&mut snap, was.as_deref(), class).map_err(err)?;
    store.save(&snap).map_err(err)?;
    Ok(snap)
}

#[tauri::command(async)]
pub fn delete_class(state: tauri::State<'_, AppState>, code: String) -> Res<Snapshot> {
    edit(&state, |snap| own_class::remove(snap, &code))
}

/// Opens own schedule's file and names the school (C7). Choosing it again opens the same file (C9).
#[tauri::command(async)]
pub fn start_own(state: tauri::State<'_, AppState>, school: String) -> Res<Snapshot> {
    let school = school.split_whitespace().collect::<Vec<_>>().join(" ");
    if school.is_empty() || school.chars().count() > 60 {
        return Err("Type your school's name.".into());
    }
    DEMO.store(false, Ordering::Relaxed);
    open_account(&state, OWN_KEY)?;
    edit(&state, |snap| snap.school = Some(school))
}

/// The school's name while own schedule is the open file, else nothing (C8).
#[tauri::command(async)]
pub fn own_schedule(state: tauri::State<'_, AppState>) -> Option<String> {
    if !own_open(&state) {
        return None;
    }
    snapshot_of(&state).ok().map(|s| s.school.unwrap_or_default())
}

/// Closes own schedule; its file stays on the phone (C9).
#[tauri::command(async)]
pub fn leave_own(state: tauri::State<'_, AppState>) -> Res<()> {
    if own_open(&state) {
        let _ = std::fs::remove_file(state.dir.join(CURRENT));
        *state.store.lock().unwrap() = Store::in_memory().map_err(err)?;
    }
    Ok(())
}
