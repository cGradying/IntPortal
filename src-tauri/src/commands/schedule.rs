use crate::*;

/// `week` set: this week only. `mark` empty: clear it.
#[tauri::command]
pub fn set_mark(state: tauri::State<'_, AppState>, session_id: String, week: Option<Date>, mark: Option<Mark>) -> Res<Snapshot> {
    edit(&state, |s| s.marks.mode.set(&session_id, week, mark))
}

/// Moves a class to another day or time, for `week` only or the whole term.
/// `slot` empty: back to the SIS time.
#[tauri::command]
pub fn set_move(state: tauri::State<'_, AppState>, session_id: String, week: Option<Date>, slot: Option<Slot>) -> Res<Snapshot> {
    if slot.is_some_and(|s| s.end <= s.start || s.end > 24 * 60) {
        return Err("A class has to end after it starts, before midnight.".into());
    }
    edit(&state, |s| s.marks.moved.set(&session_id, week, slot))
}

/// A subject's colour; empty goes back to the automatic one.
#[tauri::command]
pub fn set_color(state: tauri::State<'_, AppState>, subject_code: String, color: Option<String>) -> Res<Snapshot> {
    edit(&state, |s| match color {
        Some(c) => {
            s.colors.insert(subject_code, c);
        }
        None => {
            s.colors.remove(&subject_code);
        }
    })
}

/// A class's meeting link and description (030 C1, C2, C5). Blank clears; a
/// link that isn't https is refused and nothing is saved.
#[tauri::command]
pub async fn set_class_info(state: tauri::State<'_, AppState>, subject_code: String, link: Option<String>, about: Option<String>) -> Res<Snapshot> {
    // Held so a sync's refresh can't write back the snapshot it loaded before this save.
    let _sync = state.client.lock().await;
    let info = today::ClassInfo::clean(link, about)?;
    edit(&state, |s| {
        if info.is_empty() {
            s.class_info.remove(&subject_code);
        } else {
            s.class_info.insert(subject_code, info);
        }
    })
}

/// The term's classes as an `.ics` file, from this week through `until`.
#[tauri::command]
pub fn export_ics(state: tauri::State<'_, AppState>, from: Date, until: Date, utc_offset: Option<i32>) -> Res<String> {
    if until < from {
        return Err("The last day of classes has to be after today.".into());
    }
    let snap = snapshot_of(&state)?;
    let now = SystemTime::now().duration_since(UNIX_EPOCH).map_or(0, |d| d.as_secs() as i64);
    let deadlines = deadline_events(&state, &snap, from, until.days_since(from) + 1, utc_offset.unwrap_or(MANILA_OFFSET))?;
    Ok(calendar::ics(&snap.sessions, &snap.marks, &deadlines, from, until, &calendar::utc_stamp(now)))
}

/// Every meeting in the week holding `on`, after marks and moves.
#[tauri::command]
pub fn week(state: tauri::State<'_, AppState>, on: Date) -> Res<Vec<Meeting>> {
    let snap = snapshot_of(&state)?;
    Ok(today::week(&snap.sessions, &snap.marks, on))
}

#[derive(Serialize)]
pub struct Today {
    agenda: Agenda,
    next: Option<Upcoming>,
    /// The meeting link for Join on Up next (030 C4).
    join: Option<String>,
    countdown: Option<String>,
    glance: Glance,
    glance_line: String,
}

#[tauri::command]
pub fn today(state: tauri::State<'_, AppState>, now: Moment, sync_trouble: Option<String>, busy: Option<Vec<Busy>>) -> Res<Today> {
    let snap = snapshot_of(&state)?;
    let next = today::next_class(&snap.sessions, &snap.marks, now);
    let glance = today::glance(&snap.sessions, &snap.marks, now, sync_trouble.as_deref(), false);
    let mut agenda = today::agenda(&snap.sessions, &snap.marks, now);
    agenda.free_minutes_left = today::free_minutes(&agenda.items, now, &busy.unwrap_or_default());
    Ok(Today {
        agenda,
        countdown: next.as_ref().map(|n| n.countdown(now)),
        join: next.as_ref().and_then(|n| today::join_link(n, &snap.class_info)),
        next,
        glance_line: glance.line(),
        glance,
    })
}

/// The classes from `from` through `days` days on, as events for the
/// phone's IntPortal calendar.
#[tauri::command]
pub fn class_events(state: tauri::State<'_, AppState>, from: Date, days: i64, utc_offset: Option<i32>) -> Res<Vec<calendar::ClassEvent>> {
    let snap = snapshot_of(&state)?;
    let mut out = calendar::class_events(&snap.sessions, &snap.marks, from, days);
    out.extend(deadline_events(&state, &snap, from, days, utc_offset.unwrap_or(MANILA_OFFSET))?);
    Ok(out)
}

/// Spec 041 C21–C24: the one deadline list as calendar events, from `from` for `days` days.
pub(crate) fn deadline_events(state: &AppState, snap: &Snapshot, from: Date, days: i64, utc_offset: i32) -> Res<Vec<calendar::ClassEvent>> {
    let mabini = state.store.lock().unwrap().mabini().map_err(err)?;
    let list = deadline::deadlines(snap, &mabini, Moment { date: from, minute: 0 }, utc_offset, days);
    Ok(calendar::deadline_events(&list, from, utc_offset))
}
