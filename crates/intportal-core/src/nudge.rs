//! Everything the phone says on its own besides class reminders, through one
//! budget (spec 042): at most a few a day, the most useful first, and nothing
//! at night. Class reminders never pass through here.

use crate::{
    deadline::{local_parts, Deadline, Due},
    model::{ClassSession, Weekday},
    syllabus::Kind as ItemKind,
    today::{meetings_from, reminder_id, Date, Marks, Moment, Reminder},
};
use std::collections::BTreeMap;

/// What a heads-up is about, most useful first (C14).
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub enum Kind {
    Deadline,
    Brief,
    Study,
    AfterClass,
}

pub const PER_DAY: usize = 3;
const QUIET_FROM: u16 = 22 * 60;
const QUIET_UNTIL: u16 = 7 * 60;

/// Moves what falls in quiet hours to 7 AM (C15). A note-after-class prompt
/// is stale by morning, so it is dropped instead. Then keeps at most
/// `per_day` a day by `Kind` (C14), soonest first.
pub fn budget(list: Vec<(Kind, Reminder)>, per_day: usize) -> Vec<Reminder> {
    let mut by_day: BTreeMap<Date, Vec<(Kind, Reminder)>> = BTreeMap::new();
    for (kind, mut r) in list {
        if r.minute >= QUIET_FROM || r.minute < QUIET_UNTIL {
            if kind == Kind::AfterClass {
                continue;
            }
            if r.minute >= QUIET_FROM {
                r.date = r.date.add_days(1);
            }
            r.minute = QUIET_UNTIL;
        }
        by_day.entry(r.date).or_default().push((kind, r));
    }
    let mut out: Vec<Reminder> = by_day
        .into_values()
        .flat_map(|mut day| {
            day.sort_by_key(|(k, r)| (*k, r.minute));
            day.into_iter().take(per_day).map(|(_, r)| r)
        })
        .collect();
    out.sort_by_key(|r| (r.date, r.minute));
    out
}

fn short(day: Weekday) -> String {
    format!("{day:?}")[..3].to_string()
}

/// 6 PM on the coming Sunday (today, if it is Sunday before 6), when the week
/// after it holds anything due: the count and its heaviest day (C12, C13).
/// `list` must reach to that Sunday's week end.
pub fn brief(list: &[Deadline], sessions: &[ClassSession], marks: &Marks, now: Moment, utc_offset: i32) -> Option<Reminder> {
    let ahead = (7 - i64::from(now.date.weekday().number())).rem_euclid(7);
    let sunday = match now.date.add_days(ahead) {
        d if d == now.date && now.minute >= 18 * 60 => d.add_days(7),
        d => d,
    };
    let monday = sunday.add_days(1);
    let day_of = |d: &Deadline| match d.due {
        Due::Day(day) => day,
        Due::At(unix) => local_parts(unix, utc_offset).0,
    };
    let week: Vec<&Deadline> = list.iter().filter(|d| (monday..monday.add_days(7)).contains(&day_of(d))).collect();
    let body = match week.as_slice() {
        [] => return None,
        [one] => format!("1 due: {}{}.", one.title, if one.label().is_empty() { String::new() } else { format!(" ({})", one.label()) }),
        many => {
            let mut load: BTreeMap<Date, usize> = BTreeMap::new();
            for d in many {
                *load.entry(day_of(d)).or_default() += 1;
            }
            for m in meetings_from(sessions, marks, monday, 7) {
                *load.entry(m.date).or_default() += 1;
            }
            // max_by_key keeps the last of equals; iterate latest first so the earliest wins a tie.
            let heaviest = load.iter().rev().max_by_key(|(_, n)| **n).map(|(d, _)| short(d.weekday())).unwrap_or_default();
            let exams = many.iter().filter(|d| d.kind == ItemKind::Exam).count();
            let exams = match exams {
                0 => String::new(),
                1 => ", 1 exam".into(),
                n => format!(", {n} exams"),
            };
            format!("{} due{exams}. Heaviest: {heaviest}.", many.len())
        }
    };
    Some(Reminder { id: reminder_id(&format!("brief:{sunday}")), date: sunday, minute: 18 * 60, title: "Week ahead".into(), body, open: None })
}

