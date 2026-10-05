//! The Tauri shell: holds the store and the SIS session, and exposes the core
//! to the Svelte UI as commands. Logic lives in `intportal-core`.

use intportal_core::calendar;
use intportal_core::campus;
use intportal_core::coach::{self, Nudge, Signals};
use intportal_core::grades::{self, Goals, GradeReport, Standing};
use intportal_core::model::{ClassSession, Weekday};
use intportal_core::notes::{self, Note};
use intportal_core::schedule;
use intportal_core::sis::{self, sign_in_with_failover, Credentials, SisClient};
use intportal_core::store::{account_file, Snapshot, Store};
use intportal_core::study::{self, Card, Deck, Memory, Rating, Stats};
use intportal_core::syllabus::{self, Component, Item, Plan, Tally};
use intportal_core::today::{self, Agenda, Busy, Date, Glance, Mark, Meeting, Moment, Reminder, Slot, Upcoming};
use serde::{Deserialize, Serialize};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Mutex;
use std::time::{SystemTime, UNIX_EPOCH};
use tauri::Manager;

/// Set by `demo`: sync then plays a short fake trip instead of calling the
/// SIS, so review builds can show the sync moment without an account.
static DEMO: AtomicBool = AtomicBool::new(false);

struct AppState {
    /// The signed-in student's store; an empty in-memory one when nobody is.
    store: Mutex<Store>,
    dir: std::path::PathBuf,
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

mod keychain {
    //! The platform's keychain: Keychain Services on Apple, values sealed by
    //! an Android Keystore key on Android (`Secrets.kt`). `Ok(None)` only
    //! when nothing is saved under the name.

    #[cfg(any(target_os = "ios", target_os = "macos"))]
    fn entry(service: &str, name: &str) -> Result<keyring::Entry, String> {
        keyring::Entry::new(service, name).map_err(|e| e.to_string())
    }

    #[cfg(any(target_os = "ios", target_os = "macos"))]
    pub fn get(service: &str, name: &str) -> Result<Option<String>, String> {
        match entry(service, name)?.get_password() {
            Ok(v) => Ok(Some(v)),
            Err(keyring::Error::NoEntry) => Ok(None),
            Err(e) => Err(e.to_string()),
        }
    }

    #[cfg(any(target_os = "ios", target_os = "macos"))]
    pub fn set(service: &str, name: &str, value: &str) -> Result<(), String> {
        entry(service, name)?.set_password(value).map_err(|e| e.to_string())
    }

    #[cfg(any(target_os = "ios", target_os = "macos"))]
    pub fn delete(service: &str, name: &str) {
        if let Ok(e) = entry(service, name) {
            let _ = e.delete_credential();
        }
    }

    #[cfg(target_os = "android")]
    mod jvm {
        use jni::objects::{JClass, JObject, JString, JValue, JValueOwned};
        use jni::{JNIEnv, JavaVM};

        /// Calls a static method of `ph.intportal.app.Secrets` with the app
        /// context first. Works from any thread: the class comes through the
        /// app's class loader, which a native thread doesn't have.
        pub fn call<T>(
            method: &str,
            sig: &str,
            args: &[&str],
            read: impl FnOnce(&mut JNIEnv, JValueOwned) -> jni::errors::Result<T>,
        ) -> Result<T, String> {
            let ctx = ndk_context::android_context();
            let vm = unsafe { JavaVM::from_raw(ctx.vm().cast()) }.map_err(|e| e.to_string())?;
            let mut env = vm.attach_current_thread().map_err(|e| e.to_string())?;
            let context = unsafe { JObject::from_raw(ctx.context().cast()) };
            let out = env.with_local_frame(16, |env| {
                let loader = env.call_method(&context, "getClassLoader", "()Ljava/lang/ClassLoader;", &[])?.l()?;
                let class_name = env.new_string("ph.intportal.app.Secrets")?;
                let class = JClass::from(
                    env.call_method(&loader, "loadClass", "(Ljava/lang/String;)Ljava/lang/Class;", &[JValue::Object(&class_name)])?.l()?,
                );
                let mut strings = Vec::with_capacity(args.len());
                for a in args {
                    strings.push(JObject::from(env.new_string(a)?));
                }
                let mut jargs = vec![JValue::Object(&context)];
                jargs.extend(strings.iter().map(JValue::Object));
                let r = env.call_static_method(&class, method, sig, &jargs)?;
                read(env, r)
            });
            out.map_err(|e| {
                // A thrown exception stays pending until cleared; say what it was.
                if env.exception_check().unwrap_or(false) {
                    let thrown = env.exception_occurred().ok();
                    let _ = env.exception_clear();
                    if let Some(t) = thrown {
                        if let Ok(m) = env.call_method(&t, "toString", "()Ljava/lang/String;", &[]).and_then(|v| v.l()) {
                            if let Ok(s) = env.get_string(&JString::from(m)) {
                                return String::from(s);
                            }
                        }
                    }
                }
                e.to_string()
            })
        }
    }

