//! "What now": today's agenda, the next class, and the island's glance.
//!
//! No clock and no time zones here. The UI passes the device's local date and
//! minute of the day, so every case is testable at a fixed moment.

use crate::model::{ClassSession, Weekday};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

/// A calendar date with no time zone. Serialises as `"2026-08-03"`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub struct Date {
    pub y: i32,
    pub m: u8,
    pub d: u8,
}

impl Date {
    pub fn new(y: i32, m: u8, d: u8) -> Date {
        Date { y, m, d }
    }

    /// Days since 1970-01-01 (Howard Hinnant's days_from_civil).
    pub(crate) fn days(self) -> i64 {
        let y = i64::from(self.y) - i64::from(self.m <= 2);
        let era = y.div_euclid(400);
        let yoe = y - era * 400;
        let m = i64::from(self.m);
        let doy = (153 * (if m > 2 { m - 3 } else { m + 9 }) + 2) / 5 + i64::from(self.d) - 1;
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
        era * 146097 + doe - 719468
    }

    pub(crate) fn from_days(z: i64) -> Date {
        let z = z + 719468;
        let era = z.div_euclid(146097);
        let doe = z - era * 146097;
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
        let mp = (5 * doy + 2) / 153;
        let d = (doy - (153 * mp + 2) / 5 + 1) as u8;
        let m = if mp < 10 { mp + 3 } else { mp - 9 } as u8;
        Date { y: (yoe + era * 400 + i64::from(m <= 2)) as i32, m, d }
    }

    pub fn add_days(self, n: i64) -> Date {
        Date::from_days(self.days() + n)
    }

    pub fn weekday(self) -> Weekday {
        // 1970-01-01 was a Thursday.
        Weekday::ALL[(self.days() + 3).rem_euclid(7) as usize]
    }

    /// The Monday of this date's week. Sunday closes its week.
    pub fn week_start(self) -> Date {
        self.add_days(-(i64::from(self.weekday().number()) - 1))
    }
}

impl std::fmt::Display for Date {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{:04}-{:02}-{:02}", self.y, self.m, self.d)
    }
}

impl std::str::FromStr for Date {
    type Err = String;
    fn from_str(s: &str) -> Result<Date, String> {
        let mut it = s.splitn(3, '-').map(str::parse::<i32>);
        match (it.next(), it.next(), it.next()) {
            (Some(Ok(y)), Some(Ok(m @ 1..=12)), Some(Ok(d @ 1..=31))) => Ok(Date::new(y, m as u8, d as u8)),
            _ => Err(format!("not a YYYY-MM-DD date: {s}")),
        }
    }
}

impl Serialize for Date {
    fn serialize<S: serde::Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
        s.collect_str(self)
    }
}

impl<'de> Deserialize<'de> for Date {
    fn deserialize<D: serde::Deserializer<'de>>(d: D) -> Result<Date, D::Error> {
        String::deserialize(d)?.parse().map_err(serde::de::Error::custom)
    }
}

/// The device's local now.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct Moment {
    pub date: Date,
    /// Minutes since local midnight.
    pub minute: u16,
}

/// The student's label on a meeting. The SIS never knows about it.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Mark {
    InPerson,
    Online,
    Vacant,
}

/// A value per session id: one for the whole term, and overrides for single
/// weeks keyed by that week's Monday.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Layers<T> {
    #[serde(default = "HashMap::new")]
    pub term: HashMap<String, T>,
    #[serde(default = "HashMap::new")]
    pub weekly: HashMap<String, HashMap<Date, T>>,
}

impl<T> Default for Layers<T> {
    fn default() -> Self {
        Layers { term: HashMap::new(), weekly: HashMap::new() }
    }
}

impl<T: Copy> Layers<T> {
    /// This week's override, else the term's.
    pub fn get(&self, id: &str, on: Date) -> Option<T> {
        self.weekly.get(id).and_then(|w| w.get(&on.week_start())).or_else(|| self.term.get(id)).copied()
    }

