//! Every deadline the student has, in one list (spec 041): syllabus quizzes,
//! exams and projects, eMabini work, and the ones they add themselves. Today,
//! reminders, LAR and the calendar all read this list, so nothing due is ever
//! missing from one of them.

use crate::{
    mabini::{parse::split_course_name, MabiniData},
    model::ClassSession,
    store::Snapshot,
    syllabus::Kind,
    today::{clock, reminder_id, Date, Moment, Reminder},
    when,
};
use serde::{Deserialize, Serialize};

/// Days a deadline stays in the list, marked overdue, after it was due (C4).
pub const OVERDUE_DAYS: i64 = 3;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Source {
    Syllabus,
    Mabini,
    Own,
}

/// A whole day (syllabus, own) or an exact time in epoch seconds (eMabini).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Due {
    Day(Date),
    At(i64),
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Deadline {
    /// Stable across syncs: `syl:<code>:<item>`, `mab:<id>`, `own:<id>` (C2).
    pub id: String,
    pub source: Source,
    pub subject: Option<String>,
    /// The eMabini course's subject part, when no class matched it (C3).
    pub course: Option<String>,
    pub title: String,
    pub kind: Kind,
    pub due: Due,
    pub overdue: bool,
    /// eMabini only.
    pub url: Option<String>,
}

impl Deadline {
    /// What the student reads after the title: the subject, else the course.
    pub fn label(&self) -> &str {
        self.subject.as_deref().or(self.course.as_deref()).unwrap_or("")
    }
}

/// One the student added (C10–C14).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct OwnDeadline {
    pub id: String,
    pub title: String,
    pub subject: Option<String>,
    pub kind: Kind,
    pub date: Date,
}

/// What the quick add read from the student's text, for them to confirm (C12).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Draft {
    pub title: String,
    pub subject: Option<String>,
    pub kind: Kind,
    pub date: Option<Date>,
}

/// The local day and minute of an epoch second; `utc_offset` is local minus UTC in minutes.
pub fn local_parts(unix: i64, utc_offset: i32) -> (Date, u16) {
    let local = unix + i64::from(utc_offset) * 60;
    (Date::from_days(local.div_euclid(86_400)), (local.rem_euclid(86_400) / 60) as u16)
}

/// Local minutes since 1970, for ordering. A whole-day deadline counts as 11:59 PM (C1).
fn local_minutes(due: Due, utc_offset: i32) -> i64 {
    match due {
        Due::Day(d) => d.days() * 1440 + 1439,
        Due::At(u) => (u + i64::from(utc_offset) * 60).div_euclid(60),
    }
}

fn local_date(due: Due, utc_offset: i32) -> Date {
    match due {
        Due::Day(d) => d,
        Due::At(u) => local_parts(u, utc_offset).0,
    }
}

/// Moodle titles an event "X is due", "X closes" or "X opens"; the student wants X.
pub fn clean_title(name: &str) -> &str {
    let low = name.to_lowercase();
    [" is due", " closes", " opens"].iter().find(|s| low.ends_with(*s)).map_or(name, |s| name[..name.len() - s.len()].trim_end())
}

/// The class an eMabini course belongs to: its subject part equals or contains
/// a class's code, spaces and case aside; the longest code wins (C3).
fn class_of(course: &str, sessions: &[ClassSession]) -> Option<String> {
    let key = |s: &str| s.chars().filter(|c| c.is_alphanumeric()).collect::<String>().to_uppercase();
    let subject = key(&split_course_name(course).0);
    sessions.iter().map(|s| &s.subject_code).filter(|c| !key(c).is_empty() && subject.contains(&key(c))).max_by_key(|c| key(c).len()).cloned()
}

