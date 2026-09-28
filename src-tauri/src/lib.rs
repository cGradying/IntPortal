//! The Tauri shell: holds the store and the SIS session, and exposes the core
//! to the Svelte UI as commands. Logic lives in `intportal-core`.

use intportal_core::calendar;
use intportal_core::campus;
use intportal_core::grades::{self, Goals, GradeReport, Standing};
use intportal_core::model::{ClassSession, Weekday};
use intportal_core::notes::{self, Note};
use intportal_core::schedule;
use intportal_core::sis::{self, sign_in_with_failover, Credentials, SisClient};
use intportal_core::store::{Snapshot, Store};
use intportal_core::today::{self, Agenda, Date, Glance, Mark, Meeting, Moment, Reminder, Slot, Upcoming};
use serde::{Deserialize, Serialize};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Mutex;
use std::time::{SystemTime, UNIX_EPOCH};
use tauri::Manager;

/// Set by `demo`: sync then plays a short fake trip instead of calling the
/// SIS, so review builds can show the sync moment without an account.
static DEMO: AtomicBool = AtomicBool::new(false);

struct AppState {
    store: Mutex<Store>,
    client: tokio::sync::Mutex<Option<SisClient>>,
}

type Res<T> = Result<T, String>;

fn err(e: impl std::fmt::Display) -> String {
    e.to_string()
}

#[derive(Serialize, Deserialize)]
struct Login {
    student_number: String,
    birth_month: u8,
    birth_day: u8,
    birth_year: u16,
    password: String,
}

impl From<&Login> for Credentials {
    fn from(l: &Login) -> Credentials {
        Credentials {
            student_number: l.student_number.clone(),
            birth_month: l.birth_month,
            birth_day: l.birth_day,
            birth_year: l.birth_year,
            password: l.password.clone(),
        }
    }
}

mod vault {
    //! The login lives in the platform keychain, never in the store.
    use super::Login;

    #[cfg(any(target_os = "ios", target_os = "macos"))]
    fn entry() -> Result<keyring::Entry, String> {
        keyring::Entry::new("ph.intportal.app", "sis-login").map_err(|e| e.to_string())
    }

    #[cfg(any(target_os = "ios", target_os = "macos"))]
    pub fn save(l: &Login) -> Result<(), String> {
        let json = serde_json::to_string(l).map_err(|e| e.to_string())?;
        entry()?.set_password(&json).map_err(|e| e.to_string())
    }

    #[cfg(any(target_os = "ios", target_os = "macos"))]
    pub fn load() -> Option<Login> {
        serde_json::from_str(&entry().ok()?.get_password().ok()?).ok()
    }

    #[cfg(any(target_os = "ios", target_os = "macos"))]
    pub fn clear() {
        if let Ok(e) = entry() {
            let _ = e.delete_credential();
        }
    }

    // ponytail: Android Keystore arrives with #15; until then nothing is saved there.
    #[cfg(not(any(target_os = "ios", target_os = "macos")))]
    pub fn save(_: &Login) -> Result<(), String> {
        Err("Saving your login isn't supported on this device yet.".into())
    }
    #[cfg(not(any(target_os = "ios", target_os = "macos")))]
    pub fn load() -> Option<Login> {
        None
    }
    #[cfg(not(any(target_os = "ios", target_os = "macos")))]
    pub fn clear() {}
}

fn now_secs() -> String {
    SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_secs()).unwrap_or(0).to_string()
}

fn snapshot_of(state: &AppState) -> Res<Snapshot> {
    state.store.lock().unwrap().load().map_err(err)
}

/// Pulls the schedule and current grades into the store, keeping marks,
/// colours and history.
async fn refresh(state: &AppState, client: &SisClient, rows: Option<Vec<schedule::ScheduleRow>>) -> Res<Snapshot> {
    let rows = match rows {
        Some(r) => r,
        None => client.schedule().await.map_err(err)?,
    };
    let mut snap = snapshot_of(state)?;
    snap.sessions = schedule::parse(&rows);
    // A grades page that fails keeps the last grades; only an expired
    // session fails the whole sync, so the caller can sign in again.
    match client.grades().await {
        Ok((grade_rows, summary)) => {
            snap.grades = Some(GradeReport { subjects: grades::parse(&grade_rows), summary, school_year: None, semester: None })
        }
        Err(e @ sis::Error::SignedOut) => return Err(err(e)),
        Err(_) => {}
    }
    snap.host = Some(client.host().to_string());
    snap.last_synced = Some(now_secs());
    state.store.lock().unwrap().save(&snap).map_err(err)?;
    Ok(snap)
}

