//! A photo or paste of a schedule, read into own classes for the student to
//! check (spec 061 C10 to C14). The phone's text reader gives lines with
//! where they sit; lines at one height are one row of the table. A row with a
//! day and a time range is a class. Nothing here is sure: the review is.

use crate::model::Weekday;
use crate::own_class::{Meeting, OwnClass};
use crate::schedule::{self, ScheduleRow};
use regex::Regex;
use serde::{Deserialize, Serialize};
use std::sync::LazyLock;

/// One line the text reader found, in 0 to 1 of the photo, top-left origin.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ScanLine {
    pub text: String,
    pub x: f32,
    pub y: f32,
    pub w: f32,
    pub h: f32,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct Found {
    pub class: OwnClass,
    /// No code, or a name too short to trust (C13).
    pub unsure: bool,
}

/// Lines are joined into rows left to right: each line joins the row whose
/// rightmost line sits nearest its height, within half a line. Chaining
/// column to column follows a tilted photo, where one height for the whole
/// row would split it. Columns stay apart by two spaces, so a row splits back into cells.
pub fn rows(lines: &[ScanLine]) -> Vec<String> {
    let mut lines: Vec<&ScanLine> = lines.iter().filter(|l| !l.text.trim().is_empty()).collect();
    if lines.is_empty() {
        return vec![];
    }
    let mut heights: Vec<f32> = lines.iter().map(|l| l.h).collect();
    heights.sort_by(f32::total_cmp);
    let tol = heights[heights.len() / 2] * 0.6;
    lines.sort_by(|a, b| a.x.total_cmp(&b.x));
    let mid = |l: &ScanLine| l.y + l.h / 2.0;
    let mut out: Vec<Vec<&ScanLine>> = vec![];
    for l in lines {
        // A row takes one line per column: its last line must end before this one starts.
        let near = out
            .iter_mut()
            .filter(|row| row.last().is_some_and(|last| last.x + last.w * 0.5 < l.x && (mid(last) - mid(l)).abs() <= tol))
            .min_by(|a, b| (mid(a.last().unwrap()) - mid(l)).abs().total_cmp(&(mid(b.last().unwrap()) - mid(l)).abs()));
        match near {
            Some(row) => row.push(l),
            None => out.push(vec![l]),
        }
    }
    out.sort_by(|a, b| row_mid(a).total_cmp(&row_mid(b)));
    out.into_iter().map(|row| row.iter().map(|l| l.text.trim()).collect::<Vec<_>>().join("  ")).collect()
}

fn row_mid(row: &[&ScanLine]) -> f32 {
    row.iter().map(|l| l.y + l.h / 2.0).sum::<f32>() / row.len() as f32
}

static TIME: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"(?i)\b(\d{1,2})(?:[:.](\d{2}))?\s*([ap])?\.?\s*m?\.?\s*(?:-|–|—|to)\s*(\d{1,2})(?:[:.](\d{2}))?\s*([ap])?\.?\s*(m\b)?\.?").unwrap()
});
static CODE: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"\b([A-Z]{2,6})[ -]?(\d{2,5}[A-Z]?)\b").unwrap());
static ROOM: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"(?i)\b(?:rm|room)\.?\s*:?\s*([A-Z0-9][A-Z0-9-]*)").unwrap());
/// A short course code with one digit ("PE 2", "NSTP 1"): only taken when a name follows it.
static SHORT_CODE: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"^[A-Z]{2,6} ?\d{1,4}[A-Z]?$").unwrap());
static TEACHER: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"^(?i:prof|dr|mr|ms|mrs|engr|atty|sir|ma'am)\b").unwrap());