/// The one list: dated, not done, from `OVERDUE_DAYS` ago through the next
/// `days` days, soonest first (C1–C5). `utc_offset` is local minus UTC in minutes.
pub fn deadlines(snap: &Snapshot, mabini: &MabiniData, now: Moment, utc_offset: i32, days: i64) -> Vec<Deadline> {
    let (first, last) = (now.date.add_days(-OVERDUE_DAYS), now.date.add_days(days - 1));
    let now_min = now.date.days() * 1440 + i64::from(now.minute);
    let syllabus = snap.syllabus.iter().flat_map(|(code, plan)| {
        plan.items.iter().filter(|i| !i.done && i.kind != Kind::Lecture).filter_map(move |i| {
            Some(Deadline {
                id: format!("syl:{code}:{}", i.id),
                source: Source::Syllabus,
                subject: Some(code.clone()),
                course: None,
                title: i.topic.clone(),
                kind: i.kind,
                due: Due::Day(i.date?),
                overdue: false,
                url: None,
            })
        })
    });
    let emabini = mabini.deadlines.iter().map(|d| {
        let subject = class_of(&d.course, &snap.sessions);
        Deadline {
            id: format!("mab:{}", d.id),
            source: Source::Mabini,
            course: subject.is_none().then(|| split_course_name(&d.course).0),
            subject,
            title: clean_title(&d.name).to_string(),
            kind: if d.kind == "quiz" { Kind::Quiz } else { Kind::Project },
            due: Due::At(d.due),
            overdue: d.overdue,
            url: d.url.starts_with("https://").then(|| d.url.clone()),
        }
    });
    let own = snap.own_deadlines.iter().map(|o| Deadline {
        id: format!("own:{}", o.id),
        source: Source::Own,
        subject: o.subject.clone(),
        course: None,
        title: o.title.clone(),
        kind: o.kind,
        due: Due::Day(o.date),
        overdue: false,
        url: None,
    });
    let mut out: Vec<Deadline> = syllabus
        .chain(emabini)
        .chain(own)
        .filter(|d| !snap.done.contains(&d.id))
        .filter(|d| (first..=last).contains(&local_date(d.due, utc_offset)))
        .map(|mut d| {
            d.overdue |= local_minutes(d.due, utc_offset) < now_min;
            d
        })
        .collect();
    out.sort_by(|a, b| local_minutes(a.due, utc_offset).cmp(&local_minutes(b.due, utc_offset)).then_with(|| a.title.cmp(&b.title)));
    out
}

/// Heads-ups for the next `days` days: the evening before each deadline at
/// `minute`, and 8 AM on the day for one due at noon or later (C19).
pub fn reminders(list: &[Deadline], now: Moment, minute: u16, utc_offset: i32, days: i64) -> Vec<Reminder> {
    let later = |date: Date, m: u16| (date, m) > (now.date, now.minute) && date < now.date.add_days(days);
    let mut out = vec![];
    for d in list.iter().filter(|d| !d.overdue) {
        let (date, at) = match d.due {
            Due::Day(day) => (day, None),
            Due::At(u) => {
                let (day, m) = local_parts(u, utc_offset);
                (day, Some(m))
            }
        };
        let body = if d.label().is_empty() { d.title.clone() } else { format!("{} · {}", d.title, d.label()) };
        let eve = date.add_days(-1);
        if later(eve, minute) {
            let what = match d.kind {
                Kind::Quiz => "Quiz",
                Kind::Exam => "Exam",
                _ => "Due",
            };
            out.push(Reminder { id: reminder_id(&format!("due:{}", d.id)), date: eve, minute, title: format!("{what} tomorrow"), body: body.clone() });
        }
        if let Some(m) = at.filter(|m| *m >= 12 * 60) {
            if later(date, 8 * 60) {
                out.push(Reminder { id: reminder_id(&format!("due-day:{}", d.id)), date, minute: 8 * 60, title: format!("Due today at {}", clock(m)), body });
            }
        }
    }
    out.sort_by_key(|r| (r.date, r.minute));
    out
}

/// Words that tie a date or a subject to the sentence ("on Friday", "sa COMP").
const CONNECTORS: &[&str] = &["on", "by", "due", "until", "sa", "this", "next", "before", "bago", "for"];

