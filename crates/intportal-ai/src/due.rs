//! "What is due?": every dated piece of work the app holds (syllabus quizzes,
//! exams and projects, and eMabini deadlines), overdue first, cut at the end of
//! the window the student asked about. Pure, so it is tested without a phone.
use crate::{
    assis::Facts,
    intent::{is_filipino, resolve_when, words},
    persona::{self, Line, List},
};
use intportal_core::{
    mabini::{parse::split_course_name, MabiniData},
    model::Weekday,
    syllabus::{Kind, Plan},
    today::{Date, Moment},
};
use std::collections::BTreeMap;

/// Days a Due question looks ahead when it names no window: today and the next seven.
pub const DEFAULT_DAYS: i64 = 8;

/// One dated piece of work. `line` is what the student reads, date included.
#[derive(Debug, Clone, PartialEq)]
pub struct DueItem {
    pub date: Date,
    pub overdue: bool,
    pub line: String,
}

/// "Quiz 2: COMP 20073, Friday 2026-10-16": the topic, the subject and the day.
fn describe(title: &str, subject: &str, date: Date, overdue: bool) -> String {
    format!("{title}: {subject}, {:?} {date}{}", date.weekday(), if overdue { ", overdue" } else { "" })
}

/// Quizzes, exams and projects not done and dated today or later. Past ones are left out: a
/// syllabus item is ticked by hand, so an unticked old quiz is not proof that work was missed.
pub fn syllabus_items(syllabus: &BTreeMap<String, Plan>, today: Date) -> Vec<DueItem> {
    let mut out: Vec<DueItem> = syllabus
        .iter()
        .flat_map(|(code, p)| p.items.iter().map(move |i| (code, i)))
        .filter(|(_, i)| !i.done && i.kind != Kind::Lecture)
        .filter_map(|(code, i)| i.date.filter(|d| *d >= today).map(|d| DueItem { date: d, overdue: false, line: describe(&i.topic, code, d, false) }))
        .collect();
    out.sort_by_key(|i| i.date);
    out
}

/// The local calendar day and minute of an epoch second, `utc_offset` minutes ahead of UTC.
fn local_parts(unix: i64, utc_offset: i32) -> (Date, u16) {
    let local = unix + i64::from(utc_offset) * 60;
    (Date::new(1970, 1, 1).add_days(local.div_euclid(86_400)), (local.rem_euclid(86_400) / 60) as u16)
}

/// Moodle titles an event "X is due", "X closes" or "X opens"; the student wants X.
fn clean_title(name: &str) -> &str {
    let low = name.to_lowercase();
    [" is due", " closes", " opens"].iter().find(|s| low.ends_with(*s)).map_or(name, |s| name[..name.len() - s.len()].trim_end())
}

/// eMabini deadlines the way Today shows them: the ones Moodle calls overdue (or whose time has
/// passed) are overdue, the rest are dated by the student's local day. `utc_offset` is local minus UTC in minutes.
pub fn mabini_items(data: &MabiniData, now: Moment, utc_offset: i32) -> Vec<DueItem> {
    let mut out: Vec<DueItem> = data
        .deadlines
        .iter()
        .map(|d| {
            let (date, minute) = local_parts(d.due, utc_offset);
            let overdue = d.overdue || (date, minute) < (now.date, now.minute);
            DueItem { date, overdue, line: describe(clean_title(&d.name), &split_course_name(&d.course).0, date, overdue) }
        })
        .collect();
    out.sort_by_key(|i| (!i.overdue, i.date));
    out
}

impl Facts {
    /// Adds dated work and keeps the list overdue first, then soonest. `due` (what the model reads
    /// when it answers an open question) is the default window of the same list.
    pub fn add_due(&mut self, items: impl IntoIterator<Item = DueItem>) {
        self.due_items.extend(items);
        self.due_items.sort_by_key(|i| (!i.overdue, i.date));
        if let Some(today) = self.today {
            self.due = within(&self.due_items, today.add_days(DEFAULT_DAYS - 1)).map(|i| i.line.clone()).collect();
        }
    }
}

/// Overdue items and everything dated up to and including `last`.
fn within(items: &[DueItem], last: Date) -> impl Iterator<Item = &DueItem> {
    items.iter().filter(move |i| i.overdue || i.date <= last)
}

/// The last day a question covers. A day the message names ("tomorrow", "Friday") ends there; "this
/// week" ends on Sunday (a Sunday asking means the week ahead), "next week" a week later; nothing
/// named is today and the next seven days.
pub fn window_end(msg: &str, today: Date) -> Date {
    if let Some(day) = resolve_when(msg, today) {
        return day;
    }
    let w = words(msg);
    let has = |list: &[&str]| w.iter().any(|x| list.contains(&x.as_str()));
    if !has(&["week", "linggo", "linggong"]) {
        return today.add_days(DEFAULT_DAYS - 1);
    }
    let to_sunday = i64::from(Weekday::Sunday.number()) - i64::from(today.weekday().number());
    let this_sunday = today.add_days(if to_sunday == 0 { 7 } else { to_sunday });
    if has(&["next", "susunod", "darating"]) { this_sunday.add_days(7) } else { this_sunday }
}

