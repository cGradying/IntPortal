//! Turns scraped schedule rows into class sessions.
//!
//! The schedule cell looks like `1N - BSCS 1-1N - T/F 02:00PM-04:00PM/01:30PM-04:30PM`.
//! Days and time ranges are `/`-separated groups.

use crate::model::{ClassSession, Weekday};
use regex::Regex;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::LazyLock;

/// One row of the SIS schedule table, as scraped.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct ScheduleRow {
    pub subject_code: String,
    pub description: String,
    pub unit: String,
    pub schedule_line: String,
    pub faculty: String,
}

static DAYS_AND_TIMES: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"([A-Z]+(?:/[A-Z]+)*)\s+((?:\d{1,2}:\d{2}[AP]M-\d{1,2}:\d{2}[AP]M)(?:/\d{1,2}:\d{2}[AP]M-\d{1,2}:\d{2}[AP]M)*)")
        .unwrap()
});

/// Parses every row, numbering repeats of the same subject, day and time.
pub fn parse(rows: &[ScheduleRow]) -> Vec<ClassSession> {
    let mut seen: HashMap<(String, Weekday, u16, u16), u16> = HashMap::new();
    rows.iter()
        .flat_map(parse_row)
        .map(|mut s| {
            let n = seen.entry((s.subject_code.clone(), s.day, s.start, s.end)).or_default();
            s.occurrence = *n;
            *n += 1;
            s
        })
        .collect()
}

pub fn parse_row(row: &ScheduleRow) -> Vec<ClassSession> {
    // Not end-anchored: some rows leak a faculty name after the times.
    let Some(caps) = DAYS_AND_TIMES.captures(&row.schedule_line) else { return vec![] };
    let day_groups: Vec<Vec<Weekday>> = caps[1].split('/').map(tokenize_days).collect();
    let ranges: Vec<(u16, u16)> = caps[2].split('/').filter_map(parse_range).collect();
    if day_groups.is_empty() || ranges.is_empty() {
        return vec![];
    }

    let session = |day: Weekday, (start, end): (u16, u16)| ClassSession {
        subject_code: row.subject_code.clone(),
        description: row.description.clone(),
        faculty: row.faculty.clone(),
        day,
        start,
        end,
        occurrence: 0,
    };

    // A lone group on one side repeats across every group on the other.
    // Only when both sides carry several groups do they pair positionally.
    if day_groups.len() == 1 && ranges.len() > 1 {
        let days = &day_groups[0];
        // `TTH a/b` still pairs Tuesday with a and Thursday with b.
        if days.len() == ranges.len() {
            return days.iter().zip(&ranges).map(|(d, r)| session(*d, *r)).collect();
        }
        return ranges.iter().flat_map(|r| days.iter().map(|d| session(*d, *r))).collect();
    }
    if ranges.len() == 1 && day_groups.len() > 1 {
        return day_groups.iter().flatten().map(|d| session(*d, ranges[0])).collect();
    }
    day_groups
        .iter()
        .zip(&ranges)
        .flat_map(|(days, r)| days.iter().map(|d| session(*d, *r)))
        .collect()
}

/// `TTH` becomes Tuesday and Thursday. An unrecognised tail keeps what parsed.
fn tokenize_days(token: &str) -> Vec<Weekday> {
    let mut rest = token;
    let mut days = vec![];
    'outer: while !rest.is_empty() {
        for (code, day) in Weekday::CODES {
            if let Some(tail) = rest.strip_prefix(code) {
                days.push(day);
                rest = tail;
                continue 'outer;
            }
        }
        break;
    }
    days
}

fn parse_range(text: &str) -> Option<(u16, u16)> {
    let (a, b) = text.split_once('-')?;
    Some((parse_time(a)?, parse_time(b)?))
}

/// `02:00PM` becomes 840.
fn parse_time(text: &str) -> Option<u16> {
    let t = text.trim().to_ascii_uppercase();
    let (clock, period) = t.split_at(t.len().checked_sub(2)?);
    let (h, m) = clock.split_once(':')?;
    let (mut hour, minute): (u16, u16) = (h.parse().ok()?, m.parse().ok()?);
    if !(1..=12).contains(&hour) || minute >= 60 {
        return None;
    }
    match period {
        "PM" if hour != 12 => hour += 12,
        "AM" if hour == 12 => hour = 0,
        "AM" | "PM" => {}
        _ => return None,
    }
    Some(hour * 60 + minute)
}

#[cfg(test)]
mod tests {
    use super::*;
    use Weekday::*;

