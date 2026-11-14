use crate::*;

/// A pasted outline read into items for the student to review; nothing saved.
#[tauri::command]
pub fn parse_outline(text: String, today: Date) -> Vec<Item> {
    syllabus::parse_outline(&text, today)
}

/// Replaces a subject's plan; an empty plan removes it.
#[tauri::command]
pub fn set_plan(state: tauri::State<'_, AppState>, subject_code: String, mut plan: Plan) -> Res<Snapshot> {
    if plan.grading.iter().any(|c| !(0.0..=100.0).contains(&c.weight) || c.score.is_some_and(|s| !(0.0..=100.0).contains(&s))) {
        return Err("Weights and scores are percents, 0 to 100.".into());
    }
    plan.assign_ids();
    edit(&state, |s| {
        if plan == Plan::default() {
            s.syllabus.remove(&subject_code);
        } else {
            s.syllabus.insert(subject_code, plan);
        }
    })
}

/// The grading arithmetic, live while the student edits.
#[tauri::command]
pub fn tally(components: Vec<Component>, target: f64) -> Tally {
    syllabus::tally(&components, target)
}

/// The one deadline list (spec 041): syllabus, eMabini and the student's own,
/// overdue for up to three days, then the next `days` days, soonest first.
#[tauri::command]
pub fn deadlines(state: tauri::State<'_, AppState>, now: Moment, utc_offset: i32, days: i64) -> Res<Vec<Deadline>> {
    let store = state.store.lock().unwrap();
    Ok(deadline::deadlines(&store.load().map_err(err)?, &store.mabini().map_err(err)?, now, utc_offset, days))
}

/// Marks a deadline done or not (041 C5, C6). A syllabus item ticks its own
/// box; eMabini and own deadlines are remembered on this phone.
#[tauri::command]
pub fn set_done(state: tauri::State<'_, AppState>, id: String, done: bool) -> Res<Snapshot> {
    edit(&state, |snap| match id.strip_prefix("syl:").and_then(|rest| rest.rsplit_once(':')) {
        Some((code, item)) => {
            if let Some(i) = snap.syllabus.get_mut(code).and_then(|p| p.items.iter_mut().find(|i| i.id == item)) {
                i.done = done;
            }
        }
        None if done => {
            snap.done.insert(id);
        }
        None => {
            snap.done.remove(&id);
        }
    })
}

/// Adds the student's own deadline (an empty `id`) or replaces the one with that id (041 C12, C14).
#[tauri::command]
pub fn save_own(state: tauri::State<'_, AppState>, mut own: OwnDeadline) -> Res<Snapshot> {
    let title = own.title.trim().to_string();
    if title.is_empty() {
        return Err("Give it a name first.".into());
    }
    own.title = title;
    if own.id.is_empty() {
        own.id = format!("{:x}", std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map_err(err)?.as_nanos());
    }
    edit(&state, |snap| match snap.own_deadlines.iter_mut().find(|o| o.id == own.id) {
        Some(o) => *o = own,
        None => snap.own_deadlines.push(own),
    })
}

#[tauri::command]
pub fn delete_own(state: tauri::State<'_, AppState>, id: String) -> Res<Snapshot> {
    edit(&state, |snap| {
        snap.own_deadlines.retain(|o| o.id != id);
        snap.done.remove(&format!("own:{id}"));
    })
}

/// Reads typed, pasted or scanned text into drafts for the student to confirm (041 C11, C13, C17).
#[tauri::command]
pub fn parse_own(state: tauri::State<'_, AppState>, text: String, today: Date) -> Res<Vec<Draft>> {
    let snap = snapshot_of(&state)?;
    let mut subjects: Vec<(String, String)> = snap.sessions.iter().map(|s| (s.subject_code.clone(), s.description.clone())).collect();
    subjects.sort();
    subjects.dedup();
    Ok(deadline::parse_own(&text, today, &subjects))
}
