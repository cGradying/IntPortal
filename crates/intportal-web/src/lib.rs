//! Look around in any browser (spec 052). The app's screens call `invoke`; in
//! the web build `src/lib/web.ts` hands each call to `call` here, which answers
//! it from an in-memory demo account with the same core functions the Tauri
//! shell uses (`src-tauri/src/commands`). Nothing is kept: a reload starts over.
//!
//! ponytail: the command bodies mirror the Tauri shell's by hand. If they drift,
//! move both into the core behind a small store trait.

use intportal_core::calendar;
use intportal_core::coach::{self, Nudge, PlanStep, Signals};
use intportal_core::deadline::{self, OwnDeadline};
use intportal_core::grades::{self, Goals};
use intportal_core::mabini::MabiniData;
use intportal_core::notes::{self, Note};
use intportal_core::nudge;
use intportal_core::store::Snapshot;
use intportal_core::study::{self, Card, Deck, Memory, Rating, Stats};
use intportal_core::syllabus::{self, Component, Plan};
use intportal_core::today::{self, Busy, ClassInfo, Date, Mark, Moment, Slot};
use serde::de::DeserializeOwned;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::cell::RefCell;
use std::collections::HashMap;

/// Manila, for calls that don't say.
const MANILA: i32 = 480;
/// What the app shows for anything that needs the phone (052 C5).
pub const APP_ONLY: &str = "That works in the app. Get it on the download page.";

#[derive(Default)]
pub struct Demo {
    pub snap: Snapshot,
    pub notes: Vec<Note>,
    pub decks: Vec<Deck>,
    pub stats: Stats,
    pub mabini: MabiniData,
}

type Res = Result<Value, String>;

fn arg<T: DeserializeOwned>(args: &Value, name: &str) -> Result<T, String> {
    serde_json::from_value(args.get(name).cloned().unwrap_or(Value::Null)).map_err(|e| format!("{name}: {e}"))
}

fn out<T: Serialize>(v: T) -> Res {
    serde_json::to_value(v).map_err(|e| e.to_string())
}

impl Demo {
    /// A fresh demo account: the core's demo SIS and eMabini, plus a few decks and
    /// notes so Study and Notes have something in them.
    pub fn new(today: Date, unix: i64) -> Demo {
        let snap = intportal_core::demo::sis(Snapshot::default(), today, unix.to_string());
        Demo { notes: sample_notes(unix), decks: sample_decks(unix), mabini: intportal_core::demo::mabini(unix), snap, stats: Stats::default() }
    }

    fn edit(&mut self, change: impl FnOnce(&mut Snapshot)) -> Res {
        change(&mut self.snap);
        out(&self.snap)
    }

