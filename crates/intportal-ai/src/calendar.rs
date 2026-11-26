//! LAR changes the student's week (spec 064): their own deadlines, a meeting of any class, their own classes,
//! and the reminders LAR set. All rules, no model (C17): the words pick the change (C2), the rows pick the
//! item (C12), and dates and times are read by the rules (C13). Nothing is written here: the chat shows a
//! card and Apply goes through the commands the app already has. School data is never rewritten.
use crate::{
    assis::Proposal,
    edit::PICK_MAX,
    intent::{is_quiz, resolve_when, subject_in, words},
};
use intportal_core::{
    deadline::{parse_own, Source},
    model::Weekday,
    own_class::OwnClass,
    today::{Date, Mark, Slot},
};

/// What the shell gives LAR to match against: compact rows, never prompt text, since no model reads them.
#[derive(Debug, Clone, Default)]
pub struct Calendar {
    pub deadlines: Vec<DeadlineRow>,
    /// Every meeting slot of the week, school and own.
    pub classes: Vec<ClassRow>,
    /// The student's own classes as the class editor saves them, for C9 and C10.
    pub own_classes: Vec<OwnClass>,
    pub reminders: Vec<ReminderRow>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct DeadlineRow {
    pub id: String,
    pub title: String,
    pub subject: Option<String>,
    pub date: Date,
    pub source: Source,
}

#[derive(Debug, Clone, PartialEq)]
pub struct ClassRow {
    /// `ClassSession::id()`, the key marks and moves are kept under.
    pub session: String,
    pub code: String,
    pub name: String,
    pub day: Weekday,
    pub start: u16,
    pub end: u16,
    pub own: bool,
}

/// A reminder LAR set (spec 021), found by its text (C11).
#[derive(Debug, Clone, PartialEq)]
pub struct ReminderRow {
    pub id: i64,
    pub text: String,
    pub date: Date,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Thing {
    Deadline,
    Class,
    Reminder,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Action {
    Add,
    Move,
    Rename,
    /// A deadline's "I finished it".
    Done,
    Delete,
    /// A class: "no class", "wala", "cancel".
    NoClass,
    Online,
    /// An own class's room or name: "change my review class room to 302".
    Change,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Request {
    pub action: Action,
    pub thing: Thing,
    /// "every week", "from now on", "lagi": the whole term, not one meeting (C8).
    pub every_week: bool,
}

pub const NOT_FOUND: &str = "I couldn't find that in your week.";
pub const PASSED: &str = "That day has passed.";
pub const NO_DATE: &str = "When is it due?";
pub const SCHOOL_CLASS: &str = "Your school sets that class's room. I can mark a day online or no class, or move one meeting.";

/// A question word at the start, or "ba", asks; it never changes anything (C2, as 062's edit rule).
const ASKS: &[&str] = &[
    "how", "what", "whats", "why", "when", "where", "who", "which", "is", "are", "do", "does", "did", "will", "was", "were", "should", "paano", "ano", "anong", "bakit", "kailan", "saan", "sino", "ilan", "may",
];
const DEADLINE: &[&str] = &[
    "deadline", "deadlines", "due", "assignment", "assignments", "homework", "quiz", "quizzes", "exam", "exams", "midterm", "midterms", "finals", "prelim", "prelims", "lab", "labs", "essay", "essays", "project", "projects", "report",
    "reports", "paper", "seatwork", "takdang", "pagsusulit", "pasahan",
];
const CLASS: &[&str] = &["class", "classes", "klase", "meeting", "lecture"];
const REMINDER: &[&str] = &["reminder", "reminders", "paalala", "alarm"];
const EVERY: &[&str] = &[" every week", " from now on", " lagi", " palagi", " weekly", " every ", " all term", " buong term", " simula ngayon"];

fn has(w: &[String], list: &[&str]) -> bool {
    w.iter().any(|x| list.contains(&x.as_str()))
}

/// Does the message name a calendar thing at all (a deadline word, a class word or a subject, a reminder)?
pub fn thing_of(msg: &str, subjects: &[(String, String)]) -> Option<Thing> {
    let w = words(msg);
    if has(&w, REMINDER) {
        Some(Thing::Reminder)
    } else if has(&w, DEADLINE) {
        Some(Thing::Deadline)
    } else if has(&w, CLASS) || subject_in(msg, subjects).is_some() {
        Some(Thing::Class)
    } else {
        None
    }
}

/// A calendar change needs a verb and a thing (C2); a question, a note, cards or "remind me" is not one.
pub fn request(msg: &str, subjects: &[(String, String)]) -> Option<Request> {
    let w = words(msg);
    let joined = format!(" {} ", w.join(" "));
    if w.first().is_some_and(|x| ASKS.contains(&x.as_str())) || has(&w, &["ba"]) || msg.trim_end().ends_with('?') && !has(&w, &["can", "could", "pwede", "paki", "pakilipat"]) {
        return None;
    }
    if has(&w, &["note", "notes", "flashcard", "flashcards", "card", "cards"]) || is_quiz(msg) {
        return None;
    }
    let thing = thing_of(msg, subjects)?;
    // "Remind me to move my lab": the reminder is the request, not a change.
    if thing != Thing::Reminder && has(&w, &["remind", "ipaalala", "paalalahanan"]) {
        return None;
    }
    let every_week = EVERY.iter().any(|p| joined.contains(&format!("{p} ")) || (p.ends_with(' ') && joined.contains(p)));
    let no_class = has(&w, &["no", "wala", "walang", "cancel", "cancelled", "canceled", "suspended", "kansel"]);
    let action = if has(&w, &["finished", "finish", "done", "tapos", "natapos", "submitted", "nasubmit", "naipasa", "naipasa", "complete", "completed"]) && thing == Thing::Deadline {
        Action::Done
    } else if has(&w, &["rename", "retitle"]) || joined.contains(" change the title") || joined.contains(" change the name") || joined.contains(" palitan ang pangalan") {
        Action::Rename
    } else if has(&w, &["online"]) && thing == Thing::Class {
        Action::Online
    } else if no_class && thing == Thing::Class {
        Action::NoClass
    } else if has(&w, &["move", "moved", "ilipat", "resched", "reschedule", "rescheduled", "postpone", "postponed", "iusog", "usog"]) {
        Action::Move
    } else if has(&w, &["delete", "remove", "cancel", "erase", "burahin", "alisin", "tanggalin", "drop"]) {
        Action::Delete
    } else if has(&w, &["add", "new", "create", "idagdag", "dagdag", "magdagdag"]) {
        Action::Add
    } else if has(&w, &["change", "update", "edit", "palitan", "baguhin", "set"]) {
        // "change my lab report to Monday" moves it; "change my review class room to 302" edits the class.
        if thing == Thing::Class && has(&w, &["room", "kwarto", "name", "teacher", "prof"]) { Action::Change } else { Action::Move }
    } else {
        return None;
    };
    let fits = match thing {
        Thing::Deadline => matches!(action, Action::Add | Action::Move | Action::Rename | Action::Done | Action::Delete),
        Thing::Class => matches!(action, Action::Add | Action::Move | Action::Rename | Action::Delete | Action::NoClass | Action::Online | Action::Change),
        Thing::Reminder => matches!(action, Action::Move | Action::Delete),
    };
    fits.then_some(Request { action, thing, every_week })
}

/// "3 pm", "3pm", "3:30 PM", "15:00", "alas 3": minutes from midnight (C13). A bare number is not a time.
pub fn clock_in(msg: &str) -> Option<u16> {
    // "3:30 PM" reads as one token, "3:30pm".
    let glued = [(" p.m", "pm"), (" a.m", "am"), (" pm", "pm"), (" am", "am")].iter().fold(msg.to_lowercase(), |m, (a, b)| m.replace(a, b));
    let t: Vec<String> = glued.split_whitespace().map(|s| s.trim_matches(|c: char| !c.is_alphanumeric() && c != ':').to_string()).collect();
    let hm = |s: &str| -> Option<(u16, u16)> {
        let (h, m) = s.split_once(':').unwrap_or((s, "0"));
        let (h, m) = (h.parse::<u16>().ok()?, m.parse::<u16>().ok()?);
        (h < 24 && m < 60).then_some((h, m))
    };
    let half = |h: u16, m: u16, pm: bool| (h <= 12 && h > 0).then(|| ((h % 12) + if pm { 12 } else { 0 }) * 60 + m);
    for (i, x) in t.iter().enumerate() {
        for (suffix, pm) in [("pm", true), ("am", false), ("p.m", true), ("a.m", false)] {
            if let Some(n) = x.strip_suffix(suffix).filter(|n| !n.is_empty()).and_then(hm) {
                return half(n.0, n.1, pm);
            }
        }
        if x.contains(':') {
            if let Some((h, m)) = hm(x) {
                return Some(h * 60 + m);
            }
        }
        // "alas 3", "alas-3": afternoon from 1 to 6, as a class time reads.
        if let Some(n) = x.strip_prefix("alas").map(|r| r.trim_start_matches('-')) {
            let h = if n.is_empty() { t.get(i + 1).and_then(|y| y.parse::<u16>().ok()) } else { n.parse().ok() };
            if let Some(h) = h.filter(|h| (1..=12).contains(h)) {
                return Some(if h <= 6 { h + 12 } else { h } * 60);
            }
        }
    }
    None
}

/// A day the message names, or Err(PASSED) for one before today (C13). Explicit years and "yesterday" can be past.
pub fn day_in(msg: &str, today: Date) -> Result<Option<Date>, &'static str> {
    if has(&words(msg), &["yesterday", "kahapon"]) {
        return Err(PASSED);
    }
    match resolve_when(msg, today) {
        Some(d) if d < today => Err(PASSED),
        d => Ok(d),
    }
}

/// The request's words that say which item, not what to do with it.
fn topic(msg: &str) -> Vec<String> {
    const SKIP: &[&str] = &[
        "the", "a", "an", "my", "this", "that", "it", "to", "in", "into", "of", "on", "for", "from", "and", "with", "is", "be", "me", "i", "please", "can", "you", "could", "pls", "s", "na", "ko", "ang", "sa", "ng", "mo", "yung", "ako", "ito", "namin",
        "kami", "we", "have", "has", "our", "will", "move", "moved", "ilipat", "resched", "reschedule", "postpone", "delete", "remove", "cancel", "erase", "drop", "done", "finished", "finish", "tapos", "natapos", "submitted", "rename", "change", "update",
        "edit", "set", "no", "wala", "walang", "online", "class", "classes", "klase", "reminder", "reminders", "paalala", "every", "week", "weekly", "now", "lagi", "today", "tomorrow", "bukas", "ngayon", "next", "monday", "tuesday", "wednesday",
        "thursday", "friday", "saturday", "sunday", "mon", "tue", "wed", "thu", "fri", "sat", "sun", "lunes", "martes", "miyerkules", "huwebes", "biyernes", "sabado", "linggo", "pm", "am", "deadline", "due", "already", "just", "na", "lang",
    ];
    words(msg).into_iter().filter(|w| (w.chars().count() >= 2 || w.parse::<u32>().is_ok()) && !SKIP.contains(&w.as_str())).collect()
}

/// One clear item, two to four to pick from, or none (C12, scored as 062 C8).
#[derive(Debug, PartialEq)]
pub enum Found<T> {
    One(T),
    Pick(Vec<T>),
    None,
}

/// `full`: the item holds every word the request names, so "lab report 4" is Lab report 4, not Lab report 3.
fn best<T: Clone>(mut scored: Vec<(usize, bool, T)>) -> Found<T> {
    scored.retain(|(s, ..)| *s > 0);
    scored.sort_by_key(|s| std::cmp::Reverse(s.0));
    let full: Vec<&T> = scored.iter().filter(|s| s.1).map(|s| &s.2).collect();
    if let [x] = full.as_slice() {
        return Found::One((*x).clone());
    }
    match scored.as_slice() {
        [] => Found::None,
        [(.., x)] => Found::One(x.clone()),
        [(a, _, x), (b, ..), ..] if *a >= 2 * b => Found::One(x.clone()),
        _ => Found::Pick(scored.into_iter().take(PICK_MAX).map(|(.., x)| x).collect()),
    }
}

/// How many of `want` the text holds (three each), and whether it holds them all.
fn hits(want: &[String], text: &str) -> (usize, bool) {
    let have = words(text);
    let n = want.iter().filter(|w| have.contains(w)).count();
    (n * 3, n > 0 && n == want.len())
}

/// Deadlines by title words (three each) and the subject named (three) and the day named (two).
pub fn find_deadline(which: &str, rows: &[DeadlineRow], subject: Option<&str>, day: Option<Date>) -> Found<DeadlineRow> {
    let want = topic(which);
    // A day named that some deadline falls on narrows it to those.
    let on_day = day.filter(|d| rows.iter().any(|r| r.date == *d));
    best(
        rows.iter()
            .filter(|r| on_day.is_none_or(|d| r.date == d))
            .map(|r| {
                let (mut s, full) = hits(&want, &r.title);
                if s > 0 || want.is_empty() {
                    s += if subject.is_some() && r.subject.as_deref() == subject { 3 } else { 0 } + if day == Some(r.date) { 2 } else { 0 };
                }
                (s, full, r.clone())
            })
            .collect(),
    )
}

/// Class meetings by code, name words and the day named. With a subject named, only its meetings count.
pub fn find_class(which: &str, rows: &[ClassRow], subject: Option<&str>, day: Option<Weekday>) -> Found<ClassRow> {
    let want = topic(which);
    best(
        rows.iter()
            .filter(|r| subject.is_none_or(|s| r.code == s))
            .filter(|r| day.is_none_or(|d| r.day == d))
            .map(|r| {
                let (s, full) = if subject.is_some() { (3, false) } else { hits(&want, &format!("{} {}", r.code, r.name)) };
                (s + usize::from(day.is_some() && s > 0) * 2, full, r.clone())
            })
            .collect(),
    )
}

pub fn find_reminder(which: &str, rows: &[ReminderRow]) -> Found<ReminderRow> {
    let want = topic(which);
    best(rows.iter().map(|r| {
        let (s, full) = hits(&want, &r.text);
        (s, full, r.clone())
    }).collect())
}

/// The text before " to " / " sa " says which item; after it, where it goes ("move my lab report to Monday").
fn split_to(msg: &str) -> (String, String) {
    let low = msg.to_lowercase();
    match [" to ", " into ", " sa "].iter().filter_map(|k| low.rfind(k).map(|i| (i, k.len()))).max() {
        Some((i, n)) => (low[..i].to_string(), low[i + n..].to_string()),
        None => (low, String::new()),
    }
}

fn source_name(s: Source) -> &'static str {
    match s {
        Source::Mabini => "eMabini",
        Source::Syllabus => "your syllabus",
        Source::Own => "you",
    }
}

/// A one-meeting change lands on the meeting itself: the day named, else the next time it meets from today.
fn next_meeting(day: Weekday, today: Date) -> Date {
    let ahead = (i64::from(day.number()) - i64::from(today.weekday().number())).rem_euclid(7);
    today.add_days(ahead)
}

fn deadline_pick(v: Vec<DeadlineRow>, msg: &str) -> Proposal {
    Proposal::PickItem { candidates: v.into_iter().map(|d| (d.id, d.title, "deadline")).collect(), ask: msg.into() }
}

/// The change a calendar request asks for, as a card to confirm, or the line LAR says instead.
pub fn plan(req: Request, msg: &str, cal: &Calendar, today: Date, subjects: &[(String, String)]) -> Result<Proposal, String> {
    let subject = subject_in(msg, subjects);
    match req.thing {
        Thing::Deadline => deadline(req, msg, cal, today, subjects, subject.as_deref()),
        Thing::Class => class(req, msg, cal, today, subject.as_deref()),
        Thing::Reminder => reminder(req, msg, cal, today),
    }
}

fn deadline(req: Request, msg: &str, cal: &Calendar, today: Date, subjects: &[(String, String)], subject: Option<&str>) -> Result<Proposal, String> {
    if req.action == Action::Add {
        day_in(msg, today)?;
        // "Add a lab report due Friday": the quick add reads the rest (spec 041 C11).
        let rest = words_after(msg, &["add", "new", "create", "idagdag", "dagdag", "magdagdag"]);
        let d = parse_own(&rest, today, subjects).into_iter().next().ok_or(NO_DATE)?;
        let date = d.date.ok_or(NO_DATE)?;
        return Ok(Proposal::AddDeadline { title: d.title, subject: d.subject, kind: d.kind, date });
    }
    let (which, to) = if matches!(req.action, Action::Move | Action::Rename) { split_to(msg) } else { (msg.to_lowercase(), String::new()) };
    let named = day_in(&which, today).ok().flatten();
    let d = match find_deadline(&which, &cal.deadlines, subject, named) {
        Found::One(d) => d,
        Found::Pick(v) => return Ok(deadline_pick(v, msg)),
        Found::None => return Err(NOT_FOUND.into()),
    };
    let own = d.source == Source::Own;
    match req.action {
        Action::Done => Ok(Proposal::DoneDeadline { id: d.id, name: d.title }),
        _ if !own => Err(format!("That deadline comes from {}, so I can't move it. I can mark it done.", source_name(d.source))),
        Action::Delete => Ok(Proposal::DeleteDeadline { id: d.id, name: d.title, date: d.date }),
        Action::Rename => {
            let title = crate::edit::new_title(msg).ok_or("What should I call it? Say the new name, like \"rename the essay to Reflection paper\".")?;
            Ok(Proposal::ChangeDeadline { id: d.id, name: d.title, was: d.date, title, date: d.date })
        }
        _ => {
            let date = day_in(&to, today)?.or(day_in(msg, today)?.filter(|x| Some(*x) != named)).ok_or(NO_DATE)?;
            Ok(Proposal::ChangeDeadline { id: d.id, title: d.title.clone(), name: d.title, was: d.date, date })
        }
    }
}

fn class(req: Request, msg: &str, cal: &Calendar, today: Date, subject: Option<&str>) -> Result<Proposal, String> {
    if req.action == Action::Add {
        // A class has too many fields for one card: the class editor opens, filled with what was read (C10).
        let low = msg.to_lowercase();
        let name = [" called ", " named "].iter().find_map(|k| low.find(k).map(|i| msg[i + k.len()..].to_string())).map(|n| {
            let cut = [" on ", " every ", " at ", " tuwing ", " sa "].iter().filter_map(|k| n.to_lowercase().find(k)).min().unwrap_or(n.len());
            n[..cut].trim().trim_end_matches(['.', '!']).to_string()
        });
        return Ok(Proposal::NewClass { name: name.unwrap_or_default(), day: day_in(msg, today)?.map(Date::weekday), start: clock_in(msg) });
    }
    let (which, to) = if matches!(req.action, Action::Move | Action::Rename | Action::Change) { split_to(msg) } else { (msg.to_lowercase(), String::new()) };
    let named = day_in(&which, today)?;
    let c = match find_class(&which, &cal.classes, subject, named.map(Date::weekday)) {
        Found::One(c) => c,
        Found::Pick(v) => return Ok(Proposal::PickItem { candidates: v.into_iter().map(|c| (c.session.clone(), class_label(&c), "class")).collect(), ask: msg.into() }),
        Found::None => return Err(NOT_FOUND.into()),
    };
    let week = if req.every_week { None } else { Some(named.unwrap_or_else(|| next_meeting(c.day, today))) };
    let own_class = || cal.own_classes.iter().find(|o| o.code == c.code).cloned();
    match req.action {
        Action::NoClass => Ok(Proposal::MarkClass { name: class_label(&c), session: c.session, week, mark: Mark::Vacant }),
        Action::Online => Ok(Proposal::MarkClass { name: class_label(&c), session: c.session, week, mark: Mark::Online }),
        Action::Move => {
            let new_day = day_in(&to, today)?.map(Date::weekday);
            let start = clock_in(&to).or_else(|| clock_in(msg));
            if new_day.is_none() && start.is_none() {
                return Err("What time should it move to? Say it like \"move it to 3 pm\".".into());
            }
            let start = start.unwrap_or(c.start);
            let slot = Slot { day: new_day.unwrap_or(c.day), start, end: (start + (c.end - c.start)).min(24 * 60 - 1) };
            Ok(Proposal::MoveClass { session: c.session.clone(), name: class_label(&c), week, was: Slot { day: c.day, start: c.start, end: c.end }, slot })
        }
        Action::Delete => match own_class() {
            Some(o) if c.own => Ok(Proposal::DeleteOwnClass { code: o.code, name: o.name }),
            _ => Err("That class comes from your school, so I can't delete it. I can mark a day no class.".into()),
        },
        _ => {
            let Some(was) = own_class().filter(|_| c.own) else { return Err(SCHOOL_CLASS.into()) };
            let new = to.trim().trim_end_matches(['.', '!']).to_string();
            let new = crate::edit::new_title(msg).filter(|_| !new.is_empty()).unwrap_or(new);
            if new.is_empty() {
                return Err("What should it change to? Say it like \"change my review class room to 302\".".into());
            }
            let mut class = was.clone();
            if req.action == Action::Change && has(&words(&which), &["room", "kwarto"]) {
                class.room = new;
            } else if req.action == Action::Change && has(&words(&which), &["teacher", "prof"]) {
                class.teacher = new;
            } else {
                class.name = new;
            }
            Ok(Proposal::ChangeOwnClass { was, class })
        }
    }
}

fn reminder(req: Request, msg: &str, cal: &Calendar, today: Date) -> Result<Proposal, String> {
    let (which, to) = if req.action == Action::Move { split_to(msg) } else { (msg.to_lowercase(), String::new()) };
    let r = match find_reminder(&which, &cal.reminders) {
        Found::One(r) => r,
        Found::Pick(v) => return Ok(Proposal::PickItem { candidates: v.into_iter().map(|r| (r.id.to_string(), r.text, "reminder")).collect(), ask: msg.into() }),
        Found::None => return Err(NOT_FOUND.into()),
    };
    match req.action {
        Action::Delete => Ok(Proposal::DeleteReminder { id: r.id, text: r.text }),
        _ => {
            let date = day_in(&to, today)?.ok_or("What day should I move it to?")?;
            Ok(Proposal::MoveReminder { id: r.id, text: r.text, was: r.date, date })
        }
    }
}

/// "COMP 20073 · Fri 9:00": how a class reads on a picker row and a card.
fn class_label(c: &ClassRow) -> String {
    let name = if c.name.is_empty() { c.code.clone() } else { format!("{} {}", c.code, c.name).trim().to_string() };
    let (h, m) = (c.start / 60, c.start % 60);
    format!("{name} · {} {}:{m:02} {}", &format!("{:?}", c.day)[..3], if h % 12 == 0 { 12 } else { h % 12 }, if h < 12 { "AM" } else { "PM" })
}

/// The message after its first verb ("add a lab report due Friday" → "lab report due Friday"), articles dropped.
fn words_after(msg: &str, verbs: &[&str]) -> String {
    let t: Vec<&str> = msg.split_whitespace().collect();
    let at = t.iter().position(|x| verbs.contains(&x.to_lowercase().trim_matches(|c: char| !c.is_alphanumeric())));
    let rest = at.map_or(&t[..], |i| &t[i + 1..]);
    let skip = rest.iter().take_while(|x| ["a", "an", "the", "my", "ng", "ang", "deadline", "new"].contains(&x.to_lowercase().as_str())).count();
    rest[skip..].join(" ")
}

#[cfg(test)]
mod tests {
    use super::*;
    use intportal_core::syllabus::Kind;

