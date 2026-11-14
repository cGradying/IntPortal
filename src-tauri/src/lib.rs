//! The Tauri shell: holds the store and the SIS session, and exposes the core
//! to the Svelte UI as commands. Logic lives in `intportal-core`.

use intportal_core::calendar;
use intportal_core::campus;
use intportal_core::coach::{self, Nudge, PlanStep, Signals};
use intportal_core::nudge;
use intportal_core::deadline::{self, Deadline, Draft, OwnDeadline};
use intportal_core::grades::{self, Goals, GradeReport, Standing};
use intportal_core::mabini::{LoginPage, MabiniClient, MabiniData};
use intportal_core::model::{ClassSession, Weekday};
use intportal_core::notes::{self, Note};
use intportal_core::schedule;
use intportal_core::sis::{self, sign_in_guarded, Credentials, Ledger, SisClient};
use intportal_core::backup::{self, Backup};
use intportal_core::store::{self, account_file, NewPhoto, Photo, Snapshot, Store};
use intportal_core::study::{self, Card, Deck, Memory, Rating, Stats};
use intportal_core::syllabus::{self, Component, Item, Plan, Tally};
use intportal_core::today::{self, Agenda, Busy, Date, Glance, Mark, Meeting, Moment, Reminder, Slot, Upcoming};
use serde::{Deserialize, Serialize};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Mutex;
use std::time::{SystemTime, UNIX_EPOCH};
use tauri::Manager;

mod ai;
mod commands;
mod demo;

// Every command and helper is in scope here, so the handler list below names them plainly
// and the modules reach each other through `use crate::*`.
use commands::{account::*, backup::*, coach::*, deadlines::*, mabini::*, notes::*, schedule::*, study::*};
use demo::*;

/// Set by `demo`: sync then plays a short fake trip instead of calling the
/// SIS, so review builds can show the sync moment without an account.
static DEMO: AtomicBool = AtomicBool::new(false);

struct AppState {
    /// The signed-in student's store; an empty in-memory one when nobody is.
    store: Mutex<Store>,
    dir: std::path::PathBuf,
    client: tokio::sync::Mutex<Option<SisClient>>,
    /// Sign-in tries in the last 15 minutes. Held for the whole sign-in, so a
    /// tap and a background sync can't both spend the same try.
    ledger: tokio::sync::Mutex<Ledger>,
    /// eMabini counts apart from the SIS: a rejected SIS login never spends its tries.
    mabini_ledger: tokio::sync::Mutex<Ledger>,
    mabini: tokio::sync::Mutex<Option<MabiniClient>>,
}

const GUARD_FILE: &str = "login-guard.json";
const MABINI_GUARD_FILE: &str = "mabini-guard.json";

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

#[derive(Serialize, Deserialize)]
struct MabiniLogin {
    student_number: String,
    password: String,
}

mod keychain;

mod vault;

#[cfg(any(target_os = "ios", target_os = "macos", target_os = "android"))]
mod dbkey;

/// Opens one student's store with its key. A store the key can't open is
/// set aside, not deleted (the key may come back), and a fresh one starts:
/// the SIS data returns on the next sync.
fn open_store(dir: &std::path::Path, file: &str) -> Res<Store> {
    let path = dir.join(file);
    #[cfg(any(target_os = "ios", target_os = "macos", target_os = "android"))]
    {
        let key = dbkey::get_or_create(file)?;
        match Store::open(&path, &key) {
            Err(intportal_core::store::StoreError::Locked) => {
                std::fs::rename(&path, dir.join(format!("{file}.locked-{}", now_secs()))).map_err(err)?;
                Store::open(&path, &key).map_err(err)
            }
            opened => opened.map_err(err),
        }
    }
    #[cfg(not(any(target_os = "ios", target_os = "macos", target_os = "android")))]
    {
        Store::open_plain(&path).map_err(err)
    }
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

fn load_ledger(dir: &std::path::Path, file: &str) -> Ledger {
    std::fs::read_to_string(dir.join(file)).ok().and_then(|s| serde_json::from_str(&s).ok()).unwrap_or_default()
}

mod mabini_vault;

/// Names the file of the student signed in last, so a relaunch opens it.
const CURRENT: &str = "current-account";
/// The single store from before stores were per student.
const LEGACY: &str = "intportal.sqlite";

/// Switches to this student's own store. The first student to sign in after
/// the upgrade inherits the old single store.
fn open_account(state: &AppState, student_number: &str) -> Res<()> {
    let name = account_file(student_number);
    let path = state.dir.join(&name);
    let legacy = state.dir.join(LEGACY);
    if !path.exists() && legacy.exists() {
        std::fs::rename(&legacy, &path).map_err(err)?;
    }
    *state.store.lock().unwrap() = open_store(&state.dir, &name)?;
    std::fs::write(state.dir.join(CURRENT), &name).map_err(err)
}

/// The student number whose store is open: the signed-in number whose file is
/// the one `current-account` names. Not just "whoever is signed in", since
/// signing out of the SIS with eMabini still in leaves the SIS student's store open.
fn open_student(state: &AppState) -> Option<String> {
    let open = std::fs::read_to_string(state.dir.join(CURRENT)).ok()?;
    [vault::load().map(|l| l.student_number), mabini_vault::load().map(|l| l.student_number)]
        .into_iter()
        .flatten()
        .find(|n| account_file(n) == open.trim())
}

fn edit(state: &AppState, change: impl FnOnce(&mut Snapshot)) -> Res<Snapshot> {
    let store = state.store.lock().unwrap();
    let mut snap = store.load().map_err(err)?;
    change(&mut snap);
    store.save(&snap).map_err(err)?;
    Ok(snap)
}

/// Runs `f` on the blocking pool: photo work waits on the store and the disk, and a sync command would freeze the UI.
async fn blocking<T: Send + 'static>(app: tauri::AppHandle, f: impl FnOnce(&AppState) -> Res<T> + Send + 'static) -> Res<T> {
    tauri::async_runtime::spawn_blocking(move || {
        let state = app.state::<AppState>();
        f(&state)
    })
    .await
    .map_err(err)?
}