    /// One command, as the Tauri shell names it, with the app's camelCase arguments.
    pub fn call(&mut self, cmd: &str, a: &Value, unix: i64) -> Res {
        match cmd {
            "demo" => {
                let today: Date = arg(a, "today")?;
                *self = Demo::new(today, unix);
                out(&self.snap)
            }
            "snapshot" | "sync" | "load_history" => {
                if cmd == "sync" {
                    self.snap.last_synced = Some(unix.to_string());
                }
                out(&self.snap)
            }
            "has_login" | "has_mabini_login" => out(true),
            "sign_out" | "erase_everything" | "mabini_sign_out" => out(()),
            "portals" => out(intportal_core::portal::ALL.clone()),
            "portal_status" => out(json!({ "up": true, "host": "sis8.pup.edu.ph" })),
            "tries_left" | "mabini_tries_left" => out(json!({ "left": 3, "retry_at": null, "rejected": false })),
            "login_hint" => out(Value::Null),
            "campus" => out(intportal_core::campus::resolve(&arg::<String>(a, "studentNumber")?)),
            "mabini_data" | "mabini_sync" => out(&self.mabini),

            "set_mark" => {
                let (id, week, mark): (String, Option<Date>, Option<Mark>) = (arg(a, "sessionId")?, arg(a, "week")?, arg(a, "mark")?);
                self.edit(|s| s.marks.mode.set(&id, week, mark))
            }
            "set_move" => {
                let (id, week, slot): (String, Option<Date>, Option<Slot>) = (arg(a, "sessionId")?, arg(a, "week")?, arg(a, "slot")?);
                if slot.is_some_and(|s| s.end <= s.start || s.end > 24 * 60) {
                    return Err("A class has to end after it starts, before midnight.".into());
                }
                self.edit(|s| s.marks.moved.set(&id, week, slot))
            }
            "set_color" => {
                let (code, color): (String, Option<String>) = (arg(a, "subjectCode")?, arg(a, "color")?);
                self.edit(|s| match color {
                    Some(c) => drop(s.colors.insert(code, c)),
                    None => drop(s.colors.remove(&code)),
                })
            }
            "set_class_info" => {
                let code: String = arg(a, "subjectCode")?;
                let info = ClassInfo::clean(arg(a, "link")?, arg(a, "about")?)?;
                self.edit(|s| match info.is_empty() {
                    true => drop(s.class_info.remove(&code)),
                    false => drop(s.class_info.insert(code, info)),
                })
            }
            "week" => out(today::week(&self.snap.sessions, &self.snap.marks, arg(a, "on")?)),
            "today" => self.today(arg(a, "now")?, arg(a, "syncTrouble")?, arg(a, "busy")?),
            "class_events" => {
                let (from, days, offset): (Date, i64, Option<i32>) = (arg(a, "from")?, arg(a, "days")?, arg(a, "utcOffset")?);
                let mut list = calendar::class_events(&self.snap.sessions, &self.snap.marks, from, days);
                list.extend(self.deadline_events(from, days, offset.unwrap_or(MANILA)));
                out(list)
            }
            "export_ics" => {
                let (from, until, offset): (Date, Date, Option<i32>) = (arg(a, "from")?, arg(a, "until")?, arg(a, "utcOffset")?);
                if until < from {
                    return Err("The last day of classes has to be after today.".into());
                }
                let events = self.deadline_events(from, until.days_since(from) + 1, offset.unwrap_or(MANILA));
                out(calendar::ics(&self.snap.sessions, &self.snap.marks, &events, from, until, &calendar::utc_stamp(unix)))
            }

            "set_goals" => {
                let goals: Goals = arg(a, "goals")?;
                if goals.target_gpa.is_some_and(|g| !(1.0..=5.0).contains(&g)) {
                    return Err("A target GPA runs from 1.00 to 5.00.".into());
                }
                self.edit(|s| s.goals = goals)
            }
            "standing" => out(grades::standing(self.snap.grades.as_ref(), &self.snap.history, self.snap.goals)),
            "coach" => self.coach(arg(a, "now")?, arg(a, "dismissed")?, arg(a, "busy")?, arg(a, "utcOffset")?, unix),
            "reminders" => self.reminders(arg(a, "now")?, arg(a, "lead")?, arg(a, "days")?, arg(a, "prefs")?, unix),

            "deadlines" => out(deadline::deadlines(&self.snap, &self.mabini, arg(a, "now")?, arg(a, "utcOffset")?, arg(a, "days")?)),
            "set_done" => {
                let (id, done): (String, bool) = (arg(a, "id")?, arg(a, "done")?);
                self.edit(|snap| match id.strip_prefix("syl:").and_then(|rest| rest.rsplit_once(':')) {
                    Some((code, item)) => {
                        if let Some(i) = snap.syllabus.get_mut(code).and_then(|p| p.items.iter_mut().find(|i| i.id == item)) {
                            i.done = done;
                        }
                    }
                    None if done => drop(snap.done.insert(id)),
                    None => drop(snap.done.remove(&id)),
                })
            }
            "save_own" => {
                let mut own: OwnDeadline = arg(a, "own")?;
                own.title = own.title.trim().to_string();
                if own.title.is_empty() {
                    return Err("Give it a name first.".into());
                }
                if own.id.is_empty() {
                    own.id = format!("{unix:x}{}", self.snap.own_deadlines.len());
                }
                self.edit(|snap| match snap.own_deadlines.iter_mut().find(|o| o.id == own.id) {
                    Some(o) => *o = own,
                    None => snap.own_deadlines.push(own),
                })
            }
            "delete_own" => {
                let id: String = arg(a, "id")?;
                self.edit(|snap| {
                    snap.own_deadlines.retain(|o| o.id != id);
                    snap.done.remove(&format!("own:{id}"));
                })
            }
            "parse_own" => {
                let mut subjects: Vec<(String, String)> = self.snap.sessions.iter().map(|s| (s.subject_code.clone(), s.description.clone())).collect();
                subjects.sort();
                subjects.dedup();
                let drafts = deadline::parse_own(&arg::<String>(a, "text")?, arg(a, "today")?, &subjects);
                out(drafts.into_iter().map(|d| deadline::guess_subject(d, &self.snap.sessions)).collect::<Vec<_>>())
            }
            "parse_outline" => out(syllabus::parse_outline(&arg::<String>(a, "text")?, arg(a, "today")?)),
            "clean_scan" => out(intportal_core::scan::clean(&arg::<String>(a, "raw")?)),
            "tally" => out(syllabus::tally(&arg::<Vec<Component>>(a, "components")?, arg(a, "target")?)),
            "set_plan" => {
                let (code, mut plan): (String, Plan) = (arg(a, "subjectCode")?, arg(a, "plan")?);
                plan.assign_ids();
                self.edit(|s| match plan == Plan::default() {
                    true => drop(s.syllabus.remove(&code)),
                    false => drop(s.syllabus.insert(code, plan)),
                })
            }
            "entry_date" => out(today::entry_date(&self.snap.sessions, &self.snap.marks, &arg::<String>(a, "code")?, arg(a, "today")?)),

            "study" => self.study(arg(a, "today")?, arg(a, "utcOffset")?, unix),
            "deck" => {
                let id: String = arg(a, "id")?;
                out(self.decks.iter().find(|d| d.id == id).ok_or("That deck is gone.")?)
            }
            "save_deck" => {
                let mut deck: Deck = arg(a, "deck")?;
                if deck.name.trim().is_empty() {
                    return Err("Give the deck a name.".into());
                }
                deck.cards.retain(|c| !c.front.trim().is_empty() && !c.back.trim().is_empty());
                deck.settle_new_cards(unix);
                if deck.id.is_empty() {
                    deck.id = format!("web{}", self.decks.len() + 1);
                }
                match self.decks.iter_mut().find(|d| d.id == deck.id) {
                    Some(d) => *d = deck.clone(),
                    None => self.decks.push(deck.clone()),
                }
                out(deck)
            }
            "delete_deck" => {
                let id: String = arg(a, "id")?;
                self.decks.retain(|d| d.id != id);
                out(())
            }
            "parse_cards" => out(study::parse_cards(&arg::<String>(a, "text")?)
                .into_iter()
                .map(|(front, back)| Card { id: String::new(), front, back, accepted: vec![], memory: Memory::new(0) })
                .collect::<Vec<_>>()),
            "review_card" => {
                let (deck_id, card_id, rating, today): (String, String, Rating, Date) = (arg(a, "deckId")?, arg(a, "cardId")?, arg(a, "rating")?, arg(a, "today")?);
                let deck = self.decks.iter_mut().find(|d| d.id == deck_id).ok_or("That deck is gone.")?;
                let card = deck.cards.iter_mut().find(|c| c.id == card_id).ok_or("That card is gone.")?;
                card.memory = study::review(&card.memory, rating, unix);
                self.stats = study::count_review(&self.stats, today);
                out(json!({ "deck": deck, "stats": self.stats }))
            }
            "review_preview" => out(study::preview(&arg::<Memory>(a, "memory")?, unix)),
            "check_answer" => out(study::is_correct(&arg::<String>(a, "typed")?, &arg::<Card>(a, "card")?)),
            "distractors" => {
                let (cards, index, seed): (Vec<Card>, usize, usize) = (arg(a, "cards")?, arg(a, "index")?, arg(a, "seed")?);
                if index >= cards.len() {
                    return Err("No such card.".into());
                }
                out(study::distractors(&cards, index, 3, seed))
            }

            "notes" => {
                let mut list = self.notes.clone();
                notes::pinned_first(&mut list);
                out(list.into_iter().map(|n| json!({ "preview": notes::preview(&n.text, 80), "key": n.key, "text": n.text, "title": n.title, "updated": n.updated, "subject": n.subject, "pinned": n.pinned, "photos": n.photos })).collect::<Vec<_>>())
            }
            "notes_markdown" => {
                let key: Option<String> = arg(a, "key")?;
                let list: Vec<Note> = self.notes.iter().filter(|n| key.as_ref().is_none_or(|k| &n.key == k)).cloned().collect();
                out(notes::markdown(&list))
            }
            "set_note" => {
                let (key, text, title): (String, String, Option<String>) = (arg(a, "key")?, arg(a, "text")?, arg(a, "title")?);
                if !notes::is_known_key(&key) {
                    return Err("Unknown note".into());
                }
                if text.trim().is_empty() {
                    self.notes.retain(|n| n.key != key);
                } else if let Some(n) = self.notes.iter_mut().find(|n| n.key == key) {
                    n.text = text;
                    n.title = title.or(n.title.take());
                    n.updated = unix;
                } else {
                    self.notes.push(Note { key, text, title, updated: unix, subject: None, pinned: false, photos: 0 });
                }
                out(())
            }
            "delete_note" => {
                let key: String = arg(a, "key")?;
                self.notes.retain(|n| n.key != key);
                out(())
            }
            "set_note_pin" => {
                let (key, pinned): (String, bool) = (arg(a, "key")?, arg(a, "pinned")?);
                if let Some(n) = self.notes.iter_mut().find(|n| n.key == key) {
                    n.pinned = pinned;
                }
                out(())
            }
            "set_note_subject" => {
                let (key, subject): (String, Option<String>) = (arg(a, "key")?, arg(a, "subject")?);
                if !key.starts_with("note:") {
                    return Err("Only a freeform note can change subject.".into());
                }
                let n = self.notes.iter_mut().find(|n| n.key == key).ok_or("That note isn't saved yet.")?;
                n.subject = subject.map(|s| s.trim().to_string()).filter(|s| !s.is_empty());
                out(())
            }
            "note_photos" => out(Vec::<Value>::new()),
            "space_used" => out(json!({ "store": 0, "photos": 0, "model": 0 })),
            "ai_models" | "ai_history" => out(Vec::<Value>::new()),
            "ai_small_ram" => out(false),
            _ => Err(APP_ONLY.into()),
        }
    }