const WORDS: [(&str, Weekday); 30] = [
    ("MONDAY", Weekday::Monday),
    ("MON", Weekday::Monday),
    ("LUNES", Weekday::Monday),
    ("TUESDAY", Weekday::Tuesday),
    ("TUES", Weekday::Tuesday),
    ("TUE", Weekday::Tuesday),
    ("MARTES", Weekday::Tuesday),
    ("WEDNESDAY", Weekday::Wednesday),
    ("WED", Weekday::Wednesday),
    ("MIYERKULES", Weekday::Wednesday),
    ("MIYERKOLES", Weekday::Wednesday),
    ("THURSDAY", Weekday::Thursday),
    ("THURS", Weekday::Thursday),
    ("THUR", Weekday::Thursday),
    ("THU", Weekday::Thursday),
    ("HUWEBES", Weekday::Thursday),
    ("FRIDAY", Weekday::Friday),
    ("FRI", Weekday::Friday),
    ("BIYERNES", Weekday::Friday),
    ("SATURDAY", Weekday::Saturday),
    ("SAT", Weekday::Saturday),
    ("SABADO", Weekday::Saturday),
    ("SUNDAY", Weekday::Sunday),
    ("SUN", Weekday::Sunday),
    ("LINGGO", Weekday::Sunday),
    ("TH", Weekday::Thursday),
    ("SU", Weekday::Sunday),
    ("SA", Weekday::Saturday),
    ("R", Weekday::Thursday),
    ("M", Weekday::Monday),
];
/// Letters a joined token like MWF or TTh is made of, longest first.
const LETTERS: [(&str, Weekday); 9] = [
    ("TH", Weekday::Thursday),
    ("SU", Weekday::Sunday),
    ("SA", Weekday::Saturday),
    ("M", Weekday::Monday),
    ("T", Weekday::Tuesday),
    ("W", Weekday::Wednesday),
    ("R", Weekday::Thursday),
    ("F", Weekday::Friday),
    ("S", Weekday::Saturday),
];

/// The days a word names, or none if any part of it is not a day.
fn days_in(word: &str) -> Vec<Weekday> {
    let up = word.to_uppercase();
    let mut days = vec![];
    for part in up.split(['/', ',', '&', '.']).filter(|p| !p.is_empty()) {
        if let Some((_, d)) = WORDS.iter().find(|(w, _)| *w == part) {
            days.push(*d);
            continue;
        }
        let mut rest = part;
        'letters: while !rest.is_empty() {
            for (code, d) in LETTERS {
                if let Some(tail) = rest.strip_prefix(code) {
                    days.push(d);
                    rest = tail;
                    continue 'letters;
                }
            }
            return vec![];
        }
    }
    days.sort();
    days.dedup();
    days
}

/// Hours on a 12-hour clock with no AM or PM are school hours: 7 to 11 is
/// morning, 12 is noon, 1 to 6 is afternoon (C11).
fn school_hour(h: u16) -> u16 {
    if (1..=6).contains(&h) {
        h + 12
    } else {
        h
    }
}

fn to24(h: u16, pm: bool) -> u16 {
    match (h, pm) {
        (12, false) => 0,
        (12, true) => 12,
        (h, true) => h + 12,
        (h, false) => h,
    }
}

/// A time range in minutes, from one match of [`TIME`].
fn range(c: &regex::Captures) -> Option<(u16, u16)> {
    let num = |i: usize| c.get(i).map(|m| m.as_str().parse::<u16>().ok()).unwrap_or(Some(0));
    let (h1, m1, h2, m2) = (num(1)?, num(2)?, num(4)?, num(5)?);
    let p1 = c.get(3).map(|m| m.as_str().eq_ignore_ascii_case("p"));
    let p2 = c.get(6).map(|m| m.as_str().eq_ignore_ascii_case("p"));
    // A bare "8-10" is too likely a section or a page: it needs minutes or AM/PM.
    if c.get(2).is_none() && c.get(5).is_none() && p1.is_none() && p2.is_none() {
        return None;
    }
    if m1 >= 60 || m2 >= 60 || h1 > 23 || h2 > 23 {
        return None;
    }
    let twelve = |h: u16| (1..=12).contains(&h);
    let (start_h, end_h) = match (p1, p2) {
        (Some(a), Some(b)) if twelve(h1) && twelve(h2) => (to24(h1, a), to24(h2, b)),
        (None, Some(b)) if twelve(h1) && twelve(h2) => {
            let s = to24(h1, b);
            let e = to24(h2, b);
            (if s * 60 + m1 > e * 60 + m2 { to24(h1, false) } else { s }, e)
        }
        (Some(a), None) if twelve(h1) && twelve(h2) => {
            let s = to24(h1, a);
            let e = to24(h2, a);
            (s, if e * 60 + m2 <= s * 60 + m1 { to24(h2, true) } else { e })
        }
        _ if h1 > 12 || h2 > 12 => (h1, h2),
        _ => {
            let s = school_hour(h1);
            let e = school_hour(h2);
            (s, if e * 60 + m2 <= s * 60 + m1 && e < 12 { e + 12 } else { e })
        }
    };
    let (start, end) = (start_h * 60 + m1, end_h * 60 + m2);
    (start < end && end <= 24 * 60).then_some((start, end))
}