    /// Thursday 2026-10-15.
    const THU: Date = Date { y: 2026, m: 10, d: 15 };

    fn subjects() -> Vec<(String, String)> {
        vec![("MATH 101".into(), "Calculus".into()), ("COMP 20073".into(), "Data Structures".into()), ("ORG".into(), "Org meeting".into())]
    }

    fn dl(id: &str, title: &str, subject: Option<&str>, date: Date, source: Source) -> DeadlineRow {
        DeadlineRow { id: id.into(), title: title.into(), subject: subject.map(String::from), date, source }
    }

    fn cls(code: &str, name: &str, day: Weekday, start: u16, own: bool) -> ClassRow {
        ClassRow { session: format!("{code}-{}-{start}-{}", day.number(), start + 90), code: code.into(), name: name.into(), day, start, end: start + 90, own }
    }

    fn cal() -> Calendar {
        Calendar {
            deadlines: vec![
                dl("own:1", "Lab report 3", Some("COMP 20073"), Date::new(2026, 10, 16), Source::Own),
                dl("own:2", "Reflection essay", None, Date::new(2026, 10, 20), Source::Own),
                dl("syl:MATH 101:q2", "Quiz 2", Some("MATH 101"), Date::new(2026, 10, 19), Source::Syllabus),
                dl("mab:9", "Lab report 4", Some("COMP 20073"), Date::new(2026, 10, 22), Source::Mabini),
            ],
            classes: vec![
                cls("MATH 101", "Calculus", Weekday::Monday, 9 * 60, false),
                cls("MATH 101", "Calculus", Weekday::Friday, 9 * 60, false),
                cls("COMP 20073", "Data Structures", Weekday::Friday, 13 * 60, false),
                cls("ORG", "Org meeting", Weekday::Wednesday, 16 * 60, true),
            ],
            own_classes: vec![OwnClass { code: "ORG".into(), name: "Org meeting".into(), room: "S101".into(), teacher: String::new(), meetings: vec![] }],
            reminders: vec![ReminderRow { id: 7, text: "Pay tuition".into(), date: Date::new(2026, 10, 19) }, ReminderRow { id: 8, text: "Bring ID".into(), date: Date::new(2026, 10, 17) }],
        }
    }