#[tauri::command]
fn snapshot(state: tauri::State<'_, AppState>) -> Res<Snapshot> {
    snapshot_of(&state)
}

#[tauri::command]
fn has_login() -> bool {
    vault::load().is_some()
}

#[tauri::command]
async fn sign_in(state: tauri::State<'_, AppState>, login: Login) -> Res<Snapshot> {
    let (client, rows) = sign_in_with_failover(&(&login).into(), None).await.map_err(err)?;
    vault::save(&login)?;
    let snap = refresh(&state, &client, Some(rows)).await?;
    *state.client.lock().await = Some(client);
    Ok(snap)
}

/// Background refresh. Signs in again from the keychain when the session is
/// missing or expired.
#[tauri::command]
async fn sync(state: tauri::State<'_, AppState>) -> Res<Snapshot> {
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
    let (client, rows) = sign_in_with_failover(&(&login).into(), remembered.as_deref()).await.map_err(err)?;
    let snap = refresh(&state, &client, Some(rows)).await?;
    *guard = Some(client);
    Ok(snap)
}

#[tauri::command]
async fn load_history(state: tauri::State<'_, AppState>) -> Res<Snapshot> {
    let guard = state.client.lock().await;
    let client = guard.as_ref().ok_or("Sync first")?;
    let history = client.grade_history().await.map_err(err)?;
    let mut snap = snapshot_of(&state)?;
    snap.history = history;
    state.store.lock().unwrap().save(&snap).map_err(err)?;
    Ok(snap)
}

#[tauri::command]
async fn sign_out(state: tauri::State<'_, AppState>) -> Res<()> {
    DEMO.store(false, Ordering::Relaxed);
    *state.client.lock().await = None;
    vault::clear();
    state.store.lock().unwrap().wipe().map_err(err)
}

fn edit(state: &AppState, change: impl FnOnce(&mut Snapshot)) -> Res<Snapshot> {
    let store = state.store.lock().unwrap();
    let mut snap = store.load().map_err(err)?;
    change(&mut snap);
    store.save(&snap).map_err(err)?;
    Ok(snap)
}

/// `week` set: this week only. `mark` empty: clear it.
#[tauri::command]
fn set_mark(state: tauri::State<'_, AppState>, session_id: String, week: Option<Date>, mark: Option<Mark>) -> Res<Snapshot> {
    edit(&state, |s| s.marks.mode.set(&session_id, week, mark))
}

/// Moves a class to another day or time, for `week` only or the whole term.
/// `slot` empty: back to the SIS time.
#[tauri::command]
fn set_move(state: tauri::State<'_, AppState>, session_id: String, week: Option<Date>, slot: Option<Slot>) -> Res<Snapshot> {
    if slot.is_some_and(|s| s.end <= s.start || s.end > 24 * 60) {
        return Err("A class has to end after it starts, before midnight.".into());
    }
    edit(&state, |s| s.marks.moved.set(&session_id, week, slot))
}

/// A subject's colour; empty goes back to the automatic one.
#[tauri::command]
fn set_color(state: tauri::State<'_, AppState>, subject_code: String, color: Option<String>) -> Res<Snapshot> {
    edit(&state, |s| match color {
        Some(c) => {
            s.colors.insert(subject_code, c);
        }
        None => {
            s.colors.remove(&subject_code);
        }
    })
}

#[derive(Serialize)]
struct NoteItem {
    #[serde(flatten)]
    note: Note,
    preview: String,
}

/// Every note, the latest edit first, with a one-line preview.
#[tauri::command]
fn notes(state: tauri::State<'_, AppState>) -> Res<Vec<NoteItem>> {
    let list = state.store.lock().unwrap().notes().map_err(err)?;
    Ok(list.into_iter().map(|note| NoteItem { preview: notes::preview(&note.text, 80), note }).collect())
}