/// What one row says, before rows are joined into classes.
#[derive(Debug, Default)]
struct Row {
    code: String,
    name: String,
    room: String,
    teacher: String,
    meetings: Vec<Meeting>,
}

/// One row read: its meetings, then what is left of it as code, room, name and teacher.
fn read_row(text: &str) -> Row {
    let text = text.replace(['|', '\t'], "  ");
    let mut row = Row::default();
    // The SIS's own line ("T/F 02:00PM-04:00PM/01:30PM-04:30PM") pairs days with times its own way.
    for s in schedule::parse_row(&ScheduleRow { schedule_line: text.to_uppercase(), ..Default::default() }) {
        match row.meetings.iter_mut().find(|m| m.start == s.start && m.end == s.end) {
            Some(m) if !m.days.contains(&s.day) => m.days.push(s.day),
            Some(_) => {}
            None => row.meetings.push(Meeting { days: vec![s.day], start: s.start, end: s.end }),
        }
    }
    let sis = !row.meetings.is_empty();
    let words: Vec<(usize, usize, &str)> = word_spans(&text);
    let day_words: Vec<(usize, usize, Vec<Weekday>)> = words.iter().filter_map(|&(a, b, w)| Some((a, b, days_in(w))).filter(|(_, _, d)| !d.is_empty())).collect();
    let mut cut: Vec<(usize, usize)> = vec![];
    for c in TIME.captures_iter(&text) {
        let whole = c.get(0).unwrap();
        let Some((start, end)) = range(&c) else { continue };
        cut.push((whole.start(), whole.end()));
        if sis {
            continue;
        }
        // The days are the day word nearest the time, before it if there is one.
        let before = day_words.iter().filter(|(_, b, _)| *b <= whole.start()).max_by_key(|(_, b, _)| *b);
        let after = day_words.iter().filter(|(a, _, _)| *a >= whole.end()).min_by_key(|(a, _, _)| *a);
        let Some((_, _, days)) = before.or(after) else { continue };
        if row.meetings.iter().all(|m| (m.start, m.end) != (start, end)) {
            row.meetings.push(Meeting { days: days.clone(), start, end });
        }
    }
    for m in &mut row.meetings {
        m.days.sort();
    }
    cut.extend(day_words.iter().map(|(a, b, _)| (*a, *b)));
    if let Some(r) = ROOM.captures(&text) {
        let all = r.get(0).unwrap();
        row.room = r[1].to_string();
        cut.push((all.start(), all.end()));
    }
    let blanked = blank(&text, &cut);
    if let Some(c) = CODE.captures(&blanked) {
        let all = c.get(0).unwrap();
        row.code = format!("{} {}", &c[1], &c[2]);
        cut.push((all.start(), all.end()));
    }
    let rest = blank(&text, &cut);
    let cells: Vec<String> = rest
        .split("  ")
        .map(|c| c.trim_matches(|ch: char| !ch.is_alphanumeric() && ch != ')' && ch != '(').trim().to_string())
        .filter(|c| c.chars().filter(|ch| ch.is_alphabetic()).count() >= 2)
        .collect();
    let mut cells = cells.into_iter().peekable();
    if row.code.is_empty() && cells.peek().is_some_and(|c| SHORT_CODE.is_match(c)) {
        let code = cells.next().unwrap();
        if cells.peek().is_some() {
            row.code = code;
        } else {
            row.name = code;
        }
    }
    for cell in cells {
        if TEACHER.is_match(&cell) {
            if row.teacher.is_empty() {
                row.teacher = cell;
            }
        } else if row.name.is_empty() {
            row.name = cell.split_whitespace().collect::<Vec<_>>().join(" ");
        }
    }
    row
}

/// Each word with its byte span.
fn word_spans(text: &str) -> Vec<(usize, usize, &str)> {
    let mut out = vec![];
    let mut start = None;
    for (i, ch) in text.char_indices() {
        match (ch.is_whitespace(), start) {
            (false, None) => start = Some(i),
            (true, Some(s)) => {
                out.push((s, i, &text[s..i]));
                start = None;
            }
            _ => {}
        }
    }
    if let Some(s) = start {
        out.push((s, text.len(), &text[s..]));
    }
    out
}

