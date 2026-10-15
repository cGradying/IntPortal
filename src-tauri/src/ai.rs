//! On-device AI commands (ADR 0003). None of them writes: IntAssis returns a
//! proposal and the UI confirms it through the existing commands.
use crate::{err, snapshot_of, AppState, Res};
use intportal_ai::{
    assis::{self, Facts, Proposal},
    gen,
    intent::{self, Intent},
    llm::Llm,
    models::{self, Gate, Kind, Model},
    outline, pdf,
    prompt::Template,
    rag, why,
};
use intportal_core::{
    notes,
    syllabus::{self, Item},
    today::{self, Date, Moment},
};
use intportal_llm::{backup, download, mem, Device, Llama};
use serde::Serialize;
use std::{
    path::PathBuf,
    sync::{atomic::{AtomicBool, Ordering}, Arc, Mutex},
};
use tauri::{ipc::Channel, Manager};

struct Loaded {
    id: String,
    tpl: Template,
    llm: Box<dyn Llm>,
}

/// One chat model and, beside it, the small embedding model that finds the
/// student's notes. A busy slot fails fast instead of queueing.
#[derive(Default)]
pub struct AiState {
    engine: Arc<Mutex<Option<Loaded>>>,
    embedder: Arc<Mutex<Option<Loaded>>>,
    cancel: Arc<AtomicBool>,
}

impl AiState {
    /// The slot a model of this kind lives in.
    fn slot(&self, m: &Model) -> Arc<Mutex<Option<Loaded>>> {
        if m.kind == Kind::Embed { self.embedder.clone() } else { self.engine.clone() }
    }
}

fn models_dir(app: &tauri::AppHandle) -> Res<PathBuf> {
    Ok(app.path().app_data_dir().map_err(|e| e.to_string())?.join("models"))
}

/// Gemma and Qwen want different prompt wrappers.
fn template_for(m: &Model) -> Template {
    if m.id.starts_with("gemma") { Template::Gemma } else { Template::ChatMl }
}

/// The simulator's Metal is software and slower than the CPU.
fn device() -> Device {
    if cfg!(all(target_os = "ios", target_abi = "sim")) { Device::Cpu } else { Device::Gpu }
}

/// Stops the model when the student cancels.
struct Cancellable<'a> {
    inner: &'a mut dyn Llm,
    cancel: &'a AtomicBool,
}

impl Llm for Cancellable<'_> {
    fn generate(&mut self, prompt: &str, schema: Option<&serde_json::Value>, max: u32, on_token: &mut dyn FnMut(&str) -> bool) -> Result<String, String> {
        let cancel = self.cancel;
        self.inner.generate(prompt, schema, max, &mut |t| on_token(t) && !cancel.load(Ordering::Relaxed))
    }
    fn embed(&mut self, texts: &[&str]) -> Result<Vec<Vec<f32>>, String> {
        self.inner.embed(texts)
    }
}

#[derive(Serialize)]
pub struct ModelInfo {
    id: &'static str,
    name: &'static str,
    chat: bool,
    bytes: u64,
    installed: bool,
    default: bool,
    /// "ok", "warn" (over 60% of available memory) or "refuse" (over 90%).
    fits: &'static str,
    loaded: bool,
}

/// The Storage view's list: every model, whether it is on the phone, whether it fits.
#[tauri::command]
pub fn ai_models(app: tauri::AppHandle, ai: tauri::State<'_, AiState>) -> Res<Vec<ModelInfo>> {
    let dir = models_dir(&app)?;
    let loaded: Vec<String> = [&ai.engine, &ai.embedder].iter().filter_map(|s| s.try_lock().ok().and_then(|e| e.as_ref().map(|l| l.id.clone()))).collect();
    Ok(models::CATALOG
        .iter()
        .map(|m| ModelInfo {
            id: m.id,
            name: m.name,
            chat: m.kind == models::Kind::Chat,
            bytes: m.bytes,
            installed: dir.join(m.file).metadata().is_ok_and(|f| f.len() == m.bytes),
            default: m.id == models::DEFAULT_CHAT,
            fits: match models::gate(m, mem::available()) { Gate::Ok => "ok", Gate::Warn => "warn", Gate::Refuse => "refuse" },
            loaded: loaded.iter().any(|l| l == m.id),
        })
        .collect())
}