    fn go(msg: &str) -> Result<Proposal, String> {
        let r = request(msg, &subjects()).unwrap_or_else(|| panic!("not a change: {msg}"));
        plan(r, msg, &cal(), THU, &subjects())
    }

    #[test]
    fn c2_a_change_needs_a_verb_and_a_thing_in_english_taglish_and_filipino() {
        use Action::*;
        for (msg, action, thing) in [
            ("add a lab report due Friday", Add, Thing::Deadline),
            ("move my lab report to Monday", Move, Thing::Deadline),
            ("rename the essay to Reflection paper", Rename, Thing::Deadline),
            ("I finished the lab report", Done, Thing::Deadline),
            ("tapos na ako sa essay", Done, Thing::Deadline),
            ("done na ako sa lab report", Done, Thing::Deadline),
            ("delete the lab report", Delete, Thing::Deadline),
            ("ilipat ang lab report sa Lunes", Move, Thing::Deadline),
            ("no MATH class tomorrow", NoClass, Thing::Class),
            ("walang klase sa MATH bukas", NoClass, Thing::Class),
            ("wala kaming klase sa COMP sa Biyernes", NoClass, Thing::Class),
            ("Friday's COMP class is online", Online, Thing::Class),
            ("online ang MATH bukas", Online, Thing::Class),
            ("move tomorrow's COMP to 3 pm", Move, Thing::Class),
            ("change my org meeting room to 302", Change, Thing::Class),
            ("delete my org meeting class", Delete, Thing::Class),
            ("add a class called Review on Saturday at 9 am", Add, Thing::Class),
            ("delete the tuition reminder", Delete, Thing::Reminder),
            ("move the tuition reminder to Saturday", Move, Thing::Reminder),
            ("can you move my lab report to Monday?", Move, Thing::Deadline),
        ] {
            let r = request(msg, &subjects()).unwrap_or_else(|| panic!("{msg}"));
            assert_eq!((r.action, r.thing), (action, thing), "{msg}");
        }
    }