/// The reply to a Due question: the lead-in, every item in the window with its date, maybe a closer.
/// With nothing dated at all it falls back to `Facts::due`, the list a caller built by hand.
pub fn answer(f: &Facts, msg: &str) -> String {
    let fil = is_filipino(msg);
    let lines: Vec<String> = match f.today.filter(|_| !f.due_items.is_empty()) {
        Some(today) => within(&f.due_items, window_end(msg, today)).map(|i| i.line.clone()).collect(),
        None => f.due.clone(),
    };
    if lines.is_empty() { persona::line(Line::NoDue, fil, msg) } else { persona::list(List::Due, &lines, fil, msg) }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{assis::answer as ask, llm::FakeLlm, prompt::Template};
    use intportal_core::{
        mabini::parse::Deadline,
        syllabus::Item,
    };

    /// Monday 2026-10-26 10:00 in Manila (UTC+8).
    const MON: Date = Date { y: 2026, m: 10, d: 26 };
    const NOW: Moment = Moment { date: MON, minute: 600 };
    const OFFSET: i32 = 480;
    /// Days from 1970-01-01 to MON.
    const MON_DAYS: i64 = 20_752;

    /// Epoch seconds of `days` after Monday at `minute` local.
    fn at(days: i64, minute: i64) -> i64 {
        (MON_DAYS + days) * 86_400 + minute * 60 - i64::from(OFFSET) * 60
    }

    fn deadline(id: u64, name: &str, course: &str, due: i64, overdue: bool) -> Deadline {
        Deadline { id, name: name.into(), course_id: id, course: format!("{course}_First Sem 2627_BSIT 1-A"), kind: "assign".into(), due, overdue, url: String::new() }
    }

    /// The simulator's demo data: one overdue, one later today, one on Thursday.
    fn demo() -> MabiniData {
        MabiniData {
            deadlines: vec![
                deadline(1, "PETA 1 is due", "Physical Activity Towards Health and Fitness 1", at(0, 600) - 12 * 3600, true),
                deadline(2, "Pagsusulit 1 closes", "Filipinolohiya at Pambansang Kaunlaran", at(0, 1176), false),
                deadline(3, "Problem Set 2 is due", "Mathematics in the Modern World", at(3, 600), false),
            ],
            ..MabiniData::default()
        }
    }

    fn facts_with(items: Vec<DueItem>) -> Facts {
        let mut f = Facts { today: Some(MON), ..Facts::default() };
        f.add_due(items);
        f
    }

    fn reply(f: &Facts, msg: &str) -> String {
        let mut m = FakeLlm::new(&[]);
        let r = ask(&mut m, Template::Gemma, f, &[], msg).unwrap().reply;
        assert!(m.prompts.is_empty(), "a due question is answered by the rules, not the model");
        r
    }

    fn bullets(reply: &str) -> Vec<&str> {
        reply.lines().filter_map(|l| l.strip_prefix("- ")).collect()
    }

    #[test]
    fn the_anchor_dates_are_right() {
        assert_eq!(local_parts(at(0, 600), OFFSET), (MON, 600));
        assert_eq!(local_parts(at(3, 30), OFFSET), (Date::new(2026, 10, 29), 30));
    }

    #[test]
    fn this_week_lists_the_overdue_the_today_and_the_thursday_mabini_items() {
        let f = facts_with(mabini_items(&demo(), NOW, OFFSET));
        let r = reply(&f, "What is due this week?");
        assert_eq!(
            bullets(&r),
            [
                "PETA 1: Physical Activity Towards Health and Fitness 1, Sunday 2026-10-25, overdue",
                "Pagsusulit 1: Filipinolohiya at Pambansang Kaunlaran, Monday 2026-10-26",
                "Problem Set 2: Mathematics in the Modern World, Thursday 2026-10-29",
            ]
        );
        assert!(persona::leads(List::Due, false).contains(&r.lines().next().unwrap()), "{r}");
    }

    #[test]
    fn a_filipino_question_gets_a_filipino_lead_and_every_item() {
        let f = facts_with(mabini_items(&demo(), NOW, OFFSET));
        let r = reply(&f, "Ano ang due ko ngayong linggo?");
        assert_eq!(bullets(&r).len(), 3);
        assert!(persona::leads(List::Due, true).contains(&r.lines().next().unwrap()), "{r}");
    }

    #[test]
    fn tomorrow_ends_the_window_tomorrow_but_keeps_the_overdue_and_today() {
        let f = facts_with(mabini_items(&demo(), NOW, OFFSET));
        assert_eq!(bullets(&reply(&f, "what's due tomorrow?")).len(), 2, "Thursday is past tomorrow");
        let mut more = demo();
        more.deadlines.push(deadline(4, "Essay is due", "Mathematics in the Modern World", at(1, 900), false));
        let f = facts_with(mabini_items(&more, NOW, OFFSET));
        let r = reply(&f, "what's due tomorrow?");
        assert_eq!(bullets(&r).len(), 3);
        assert!(r.contains("Essay: Mathematics in the Modern World, Tuesday 2026-10-27"), "{r}");
    }

    #[test]
    fn with_no_window_it_looks_eight_days_and_next_week_looks_further() {
        let mut data = demo();
        data.deadlines.push(deadline(4, "Report is due", "Mathematics in the Modern World", at(10, 600), false)); // Thu Nov 5
        let f = facts_with(mabini_items(&data, NOW, OFFSET));
        assert_eq!(bullets(&reply(&f, "ano ang due ko")).len(), 3);
        assert_eq!(bullets(&reply(&f, "what is due in the next few days?")).len(), 3);
        assert_eq!(bullets(&reply(&f, "what is due this week?")).len(), 3, "Nov 5 is next week");
        assert_eq!(bullets(&reply(&f, "what is due next week?")).len(), 4);
    }

    #[test]
    fn every_one_of_n_items_appears_with_its_date() {
        let deadlines: Vec<Deadline> = (0..12).map(|n| deadline(n + 1, &format!("Task {n} is due"), "Math", at(n as i64 % 6, 480 + n as i64), false)).collect();
        let f = facts_with(mabini_items(&MabiniData { deadlines, ..MabiniData::default() }, NOW, OFFSET));
        let r = reply(&f, "what is due this week?");
        let got = bullets(&r);
        assert_eq!(got.len(), 12);
        for n in 0..12 {
            assert!(got.iter().any(|l| l.starts_with(&format!("Task {n}: Math, ")) && l.contains("2026-10-")), "Task {n} missing from {r}");
        }
    }

    #[test]
    fn syllabus_and_mabini_work_share_one_list_soonest_first() {
        let item = |topic: &str, kind, date: Date, done| Item { id: "1".into(), topic: topic.into(), kind, week: None, date: Some(date), done };
        let mut syllabus = BTreeMap::new();
        syllabus.insert(
            "COMP 20073".to_string(),
            Plan {
                items: vec![
                    item("Quiz 2", Kind::Quiz, Date::new(2026, 10, 28), false),
                    item("Quiz 1", Kind::Quiz, Date::new(2026, 10, 20), false), // past, not ticked: not proof of missed work
                    item("Midterm", Kind::Exam, Date::new(2026, 10, 27), true), // done
                    item("Intro", Kind::Lecture, Date::new(2026, 10, 27), false), // a lecture is not work
                ],
                ..Plan::default()
            },
        );
        let mut f = facts_with(syllabus_items(&syllabus, MON));
        f.add_due(mabini_items(&demo(), NOW, OFFSET));
        let lines: Vec<&str> = f.due_items.iter().map(|i| i.line.as_str()).collect();
        assert_eq!(lines.len(), 4);
        assert!(lines[0].contains("overdue") && lines[1].starts_with("Pagsusulit 1") && lines[2] == "Quiz 2: COMP 20073, Wednesday 2026-10-28" && lines[3].starts_with("Problem Set 2"), "{lines:?}");
        assert_eq!(f.due.len(), 4, "the model sees the same list for an open question");
    }

    #[test]
    fn nothing_dated_is_the_no_due_line_and_a_hand_built_list_still_answers() {
        let none = Facts { today: Some(MON), ..Facts::default() };
        let r = reply(&none, "what is due this week?");
        assert!(persona::lines(Line::NoDue, false).contains(&r.as_str()), "{r}");
        let by_hand = Facts { today: Some(MON), due: vec!["Quiz 2: COMP 20073, Fri 2026-10-30".into()], ..Facts::default() };
        assert_eq!(bullets(&reply(&by_hand, "what is due?")), ["Quiz 2: COMP 20073, Fri 2026-10-30"]);
    }

    #[test]
    fn this_week_on_a_sunday_means_the_week_ahead() {
        let sunday = Date::new(2026, 11, 1);
        assert_eq!(window_end("due this week", MON), sunday);
        assert_eq!(window_end("due this week", sunday), Date::new(2026, 11, 8));
        assert_eq!(window_end("due next week", MON), Date::new(2026, 11, 8));
        assert_eq!(window_end("ano ang due bukas", MON), Date::new(2026, 10, 27));
        assert_eq!(window_end("ano ang due sa susunod na linggo", MON), Date::new(2026, 11, 8));
    }

    #[test]
    fn a_deadline_later_today_is_today_and_one_earlier_today_is_overdue() {
        let data = MabiniData { deadlines: vec![deadline(1, "A is due", "Math", at(0, 540), false), deadline(2, "B is due", "Math", at(0, 900), false)], ..MabiniData::default() };
        let items = mabini_items(&data, NOW, OFFSET);
        assert_eq!((items[0].overdue, items[0].line.as_str()), (true, "A: Math, Monday 2026-10-26, overdue"));
        assert_eq!((items[1].overdue, items[1].line.as_str()), (false, "B: Math, Monday 2026-10-26"));
    }
}