#[derive(Clone, Serialize)]
pub struct Progress {
    done: u64,
    total: u64,
}

/// Downloads a model, reporting progress. Cancel with `ai_cancel`; a later call resumes.
#[tauri::command]
pub async fn ai_download(app: tauri::AppHandle, ai: tauri::State<'_, AiState>, id: String, on_progress: Channel<Progress>) -> Res<()> {
    let m = *models::find(&id).ok_or("Unknown model")?;
    let dir = models_dir(&app)?;
    let cancel = ai.cancel.clone();
    cancel.store(false, Ordering::Relaxed);
    tokio::task::spawn_blocking(move || {
        std::fs::create_dir_all(&dir).map_err(|e| e.to_string())?;
        backup::exclude(&dir)?;
        download::download(&m, &dir, &mut |done, total| {
            let _ = on_progress.send(Progress { done, total });
            !cancel.load(Ordering::Relaxed)
        })
        .map(|_| ())
    })
    .await
    .map_err(|e| e.to_string())?
}

/// Deletes a model and its half-finished download; unloads it first if it is the loaded one.
#[tauri::command]
pub fn ai_delete(app: tauri::AppHandle, ai: tauri::State<'_, AiState>, id: String) -> Res<()> {
    let m = models::find(&id).ok_or("Unknown model")?;
    let slot = ai.slot(m);
    let mut engine = slot.try_lock().map_err(|_| "IntAssis is busy".to_string())?;
    if engine.as_ref().is_some_and(|l| l.id == id) {
        *engine = None;
    }
    drop(engine);
    let dir = models_dir(&app)?;
    for f in [m.file.to_string(), format!("{}.part", m.file)] {
        match std::fs::remove_file(dir.join(f)) {
            Ok(()) => {}
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => {}
            Err(e) => return Err(e.to_string()),
        }
    }
    Ok(())
}

/// Loads a downloaded model into memory, unless the phone can't hold it.
#[tauri::command]
pub async fn ai_load(app: tauri::AppHandle, ai: tauri::State<'_, AiState>, id: String) -> Res<()> {
    let m = *models::find(&id).ok_or("Unknown model")?;
    if models::gate(&m, mem::available()) == Gate::Refuse {
        return Err("This model needs more memory than this phone has free. Try a smaller one.".into());
    }
    let path = models_dir(&app)?.join(m.file);
    if !path.exists() {
        return Err("Download the model first".into());
    }
    let slot = ai.slot(&m);
    tokio::task::spawn_blocking(move || load_into(&slot, &m, &path)).await.map_err(|e| e.to_string())?
}

fn load_into(slot: &Mutex<Option<Loaded>>, m: &Model, path: &std::path::Path) -> Res<()> {
    let mut slot = slot.try_lock().map_err(|_| "IntAssis is busy".to_string())?;
    *slot = None; // free the old one before the new one loads
    let llm = Llama::load(path, m.n_ctx, device())?;
    *slot = Some(Loaded { id: m.id.into(), tpl: template_for(m), llm: Box::new(llm) });
    Ok(())
}

/// The UI calls this when the app is hidden: iOS ends an app that holds a
/// gigabyte in the background.
#[tauri::command]
pub fn ai_unload(ai: tauri::State<'_, AiState>) {
    ai.cancel.store(true, Ordering::Relaxed);
    for slot in [&ai.engine, &ai.embedder] {
        if let Ok(mut e) = slot.lock() {
            *e = None;
        }
    }
}

#[tauri::command]
pub fn ai_cancel(ai: tauri::State<'_, AiState>) {
    ai.cancel.store(true, Ordering::Relaxed);
}

