//! The term's classes as an iCalendar (`.ics`) file, for the phone's calendar,
//! Google Calendar's import, or anywhere else.
//!
//! Times are floating local time (no time zone): a class schedule is read in
//! whatever zone the student is in, and it keeps the file free of a VTIMEZONE
//! block. `UNTIL` is floating too, as RFC 5545 requires with a floating start.
//!
//! One repeating VEVENT per class. The student's week-only edits become
//! exceptions: a week marked vacant or moved is an EXDATE on the series, and
//! a week-only move is its own one-off VEVENT.

use crate::model::{ClassSession, Weekday};
use crate::today::{meetings_from, Date, Mark, Marks, Slot};
use serde::{Deserialize, Serialize};

fn by_day(d: Weekday) -> &'static str {
    ["MO", "TU", "WE", "TH", "FR", "SA", "SU"][usize::from(d.number()) - 1]
}

fn stamp(date: Date, minute: u16) -> String {
    format!("{:04}{:02}{:02}T{:02}{:02}00", date.y, date.m, date.d, minute / 60, minute % 60)
}

fn escape(text: &str) -> String {
    text.replace('\\', "\\\\").replace(';', r"\;").replace(',', "\\,").replace('\n', "\\n")
}

/// Folds a content line at 75 octets, continuation lines starting with a
/// space, never splitting a UTF-8 character.
fn fold(line: &str) -> String {
    let mut out = String::new();
    let mut used = 0;
    for ch in line.chars() {
        let n = ch.len_utf8();
        if used + n > 75 {
            out.push_str("\r\n ");
            used = 1;
        }
        out.push(ch);
        used += n;
    }
    out
}

fn event(lines: &mut Vec<String>, uid: &str, now: &str, session: &ClassSession, slot: Slot, date: Date, online: bool) {
    lines.push("BEGIN:VEVENT".into());
    lines.push(format!("UID:{uid}"));
    lines.push(format!("DTSTAMP:{now}"));
    lines.push(format!("DTSTART:{}", stamp(date, slot.start)));
    lines.push(format!("DTEND:{}", stamp(date, slot.end)));
    lines.push(format!("SUMMARY:{}", escape(&format!("{}{}", session.subject_code, if online { " (Online)" } else { "" }))));
    lines.push(format!("DESCRIPTION:{}", escape(&notes(session))));
    if online {
        lines.push("LOCATION:Online".into());
    }
}

fn notes(session: &ClassSession) -> String {
    if session.faculty.is_empty() {
        session.description.clone()
    } else {
        format!("{}\n{}", session.description, session.faculty)
    }
}

/// One class meeting as an event in the phone's own IntPortal calendar.
/// `key` names the meeting, so a sync replaces it rather than adding twice.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ClassEvent {
    pub key: String,
    pub title: String,
    pub notes: String,
    pub date: Date,
    pub start: u16,
    pub end: u16,
}

/// The meetings from `from` through `days` days on, with the student's
/// edits applied: vacant weeks left out, moved weeks moved.
pub fn class_events(sessions: &[ClassSession], marks: &Marks, from: Date, days: i64) -> Vec<ClassEvent> {
    meetings_from(sessions, marks, from, days)
        .into_iter()
        .map(|m| ClassEvent {
            key: format!("{}@{}", m.id, m.date),
            title: format!("{}{}", m.session.subject_code, if m.mark == Mark::Online { " (Online)" } else { "" }),
            notes: notes(&m.session),
            date: m.date,
            start: m.session.start,
            end: m.session.end,
        })
        .collect()
}

/// `YYYYMMDDTHHMMSSZ` for a Unix time, for DTSTAMP.
pub fn utc_stamp(unix_secs: i64) -> String {
    let date = Date::from_days(unix_secs.div_euclid(86_400));
    let t = unix_secs.rem_euclid(86_400);
    format!("{:04}{:02}{:02}T{:02}{:02}{:02}Z", date.y, date.m, date.d, t / 3600, t / 60 % 60, t % 60)
}