    #[test]
    fn c2_questions_and_other_requests_never_change_anything() {
        for msg in [
            "When is my lab due?",
            "what's due this week",
            "Is my COMP class online tomorrow?",
            "May klase ba ako bukas?",
            "Online ba ang MATH bukas",
            "kailan ang quiz sa MATH?",
            "ano ang due ko",
            "remind me to finish the lab report",
            "add a note: the lab moved to Monday",
            "make a quiz on recursion",
            "make 5 flashcards on heaps",
            "explain recursion",
            "Anong klase ko ngayon?",
        ] {
            assert_eq!(request(msg, &subjects()), None, "{msg}");
        }
    }

    #[test]
    fn c8_every_week_only_when_said() {
        for msg in ["MATH class is online every week", "no ORG class from now on", "lagi nang online ang COMP"] {
            assert!(request(msg, &subjects()).unwrap().every_week, "{msg}");
        }
        assert!(!request("no MATH class tomorrow", &subjects()).unwrap().every_week);
    }

    #[test]
    fn c13_dates_and_times_are_read_by_the_rules() {
        for (msg, want) in [("tomorrow", 16), ("Friday", 16), ("next Monday", 19), ("bukas", 16), ("sa Biyernes", 16), ("Oct 30", 30)] {
            assert_eq!(day_in(msg, THU), Ok(Some(Date::new(2026, 10, want))), "{msg}");
        }
        assert_eq!(day_in("Dec 3", THU), Ok(Some(Date::new(2026, 12, 3))));
        assert_eq!(day_in("10/1/2026", THU), Err(PASSED));
        assert_eq!(day_in("kahapon", THU), Err(PASSED));
        assert_eq!(day_in("the lab report", THU), Ok(None));
        for (msg, want) in [("3 pm", 15 * 60), ("3pm", 15 * 60), ("3:30 PM", 15 * 60 + 30), ("10 am", 600), ("12 pm", 720), ("12am", 0), ("15:00", 900), ("alas 3", 900), ("alas-9", 540)] {
            assert_eq!(clock_in(msg), Some(want), "{msg}");
        }
        for msg in ["room 302", "lab 3", "at 3", "13 pm"] {
            assert_eq!(clock_in(msg), None, "{msg}");
        }
    }