/// Saves as the student types; blank text deletes the note.
#[tauri::command]
fn set_note(state: tauri::State<'_, AppState>, key: String, text: String, title: Option<String>) -> Res<()> {
    if !(key.starts_with("class:") || key.starts_with("day:")) {
        return Err("Unknown note".into());
    }
    let now = SystemTime::now().duration_since(UNIX_EPOCH).map_or(0, |d| d.as_secs() as i64);
    state.store.lock().unwrap().set_note(&key, &text, title.as_deref(), now).map_err(err)
}

/// The term's classes as an `.ics` file, from this week through `until`.
#[tauri::command]
fn export_ics(state: tauri::State<'_, AppState>, from: Date, until: Date) -> Res<String> {
    if until < from {
        return Err("The last day of classes has to be after today.".into());
    }
    let snap = snapshot_of(&state)?;
    let now = SystemTime::now().duration_since(UNIX_EPOCH).map_or(0, |d| d.as_secs() as i64);
    Ok(calendar::ics(&snap.sessions, &snap.marks, from, until, &calendar::utc_stamp(now)))
}

/// The target GPA and the program's units; either can be empty.
#[tauri::command]
fn set_goals(state: tauri::State<'_, AppState>, goals: Goals) -> Res<Snapshot> {
    if goals.target_gpa.is_some_and(|g| !(1.0..=5.0).contains(&g)) {
        return Err("A target GPA runs from 1.00 to 5.00.".into());
    }
    if goals.program_units.is_some_and(|u| !(1.0..=400.0).contains(&u)) {
        return Err("Program units look off; check your curriculum.".into());
    }
    edit(&state, |s| s.goals = goals)
}

/// GPA, cumulative GPA, units, past terms and the target's reach.
#[tauri::command]
fn standing(state: tauri::State<'_, AppState>) -> Res<Standing> {
    let snap = snapshot_of(&state)?;
    Ok(grades::standing(snap.grades.as_ref(), &snap.history, snap.goals))
}

/// Every meeting in the week holding `on`, after marks and moves.
#[tauri::command]
fn week(state: tauri::State<'_, AppState>, on: Date) -> Res<Vec<Meeting>> {
    let snap = snapshot_of(&state)?;
    Ok(today::week(&snap.sessions, &snap.marks, on))
}

#[derive(Serialize)]
struct Today {
    agenda: Agenda,
    next: Option<Upcoming>,
    countdown: Option<String>,
    glance: Glance,
    glance_line: String,
}

#[tauri::command]
fn today(state: tauri::State<'_, AppState>, now: Moment, sync_trouble: Option<String>) -> Res<Today> {
    let snap = snapshot_of(&state)?;
    let next = today::next_class(&snap.sessions, &snap.marks, now);
    let glance = today::glance(&snap.sessions, &snap.marks, now, sync_trouble.as_deref(), false);
    Ok(Today {
        agenda: today::agenda(&snap.sessions, &snap.marks, now),
        countdown: next.as_ref().map(|n| n.countdown(now)),
        next,
        glance_line: glance.line(),
        glance,
    })
}

/// The campus a student number belongs to, as the student types it.
#[tauri::command]
fn campus(student_number: String) -> campus::Resolution {
    campus::resolve(&student_number)
}

/// The next `days` of class reminders; the UI hands them to the platform.
#[tauri::command]
fn reminders(state: tauri::State<'_, AppState>, now: Moment, lead: u16, days: u16) -> Res<Vec<Reminder>> {
    let snap = snapshot_of(&state)?;
    Ok(today::reminders(&snap.sessions, &snap.marks, now, lead, days))
}