    #[cfg(target_os = "android")]
    fn key(service: &str, name: &str) -> String {
        format!("{service}/{name}")
    }

    #[cfg(target_os = "android")]
    pub fn get(service: &str, name: &str) -> Result<Option<String>, String> {
        jvm::call("get", "(Landroid/content/Context;Ljava/lang/String;)Ljava/lang/String;", &[&key(service, name)], |env, v| {
            let o = v.l()?;
            if o.is_null() {
                return Ok(None);
            }
            Ok(Some(env.get_string(&jni::objects::JString::from(o))?.into()))
        })
    }

    #[cfg(target_os = "android")]
    pub fn set(service: &str, name: &str, value: &str) -> Result<(), String> {
        jvm::call("set", "(Landroid/content/Context;Ljava/lang/String;Ljava/lang/String;)V", &[&key(service, name), value], |_, _| Ok(()))
    }

    #[cfg(target_os = "android")]
    pub fn delete(service: &str, name: &str) {
        let _ = jvm::call("delete", "(Landroid/content/Context;Ljava/lang/String;)V", &[&key(service, name)], |_, _| Ok(()));
    }

    // Desktop dev builds keep nothing.
    #[cfg(not(any(target_os = "ios", target_os = "macos", target_os = "android")))]
    pub fn get(_: &str, _: &str) -> Result<Option<String>, String> {
        Ok(None)
    }
    #[cfg(not(any(target_os = "ios", target_os = "macos", target_os = "android")))]
    pub fn set(_: &str, _: &str, _: &str) -> Result<(), String> {
        Err("Saving your login isn't supported on this device yet.".into())
    }
    #[cfg(not(any(target_os = "ios", target_os = "macos", target_os = "android")))]
    pub fn delete(_: &str, _: &str) {}
}

mod vault {
    //! The login lives in the platform keychain, never in the store.
    use super::{keychain, Login};

    const SERVICE: &str = "ph.intportal.app";
    const NAME: &str = "sis-login";

    pub fn save(l: &Login) -> Result<(), String> {
        keychain::set(SERVICE, NAME, &serde_json::to_string(l).map_err(|e| e.to_string())?)
    }

    pub fn load() -> Option<Login> {
        serde_json::from_str(&keychain::get(SERVICE, NAME).ok()??).ok()
    }

    pub fn clear() {
        keychain::delete(SERVICE, NAME)
    }
}

#[cfg(any(target_os = "ios", target_os = "macos", target_os = "android"))]
mod dbkey {
    //! Each student's store key: 32 random bytes in the keychain, named by
    //! the store's file. Made once, on the first open of that store.
    use super::keychain;

    const SERVICE: &str = "ph.intportal.app.db";

    pub fn get_or_create(file: &str) -> Result<[u8; 32], String> {
        match keychain::get(SERVICE, file)? {
            Some(hex) => parse(&hex).ok_or_else(|| "The store key in the keychain is damaged.".to_string()),
            // Only a missing key is made anew. Any other keychain error (say,
            // before the phone's first unlock) has already returned above and
            // must not replace a real key.
            None => {
                let mut key = [0u8; 32];
                getrandom::fill(&mut key).map_err(|e| e.to_string())?;
                keychain::set(SERVICE, file, &key.iter().map(|b| format!("{b:02x}")).collect::<String>())?;
                Ok(key)
            }
        }
    }