/// Runs `f` on the loaded model off the UI thread. Fails fast when another
/// request holds it, and clears the cancel flag first.
async fn with_model<T: Send + 'static>(ai: &AiState, f: impl FnOnce(&mut dyn Llm, Template) -> Res<T> + Send + 'static) -> Res<T> {
    let (engine, cancel) = (ai.engine.clone(), ai.cancel.clone());
    cancel.store(false, Ordering::Relaxed);
    tokio::task::spawn_blocking(move || {
        let mut slot = engine.try_lock().map_err(|_| "IntAssis is busy".to_string())?;
        let l = slot.as_mut().ok_or("Turn IntAssis on first")?;
        f(&mut Cancellable { inner: l.llm.as_mut(), cancel: &cancel }, l.tpl)
    })
    .await
    .map_err(|e| e.to_string())?
}

/// What IntAssis may know right now, from the student's own data.
pub fn facts_for(snap: &intportal_core::store::Snapshot, now: Moment) -> Facts {
    let agenda = today::agenda(&snap.sessions, &snap.marks, now);
    let classes_today = agenda
        .items
        .iter()
        .map(|i| format!("{} {}, {} to {}", i.meeting.session.subject_code, i.meeting.session.description, today::clock(i.meeting.session.start), today::clock(i.meeting.session.end)))
        .collect();
    let all: Vec<_> = snap.syllabus.iter().flat_map(|(code, p)| p.items.iter().map(move |i| (code.clone(), i.clone()))).collect();
    let due = syllabus::due(&all, now.date, 8).into_iter().map(|(code, i)| format!("{}: {code}, {}", i.topic, i.date.map(|d| format!("{:?} {d}", d.weekday())).unwrap_or_default())).collect();
    let standing = snap
        .syllabus
        .iter()
        .filter_map(|(code, p)| {
            let t = syllabus::tally(&p.grading, p.target.unwrap_or(75.0));
            let now_pct = t.standing?;
            Some(match t.needed {
                Some(n) => format!("{code}: {now_pct:.0}% so far, needs {n:.0}% on the rest for {:.0}%", t.target),
                None => format!("{code}: {now_pct:.0}% so far"),
            })
        })
        .collect();
    let mut subjects: Vec<String> = snap.sessions.iter().map(|s| s.subject_code.clone()).collect();
    subjects.sort();
    subjects.dedup();
    Facts { today: Some(now.date), classes_today, due, standing, subjects, ..Facts::default() }
}

#[derive(Serialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum ProposalDto {
    AddNote { subject: Option<String>, text: String },
    SetReminder { date: Date, text: String },
    MakeCards { topic: String },
}

impl From<Proposal> for ProposalDto {
    fn from(p: Proposal) -> Self {
        match p {
            Proposal::AddNote { subject, text } => ProposalDto::AddNote { subject, text },
            Proposal::SetReminder { date, text } => ProposalDto::SetReminder { date, text },
            Proposal::MakeCards { topic } => ProposalDto::MakeCards { topic },
        }
    }
}

/// A note an answer drew on. The chat shows it as a chip that opens the note.
#[derive(Serialize)]
pub struct Source {
    key: String,
    title: String,
}

#[derive(Serialize)]
pub struct Ask {
    reply: String,
    /// The one thing IntAssis offers to do. The UI shows a confirm card.
    proposal: Option<ProposalDto>,
    /// The notes the model was shown for an open question.
    sources: Vec<Source>,
}

/// Loads the embedding model when it is on the phone but not in memory.
/// False when it was never downloaded: IntAssis then answers without notes.
fn embedder_ready(app: &tauri::AppHandle, slot: &Mutex<Option<Loaded>>) -> Res<bool> {
    let m = models::find(models::EMBED).ok_or("Unknown model")?;
    let path = models_dir(app)?.join(m.file);
    if !path.metadata().is_ok_and(|f| f.len() == m.bytes) {
        return Ok(false);
    }
    if slot.try_lock().map_err(|_| "IntAssis is busy".to_string())?.is_none() {
        load_into(slot, m, &path)?;
    }
    Ok(true)
}

/// Embeds notes edited since the last search. Quiet when the model is not installed.
fn index(app: &tauri::AppHandle, slot: &Mutex<Option<Loaded>>) -> Res<()> {
    if !embedder_ready(app, slot)? {
        return Ok(());
    }
    let mut guard = slot.try_lock().map_err(|_| "IntAssis is busy".to_string())?;
    let l = guard.as_mut().ok_or("Turn IntAssis on first")?;
    rag::refresh(&app.state::<AppState>().store, l.llm.as_mut(), models::EMBED).map_err(err)
}