    #[test]
    fn c12_one_clear_match_a_picker_or_none() {
        assert!(matches!(find_deadline("the essay", &cal().deadlines, None, None), Found::One(d) if d.id == "own:2"));
        match find_deadline("my lab report", &cal().deadlines, None, None) {
            Found::Pick(v) => assert_eq!(v.iter().map(|d| d.id.as_str()).collect::<Vec<_>>(), ["own:1", "mab:9"]),
            other => panic!("{other:?}"),
        }
        // The day named settles it.
        assert!(matches!(find_deadline("lab report", &cal().deadlines, None, Some(Date::new(2026, 10, 16))), Found::One(d) if d.id == "own:1"));
        assert_eq!(find_deadline("thesis", &cal().deadlines, None, None), Found::None);
        assert!(matches!(find_reminder("the tuition reminder", &cal().reminders), Found::One(r) if r.id == 7));
        assert_eq!(find_reminder("the gym reminder", &cal().reminders), Found::None);
    }

    #[test]
    fn c12_the_picker_offers_two_to_four_rows_with_their_kind() {
        match go("move my lab report to Monday").unwrap() {
            Proposal::PickItem { candidates, ask } => {
                assert_eq!(candidates.iter().map(|c| (c.0.as_str(), c.2)).collect::<Vec<_>>(), [("own:1", "deadline"), ("mab:9", "deadline")]);
                assert_eq!(ask, "move my lab report to Monday");
            }
            p => panic!("{p:?}"),
        }
        match go("MATH class is online every week").unwrap() {
            Proposal::PickItem { candidates, .. } => assert_eq!(candidates.iter().map(|c| c.1.as_str()).collect::<Vec<_>>(), ["MATH 101 Calculus · Mon 9:00 AM", "MATH 101 Calculus · Fri 9:00 AM"]),
            p => panic!("{p:?}"),
        }
        assert_eq!(go("delete the thesis deadline"), Err(NOT_FOUND.into()));
    }