    fn deadline_events(&self, from: Date, days: i64, offset: i32) -> Vec<calendar::ClassEvent> {
        let list = deadline::deadlines(&self.snap, &self.mabini, Moment { date: from, minute: 0 }, offset, days);
        calendar::deadline_events(&list, from, offset)
    }

    fn today(&self, now: Moment, trouble: Option<String>, busy: Option<Vec<Busy>>) -> Res {
        let s = &self.snap;
        let next = today::next_class(&s.sessions, &s.marks, now);
        let glance = today::glance(&s.sessions, &s.marks, now, trouble.as_deref(), false);
        let mut agenda = today::agenda(&s.sessions, &s.marks, now);
        agenda.free_minutes_left = today::free_minutes(&agenda.items, now, &busy.unwrap_or_default());
        out(json!({
            "agenda": agenda,
            "countdown": next.as_ref().map(|n| n.countdown(now)),
            "join": next.as_ref().and_then(|n| today::join_link(n, &s.class_info)),
            "next": next,
            "glance_line": glance.line(),
            "glance": glance,
        }))
    }

    fn coach(&self, now: Moment, dismissed: Vec<String>, busy: Option<Vec<Busy>>, offset: Option<i32>, unix: i64) -> Res {
        let snap = &self.snap;
        let offset = offset.unwrap_or(MANILA);
        let agenda = today::agenda(&snap.sessions, &snap.marks, now);
        let busy = busy.unwrap_or_default();
        let needed = snap.goals.target_gpa.zip(snap.grades.as_ref()).and_then(|(t, g)| grades::needed_average(&g.subjects, t).filter(|n| (1.0..5.0).contains(n)).map(|n| (n, t)));
        let week = deadline::deadlines(snap, &self.mabini, now, offset, 8);
        let day_of = |d: &deadline::Deadline| match d.due {
            deadline::Due::Day(day) => day,
            deadline::Due::At(u) => deadline::local_parts(u, offset).0,
        };
        let within = |d: &deadline::Deadline, days: i64| d.overdue || day_of(d) < now.date.add_days(days);
        let step = |d: &deadline::Deadline, subject: Option<String>| PlanStep { id: d.id.clone(), title: d.title.clone(), when: deadline::when_word(d, now, offset), subject, url: d.url.clone() };
        let signals = Signals {
            due_soon: week.iter().filter(|d| within(d, 2)).cloned().collect(),
            cards_due: self.decks.iter().map(|d| d.due(unix)).sum(),
            study_streak: study::current_streak(&self.stats, now.date),
            studied_today: self.stats.last_day == Some(now.date),
            free_minutes: today::free_minutes(&agenda.items, now, &busy),
            needed_average: needed,
            classes_left: agenda.items.iter().filter(|i| i.phase != today::Phase::Past).count(),
            gap: today::gaps(&agenda.items, now, &busy).into_iter().find(|g| g.minutes >= 30),
            plan_step: week.iter().find(|d| within(d, 4)).map(|d| step(d, d.subject.clone())),
            cards_by_subject: cards_by_subject(&self.decks, unix).into_iter().collect(),
            later: week.iter().find(|d| !within(d, 2)).map(|d| step(d, Some(d.label().to_string()).filter(|l| !l.is_empty()))),
        };
        let pick: Option<Nudge> = coach::pick(&signals, &dismissed);
        out(pick.map(|n| json!({ "line": n.line(), "key": n.key(), "nudge": n })))
    }