/// The student's notes closest to `query`, as lines for the prompt and as chips for the UI.
fn recall(app: &tauri::AppHandle, slot: &Mutex<Option<Loaded>>, query: &str) -> Res<(Vec<String>, Vec<Source>)> {
    if !embedder_ready(app, slot)? {
        return Ok((vec![], vec![]));
    }
    let mut guard = slot.try_lock().map_err(|_| "IntAssis is busy".to_string())?;
    let l = guard.as_mut().ok_or("Turn IntAssis on first")?;
    let state = app.state::<AppState>();
    let hits = rag::search(&state.store, l.llm.as_mut(), models::EMBED, query, 4).map_err(err)?;
    let all = state.store.lock().unwrap().notes().map_err(err)?;
    let (mut lines, mut sources) = (vec![], Vec::<Source>::new());
    for h in hits {
        let Some(note) = all.iter().find(|n| n.key == h.note_key) else { continue };
        let title = notes::heading(note);
        lines.push(format!("{title}: {}", h.text.split_whitespace().collect::<Vec<_>>().join(" ")));
        if !sources.iter().any(|s| s.key == note.key) {
            sources.push(Source { key: note.key.clone(), title });
        }
    }
    Ok((lines, sources))
}

/// The note the student has open, cut to what fits the prompt.
fn open_note(state: &AppState, key: &str) -> Option<String> {
    let all = state.store.lock().unwrap().notes().ok()?;
    let n = all.into_iter().find(|n| n.key == key)?;
    Some(format!("{}: {}", notes::heading(&n), n.text.chars().take(2500).collect::<String>()))
}

/// After a note is saved: embed what changed, so the next question finds it.
#[tauri::command]
pub async fn ai_index(app: tauri::AppHandle, ai: tauri::State<'_, AiState>) -> Res<()> {
    let slot = ai.embedder.clone();
    tokio::task::spawn_blocking(move || index(&app, &slot)).await.map_err(|e| e.to_string())?
}

/// One chat turn. `history` is (student, IntAssis) pairs, oldest first.
/// `open_key` is the note the student is looking at, if any.
#[tauri::command]
pub async fn ai_ask(app: tauri::AppHandle, ai: tauri::State<'_, AiState>, now: Moment, message: String, history: Vec<(String, String)>, open_key: Option<String>) -> Res<Ask> {
    let state = app.state::<AppState>();
    let mut facts = facts_for(&snapshot_of(&state)?, now);
    let mut sources = vec![];
    // Only an open question reads the notes: the rest are answered from the schedule or acted on.
    if intent::detect(&message) == Intent::Ask {
        facts.open_note = open_key.and_then(|k| open_note(&state, &k));
        let (slot, q, handle) = (ai.embedder.clone(), message.clone(), app.clone());
        // Notes are a bonus: if searching fails the answer still comes from the schedule.
        if let Ok(Ok((lines, found))) = tokio::task::spawn_blocking(move || recall(&handle, &slot, &q)).await {
            (facts.hits, sources) = (lines, found);
        }
    }
    with_model(&ai, move |llm, tpl| {
        let a = assis::answer(llm, tpl, &facts, &history, &message)?;
        Ok(Ask { reply: a.reply, proposal: a.proposal.map(Into::into), sources })
    })
    .await
}

#[derive(Serialize)]
pub struct WhyDto {
    why: String,
    tip: String,
}

/// After a wrong card answer: why the right one is right.
#[tauri::command]
pub async fn ai_why(ai: tauri::State<'_, AiState>, front: String, back: String, typed: String, note: Option<String>) -> Res<WhyDto> {
    with_model(&ai, move |llm, tpl| {
        let w = why::explain(llm, tpl, &front, &back, &typed, note.as_deref())?;
        Ok(WhyDto { why: w.why, tip: w.tip })
    })
    .await
}

#[derive(Serialize)]
pub struct CardDto {
    front: String,
    back: String,
}