/// Every class from the week holding `from` through `until`, the last day of
/// classes. `now_utc` is `YYYYMMDDTHHMMSSZ`, for DTSTAMP.
pub fn ics(sessions: &[ClassSession], marks: &Marks, from: Date, until: Date, now_utc: &str) -> String {
    let monday = from.week_start();
    let weeks: Vec<Date> = std::iter::successors(Some(monday), |w| Some(w.add_days(7))).take_while(|w| *w <= until).collect();
    let mut lines: Vec<String> = ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//IntPortal//Schedule//EN", "CALSCALE:GREGORIAN"].map(String::from).into();
    for s in sessions {
        let id = s.id();
        let own = Slot { day: s.day, start: s.start, end: s.end };
        let term_mark = marks.mode.term.get(&id).copied().unwrap_or(Mark::InPerson);
        let term_slot = marks.moved.term.get(&id).copied().unwrap_or(own);
        let on = |w: Date, slot: Slot| w.add_days(i64::from(slot.day.number()) - 1);
        let first = on(monday, term_slot);
        let mut exdates = vec![];
        for &w in &weeks {
            let mark = marks.mode.get(&id, w).unwrap_or(Mark::InPerson);
            let slot = marks.moved.get(&id, w).unwrap_or(own);
            let changed = mark != term_mark || slot != term_slot;
            if !changed {
                continue;
            }
            if term_mark != Mark::Vacant {
                exdates.push(stamp(on(w, term_slot), term_slot.start));
            }
            if mark != Mark::Vacant {
                let date = on(w, slot);
                event(&mut lines, &format!("{id}-{w}@intportal"), now_utc, s, slot, date, mark == Mark::Online);
                lines.push("END:VEVENT".into());
            }
        }
        if term_mark == Mark::Vacant {
            continue;
        }
        event(&mut lines, &format!("{id}@intportal"), now_utc, s, term_slot, first, term_mark == Mark::Online);
        lines.push(format!("RRULE:FREQ=WEEKLY;UNTIL={};BYDAY={}", stamp(until, 23 * 60 + 59), by_day(term_slot.day)));
        if !exdates.is_empty() {
            lines.push(format!("EXDATE:{}", exdates.join(",")));
        }
        lines.push("END:VEVENT".into());
    }
    lines.push("END:VCALENDAR".into());
    lines.iter().map(|l| fold(l)).collect::<Vec<_>>().join("\r\n") + "\r\n"
}

#[cfg(test)]
mod tests {
    use super::*;
    use Weekday::*;

    fn s(code: &str, day: Weekday, start: u16, end: u16) -> ClassSession {
        ClassSession { subject_code: code.into(), description: "Data Structures, Algorithms".into(), faculty: "SANTOS, JUAN".into(), day, start, end, occurrence: 0 }
    }

    const NOW: &str = "20260927T120000Z";
    // 2026-08-03 is a Monday.
    fn mon() -> Date {
        Date::new(2026, 8, 3)
    }

    #[test]
    fn a_class_repeats_weekly_until_the_last_day() {
        let out = ics(&[s("COMP 20073", Tuesday, 540, 630)], &Marks::default(), Date::new(2026, 8, 5), Date::new(2026, 12, 12), NOW);
        let body: Vec<&str> = out.split("\r\n").collect();
        assert_eq!(body[0], "BEGIN:VCALENDAR");
        assert!(body.contains(&"UID:COMP 20073-2-540-630@intportal"));
        assert!(body.contains(&"DTSTART:20260804T090000"));
        assert!(body.contains(&"DTEND:20260804T103000"));
        assert!(body.contains(&"RRULE:FREQ=WEEKLY;UNTIL=20261212T235900;BYDAY=TU"));
        assert!(body.contains(&"DESCRIPTION:Data Structures\\, Algorithms\\nSANTOS\\, JUAN"));
        assert!(out.ends_with("END:VCALENDAR\r\n"));
    }