    fn parse_line(line: &str) -> Vec<ClassSession> {
        parse_row(&ScheduleRow {
            subject_code: "TEST 001".into(),
            description: "Test Subject".into(),
            faculty: "SANTOS, JUAN".into(),
            schedule_line: line.into(),
            ..Default::default()
        })
    }

    fn days(s: &[ClassSession]) -> Vec<Weekday> {
        s.iter().map(|s| s.day).collect()
    }

    fn times(s: &[ClassSession]) -> Vec<(u16, u16)> {
        s.iter().map(|s| (s.start, s.end)).collect()
    }

    #[test]
    fn joined_day_run_with_one_range_per_day_pairs_positionally() {
        let s = parse_line("1N - BSCS 1-1N - TTH 07:30AM-09:00AM/10:30AM-12:00PM");
        assert_eq!(days(&s), [Tuesday, Thursday]);
        assert_eq!(times(&s), [(450, 540), (630, 720)]);
    }

    #[test]
    fn two_days_pair_with_their_own_times() {
        let s = parse_line("1N - BSCS 1-1N - T/F 02:00PM-04:00PM/01:30PM-04:30PM");
        assert_eq!(days(&s), [Tuesday, Friday]);
        assert_eq!(times(&s), [(840, 960), (810, 990)]);
    }

    #[test]
    fn same_day_twice_becomes_two_blocks() {
        let s = parse_line("1N - BSCS 1-1N - SUN/SUN 08:00AM-12:00PM/01:00PM-06:00PM");
        assert_eq!(days(&s), [Sunday, Sunday]);
        assert_eq!(times(&s), [(480, 720), (780, 1080)]);
    }

    #[test]
    fn single_day_single_range() {
        let s = parse_line("1N - BSCS 1-1N - S 07:30AM-10:30AM");
        assert_eq!(days(&s), [Saturday]);
        assert_eq!(times(&s), [(450, 630)]);
    }

    #[test]
    fn multi_letter_day_codes_are_not_swallowed() {
        assert_eq!(days(&parse_line("1N - X - TH 09:00AM-11:00AM")), [Thursday]);
        assert_eq!(days(&parse_line("1N - X - SUN 09:00AM-11:00AM")), [Sunday]);
    }

    #[test]
    fn noon_and_midnight_boundaries() {
        assert_eq!(times(&parse_line("1N - X - M 12:00PM-01:00PM")), [(720, 780)]);
        assert_eq!(times(&parse_line("1N - X - M 12:30AM-01:30AM")), [(30, 90)]);
    }

    #[test]
    fn trailing_text_after_times_does_not_break_the_match() {
        let s = parse_line("4 - BSEE 1-4 - M/TH 07:30AM-10:30AM/07:30AM-10:30AM TAROY, JOSE CARLOS BASILIO");
        assert_eq!(days(&s), [Monday, Thursday]);
        assert_eq!(times(&s), [(450, 630), (450, 630)]);
    }

    #[test]
    fn unparseable_rows_are_skipped() {
        assert!(parse_line("").is_empty());
        assert!(parse_line("1N - BSCS 1-1N - TBA").is_empty());
        assert!(parse_line("no times here at all").is_empty());
    }

    #[test]
    fn day_run_with_single_range_covers_every_day() {
        let s = parse_line("1N - X - TTH 01:00PM-02:30PM");
        assert_eq!(days(&s), [Tuesday, Thursday]);
        assert_eq!(times(&s), [(780, 870), (780, 870)]);
        assert_eq!(days(&parse_line("1N - X - MW 08:00AM-09:30AM")), [Monday, Wednesday]);
    }

    #[test]
    fn single_day_group_with_several_ranges_covers_every_range() {
        let s = parse_line("1N - X - S 07:30AM-10:30AM/01:00PM-04:00PM");
        assert_eq!(days(&s), [Saturday, Saturday]);
        assert_eq!(times(&s), [(450, 630), (780, 960)]);
    }

    #[test]
    fn several_day_groups_with_one_range_cover_every_group() {
        let s = parse_line("1N - X - TTH/S 01:00PM-02:30PM");
        assert_eq!(days(&s), [Tuesday, Thursday, Saturday]);
    }

    #[test]
    fn duplicate_rows_get_unique_ids_and_originals_keep_theirs() {
        let row = ScheduleRow {
            subject_code: "TEST 001".into(),
            schedule_line: "1N - X - S 07:30AM-10:30AM".into(),
            ..Default::default()
        };
        let s = parse(&[row.clone(), row]);
        assert_eq!(s.iter().map(ClassSession::id).collect::<Vec<_>>(), ["TEST 001-6-450-630", "TEST 001-6-450-630-1"]);
    }
}