    #[test]
    fn deadlines_add_move_rename_done_delete() {
        assert_eq!(go("add a lab report due Friday"), Ok(Proposal::AddDeadline { title: "Lab report".into(), subject: None, kind: Kind::Project, date: Date::new(2026, 10, 16) }));
        assert_eq!(go("add a quiz for MATH 101 on Monday"), Ok(Proposal::AddDeadline { title: "Quiz".into(), subject: Some("MATH 101".into()), kind: Kind::Quiz, date: Date::new(2026, 10, 19) }));
        assert_eq!(go("add a lab report"), Err(NO_DATE.into()));
        assert_eq!(go("add a lab report due 10/1/2026"), Err(PASSED.into()));
        assert_eq!(go("move the essay to Monday"), Ok(Proposal::ChangeDeadline { id: "own:2".into(), name: "Reflection essay".into(), was: Date::new(2026, 10, 20), title: "Reflection essay".into(), date: Date::new(2026, 10, 19) }));
        assert_eq!(go("ilipat ang essay sa Lunes"), go("move the essay to Monday"));
        assert_eq!(go("move the essay"), Err(NO_DATE.into()));
        assert_eq!(go("rename the essay to Reflection paper"), Ok(Proposal::ChangeDeadline { id: "own:2".into(), name: "Reflection essay".into(), was: Date::new(2026, 10, 20), title: "Reflection paper".into(), date: Date::new(2026, 10, 20) }));
        assert_eq!(go("I finished Quiz 2"), Ok(Proposal::DoneDeadline { id: "syl:MATH 101:q2".into(), name: "Quiz 2".into() }));
        assert_eq!(go("tapos na ako sa essay"), Ok(Proposal::DoneDeadline { id: "own:2".into(), name: "Reflection essay".into() }));
        assert_eq!(go("delete the essay"), Ok(Proposal::DeleteDeadline { id: "own:2".into(), name: "Reflection essay".into(), date: Date::new(2026, 10, 20) }));
    }