    fn reminders(&self, now: Moment, lead: u16, days: u16, prefs: Option<Prefs>, unix: i64) -> Res {
        let snap = &self.snap;
        let prefs = prefs.unwrap_or_default();
        let warm = if prefs.warm_up.unwrap_or(true) { cards_by_subject(&self.decks, unix) } else { Default::default() };
        let mut list = if lead > 0 { today::reminders(&snap.sessions, &snap.marks, now, lead, days, &warm) } else { vec![] };
        let mut rest = vec![];
        let due = deadline::deadlines(snap, &self.mabini, now, prefs.utc_offset, i64::from(days).max(14));
        if let Some(minute) = prefs.deadlines {
            rest.extend(deadline::reminders(&due, now, minute, prefs.utc_offset, i64::from(days)).into_iter().map(|r| (nudge::Kind::Deadline, r)));
        }
        if prefs.brief.unwrap_or(true) {
            rest.extend(nudge::brief(&due, &snap.sessions, &snap.marks, now, prefs.utc_offset).filter(|r| r.date < now.date.add_days(i64::from(days))).map(|r| (nudge::Kind::Brief, r)));
        }
        if let Some(minute) = prefs.study {
            rest.extend(study::study_reminders(&self.decks, now, minute, i64::from(days), prefs.utc_offset).into_iter().map(|r| (nudge::Kind::Study, r)));
        }
        if prefs.after_class.unwrap_or(true) {
            let noted = notes::class_codes_with_text(&self.notes);
            rest.extend(nudge::after_class(&snap.sessions, &snap.marks, &noted, now, i64::from(days)).into_iter().map(|r| (nudge::Kind::AfterClass, r)));
        }
        list.extend(nudge::budget(rest, nudge::PER_DAY));
        list.sort_by_key(|r| (r.date, r.minute));
        out(list)
    }