/// Review builds only: a fake week and term so every screen can be seen
/// without an SIS account.
#[tauri::command]
fn demo(state: tauri::State<'_, AppState>, today: Date) -> Res<Snapshot> {
    if !cfg!(debug_assertions) {
        return Err("demo is only in review builds".into());
    }
    DEMO.store(true, Ordering::Relaxed);
    let s = |code: &str, desc: &str, day: Weekday, start: u16, end: u16| ClassSession {
        subject_code: code.into(),
        description: desc.into(),
        faculty: "SANTOS, JUAN".into(),
        day,
        start,
        end,
        occurrence: 0,
    };
    let wd = today.weekday();
    let sessions = vec![
        s("COMP 20073", "Data Structures and Algorithms", wd, 7 * 60 + 30, 9 * 60),
        s("GEED 10053", "Purposive Communication", wd, 10 * 60 + 30, 12 * 60),
        s("MATH 20013", "Discrete Structures", wd, 13 * 60, 14 * 60 + 30),
        s("COMP 20083", "Object-Oriented Programming", wd, 16 * 60, 19 * 60),
        s("PATHFIT 2", "Physical Activity Towards Health and Fitness 2", today.add_days(1).weekday(), 8 * 60, 10 * 60),
        s("GEED 10103", "Filipinolohiya at Pambansang Kaunlaran", today.add_days(1).weekday(), 13 * 60, 16 * 60),
    ];
    let g = |code: &str, desc: &str, units: &str, grade: &str| grades::GradeRow {
        subject_code: code.into(),
        description: desc.into(),
        faculty: "SANTOS, JUAN".into(),
        unit: units.into(),
        section_code: "1".into(),
        final_grade: grade.into(),
        grade_status: if grade.is_empty() { String::new() } else { "Passed".into() },
    };
    let rows = [
        g("COMP 20073", "Data Structures and Algorithms", "3", "1.25"),
        g("GEED 10053", "Purposive Communication", "3", "1.50"),
        g("MATH 20013", "Discrete Structures", "3", ""),
        g("COMP 20083", "Object-Oriented Programming", "3", ""),
        g("PATHFIT 2", "Physical Activity Towards Health and Fitness 2", "2", "1.00"),
        g("GEED 10103", "Filipinolohiya at Pambansang Kaunlaran", "3", ""),
    ];
    let summary = [("Admission Status", "Freshman"), ("Scholastic Status", "Regular"), ("Course", "BSCS")]
        .into_iter()
        .map(|(k, v)| (k.to_string(), v.to_string()))
        .collect();
    let history = [("2025-2026", "First Semester", ["1.50", "1.75", "1.25"]), ("2025-2026", "Second Semester", ["1.25", "1.50", "1.25"])]
        .into_iter()
        .map(|(y, sem, gs)| GradeReport {
            subjects: grades::parse(&[g("COMP 001", "Intro", "3", gs[0]), g("GEED 004", "Math", "3", gs[1]), g("GEED 005", "Comm", "3", gs[2])]),
            summary: Default::default(),
            school_year: Some(y.into()),
            semester: Some(sem.into()),
        })
        .collect();
    let snap = Snapshot {
        sessions,
        grades: Some(GradeReport { subjects: grades::parse(&rows), summary, school_year: Some("2026-2027".into()), semester: Some("First Semester".into()) }),
        history,
        host: Some("sis8.pup.edu.ph".into()),
        last_synced: Some(now_secs()),
        ..Default::default()
    };
    state.store.lock().unwrap().save(&snap).map_err(err)?;
    Ok(snap)
}

/// iOS 26 blurs and fades content under the status bar. The island glance is
/// drawn there and must stay crisp black to merge with the hardware island.
#[cfg(target_os = "ios")]
fn hide_top_edge_effect(webview: *mut std::ffi::c_void) {
    use objc2::runtime::{AnyObject, Bool};
    use objc2::{msg_send, sel};
    // SAFETY: Tauri hands us a live WKWebView; every call below is guarded by
    // respondsToSelector, so older iOS versions skip it.
    unsafe {
        let webview = &*(webview as *const AnyObject);
        let scroll: *mut AnyObject = msg_send![webview, scrollView];
        let Some(scroll) = scroll.as_ref() else { return };
        let has: Bool = msg_send![scroll, respondsToSelector: sel!(topEdgeEffect)];
        if !has.as_bool() {
            return;
        }
        let effect: *mut AnyObject = msg_send![scroll, topEdgeEffect];
        if let Some(effect) = effect.as_ref() {
            let _: () = msg_send![effect, setHidden: true];
        }
    }
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_notification::init())
        .setup(|app| {
            let dir = app.path().app_data_dir()?;
            std::fs::create_dir_all(&dir)?;
            let store = Store::open(&dir.join("intportal.sqlite")).map_err(|e| e.to_string())?;
            app.manage(AppState { store: Mutex::new(store), client: tokio::sync::Mutex::new(None) });
            #[cfg(target_os = "ios")]
            for window in app.webview_windows().values() {
                window.with_webview(|w| hide_top_edge_effect(w.inner()))?;
            }
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            snapshot, has_login, sign_in, sync, load_history, sign_out, set_mark, set_move, set_color, week, set_goals, standing, notes, set_note, export_ics, today, reminders, campus, demo
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