fn kind_in(text: &str) -> Kind {
    let w = when::words(text);
    let has = |list: &[&str]| w.iter().any(|x| list.contains(&x.as_str()));
    if has(&["quiz", "quizzes", "seatwork"]) {
        Kind::Quiz
    } else if has(&["exam", "exams", "midterm", "midterms", "final", "finals", "prelim", "prelims"]) {
        Kind::Exam
    } else {
        Kind::Project
    }
}

fn draft(line: &str, today: Date, subjects: &[(String, String)]) -> Draft {
    let tokens: Vec<&str> = line.split_whitespace().collect();
    let found = when::when_in(line, today);
    let subject = when::subject_in(line, subjects);
    let mut drop = vec![false; tokens.len()];
    for i in found.iter().flat_map(|(_, idx)| idx.iter().copied()) {
        drop[i] = true;
    }
    if let Some(code) = &subject {
        let parts = when::words(code);
        let squashed = parts.concat();
        for (i, t) in tokens.iter().enumerate() {
            let w = when::words(t).concat();
            if !w.is_empty() && (parts.contains(&w) || w == squashed) {
                drop[i] = true;
            }
        }
    }
    // A connector goes with the date or subject right after it.
    for i in 0..tokens.len().saturating_sub(1) {
        if drop[i + 1] && !drop[i] && CONNECTORS.contains(&when::words(tokens[i]).concat().as_str()) {
            drop[i] = true;
        }
    }
    let kind = kind_in(line);
    let rest: Vec<&str> = tokens.iter().zip(&drop).filter(|(_, d)| !**d).map(|(t, _)| *t).collect();
    let rest = rest.join(" ");
    let rest = rest.trim_matches(|c: char| c.is_whitespace() || ",;:-".contains(c));
    let mut title: String = rest.chars().take(80).collect();
    if let Some(first) = title.chars().next() {
        title.replace_range(..first.len_utf8(), &first.to_uppercase().to_string());
    } else {
        title = match kind {
            Kind::Quiz => "Quiz",
            Kind::Exam => "Exam",
            _ => "Project",
        }
        .into();
    }
    Draft { title, subject, kind, date: found.map(|(d, _)| d) }
}