    fn study(&self, today: Date, offset: Option<i32>, unix: i64) -> Res {
        let offset = offset.unwrap_or(MANILA);
        let decks: Vec<Value> = self
            .decks
            .iter()
            .map(|d| json!({ "id": d.id, "name": d.name, "subject": d.subject, "cards": d.cards.len(), "due": d.due(unix), "mastery": study::mastery(&d.cards), "forecast": study::forecast_7(&d.cards, today, offset) }))
            .collect();
        let reviews_today = if self.stats.last_day == Some(today) { self.stats.reviews_today } else { 0 };
        out(json!({
            "due": self.decks.iter().map(|d| d.due(unix)).sum::<usize>(),
            "decks": decks,
            "streak": study::current_streak(&self.stats, today),
            "reviews_today": reviews_today,
            "week": study::week(&self.stats, today),
        }))
    }
}

#[derive(Deserialize, Default)]
struct Prefs {
    deadlines: Option<u16>,
    study: Option<u16>,
    #[serde(default)]
    utc_offset: i32,
    warm_up: Option<bool>,
    after_class: Option<bool>,
    brief: Option<bool>,
}

fn cards_by_subject(decks: &[Deck], unix: i64) -> HashMap<String, usize> {
    let mut map = HashMap::new();
    for d in decks {
        if let Some(code) = &d.subject {
            *map.entry(code.clone()).or_default() += d.due(unix);
        }
    }
    map
}