    /// `week` set: that week only. `value` empty: clear it.
    pub fn set(&mut self, id: &str, week: Option<Date>, value: Option<T>) {
        match (week, value) {
            (Some(w), Some(v)) => {
                self.weekly.entry(id.to_string()).or_default().insert(w.week_start(), v);
            }
            (Some(w), None) => {
                if let Some(weeks) = self.weekly.get_mut(id) {
                    weeks.remove(&w.week_start());
                    if weeks.is_empty() {
                        self.weekly.remove(id);
                    }
                }
            }
            (None, Some(v)) => {
                self.term.insert(id.to_string(), v);
            }
            (None, None) => {
                self.term.remove(id);
            }
        }
    }
}

/// When a meeting happens instead, if the student moved it: the old app's
/// "change its time". The day stays within the same week.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct Slot {
    pub day: Weekday,
    pub start: u16,
    pub end: u16,
}

/// The student's edits to the timetable. The SIS never knows about them.
/// `mode` flattens so marks saved before moves existed still load.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct Marks {
    #[serde(flatten)]
    pub mode: Layers<Mark>,
    #[serde(default)]
    pub moved: Layers<Slot>,
}

impl Marks {
    pub fn get(&self, session: &ClassSession, on: Date) -> Mark {
        self.mode.get(&session.id(), on).unwrap_or(Mark::InPerson)
    }

    /// Online classes still count: you still have to show up.
    pub fn is_vacant(&self, session: &ClassSession, on: Date) -> bool {
        self.get(session, on) == Mark::Vacant
    }
}

/// One session meeting on one date, after the student's edits. `session`
/// carries the effective day and times; `id` stays the original session's,
/// so marks, moves and reminders keep finding it.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Meeting {
    pub id: String,
    pub session: ClassSession,
    pub date: Date,
    pub mark: Mark,
    pub moved: bool,
}

impl Meeting {
    fn start_abs(&self) -> i64 {
        self.date.days() * 1440 + i64::from(self.session.start)
    }

    fn end_abs(&self) -> i64 {
        self.date.days() * 1440 + i64::from(self.session.end)
    }
}

/// Every meeting in the week holding `on`, vacant ones included, by date
/// and start time.
pub fn week(sessions: &[ClassSession], marks: &Marks, on: Date) -> Vec<Meeting> {
    let monday = on.week_start();
    let mut out: Vec<Meeting> = sessions
        .iter()
        .map(|s| {
            let id = s.id();
            let slot = marks.moved.get(&id, monday);
            let mut session = s.clone();
            if let Some(slot) = slot {
                (session.day, session.start, session.end) = (slot.day, slot.start, slot.end);
            }
            let date = monday.add_days(i64::from(session.day.number()) - 1);
            Meeting { mark: marks.get(s, date), id, session, date, moved: slot.is_some() }
        })
        .collect();
    out.sort_by_key(|m| (m.date, m.session.start, m.session.end));
    out
}

/// Meetings from `from` through `days` days on, vacant ones left out.
pub(crate) fn meetings_from(sessions: &[ClassSession], marks: &Marks, from: Date, days: i64) -> Vec<Meeting> {
    let last = from.add_days(days - 1);
    let mut monday = from.week_start();
    let mut out = Vec::new();
    while monday <= last {
        out.extend(week(sessions, marks, monday).into_iter().filter(|m| m.date >= from && m.date <= last && m.mark != Mark::Vacant));
        monday = monday.add_days(7);
    }
    out
}