    fn parse(hex: &str) -> Option<[u8; 32]> {
        let mut key = [0u8; 32];
        if hex.len() != 64 {
            return None;
        }
        for (i, b) in key.iter_mut().enumerate() {
            *b = u8::from_str_radix(hex.get(i * 2..i * 2 + 2)?, 16).ok()?;
        }
        Some(key)
    }
}

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
    open_account(&state, &login.student_number)?;
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
    state.store.lock().unwrap().forget_sis().map_err(err)?;
    // Nobody is signed in now: the landing reads an empty store, and the
    // student's own work waits in their file for the next sign-in.
    let _ = std::fs::remove_file(state.dir.join(CURRENT));
    *state.store.lock().unwrap() = Store::in_memory().map_err(err)?;
    Ok(())
}

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

/// Everything on this phone, the student's own notes and decks included.
#[tauri::command]
fn erase_everything(state: tauri::State<'_, AppState>) -> Res<()> {
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

/// Notes as Markdown: one note by `key`, or every note when it's empty.
#[tauri::command]
fn notes_markdown(state: tauri::State<'_, AppState>, key: Option<String>) -> Res<String> {
    let mut list = state.store.lock().unwrap().notes().map_err(err)?;
    if let Some(k) = key {
        list.retain(|n| n.key == k);
    }
    Ok(notes::markdown(&list))
}

/// Saves as the student types; blank text deletes the note.
#[tauri::command]
fn set_note(state: tauri::State<'_, AppState>, key: String, text: String, title: Option<String>) -> Res<()> {
    if !notes::is_known_key(&key) {
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

/// A pasted outline read into items for the student to review; nothing saved.
#[tauri::command]
fn parse_outline(text: String, today: Date) -> Vec<Item> {
    syllabus::parse_outline(&text, today)
}

/// Replaces a subject's plan; an empty plan removes it.
#[tauri::command]
fn set_plan(state: tauri::State<'_, AppState>, subject_code: String, mut plan: Plan) -> Res<Snapshot> {
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
fn tally(components: Vec<Component>, target: f64) -> Tally {
    syllabus::tally(&components, target)
}

/// Quizzes, exams and projects due in the next `days` days, every subject.
#[tauri::command]
fn due(state: tauri::State<'_, AppState>, today: Date, days: i64) -> Res<Vec<(String, Item)>> {
    let snap = snapshot_of(&state)?;
    let all: Vec<(String, Item)> = snap.syllabus.iter().flat_map(|(code, p)| p.items.iter().map(move |i| (code.clone(), i.clone()))).collect();
    Ok(syllabus::due(&all, today, days))
}

fn unix_now() -> i64 {
    SystemTime::now().duration_since(UNIX_EPOCH).map_or(0, |d| d.as_secs() as i64)
}

#[derive(Serialize)]
struct DeckSummary {
    id: String,
    name: String,
    subject: Option<String>,
    cards: usize,
    due: usize,
}

#[derive(Serialize)]
struct StudyOverview {
    decks: Vec<DeckSummary>,
    due: usize,
    streak: u32,
    reviews_today: u32,
}

/// Every deck with its due count, and the streak as of `today`.
#[tauri::command]
fn study(state: tauri::State<'_, AppState>, today: Date) -> Res<StudyOverview> {
    let store = state.store.lock().unwrap();
    let now = unix_now();
    let decks: Vec<DeckSummary> = store
        .decks()
        .map_err(err)?
        .into_iter()
        .map(|d| DeckSummary { due: d.due(now), cards: d.cards.len(), id: d.id, name: d.name, subject: d.subject })
        .collect();
    let stats = store.study_stats().map_err(err)?;
    let reviews_today = if stats.last_day == Some(today) { stats.reviews_today } else { 0 };
    Ok(StudyOverview { due: decks.iter().map(|d| d.due).sum(), decks, streak: study::current_streak(&stats, today), reviews_today })
}

#[tauri::command]
fn deck(state: tauri::State<'_, AppState>, id: String) -> Res<Deck> {
    state.store.lock().unwrap().deck(&id).map_err(err)?.ok_or_else(|| "That deck is gone.".to_string())
}

/// Creates or replaces a deck; new cards (empty id) are numbered and due now.
#[tauri::command]
fn save_deck(state: tauri::State<'_, AppState>, mut deck: Deck) -> Res<Deck> {
    if deck.name.trim().is_empty() {
        return Err("Give the deck a name.".into());
    }
    deck.cards.retain(|c| !c.front.trim().is_empty() && !c.back.trim().is_empty());
    deck.settle_new_cards(unix_now());
    state.store.lock().unwrap().save_deck(&deck).map_err(err)?;
    Ok(deck)
}

#[tauri::command]
fn delete_deck(state: tauri::State<'_, AppState>, id: String) -> Res<()> {
    state.store.lock().unwrap().delete_deck(&id).map_err(err)
}

/// Pasted "front - back" lines as unsaved cards, for review before adding.
#[tauri::command]
fn parse_cards(text: String) -> Vec<Card> {
    study::parse_cards(&text)
        .into_iter()
        .map(|(front, back)| Card { id: String::new(), front, back, accepted: vec![], memory: Memory::new(0) })
        .collect()
}

#[derive(Serialize)]
struct Reviewed {
    deck: Deck,
    stats: Stats,
}

/// Rates one card, reschedules it and counts the review toward the streak.
#[tauri::command]
fn review_card(state: tauri::State<'_, AppState>, deck_id: String, card_id: String, rating: Rating, today: Date) -> Res<Reviewed> {
    let store = state.store.lock().unwrap();
    let mut deck = store.deck(&deck_id).map_err(err)?.ok_or("That deck is gone.")?;
    let card = deck.cards.iter_mut().find(|c| c.id == card_id).ok_or("That card is gone.")?;
    card.memory = study::review(&card.memory, rating, unix_now());
    let stats = study::count_review(&store.study_stats().map_err(err)?, today);
    store.save_deck(&deck).map_err(err)?;
    store.save_study_stats(&stats).map_err(err)?;
    Ok(Reviewed { deck, stats })
}

#[tauri::command]
fn check_answer(card: Card, typed: String) -> bool {
    study::is_correct(&typed, &card)
}

#[tauri::command]
fn distractors(cards: Vec<Card>, index: usize, seed: usize) -> Res<Vec<String>> {
    if index >= cards.len() {
        return Err("No such card.".into());
    }
    Ok(study::distractors(&cards, index, 3, seed))
}

#[derive(Serialize)]
struct CoachLine {
    nudge: Nudge,
    line: String,
    key: String,
}

/// Today's one nudge, from deadlines, flashcards, free time and the target
/// GPA. `dismissed` holds the keys waved off today.
#[tauri::command]
fn coach(state: tauri::State<'_, AppState>, now: Moment, dismissed: Vec<String>, busy: Option<Vec<Busy>>) -> Res<Option<CoachLine>> {
    let store = state.store.lock().unwrap();
    let snap = store.load().map_err(err)?;
    let unix = unix_now();
    let items: Vec<(String, Item)> = snap.syllabus.iter().flat_map(|(c, p)| p.items.iter().map(move |i| (c.clone(), i.clone()))).collect();
    let stats = store.study_stats().map_err(err)?;
    let agenda = today::agenda(&snap.sessions, &snap.marks, now);
    let needed = snap.goals.target_gpa.zip(snap.grades.as_ref()).and_then(|(t, g)| grades::needed_average(&g.subjects, t).filter(|n| (1.0..5.0).contains(n)).map(|n| (n, t)));
    let signals = Signals {
        due_soon: syllabus::due(&items, now.date, 2).into_iter().map(|(c, i)| (c, i.topic)).collect(),
        cards_due: store.decks().map_err(err)?.iter().map(|d| d.due(unix)).sum(),
        study_streak: study::current_streak(&stats, now.date),
        studied_today: stats.last_day == Some(now.date),
        free_minutes: today::free_minutes(&agenda.items, now, &busy.unwrap_or_default()),
        needed_average: needed,
        classes_left: agenda.items.iter().filter(|i| i.phase != today::Phase::Past).count(),
    };
    Ok(coach::pick(&signals, &dismissed).map(|n| CoachLine { line: n.line(), key: n.key(), nudge: n }))
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
fn today(state: tauri::State<'_, AppState>, now: Moment, sync_trouble: Option<String>, busy: Option<Vec<Busy>>) -> Res<Today> {
    let snap = snapshot_of(&state)?;
    let next = today::next_class(&snap.sessions, &snap.marks, now);
    let glance = today::glance(&snap.sessions, &snap.marks, now, sync_trouble.as_deref(), false);
    let mut agenda = today::agenda(&snap.sessions, &snap.marks, now);
    agenda.free_minutes_left = today::free_minutes(&agenda.items, now, &busy.unwrap_or_default());
    Ok(Today {
        agenda,
        countdown: next.as_ref().map(|n| n.countdown(now)),
        next,
        glance_line: glance.line(),
        glance,
    })
}

/// The classes from `from` through `days` days on, as events for the
/// phone's IntPortal calendar.
#[tauri::command]
fn class_events(state: tauri::State<'_, AppState>, from: Date, days: i64) -> Res<Vec<calendar::ClassEvent>> {
    let snap = snapshot_of(&state)?;
    Ok(calendar::class_events(&snap.sessions, &snap.marks, from, days))
}

/// The campus a student number belongs to, as the student types it.
#[tauri::command]
fn campus(student_number: String) -> campus::Resolution {
    campus::resolve(&student_number)
}

/// Extra reminders the student turned on; a minute of the day, or empty for off.
#[derive(Deserialize, Default)]
struct ReminderPrefs {
    deadlines: Option<u16>,
    study: Option<u16>,
    /// Local minus UTC, in minutes.
    utc_offset: i32,
}

/// The next `days` of reminders, soonest first: classes, deadlines the
/// evening before, and study days. The UI hands them to the platform.
#[tauri::command]
fn reminders(state: tauri::State<'_, AppState>, now: Moment, lead: u16, days: u16, prefs: Option<ReminderPrefs>) -> Res<Vec<Reminder>> {
    let store = state.store.lock().unwrap();
    let snap = store.load().map_err(err)?;
    let prefs = prefs.unwrap_or_default();
    let mut out = if lead > 0 { today::reminders(&snap.sessions, &snap.marks, now, lead, days) } else { vec![] };
    if let Some(minute) = prefs.deadlines {
        let items: Vec<(String, Item)> = snap.syllabus.iter().flat_map(|(c, p)| p.items.iter().map(move |i| (c.clone(), i.clone()))).collect();
        out.extend(syllabus::deadline_reminders(&items, now, minute, i64::from(days)));
    }
    if let Some(minute) = prefs.study {
        out.extend(study::study_reminders(&store.decks().map_err(err)?, now, minute, i64::from(days), prefs.utc_offset));
    }
    out.sort_by_key(|r| (r.date, r.minute));
    Ok(out)
}

/// Review builds only: a fake week and term so every screen can be seen
/// without an SIS account.
#[tauri::command]
fn demo(state: tauri::State<'_, AppState>, today: Date) -> Res<Snapshot> {
    if !cfg!(debug_assertions) {
        return Err("demo is only in review builds".into());
    }
    DEMO.store(true, Ordering::Relaxed);
    open_account(&state, "demo")?;
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
    // Only the SIS side is fake; the student's own marks, goals and pages stay.
    let snap = Snapshot {
        sessions,
        grades: Some(GradeReport { subjects: grades::parse(&rows), summary, school_year: Some("2026-2027".into()), semester: Some("First Semester".into()) }),
        history,
        host: Some("sis8.pup.edu.ph".into()),
        last_synced: Some(now_secs()),
        ..snapshot_of(&state)?
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
    let builder = tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_notification::init());
    #[cfg(mobile)]
    let builder = builder.plugin(tauri_plugin_haptics::init()).plugin(tauri_plugin_biometric::init()).plugin(tauri_plugin_glance::init()).plugin(tauri_plugin_calendar::init());
    builder
        .setup(|app| {
            let dir = app.path().app_data_dir()?;
            std::fs::create_dir_all(&dir)?;
            let store = match std::fs::read_to_string(dir.join(CURRENT)) {
                Ok(name) if name.starts_with("account-") => open_store(&dir, name.trim())?,
                _ => Store::in_memory().map_err(err)?,
            };
            app.manage(AppState { store: Mutex::new(store), dir: dir.clone(), client: tokio::sync::Mutex::new(None) });
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
            snapshot, has_login, sign_in, sync, load_history, sign_out, erase_everything, set_mark, set_move, set_color, week, set_goals, standing, notes, set_note, notes_markdown, export_ics, parse_outline, set_plan, tally, due, study, deck, save_deck, delete_deck, parse_cards, review_card, check_answer, distractors, coach, today, class_events, reminders, campus, demo
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