const DAY: i64 = 86_400;

fn sample_decks(unix: i64) -> Vec<Deck> {
    // Due times and stabilities spread so the deck rows show mastery and a forecast.
    let card = |n: usize, front: &str, back: &str, due_days: f64, reps: u32, stability: f64| Card {
        id: n.to_string(),
        front: front.into(),
        back: back.into(),
        accepted: vec![],
        memory: Memory { due: unix + (due_days * DAY as f64) as i64, reps, stability, last_review: (reps > 0).then_some(unix - 3 * DAY), ..Memory::new(unix) },
    };
    let dsa = [
        ("Stack", "Last in, first out", -0.2, 3, 9.0),
        ("Queue", "First in, first out", 0.0, 2, 12.0),
        ("Binary search", "Halves a sorted range each step: O(log n)", 1.0, 2, 8.0),
        ("Hash table", "Key to slot by a hash; O(1) on average", 2.0, 1, 3.0),
        ("Linked list", "Nodes that point to the next node", 4.0, 4, 21.0),
        ("Big-O of merge sort", "O(n log n)", -1.0, 0, 0.0),
        ("Heap", "A tree where each parent beats its children", 6.0, 1, 2.0),
        ("Graph", "Vertices joined by edges", 0.0, 0, 0.0),
    ];
    let discrete = [
        ("Tautology", "True under every assignment", 0.0, 2, 10.0),
        ("Contrapositive of p → q", "¬q → ¬p", 1.0, 1, 4.0),
        ("Bijection", "One-to-one and onto", 3.0, 3, 15.0),
        ("Pigeonhole principle", "n + 1 pigeons in n holes: one hole has two", 5.0, 0, 0.0),
    ];
    let make = |id: &str, name: &str, subject: &str, rows: &[(&str, &str, f64, u32, f64)]| Deck {
        id: id.into(),
        name: name.into(),
        subject: Some(subject.into()),
        cards: rows.iter().enumerate().map(|(i, r)| card(i + 1, r.0, r.1, r.2, r.3, r.4)).collect(),
    };
    vec![make("dsa", "Data structures", "COMP 20073", &dsa), make("logic", "Logic and sets", "MATH 20013", &discrete)]
}