/// Five minutes after each class ends, for subjects whose class note the
/// student has written in (C8).
pub fn after_class(sessions: &[ClassSession], marks: &Marks, noted: &[String], now: Moment, days: i64) -> Vec<Reminder> {
    let now_abs = now.date.days() * 1440 + i64::from(now.minute);
    meetings_from(sessions, marks, now.date, days)
        .into_iter()
        .filter(|m| noted.contains(&m.session.subject_code))
        .filter_map(|m| {
            let at = m.date.days() * 1440 + i64::from(m.session.end) + 5;
            (at > now_abs).then(|| Reminder {
                id: reminder_id(&format!("after:{}@{}", m.id, m.date)),
                date: Date::from_days(at.div_euclid(1440)),
                minute: at.rem_euclid(1440) as u16,
                title: format!("{} just ended", m.session.subject_code),
                body: "Add today's note?".into(),
                open: Some(format!("note:class:{}", m.session.subject_code)),
            })
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::deadline::Source;

    const TUE: Date = Date { y: 2026, m: 11, d: 3 };

    fn r(date: Date, minute: u16, title: &str) -> Reminder {
        Reminder { id: reminder_id(title), date, minute, title: title.into(), body: String::new(), open: None }
    }

    fn titles(list: &[Reminder]) -> Vec<(String, u16, String)> {
        list.iter().map(|r| (r.date.to_string(), r.minute, r.title.clone())).collect()
    }

    #[test]
    fn c14_budget_caps_three_by_rank() {
        let list = vec![
            (Kind::AfterClass, r(TUE, 10 * 60 + 35, "after A")),
            (Kind::Study, r(TUE, 17 * 60, "study")),
            (Kind::Deadline, r(TUE, 19 * 60, "deadline 1")),
            (Kind::AfterClass, r(TUE, 13 * 60 + 5, "after B")),
            (Kind::Deadline, r(TUE, 8 * 60, "deadline 2")),
            (Kind::AfterClass, r(TUE.add_days(1), 9 * 60, "tomorrow")),
        ];
        let got = titles(&budget(list, 3));
        let want = [("2026-11-03", 480, "deadline 2"), ("2026-11-03", 1020, "study"), ("2026-11-03", 1140, "deadline 1"), ("2026-11-04", 540, "tomorrow")];
        assert_eq!(got, want.map(|(d, m, t)| (d.to_string(), m, t.to_string())), "two deadlines and the study day beat both after-class prompts");
    }

    #[test]
    fn c15_quiet_hours_move_or_drop() {
        let list = vec![(Kind::Deadline, r(TUE, 22 * 60 + 30, "late")), (Kind::Study, r(TUE, 6 * 60, "early")), (Kind::AfterClass, r(TUE, 22 * 60 + 5, "after"))];
        let got = titles(&budget(list, 3));
        let want = [("2026-11-03", 420, "early"), ("2026-11-04", 420, "late")];
        assert_eq!(got, want.map(|(d, m, t)| (d.to_string(), m, t.to_string())));
    }

    fn due(title: &str, kind: ItemKind, date: Date) -> Deadline {
        Deadline { id: title.into(), source: Source::Own, subject: Some("COMP 20073".into()), course: None, title: title.into(), kind, due: Due::Day(date), overdue: false, url: None }
    }

    #[test]
    fn c12_brief_only_with_work_due() {
        let now = Moment { date: TUE, minute: 600 };
        assert_eq!(brief(&[], &[], &Marks::default(), now, 480), None);
        let one = brief(&[due("Lab 4", ItemKind::Project, Date::new(2026, 11, 11))], &[], &Marks::default(), now, 480).unwrap();
        assert_eq!((one.date, one.minute, one.title.as_str(), one.body.as_str()), (Date::new(2026, 11, 8), 1080, "Week ahead", "1 due: Lab 4 (COMP 20073)."));
        let this_week = brief(&[due("Lab 3", ItemKind::Project, Date::new(2026, 11, 5))], &[], &Marks::default(), now, 480);
        assert_eq!(this_week, None, "the brief is about the week after Sunday");
    }

    #[test]
    fn c13_heaviest_day_tie_goes_earlier() {
        let list = [due("Quiz", ItemKind::Quiz, Date::new(2026, 11, 10)), due("Midterm", ItemKind::Exam, Date::new(2026, 11, 12)), due("Lab", ItemKind::Project, Date::new(2026, 11, 13))];
        let b = brief(&list, &[], &Marks::default(), Moment { date: TUE, minute: 600 }, 480).unwrap();
        assert_eq!(b.body, "3 due, 1 exam. Heaviest: Tue.");
    }

    #[test]
    fn c8_after_class_only_for_noted_subjects() {
        let s = |code: &str, start: u16, end: u16| ClassSession { subject_code: code.into(), description: String::new(), faculty: String::new(), day: Weekday::Tuesday, start, end, occurrence: 0 };
        let w = [s("COMP 20073", 540, 630), s("GEED 10053", 660, 750)];
        let got = after_class(&w, &Marks::default(), &["COMP 20073".into()], Moment { date: TUE, minute: 0 }, 1);
        assert_eq!(got.len(), 1);
        assert_eq!((got[0].minute, got[0].title.as_str(), got[0].open.as_deref()), (635, "COMP 20073 just ended", Some("note:class:COMP 20073")));
    }
}