    #[test]
    fn school_deadlines_can_only_be_marked_done() {
        assert_eq!(go("move quiz 2 to Friday"), Err("That deadline comes from your syllabus, so I can't move it. I can mark it done.".into()));
        assert_eq!(go("delete lab report 4"), Err("That deadline comes from eMabini, so I can't move it. I can mark it done.".into()));
    }

    #[test]
    fn classes_one_meeting_by_default_every_week_when_said() {
        let math_fri = cal().classes[1].session.clone();
        assert_eq!(go("no MATH class tomorrow"), Ok(Proposal::MarkClass { session: math_fri.clone(), name: "MATH 101 Calculus · Fri 9:00 AM".into(), week: Some(Date::new(2026, 10, 16)), mark: Mark::Vacant }));
        assert_eq!(go("walang klase sa MATH bukas"), go("no MATH class tomorrow"));
        let comp = cal().classes[2].session.clone();
        assert!(matches!(go("Friday's COMP class is online"), Ok(Proposal::MarkClass { session, week: Some(w), mark: Mark::Online, .. }) if session == comp && w == Date::new(2026, 10, 16)));
        assert!(matches!(go("COMP is online every week"), Ok(Proposal::MarkClass { week: None, mark: Mark::Online, .. })));
        // No day named: the next time it meets.
        assert!(matches!(go("no ORG class"), Ok(Proposal::MarkClass { week: Some(w), .. }) if w == Date::new(2026, 10, 21)));
        assert_eq!(go("no MATH class on Thursday"), Err(NOT_FOUND.into()), "MATH doesn't meet on Thursdays");
        assert_eq!(go("no MATH class on 10/1/2026"), Err(PASSED.into()));
    }