fn sample_notes(unix: i64) -> Vec<Note> {
    let note = |key: &str, title: Option<&str>, text: &str, ago: i64, pinned: bool| Note { key: key.into(), text: text.into(), title: title.map(Into::into), updated: unix - ago, subject: None, pinned, photos: 0 };
    vec![
        note("class:COMP 20073", Some("Data Structures and Algorithms"), "# Trees\n- [x] Read chapter 6\n- [ ] Lab 4: a BST with delete\n\nIn-order walk of a BST gives the keys sorted.", 3600, true),
        note("class:GEED 10053", Some("Purposive Communication"), "Reaction paper: 500 words, APA, due Friday.", 2 * DAY, false),
    ]
}

thread_local! {
    static DEMO: RefCell<Demo> = RefCell::new(Demo::default());
    static OUT: RefCell<Vec<u8>> = const { RefCell::new(Vec::new()) };
}

/// Room for the JavaScript side to write a string into.
#[no_mangle]
pub extern "C" fn alloc(len: usize) -> *mut u8 {
    let mut buf = Vec::<u8>::with_capacity(len);
    let ptr = buf.as_mut_ptr();
    std::mem::forget(buf);
    ptr
}

/// # Safety
/// `ptr` and `len` come from `alloc`.
#[no_mangle]
pub unsafe extern "C" fn dealloc(ptr: *mut u8, len: usize) {
    drop(Vec::from_raw_parts(ptr, 0, len));
}

/// Runs one command. `cmd` and `args` (JSON) are UTF-8 written by the caller;
/// `now_ms` is the browser's clock. Returns 0 with JSON in `out_*`, or 1 with
/// the error message there.
///
/// # Safety
/// The pointers point at `cmd_len` and `args_len` readable bytes.
#[no_mangle]
pub unsafe extern "C" fn call(cmd: *const u8, cmd_len: usize, args: *const u8, args_len: usize, now_ms: f64) -> u32 {
    let cmd = std::str::from_utf8(std::slice::from_raw_parts(cmd, cmd_len)).unwrap_or("");
    let args = std::slice::from_raw_parts(args, args_len);
    let args: Value = serde_json::from_slice(args).unwrap_or(Value::Null);
    let result = DEMO.with(|d| d.borrow_mut().call(cmd, &args, (now_ms / 1000.0) as i64));
    let (code, text) = match result {
        Ok(v) => (0, v.to_string()),
        Err(e) => (1, e),
    };
    OUT.with(|o| *o.borrow_mut() = text.into_bytes());
    code
}

#[no_mangle]
pub extern "C" fn out_ptr() -> *const u8 {
    OUT.with(|o| o.borrow().as_ptr())
}

#[no_mangle]
pub extern "C" fn out_len() -> usize {
    OUT.with(|o| o.borrow().len())
}