/// The text with every span turned into two spaces, so cells stay apart.
fn blank(text: &str, spans: &[(usize, usize)]) -> String {
    let mut out = String::with_capacity(text.len());
    for (i, ch) in text.char_indices() {
        if spans.iter().any(|&(a, b)| i >= a && i < b) {
            if !out.ends_with("  ") {
                out.push_str("  ");
            }
        } else {
            out.push(ch);
        }
    }
    out
}

/// Rows into classes (C11, C13). A row with no time lends its words to the
/// class under it that has no name; rows with one code are one class.
pub fn read(rows: &[String]) -> Vec<Found> {
    let mut out: Vec<OwnClass> = vec![];
    let mut waiting = String::new();
    for text in rows {
        let row = read_row(text);
        if row.meetings.is_empty() {
            let words = text.trim();
            waiting = if words.chars().filter(|c| c.is_alphabetic()).count() >= 3 { words.to_string() } else { String::new() };
            continue;
        }
        let name = if row.name.is_empty() { std::mem::take(&mut waiting) } else { row.name };
        waiting.clear();
        let same = |c: &OwnClass| if row.code.is_empty() { !name.is_empty() && c.code.is_empty() && c.name == name } else { c.code == row.code };
        match out.iter_mut().find(|c| same(c)) {
            Some(c) => {
                for m in row.meetings {
                    match c.meetings.iter_mut().find(|k| (k.start, k.end) == (m.start, m.end)) {
                        Some(k) => {
                            k.days.extend(m.days);
                            k.days.sort();
                            k.days.dedup();
                        }
                        None => c.meetings.push(m),
                    }
                }
                if c.room.is_empty() {
                    c.room = row.room;
                }
            }
            None => out.push(OwnClass { code: row.code, name, room: row.room, teacher: row.teacher, meetings: row.meetings }),
        }
    }
    out.into_iter()
        .map(|mut class| {
            let unsure = class.code.is_empty() || class.name.chars().filter(|c| c.is_alphabetic()).count() < 3;
            if class.name.is_empty() {
                class.name = if class.code.is_empty() { "Class".into() } else { class.code.clone() };
            }
            Found { class, unsure }
        })
        .collect()
}

/// Typed or pasted text, line by line, with no positions (C14).
pub fn read_text(text: &str) -> Vec<Found> {
    read(&text.lines().map(str::to_string).collect::<Vec<_>>())
}

#[cfg(test)]
mod tests {
    use super::*;
    use Weekday::*;

    fn one(text: &str) -> Found {
        let f = read_text(text);
        assert_eq!(f.len(), 1, "{text}: {f:?}");
        f.into_iter().next().unwrap()
    }
    fn m(days: &[Weekday], start: u16, end: u16) -> Meeting {
        Meeting { days: days.to_vec(), start, end }
    }

    #[test]
    fn a_registration_form_row_gives_code_name_days_time_and_room() {
        let f = one("COMP 20073  Data Structures and Algorithms  3  MWF 7:30AM-9:00AM  Rm 301  Prof. Dela Cruz");
        assert_eq!(f.class.code, "COMP 20073");
        assert_eq!(f.class.name, "Data Structures and Algorithms");
        assert_eq!(f.class.meetings, [m(&[Monday, Wednesday, Friday], 450, 540)]);
        assert_eq!((f.class.room.as_str(), f.class.teacher.as_str(), f.unsure), ("301", "Prof. Dela Cruz", false));
    }

    #[test]
    fn days_read_joined_split_short_long_and_in_filipino() {
        for (text, days) in [
            ("IT101 Intro TTh 10:00-11:30 AM", vec![Tuesday, Thursday]),
            ("IT101 Intro M/W 10:00-11:30 AM", vec![Monday, Wednesday]),
            ("IT101 Intro Mon 10:00-11:30 AM", vec![Monday]),
            ("IT101 Intro Huwebes 10:00-11:30 AM", vec![Thursday]),
            ("IT101 Intro Sat 10:00-11:30 AM", vec![Saturday]),
            ("IT101 Intro Su 10:00-11:30 AM", vec![Sunday]),
        ] {
            assert_eq!(one(text).class.meetings[0].days, days, "{text}");
        }
    }