const PHOTO_TMP: &str = "photo-tmp";

/// Minutes ahead of UTC in the school's time zone, for a phone that does not say its own.
pub(crate) const MANILA_OFFSET: i32 = 480;

fn unix_now() -> i64 {
    SystemTime::now().duration_since(UNIX_EPOCH).map_or(0, |d| d.as_secs() as i64)
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
    let builder = tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_notification::init());
    #[cfg(mobile)]
    let builder = builder.plugin(tauri_plugin_haptics::init()).plugin(tauri_plugin_biometric::init()).plugin(tauri_plugin_glance::init()).plugin(tauri_plugin_calendar::init()).plugin(tauri_plugin_camera::init());
    builder
        .manage(ai::AiState::default())
        .setup(|app| {
            let dir = app.path().app_data_dir()?;
            std::fs::create_dir_all(&dir)?;
            // A photo the plugin saved but nobody took in (046 Data).
            let _ = std::fs::remove_dir_all(dir.join(PHOTO_TMP));
            let store = match std::fs::read_to_string(dir.join(CURRENT)) {
                Ok(name) if name.starts_with("account-") => open_store(&dir, name.trim())?,
                _ => Store::in_memory().map_err(err)?,
            };
            app.manage(AppState { store: Mutex::new(store), dir: dir.clone(), client: tokio::sync::Mutex::new(None), ledger: tokio::sync::Mutex::new(load_ledger(&dir, GUARD_FILE)),
                mabini_ledger: tokio::sync::Mutex::new(load_ledger(&dir, MABINI_GUARD_FILE)),
                mabini: tokio::sync::Mutex::new(None),
            });
            // Signed in before stores were per student: move them over now.
            if !dir.join(CURRENT).exists() {
                if let Some(login) = vault::load() {
                    open_account(&app.state::<AppState>(), &login.student_number)?;
                }
            }
            #[cfg(target_os = "ios")]
            for window in app.webview_windows().values() {
                window.with_webview(|w| hide_top_edge_effect(w.inner()))?;
            }
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            snapshot, has_login, portals, tries_left, mabini_sign_in, mabini_sync, mabini_data, has_mabini_login, login_hint, mabini_tries_left, mabini_sign_out, sign_in, sync, load_history, sign_out, erase_everything, backup_make, backup_preview, backup_restore, space_used, set_mark, set_move, set_color, set_class_info, week, set_goals, standing, notes, set_note, delete_note, photo_dir, add_photo, note_photos, photo_bytes, photo_thumb, set_photo_thumb, notes_zip, delete_photo, set_note_pin, set_note_subject, entry_date, notes_markdown, export_ics, parse_outline, set_plan, tally, deadlines, set_done, save_own, delete_own, parse_own, study, deck, save_deck, delete_deck, parse_cards, review_card, check_answer, distractors, coach, today, class_events, reminders, campus, demo,
            ai::ai_models, ai::ai_small_ram, ai::ai_download, ai::ai_delete, ai::ai_load, ai::ai_unload, ai::ai_index, ai::ai_cancel, ai::ai_ask, ai::ai_history, ai::ai_clear_history, ai::ai_note, ai::ai_why, ai::ai_cards, ai::ai_pdf_text, ai::ai_outline_text, ai::ai_guide
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