/// getrandom's hook on wasm32-unknown-unknown (built with
/// `--cfg getrandom_backend="custom"`). Only hash seeds ask; the demo has no secrets.
#[cfg(target_arch = "wasm32")]
#[no_mangle]
unsafe extern "Rust" fn __getrandom_v03_custom(dest: *mut u8, len: usize) -> Result<(), getrandom::Error> {
    let mut x: u64 = 0x9e37_79b9_7f4a_7c15;
    for i in 0..len {
        x ^= x << 13;
        x ^= x >> 7;
        x ^= x << 17;
        *dest.add(i) = x as u8;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    const TUE: Date = Date { y: 2026, m: 11, d: 17 };
    // 2026-11-17 10:00 in Manila.
    const UNIX: i64 = 1_795_312_800;

    fn demo() -> Demo {
        let mut d = Demo::default();
        d.call("demo", &json!({ "today": "2026-11-17" }), UNIX).unwrap();
        d
    }

    fn now() -> Value {
        json!({ "date": "2026-11-17", "minute": 600 })
    }

    #[test]
    fn c3_reads_answer_as_on_the_phone() {
        let mut d = demo();
        let today = d.call("today", &json!({ "now": now(), "syncTrouble": null, "busy": [] }), UNIX).unwrap();
        assert_eq!(today["next"]["session"]["subject_code"], "GEED 10053", "the 10:30 class is next at 10:00");
        let due = d.call("deadlines", &json!({ "now": now(), "utcOffset": 480, "days": 14 }), UNIX).unwrap();
        assert!(due.as_array().unwrap().len() >= 3, "eMabini's sample deadlines show: {due}");
        let study = d.call("study", &json!({ "today": "2026-11-17", "utcOffset": 480 }), UNIX).unwrap();
        assert_eq!(study["decks"][0]["cards"], 8);
        assert!(study["due"].as_u64().unwrap() >= 3);
        assert_eq!(d.call("week", &json!({ "on": "2026-11-17" }), UNIX).unwrap().as_array().unwrap().len(), 6);
        assert!(d.call("coach", &json!({ "now": now(), "dismissed": [], "busy": [], "utcOffset": 480 }), UNIX).unwrap().is_object());
        assert!(d.call("standing", &json!({}), UNIX).is_ok());
        assert_eq!(d.call("notes", &json!({}), UNIX).unwrap().as_array().unwrap().len(), 2);
        assert!(d.call("reminders", &json!({ "now": now(), "lead": 10, "days": 7, "prefs": { "utc_offset": 480, "deadlines": 1200 } }), UNIX).is_ok());
    }

    #[test]
    fn c4_writes_last_for_the_visit() {
        let mut d = demo();
        let id = d.call("deadlines", &json!({ "now": now(), "utcOffset": 480, "days": 14 }), UNIX).unwrap()[0]["id"].as_str().unwrap().to_string();
        let snap = d.call("set_done", &json!({ "id": id, "done": true }), UNIX).unwrap();
        assert!(snap["done"].as_array().unwrap().iter().any(|v| v == &json!(id)));
        d.call("set_note", &json!({ "key": "day:2026-11-17", "text": "Bring the lab manual", "title": null }), UNIX).unwrap();
        assert_eq!(d.call("notes", &json!({}), UNIX).unwrap().as_array().unwrap().len(), 3);
        let r = d.call("review_card", &json!({ "deckId": "dsa", "cardId": "1", "rating": "good", "today": "2026-11-17" }), UNIX).unwrap();
        assert_eq!(r["stats"]["reviews_today"], 1);
        let deck = d.call("save_deck", &json!({ "deck": { "id": "", "name": "New", "subject": null, "cards": [{ "id": "", "front": "a", "back": "b", "memory": Memory::new(0) }] } }), UNIX).unwrap();
        assert_eq!(deck["cards"][0]["id"], "1");
        let snap = d.call("save_own", &json!({ "own": { "id": "", "title": " Quiz 3 ", "subject": null, "kind": "quiz", "date": "2026-11-20" } }), UNIX).unwrap();
        assert_eq!(snap["own_deadlines"][0]["title"], "Quiz 3");
        // A reload starts the demo over.
        let fresh = demo();
        assert_eq!(fresh.notes.len(), 2);
        let _ = TUE;
    }

    #[test]
    fn c5_the_phone_only_things_say_so() {
        let mut d = demo();
        for cmd in ["sign_in", "mabini_sign_in", "backup_make", "add_photo", "ai_download", "notes_zip", "photo_dir"] {
            assert_eq!(d.call(cmd, &json!({}), UNIX), Err(APP_ONLY.to_string()), "{cmd}");
        }
    }
}