    #[test]
    fn times_read_every_common_way() {
        for (text, span) in [
            ("MATH 1A Calculus M 7:30-9:00 AM", (450, 540)),
            ("MATH 1A Calculus M 7:30 - 9:00am", (450, 540)),
            ("MATH 1A Calculus M 13:00-14:30", (780, 870)),
            ("MATH 1A Calculus M 1PM-4PM", (780, 960)),
            ("MATH 1A Calculus M 10:00-1:00", (600, 780)),
            ("MATH 1A Calculus M 10:00-1:00 PM", (600, 780)),
            ("MATH 1A Calculus M 11:30AM-1:00", (690, 780)),
            ("MATH 1A Calculus M 2:00 to 3:30", (840, 930)),
            ("MATH 1A Calculus M 7:30–9:00 AM", (450, 540)),
        ] {
            let got = one(text).class.meetings[0].clone();
            assert_eq!((got.start, got.end), span, "{text}");
        }
    }

    #[test]
    fn the_sis_line_pairs_its_days_and_times() {
        let f = one("COMP 20083  Programming  1N - BSCS 1-1N - T/F 02:00PM-04:00PM/01:30PM-04:30PM");
        assert_eq!(f.class.meetings, [m(&[Tuesday], 840, 960), m(&[Friday], 810, 990)]);
    }

    #[test]
    fn a_section_or_a_page_number_is_not_a_time() {
        assert!(read_text("BSCS 1-1N\nPage 1-2").is_empty());
    }

    #[test]
    fn rows_with_one_code_are_one_class_and_a_name_row_names_the_class_below() {
        let f = read_text("GEED 10053  Purposive Communication  T 7:30AM-9:00AM\nGEED 10053  Purposive Communication  F 7:30AM-9:00AM\nPhysical Education 2\nW 3:00PM-5:00PM");
        assert_eq!(f.len(), 2);
        assert_eq!(f[0].class.meetings, [m(&[Tuesday, Friday], 450, 540)]);
        assert_eq!((f[1].class.name.as_str(), f[1].unsure), ("Physical Education 2", true));
    }

    #[test]
    fn photo_lines_at_one_height_are_one_row() {
        let l = |text: &str, x: f32, y: f32| ScanLine { text: text.into(), x, y, w: 0.2, h: 0.02 };
        // Out of order, the way a text reader can hand back a table, and a little crooked.
        let lines = [l("MWF 8:00-9:00 AM", 0.6, 0.301), l("NSTP 1", 0.05, 0.3), l("Civic Welfare", 0.25, 0.305), l("TTh 1:00-2:30 PM", 0.6, 0.402), l("PE 2", 0.05, 0.4), l("Rhythmic Activities", 0.25, 0.398)];
        let r = rows(&lines);
        assert_eq!(r, ["NSTP 1  Civic Welfare  MWF 8:00-9:00 AM", "PE 2  Rhythmic Activities  TTh 1:00-2:30 PM"]);
        let f = read(&r);
        assert_eq!(f.iter().map(|f| (f.class.name.as_str(), f.class.meetings[0].start)).collect::<Vec<_>>(), [("Civic Welfare", 480), ("Rhythmic Activities", 780)]);
    }

    #[test]
    fn a_tilted_photo_still_keeps_each_row_together() {
        // Tilted so the right end of a row sits a whole line lower than its left end.
        let tilt = |x: f32, y: f32| y + x * 0.03;
        let l = |text: &str, x: f32, y: f32| ScanLine { text: text.into(), x, y: tilt(x, y), w: 0.012 * text.len() as f32, h: 0.02 };
        let mut lines = vec![];
        for (i, (code, name, when)) in [("MATH 102", "Calculus 1", "TTh 10:00-11:30 AM"), ("PE 2", "Rhythmic Activities", "S 8:00-10:00 AM"), ("NSTP 1", "Civic Welfare", "S 1:00-4:00 PM")].into_iter().enumerate() {
            let y = 0.2 + i as f32 * 0.045;
            lines.extend([l(code, 0.04, y), l(name, 0.19, y), l("3", 0.51, y), l(when, 0.57, y)]);
        }
        let f = read(&rows(&lines));
        assert_eq!(f.iter().map(|f| (f.class.code.as_str(), f.class.name.as_str())).collect::<Vec<_>>(), [("MATH 102", "Calculus 1"), ("PE 2", "Rhythmic Activities"), ("NSTP 1", "Civic Welfare")]);
    }

    #[test]
    fn a_row_with_no_code_is_marked_for_checking() {
        let f = one("Org meeting  F 5:00-6:00 PM");
        assert_eq!((f.class.code.as_str(), f.class.name.as_str(), f.unsure), ("", "Org meeting", true));
    }
}