    #[test]
    fn term_marks_and_moves_shape_the_series() {
        let w = [s("A", Monday, 480, 540), s("B", Monday, 600, 660), s("C", Monday, 700, 760)];
        let mut marks = Marks::default();
        marks.mode.set(&w[0].id(), None, Some(Mark::Vacant));
        marks.mode.set(&w[1].id(), None, Some(Mark::Online));
        marks.moved.set(&w[2].id(), None, Some(Slot { day: Friday, start: 900, end: 960 }));
        let out = ics(&w, &marks, mon(), Date::new(2026, 8, 31), NOW);
        assert!(!out.contains("SUMMARY:A"));
        assert!(out.contains("SUMMARY:B (Online)\r\nDESCRIPTION"));
        assert!(out.contains("LOCATION:Online"));
        assert!(out.contains("DTSTART:20260807T150000"));
        assert!(out.contains("BYDAY=FR"));
    }

    #[test]
    fn week_only_edits_become_exceptions() {
        let w = [s("A", Monday, 480, 540)];
        let mut marks = Marks::default();
        marks.mode.set(&w[0].id(), Some(Date::new(2026, 8, 10)), Some(Mark::Vacant));
        marks.moved.set(&w[0].id(), Some(Date::new(2026, 8, 17)), Some(Slot { day: Wednesday, start: 780, end: 840 }));
        let out = ics(&w, &marks, mon(), Date::new(2026, 8, 31), NOW);
        assert!(out.contains("EXDATE:20260810T080000,20260817T080000"));
        assert!(out.contains("UID:A-1-480-540-2026-08-17@intportal\r\nDTSTAMP:20260927T120000Z\r\nDTSTART:20260819T130000"));
        assert!(!out.contains("-2026-08-10@intportal"));
    }

    #[test]
    fn utc_stamp_reads_unix_time() {
        assert_eq!(utc_stamp(0), "19700101T000000Z");
        assert_eq!(utc_stamp(1_790_523_807), "20260927T154327Z");
    }

    #[test]
    fn long_lines_fold_at_75_octets_without_splitting_characters() {
        let line = format!("DESCRIPTION:{}", "ñ".repeat(60));
        let folded = fold(&line);
        assert!(folded.split("\r\n").all(|l| l.len() <= 75));
        assert_eq!(folded.replace("\r\n ", ""), line);
    }

    #[test]
    fn class_events_skip_vacant_weeks_and_follow_moves() {
        let w = [s("COMP 002", Monday, 9 * 60, 10 * 60 + 50), s("GEED 005", Wednesday, 13 * 60, 14 * 60)];
        let mut marks = Marks::default();
        marks.mode.set(&w[0].id(), Some(mon()), Some(Mark::Vacant));
        marks.mode.set(&w[1].id(), None, Some(Mark::Online));
        marks.moved.set(&w[1].id(), Some(mon().add_days(7)), Some(Slot { day: Thursday, start: 8 * 60, end: 9 * 60 }));
        let got: Vec<(String, String, u16, u16)> =
            class_events(&w, &marks, mon(), 14).into_iter().map(|e| (e.date.to_string(), e.title, e.start, e.end)).collect();
        assert_eq!(
            got,
            [
                ("2026-08-05".to_string(), "GEED 005 (Online)".to_string(), 13 * 60, 14 * 60),
                ("2026-08-10".to_string(), "COMP 002".to_string(), 9 * 60, 10 * 60 + 50),
                ("2026-08-13".to_string(), "GEED 005 (Online)".to_string(), 8 * 60, 9 * 60),
            ]
        );
        let keys: std::collections::HashSet<String> = class_events(&w, &marks, mon(), 14).into_iter().map(|e| e.key).collect();
        assert_eq!(keys.len(), 3);
    }
}