    #[test]
    fn classes_move_keeps_the_length_and_the_week() {
        let comp = cal().classes[2].clone();
        assert_eq!(
            go("move tomorrow's COMP to 3 pm"),
            Ok(Proposal::MoveClass { session: comp.session.clone(), name: "COMP 20073 Data Structures · Fri 1:00 PM".into(), week: Some(Date::new(2026, 10, 16)), was: Slot { day: Weekday::Friday, start: 780, end: 870 }, slot: Slot { day: Weekday::Friday, start: 900, end: 990 } })
        );
        assert!(matches!(go("move my org meeting class to 3 pm every week"), Ok(Proposal::MoveClass { week: None, slot: Slot { day: Weekday::Wednesday, start: 900, .. }, .. })));
        assert!(go("move tomorrow's COMP").is_err());
    }

    #[test]
    fn own_classes_change_and_delete_school_classes_dont() {
        let was = cal().own_classes[0].clone();
        assert_eq!(go("change my org meeting room to 302"), Ok(Proposal::ChangeOwnClass { was: was.clone(), class: OwnClass { room: "302".into(), ..was.clone() } }));
        assert_eq!(go("rename my org meeting class to Org night"), Ok(Proposal::ChangeOwnClass { was: was.clone(), class: OwnClass { name: "Org night".into(), ..was.clone() } }));
        assert_eq!(go("delete my org meeting class"), Ok(Proposal::DeleteOwnClass { code: "ORG".into(), name: "Org meeting".into() }));
        assert_eq!(go("change the COMP class room to 302"), Err(SCHOOL_CLASS.into()));
        assert!(go("delete my COMP class").unwrap_err().contains("from your school"));
    }

    #[test]
    fn c10_add_a_class_opens_the_editor_with_what_was_read() {
        assert_eq!(go("add a class called Review on Saturday at 9 am"), Ok(Proposal::NewClass { name: "Review".into(), day: Some(Weekday::Saturday), start: Some(540) }));
        assert_eq!(go("add a class"), Ok(Proposal::NewClass { name: String::new(), day: None, start: None }));
    }

    #[test]
    fn c11_lars_reminders_found_by_their_text() {
        assert_eq!(go("delete the tuition reminder"), Ok(Proposal::DeleteReminder { id: 7, text: "Pay tuition".into() }));
        assert_eq!(go("move the tuition reminder to Saturday"), Ok(Proposal::MoveReminder { id: 7, text: "Pay tuition".into(), was: Date::new(2026, 10, 19), date: Date::new(2026, 10, 17) }));
        assert_eq!(go("move the tuition reminder"), Err("What day should I move it to?".into()));
        assert_eq!(go("delete the gym reminder"), Err(NOT_FOUND.into()));
    }
}