#[derive(Serialize)]
pub struct Cards {
    cards: Vec<CardDto>,
    /// Why it stopped before `want`, if it did. The cards that arrived are kept.
    stopped: Option<String>,
}

/// Flashcards from a note's text or a PDF's text, for the existing deck review.
#[tauri::command]
pub async fn ai_cards(ai: tauri::State<'_, AiState>, text: String, want: usize) -> Res<Cards> {
    with_model(&ai, move |llm, _| {
        let o = gen::cards(llm, &text, want.clamp(1, 40));
        Ok(Cards { cards: o.cards.into_iter().map(|c| CardDto { front: c.front, back: c.back }).collect(), stopped: o.stopped })
    })
    .await
}

/// A PDF's text. The bytes arrive as the raw request body (`invoke(cmd, bytes)`).
#[tauri::command]
pub fn ai_pdf_text(request: tauri::ipc::Request<'_>) -> Res<String> {
    match request.body() {
        tauri::ipc::InvokeBody::Raw(bytes) => pdf::text(bytes),
        _ => Err("Send the PDF as raw bytes".into()),
    }
}

/// An outline from pasted or PDF text: the rule-based reader first, the model for the gaps.
#[tauri::command]
pub async fn ai_outline_text(ai: tauri::State<'_, AiState>, text: String, today: Date, weeks: u16) -> Res<Vec<Item>> {
    with_model(&ai, move |llm, tpl| outline::from_text(llm, tpl, &text, today, weeks.clamp(1, 24))).await
}

/// A week-by-week guide from a course title. Progress is (week, weeks).
#[tauri::command]
pub async fn ai_guide(ai: tauri::State<'_, AiState>, course: String, weeks: u16, on_progress: Channel<(u16, u16)>) -> Res<Vec<Item>> {
    let cancel = ai.cancel.clone();
    with_model(&ai, move |llm, tpl| {
        outline::from_title(llm, tpl, &course, weeks.clamp(1, 24), &mut |w, n| {
            let _ = on_progress.send((w, n));
            !cancel.load(Ordering::Relaxed)
        })
    })
    .await
}

#[cfg(test)]
mod tests {
    use super::*;
    use intportal_core::{
        model::{ClassSession, Weekday},
        store::Snapshot,
        syllabus::{Item, Kind, Plan},
    };

    fn snap() -> Snapshot {
        let mut s = Snapshot::default();
        s.sessions.push(ClassSession { subject_code: "COMP 20073".into(), description: "Data Structures".into(), faculty: "x".into(), day: Weekday::Thursday, start: 540, end: 630, occurrence: 0 });
        s.syllabus.insert("COMP 20073".into(), Plan { items: vec![Item { id: "1".into(), topic: "Quiz 2".into(), kind: Kind::Quiz, week: None, date: Some(Date::new(2026, 10, 16)), done: false }], ..Plan::default() });
        s
    }

    #[test]
    fn facts_hold_todays_classes_deadlines_and_subjects() {
        let f = facts_for(&snap(), Moment { date: Date::new(2026, 10, 15), minute: 480 });
        assert_eq!(f.classes_today, ["COMP 20073 Data Structures, 9AM to 10:30AM"]);
        assert_eq!(f.due, ["Quiz 2: COMP 20073, Friday 2026-10-16"]);
        assert_eq!(f.subjects, ["COMP 20073"]);
        assert_eq!(f.today, Some(Date::new(2026, 10, 15)));
    }

    #[test]
    fn a_cancelled_model_stops_streaming() {
        let cancel = AtomicBool::new(true);
        let mut fake = intportal_ai::llm::FakeLlm::new(&["one two three"]);
        let mut c = Cancellable { inner: &mut fake, cancel: &cancel };
        assert_eq!(c.generate("p", None, 8, &mut |_| true).unwrap(), "one ");
    }

    #[test]
    fn a_proposal_serialises_with_its_kind() {
        let p = ProposalDto::SetReminder { date: Date::new(2026, 10, 16), text: "Pay tuition".into() };
        assert_eq!(serde_json::to_string(&p).unwrap(), r#"{"kind":"set_reminder","date":"2026-10-16","text":"Pay tuition"}"#);
    }
}