/// `8AM`, `2:30PM`: the old app's format.
pub fn clock(minutes: u16) -> String {
    let (h24, m) = (minutes / 60, minutes % 60);
    let period = if h24 >= 12 { "PM" } else { "AM" };
    let h = match h24 % 12 {
        0 => 12,
        h => h,
    };
    if m == 0 {
        format!("{h}{period}")
    } else {
        format!("{h}:{m:02}{period}")
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Phase {
    Past,
    InSession,
    Upcoming,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct AgendaItem {
    #[serde(flatten)]
    pub meeting: Meeting,
    pub phase: Phase,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Agenda {
    /// Today's non-vacant meetings by start time.
    pub items: Vec<AgendaItem>,
    pub tomorrow_first: Option<ClassSession>,
    /// Free minutes still ahead today, from gaps of 15 minutes or more.
    pub free_minutes_left: u16,
}

/// Something on the student's own calendar, such as an org meeting or a
/// shift. It takes its time out of the free gaps between classes.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Busy {
    pub from: Moment,
    pub to: Moment,
    pub title: String,
}

/// Free minutes still ahead today: the gaps between today's classes with the
/// student's own events cut out, counting only pieces of 15 minutes or more.
pub fn free_minutes(items: &[AgendaItem], now: Moment, busy: &[Busy]) -> u16 {
    let midnight = now.date.days() * 1440;
    let at = |m: Moment| m.date.days() * 1440 + i64::from(m.minute) - midnight;
    let busy: Vec<(i64, i64)> = busy.iter().map(|b| (at(b.from), at(b.to))).collect();
    let total: i64 = items
        .windows(2)
        .map(|w| (i64::from(w[0].meeting.session.end), i64::from(w[1].meeting.session.start)))
        .filter(|&(_, start)| start > i64::from(now.minute))
        .map(|(end, start)| {
            let mut cuts: Vec<(i64, i64)> = busy.iter().map(|&(a, b)| (a.max(end), b.min(start))).filter(|(a, b)| a < b).collect();
            cuts.sort_unstable();
            let (mut from, mut free) = (end, 0);
            for (a, b) in cuts {
                if a - from >= 15 {
                    free += a - from;
                }
                from = from.max(b);
            }
            if start - from >= 15 {
                free += start - from;
            }
            free
        })
        .sum();
    u16::try_from(total).unwrap_or(u16::MAX)
}

pub fn agenda(sessions: &[ClassSession], marks: &Marks, now: Moment) -> Agenda {
    let items: Vec<AgendaItem> = meetings_from(sessions, marks, now.date, 1)
        .into_iter()
        .map(|m| AgendaItem {
            phase: if m.session.end <= now.minute {
                Phase::Past
            } else if m.session.start <= now.minute {
                Phase::InSession
            } else {
                Phase::Upcoming
            },
            meeting: m,
        })
        .collect();
    let free_minutes_left = free_minutes(&items, now, &[]);
    let tomorrow_first = meetings_from(sessions, marks, now.date.add_days(1), 1).into_iter().next().map(|m| m.session);
    Agenda { items, tomorrow_first, free_minutes_left }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Upcoming {
    pub session: ClassSession,
    pub date: Date,
    pub is_now: bool,
    /// Whole minutes until it starts; 0 once it has.
    pub minutes_away: i64,
}

/// The next meeting that hasn't finished, looking through next week so
/// Sunday night still finds Monday's first class.
pub fn next_class(sessions: &[ClassSession], marks: &Marks, now: Moment) -> Option<Upcoming> {
    let now_abs = now.date.days() * 1440 + i64::from(now.minute);
    let week_start = now.date.week_start();
    meetings_from(sessions, marks, week_start, 14)
        .into_iter()
        .filter(|m| m.end_abs() > now_abs)
        .min_by_key(|m| (m.start_abs(), m.session.start))
        .map(|m| {
            let start = m.start_abs();
            Upcoming { is_now: start <= now_abs, minutes_away: (start - now_abs).max(0), date: m.date, session: m.session }
        })
}

impl Upcoming {
    /// "in session until 10:50AM", "starting now", "in 25 min", "at 2PM", "MON 9AM".
    pub fn countdown(&self, now: Moment) -> String {
        if self.is_now {
            return format!("in session until {}", clock(self.session.end));
        }
        match self.minutes_away {
            0 => "starting now".into(),
            m if m < 60 => format!("in {m} min"),
            _ if self.date == now.date => format!("at {}", clock(self.session.start)),
            _ => format!("{} {}", short_day(self.session.day), clock(self.session.start)),
        }
    }
}

fn short_day(d: Weekday) -> &'static str {
    ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"][usize::from(d.number()) - 1]
}

/// The island's one line, in priority order (legacy spec 12).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum Glance {
    InSession { code: String, until: String },
    NextToday { code: String, when: String },
    SyncTrouble { message: String },
    Thinking,
    DayDone { tomorrow: Option<String> },
}

impl Glance {
    pub fn line(&self) -> String {
        match self {
            Glance::InSession { code, until } => format!("{code} · until {until}"),
            Glance::NextToday { code, when } => format!("{code} · {when}"),
            Glance::SyncTrouble { message } => format!("{message} · Try again"),
            Glance::Thinking => "IntAssis is thinking".into(),
            Glance::DayDone { tomorrow: Some(t) } => format!("No more classes today · Tomorrow {t}"),
            Glance::DayDone { tomorrow: None } => "No more classes today".into(),
        }
    }
}

pub fn glance(
    sessions: &[ClassSession],
    marks: &Marks,
    now: Moment,
    sync_trouble: Option<&str>,
    assistant_busy: bool,
) -> Glance {
    let next = next_class(sessions, marks, now);
    if let Some(n) = next.as_ref().filter(|n| n.is_now) {
        return Glance::InSession { code: n.session.subject_code.clone(), until: clock(n.session.end) };
    }
    if let Some(n) = next.as_ref().filter(|n| n.date == now.date) {
        let when = if n.minutes_away < 60 { format!("in {}m", n.minutes_away) } else { format!("at {}", clock(n.session.start)) };
        return Glance::NextToday { code: n.session.subject_code.clone(), when };
    }
    if let Some(m) = sync_trouble {
        return Glance::SyncTrouble { message: m.into() };
    }
    if assistant_busy {
        return Glance::Thinking;
    }
    let tomorrow = agenda(sessions, marks, now)
        .tomorrow_first
        .map(|s| format!("{} at {}", s.subject_code, clock(s.start)));
    Glance::DayDone { tomorrow }
}

/// One class reminder for the platform to deliver at `date` + `minute`.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Reminder {
    /// Stable per session and date, so rescheduling replaces rather than duplicates.
    pub id: i32,
    pub date: Date,
    pub minute: u16,
    pub title: String,
    pub body: String,
}

/// A stable, positive id for a reminder, so rescheduling replaces it.
pub fn reminder_id(key: &str) -> i32 {
    let mut h: i32 = 17;
    for b in key.bytes() {
        h = h.wrapping_mul(31).wrapping_add(i32::from(b));
    }
    h & 0x7fff_ffff
}

/// Reminders `lead` minutes before every meeting in the next `days` days that
/// hasn't started yet. A meeting marked vacant for its week is skipped, so a
/// one-week cancellation silences just that week (the old app could only
/// skip whole-term vacancies).
pub fn reminders(sessions: &[ClassSession], marks: &Marks, now: Moment, lead: u16, days: u16) -> Vec<Reminder> {
    let now_abs = now.date.days() * 1440 + i64::from(now.minute);
    let mut out: Vec<(i64, Reminder)> = meetings_from(sessions, marks, now.date, i64::from(days))
        .into_iter()
        .filter_map(|m| {
            let at = m.start_abs() - i64::from(lead);
            if at <= now_abs {
                return None;
            }
            let s = &m.session;
            Some((
                at,
                Reminder {
                    id: reminder_id(&format!("{}@{}", m.id, m.date)),
                    date: Date::from_days(at.div_euclid(1440)),
                    minute: at.rem_euclid(1440) as u16,
                    title: format!("{} in {lead} min", s.subject_code),
                    body: format!("{} · {}{}", s.description, clock(s.start), if m.mark == Mark::Online { " · Online" } else { "" }),
                },
            ))
        })
        .collect();
    out.sort_by_key(|(at, _)| *at);
    out.into_iter().map(|(_, r)| r).collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use Weekday::*;

    fn s(code: &str, day: Weekday, start: u16, end: u16) -> ClassSession {
        ClassSession {
            subject_code: code.into(),
            description: String::new(),
            faculty: String::new(),
            day,
            start,
            end,
            occurrence: 0,
        }
    }

    // 2026-08-03 is a Monday.
    fn at(d: u8, h: u16, m: u16) -> Moment {
        Moment { date: Date::new(2026, 8, d), minute: h * 60 + m }
    }

    fn week() -> Vec<ClassSession> {
        vec![
            s("COMP 002", Monday, 9 * 60, 10 * 60 + 50),
            s("GEED 005", Monday, 13 * 60, 14 * 60 + 30),
            s("COMP 001", Tuesday, 9 * 60, 12 * 60),
        ]
    }

    #[test]
    fn civil_dates() {
        let mon = Date::new(2026, 8, 3);
        let days: Vec<Weekday> = (0..7).map(|i| mon.add_days(i).weekday()).collect();
        assert_eq!(days, Weekday::ALL);
        assert_eq!(Date::new(2026, 8, 9).week_start(), mon);
        assert_eq!(Date::new(2026, 12, 31).add_days(1), Date::new(2027, 1, 1));
        assert_eq!(Date::new(2028, 2, 28).add_days(1), Date::new(2028, 2, 29));
        assert_eq!(Date::new(2026, 8, 3).to_string(), "2026-08-03");
        assert_eq!("2026-08-03".parse(), Ok(Date::new(2026, 8, 3)));
        assert!("2026-13-01".parse::<Date>().is_err());
    }

    #[test]
    fn clock_format() {
        assert_eq!([clock(0), clock(480), clock(870), clock(720), clock(1439)], ["12AM", "8AM", "2:30PM", "12PM", "11:59PM"]);
    }

    #[test]
    fn glance_in_session() {
        assert_eq!(glance(&week(), &Marks::default(), at(3, 9, 30), None, false).line(), "COMP 002 · until 10:50AM");
    }

    #[test]
    fn glance_next_today_counts_down_then_names_the_time() {
        let g = glance(&week(), &Marks::default(), at(3, 8, 48), None, false);
        assert_eq!(g.line(), "COMP 002 · in 12m");
        assert_eq!(glance(&week(), &Marks::default(), at(3, 11, 0), None, false).line(), "GEED 005 · at 1PM");
    }

    #[test]
    fn a_class_outranks_sync_trouble_but_sync_trouble_outranks_the_day_summary() {
        let trouble = Some("Couldn't reach SIS");
        assert_eq!(glance(&week(), &Marks::default(), at(3, 9, 30), trouble, false).line(), "COMP 002 · until 10:50AM");
        assert_eq!(glance(&week(), &Marks::default(), at(3, 15, 0), trouble, false).line(), "Couldn't reach SIS · Try again");
    }

    #[test]
    fn glance_thinking() {
        assert_eq!(glance(&week(), &Marks::default(), at(3, 15, 0), None, true), Glance::Thinking);
    }

    #[test]
    fn glance_day_done_names_tomorrow() {
        assert_eq!(
            glance(&week(), &Marks::default(), at(3, 15, 0), None, false).line(),
            "No more classes today · Tomorrow COMP 001 at 9AM"
        );
        assert_eq!(glance(&week(), &Marks::default(), at(4, 13, 0), None, false).line(), "No more classes today");
    }

    #[test]
    fn next_class_wraps_from_sunday_night_to_monday() {
        let n = next_class(&week(), &Marks::default(), at(9, 21, 0)).unwrap();
        assert_eq!((n.session.subject_code.as_str(), n.date), ("COMP 002", Date::new(2026, 8, 10)));
        assert_eq!(n.countdown(at(9, 21, 0)), "MON 9AM");
    }

    #[test]
    fn countdown_phrases() {
        let w = week();
        let m = Marks::default();
        assert_eq!(next_class(&w, &m, at(3, 8, 35)).unwrap().countdown(at(3, 8, 35)), "in 25 min");
        assert_eq!(next_class(&w, &m, at(3, 9, 0)).unwrap().countdown(at(3, 9, 0)), "in session until 10:50AM");
        assert_eq!(next_class(&w, &m, at(3, 11, 0)).unwrap().countdown(at(3, 11, 0)), "at 1PM");
    }

    #[test]
    fn vacant_this_week_only_skips_this_week_but_not_next() {
        let w = week();
        let mut marks = Marks::default();
        marks.mode.set(&w[0].id(), Some(Date::new(2026, 8, 3)), Some(Mark::Vacant));
        assert_eq!(glance(&w, &marks, at(3, 8, 0), None, false).line(), "GEED 005 · at 1PM");
        let n = next_class(&w, &marks, at(9, 21, 0)).unwrap();
        assert_eq!(n.session.subject_code, "COMP 002");
    }

    #[test]
    fn online_classes_still_count() {
        let w = week();
        let mut marks = Marks::default();
        marks.mode.set(&w[0].id(), None, Some(Mark::Online));
        assert_eq!(glance(&w, &marks, at(3, 8, 48), None, false).line(), "COMP 002 · in 12m");
    }

    #[test]
    fn reminders_fire_ahead_skip_the_past_and_vacant_weeks() {
        let w = week();
        let r = reminders(&w, &Marks::default(), at(3, 9, 30), 10, 7);
        let when: Vec<(String, u16, String)> = r.iter().map(|r| (r.date.to_string(), r.minute, r.title.clone())).collect();
        assert_eq!(
            when,
            [
                ("2026-08-03".to_string(), 12 * 60 + 50, "GEED 005 in 10 min".to_string()),
                ("2026-08-04".to_string(), 8 * 60 + 50, "COMP 001 in 10 min".to_string()),
            ]
        );
        let mut marks = Marks::default();
        marks.mode.set(&w[1].id(), Some(Date::new(2026, 8, 3)), Some(Mark::Vacant));
        marks.mode.set(&w[2].id(), None, Some(Mark::Online));
        let r = reminders(&w, &marks, at(3, 9, 30), 10, 8);
        assert_eq!(r.iter().map(|r| r.date.to_string()).collect::<Vec<_>>(), ["2026-08-04", "2026-08-10", "2026-08-10"]);
        assert_eq!(r[0].body, " · 9AM · Online");
    }

    #[test]
    fn reminder_before_an_early_class_lands_the_previous_evening() {
        let r = reminders(&[s("NSTP 001", Tuesday, 5, 60)], &Marks::default(), at(3, 12, 0), 15, 7);
        assert_eq!((r[0].date, r[0].minute), (Date::new(2026, 8, 3), 23 * 60 + 50));
    }

    #[test]
    fn reminder_ids_are_stable_and_distinct() {
        let a = reminders(&week(), &Marks::default(), at(3, 0, 0), 10, 14);
        let b = reminders(&week(), &Marks::default(), at(3, 0, 0), 10, 14);
        assert_eq!(a, b);
        let ids: std::collections::HashSet<i32> = a.iter().map(|r| r.id).collect();
        assert_eq!(ids.len(), a.len());
    }

    #[test]
    fn agenda_phases_free_time_and_tomorrow() {
        let a = agenda(&week(), &Marks::default(), at(3, 10, 0));
        let phases: Vec<Phase> = a.items.iter().map(|i| i.phase).collect();
        assert_eq!(phases, [Phase::InSession, Phase::Upcoming]);
        assert_eq!(a.free_minutes_left, 130);
        assert_eq!(a.tomorrow_first.unwrap().subject_code, "COMP 001");
        assert_eq!(agenda(&week(), &Marks::default(), at(3, 13, 30)).free_minutes_left, 0);
    }

    fn moved(w: &[ClassSession], i: usize, week: Option<Date>, day: Weekday, start: u16, end: u16) -> Marks {
        let mut marks = Marks::default();
        marks.moved.set(&w[i].id(), week, Some(Slot { day, start, end }));
        marks
    }

    #[test]
    fn a_class_moved_for_the_term_shows_at_its_new_time_everywhere() {
        let w = week();
        // GEED 005 moves from Monday 1PM to Wednesday 3PM for the term.
        let marks = moved(&w, 1, None, Wednesday, 15 * 60, 16 * 60);
        let wk = super::week(&w, &marks, Date::new(2026, 8, 5));
        let geed = wk.iter().find(|m| m.session.subject_code == "GEED 005").unwrap();
        assert_eq!((geed.date, geed.session.start, geed.moved, geed.id.as_str()), (Date::new(2026, 8, 5), 900, true, "GEED 005-1-780-870"));
        assert_eq!(glance(&w, &marks, at(3, 11, 0), None, false).line(), "No more classes today · Tomorrow COMP 001 at 9AM");
        assert_eq!(glance(&w, &marks, at(5, 14, 50), None, false).line(), "GEED 005 · in 10m");
        let r = reminders(&w, &marks, at(3, 11, 0), 10, 3);
        assert_eq!(r.iter().map(|r| (r.date.to_string(), r.minute)).collect::<Vec<_>>(), [("2026-08-04".into(), 530), ("2026-08-05".into(), 890)]);
    }

    #[test]
    fn a_class_moved_for_one_week_returns_the_next() {
        let w = week();
        let marks = moved(&w, 0, Some(Date::new(2026, 8, 5)), Monday, 7 * 60, 8 * 60);
        assert_eq!(glance(&w, &marks, at(3, 6, 55), None, false).line(), "COMP 002 · in 5m");
        let n = next_class(&w, &marks, at(9, 21, 0)).unwrap();
        assert_eq!((n.date, n.session.start), (Date::new(2026, 8, 10), 9 * 60));
    }

    #[test]
    fn marks_follow_a_moved_class_by_its_original_id() {
        let w = week();
        let mut marks = moved(&w, 1, None, Wednesday, 15 * 60, 16 * 60);
        marks.mode.set(&w[1].id(), Some(Date::new(2026, 8, 3)), Some(Mark::Vacant));
        assert!(agenda(&w, &marks, at(5, 8, 0)).items.is_empty());
        assert_eq!(agenda(&w, &marks, at(12, 8, 0)).items[0].meeting.session.subject_code, "GEED 005");
    }

    #[test]
    fn clearing_a_week_override_falls_back_to_the_term() {
        let mut l: Layers<Mark> = Layers::default();
        l.set("x", None, Some(Mark::Online));
        l.set("x", Some(Date::new(2026, 8, 5)), Some(Mark::Vacant));
        assert_eq!(l.get("x", Date::new(2026, 8, 3)), Some(Mark::Vacant));
        l.set("x", Some(Date::new(2026, 8, 3)), None);
        assert_eq!(l.get("x", Date::new(2026, 8, 3)), Some(Mark::Online));
        assert!(l.weekly.is_empty());
        l.set("x", None, None);
        assert_eq!(l.get("x", Date::new(2026, 8, 3)), None);
    }

    fn busy(from: Moment, to: Moment) -> Busy {
        Busy { from, to, title: "Org meeting".into() }
    }

    #[test]
    fn calendar_events_take_their_time_out_of_the_free_gaps() {
        let a = agenda(&week(), &Marks::default(), at(3, 10, 0));
        let free = |b: &[Busy]| free_minutes(&a.items, at(3, 10, 0), b);
        assert_eq!(free(&[]), 130);
        assert_eq!(free(&[busy(at(3, 11, 30), at(3, 12, 0))]), 100, "inside the gap");
        assert_eq!(free(&[busy(at(3, 12, 45), at(3, 13, 30))]), 115, "running into a class");
        assert_eq!(free(&[busy(at(3, 9, 15), at(3, 10, 0))]), 130, "during a class");
        assert_eq!(free(&[busy(at(3, 11, 0), at(3, 12, 50))]), 0, "leftovers under 15 minutes don't count");
        assert_eq!(free(&[busy(at(2, 22, 0), at(3, 11, 30))]), 90, "from last night");
        assert_eq!(free(&[busy(at(4, 11, 0), at(4, 12, 0))]), 130, "another day");
    }
}