/// The quick add (C11, C13, C17): one draft for the text, or one per line when
/// two or more lines name a day (a photo of a board, a pasted list).
/// `subjects` is (code, description).
pub fn parse_own(text: &str, today: Date, subjects: &[(String, String)]) -> Vec<Draft> {
    let lines: Vec<&str> = text.lines().map(str::trim).filter(|l| !l.is_empty()).collect();
    let dated: Vec<&str> = lines.iter().copied().filter(|l| when::resolve_when(l, today).is_some()).collect();
    if dated.len() >= 2 {
        return dated.into_iter().map(|l| draft(l, today, subjects)).collect();
    }
    let all = lines.join(" ");
    if all.is_empty() {
        vec![]
    } else {
        vec![draft(&all, today, subjects)]
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{
        mabini::parse::Deadline as MabiniDeadline,
        syllabus::{Item, Plan},
    };

    const TUE: Date = Date { y: 2026, m: 11, d: 3 };
    const NOON: Moment = Moment { date: TUE, minute: 12 * 60 };
    const PH: i32 = 480;

    /// Epoch seconds of a Manila local day and minute.
    fn at(date: Date, minute: u16) -> i64 {
        (date.days() * 1440 + i64::from(minute) - i64::from(PH)) * 60
    }

    fn session(code: &str) -> ClassSession {
        ClassSession { subject_code: code.into(), description: String::new(), faculty: String::new(), day: crate::model::Weekday::Monday, start: 480, end: 570, occurrence: 0 }
    }

    fn item(id: &str, topic: &str, kind: Kind, date: Date) -> Item {
        Item { id: id.into(), topic: topic.into(), kind, week: None, date: Some(date), done: false }
    }

    fn mab(id: u64, name: &str, course: &str, due: i64) -> MabiniDeadline {
        MabiniDeadline { id, name: name.into(), course_id: 1, course: course.into(), kind: "assign".into(), due, overdue: false, url: format!("https://emabini.pup.edu.ph/mod/assign/view.php?id={id}") }
    }

    fn world() -> (Snapshot, MabiniData) {
        let mut snap = Snapshot { sessions: vec![session("COMP 20073"), session("GEED 10053")], ..Default::default() };
        snap.syllabus.insert(
            "COMP 20073".into(),
            Plan {
                items: vec![
                    item("1", "Quiz 2", Kind::Quiz, TUE.add_days(3)),
                    item("2", "Loops", Kind::Lecture, TUE.add_days(1)),
                    Item { done: true, ..item("3", "Quiz 1", Kind::Quiz, TUE.add_days(1)) },
                    item("4", "Lab 1", Kind::Project, TUE.add_days(-5)),
                ],
                ..Default::default()
            },
        );
        snap.own_deadlines.push(OwnDeadline { id: "a1".into(), title: "Org fee".into(), subject: None, kind: Kind::Project, date: TUE.add_days(1) });
        let mabini = MabiniData {
            deadlines: vec![
                mab(7, "Essay 1 is due", "GEED10053_First Sem 2627_BSIT 1-A", at(TUE, 23 * 60 + 59)),
                mab(8, "Reflection is due", "Purposive Communication_First Sem 2627_BSIT 1-A", at(TUE.add_days(-1), 17 * 60)),
            ],
            ..Default::default()
        };
        (snap, mabini)
    }

    fn ids(list: &[Deadline]) -> Vec<&str> {
        list.iter().map(|d| d.id.as_str()).collect()
    }

    #[test]
    fn c1_three_sources_one_sorted_list() {
        let (snap, mabini) = world();
        let list = deadlines(&snap, &mabini, NOON, PH, 7);
        assert_eq!(ids(&list), ["mab:8", "mab:7", "own:a1", "syl:COMP 20073:1"], "lectures, done and old items out; soonest first");
        assert_eq!(list[1].title, "Essay 1");
        assert_eq!(list[2].due, Due::Day(TUE.add_days(1)));
    }

    #[test]
    fn c2_ids_stable_across_sync() {
        let (snap, mabini) = world();
        let mut resynced = mabini.clone();
        resynced.deadlines.reverse();
        resynced.last_synced = Some(99);
        assert_eq!(ids(&deadlines(&snap, &mabini, NOON, PH, 7)), ids(&deadlines(&snap, &resynced, NOON, PH, 7)));
    }

    #[test]
    fn c3_mabini_course_matches_subject_code() {
        let (snap, mabini) = world();
        let list = deadlines(&snap, &mabini, NOON, PH, 7);
        let essay = list.iter().find(|d| d.id == "mab:7").unwrap();
        assert_eq!((essay.subject.as_deref(), essay.course.as_deref()), (Some("GEED 10053"), None));
        let other = list.iter().find(|d| d.id == "mab:8").unwrap();
        assert_eq!((other.subject.as_deref(), other.course.as_deref()), (None, Some("Purposive Communication")));
        assert_eq!(other.label(), "Purposive Communication");
    }

    #[test]
    fn c4_overdue_drops_after_three_days() {
        let (snap, mabini) = world();
        let list = deadlines(&snap, &mabini, NOON, PH, 7);
        assert!(list.iter().find(|d| d.id == "mab:8").unwrap().overdue, "yesterday 5 PM is overdue");
        assert!(!list.iter().find(|d| d.id == "mab:7").unwrap().overdue, "tonight 11:59 PM is not yet");
        let later = Moment { date: TUE.add_days(2), minute: 9 * 60 };
        assert!(ids(&deadlines(&snap, &mabini, later, PH, 7)).contains(&"mab:8"), "due Monday, still listed Thursday");
        let gone = Moment { date: TUE.add_days(3), minute: 9 * 60 };
        assert!(!ids(&deadlines(&snap, &mabini, gone, PH, 7)).contains(&"mab:8"));
    }

    #[test]
    fn c5_done_hides_everywhere() {
        let (mut snap, mabini) = world();
        snap.done.extend(["mab:7".to_string(), "own:a1".to_string()]);
        let list = deadlines(&snap, &mabini, NOON, PH, 7);
        assert_eq!(ids(&list), ["mab:8", "syl:COMP 20073:1"]);
        let rem = reminders(&list, NOON, 19 * 60, PH, 7);
        assert!(rem.iter().all(|r| !r.body.contains("Essay") && !r.body.contains("Org fee")));
    }

    #[test]
    fn c11_parse_own() {
        let subjects = vec![("COMP 20073".to_string(), "Data Structures".to_string()), ("CS 201".to_string(), "Programming".to_string())];
        let one = |t: &str| parse_own(t, TUE, &subjects).remove(0);
        assert_eq!(one("quiz COMP fri"), Draft { title: "Quiz".into(), subject: Some("COMP 20073".into()), kind: Kind::Quiz, date: Some(Date::new(2026, 11, 6)) });
        assert_eq!(one("Exam sa Lunes CS 201"), Draft { title: "Exam".into(), subject: Some("CS 201".into()), kind: Kind::Exam, date: Some(Date::new(2026, 11, 9)) });
        assert_eq!(one("report on 11/24"), Draft { title: "Report".into(), subject: None, kind: Kind::Project, date: Some(Date::new(2026, 11, 24)) });
        let gc = one("Guys! May quiz tayo sa COMP 20073 on Friday about linked lists");
        assert_eq!((gc.title.as_str(), gc.kind, gc.date), ("Guys! May quiz tayo about linked lists", Kind::Quiz, Some(Date::new(2026, 11, 6))));
    }

    #[test]
    fn c13_no_date_found_leaves_it_for_the_student() {
        let d = parse_own("org fee", TUE, &[]).remove(0);
        assert_eq!((d.title.as_str(), d.subject, d.date), ("Org fee", None, None));
        assert!(parse_own("   \n ", TUE, &[]).is_empty());
    }

    #[test]
    fn c17_many_dated_lines() {
        let board = "Reminders:\nQuiz 3 - Nov 10\nLab report due 11/14\nbring calculator";
        let got: Vec<(String, Option<Date>)> = parse_own(board, TUE, &[]).into_iter().map(|d| (d.title, d.date)).collect();
        assert_eq!(got, [("Quiz 3".to_string(), Some(Date::new(2026, 11, 10))), ("Lab report".to_string(), Some(Date::new(2026, 11, 14)))]);
    }

    #[test]
    fn c19_reminders_all_sources() {
        let (snap, mut mabini) = world();
        mabini.deadlines.push(mab(9, "Problem set is due", "COMP20073_First Sem 2627_BSIT 1-A", at(TUE.add_days(2), 15 * 60)));
        mabini.deadlines.push(mab(10, "Short quiz closes", "COMP20073_First Sem 2627_BSIT 1-A", at(TUE.add_days(2), 9 * 60)));
        let list = deadlines(&snap, &mabini, NOON, PH, 7);
        let got: Vec<(String, u16, String, String)> = reminders(&list, NOON, 19 * 60, PH, 7).into_iter().map(|r| (r.date.to_string(), r.minute, r.title, r.body)).collect();
        let want = [
            ("2026-11-03", 19 * 60, "Due tomorrow", "Org fee"),
            ("2026-11-04", 19 * 60, "Due tomorrow", "Short quiz · COMP 20073"),
            ("2026-11-04", 19 * 60, "Due tomorrow", "Problem set · COMP 20073"),
            ("2026-11-05", 8 * 60, "Due today at 3PM", "Problem set · COMP 20073"),
            ("2026-11-05", 19 * 60, "Quiz tomorrow", "Quiz 2 · COMP 20073"),
        ];
        let want: Vec<(String, u16, String, String)> = want.iter().map(|(d, m, t, b)| (d.to_string(), *m, t.to_string(), b.to_string())).collect();
        assert_eq!(got, want, "tonight's essay is past its evening-before and its 8 AM; the 9 AM quiz gets no 8 AM");
    }
}
