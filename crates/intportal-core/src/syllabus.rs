//! A subject's syllabus: its outline (topics, quizzes, exams, projects, by
//! week or date) and its grading system (weighted components), with the
//! arithmetic students do by hand every term.

use crate::today::{reminder_id, Date, Moment, Reminder};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Kind {
    Lecture,
    Quiz,
    Exam,
    Project,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Item {
    /// Unique within the subject; empty until saved.
    #[serde(default)]
    pub id: String,
    pub topic: String,
    pub kind: Kind,
    pub week: Option<u16>,
    pub date: Option<Date>,
    #[serde(default)]
    pub done: bool,
}

/// One weighted piece of a subject's grade, "Midterm Exam 30%". `score` is
/// the student's own percent, empty until they get it back.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Component {
    pub name: String,
    /// Percent of the final grade.
    pub weight: f64,
    pub score: Option<f64>,
}

/// Everything the student keeps for one subject.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct Plan {
    #[serde(default)]
    pub items: Vec<Item>,
    #[serde(default)]
    pub grading: Vec<Component>,
    /// The percent they aim for in this subject.
    pub target: Option<f64>,
}

impl Plan {
    /// Numbers new items (empty id) after the highest one already used, so
    /// ids stay stable as items are added and removed.
    pub fn assign_ids(&mut self) {
        let first = self.items.iter().filter_map(|i| i.id.parse::<u32>().ok()).max().map_or(1, |n| n + 1);
        for (n, item) in (first..).zip(self.items.iter_mut().filter(|i| i.id.is_empty())) {
            item.id = n.to_string();
        }
    }
}

/// Where a subject stands on its grading system.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Tally {
    /// Sum of the weights; a finished grading system is 100.
    pub weight_total: f64,
    /// Weighted percent earned so far, out of the scored weights.
    pub earned: f64,
    pub scored_weight: f64,
    /// `earned` scaled to what the scored parts allow: the percent to date.
    pub standing: Option<f64>,
    /// PUP's grade for `standing`.
    pub equivalent: Option<f64>,
    /// The average needed on the unscored parts for `target` percent.
    pub needed: Option<f64>,
    pub target: f64,
}

fn round1(x: f64) -> f64 {
    (x * 10.0).round() / 10.0
}

/// PUP's usual table from a percent to a grade: 97 and up is 1.00, each
/// three points down is a quarter step, 75 is 3.00, below that 5.00.
/// Professors can use their own; this is the common one.
pub fn equivalent(percent: f64) -> f64 {
    const TABLE: [(f64, f64); 9] = [(97.0, 1.0), (94.0, 1.25), (91.0, 1.5), (88.0, 1.75), (85.0, 2.0), (82.0, 2.25), (79.0, 2.5), (76.0, 2.75), (75.0, 3.0)];
    let p = percent.round();
    TABLE.iter().find(|(min, _)| p >= *min).map_or(5.0, |(_, g)| *g)
}

pub fn tally(components: &[Component], target: f64) -> Tally {
    let weight_total: f64 = components.iter().map(|c| c.weight).sum();
    let scored: Vec<&Component> = components.iter().filter(|c| c.score.is_some()).collect();
    let scored_weight: f64 = scored.iter().map(|c| c.weight).sum();
    let earned: f64 = scored.iter().map(|c| c.score.unwrap_or(0.0) * c.weight / 100.0).sum();
    let standing = (scored_weight > 0.0).then(|| round1(earned / scored_weight * 100.0));
    let remaining = weight_total - scored_weight;
    let needed = (remaining > 0.0).then(|| round1((target - earned) / remaining * 100.0));
    Tally { weight_total, earned: round1(earned), scored_weight, standing, equivalent: standing.map(equivalent), needed, target }
}

/// Items not done, dated from `today` through `days` days on, soonest first.
pub fn due(items: &[(String, Item)], today: Date, days: i64) -> Vec<(String, Item)> {
    let last = today.add_days(days - 1);
    let mut out: Vec<(String, Item)> =
        items.iter().filter(|(_, i)| !i.done && i.kind != Kind::Lecture && i.date.is_some_and(|d| d >= today && d <= last)).cloned().collect();
    out.sort_by_key(|(_, i)| i.date);
    out
}

/// A heads-up the evening before each dated quiz, exam and project that is
/// not done, at `minute` (7 PM by default), for the next `days` days.
pub fn deadline_reminders(items: &[(String, Item)], now: Moment, minute: u16, days: i64) -> Vec<Reminder> {
    let mut out: Vec<Reminder> = items
        .iter()
        .filter(|(_, i)| !i.done && i.kind != Kind::Lecture)
        .filter_map(|(code, i)| {
            let date = i.date?.add_days(-1);
            let later = date > now.date || (date == now.date && minute > now.minute);
            (later && date < now.date.add_days(days)).then(|| Reminder {
                id: reminder_id(&format!("due:{code}:{}:{}", i.id, i.topic)),
                date,
                minute,
                title: format!("{} tomorrow", match i.kind {
                    Kind::Quiz => "Quiz",
                    Kind::Exam => "Exam",
                    _ => "Due",
                }),
                body: format!("{} · {code}", i.topic),
            })
        })
        .collect();
    out.sort_by_key(|r| (r.date, r.minute));
    out
}

const MONTHS: [&str; 12] = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"];

/// A month and day with no year lands on the year that puts it no more than
/// two months before `today`, since outlines run forward from the term start.
fn with_year(m: u8, d: u8, today: Date) -> Option<Date> {
    if !(1..=12).contains(&m) || !(1..=31).contains(&d) {
        return None;
    }
    let this = Date::new(today.y, m, d);
    Some(if this < today.add_days(-60) { Date::new(today.y + 1, m, d) } else { this })
}

fn find_date(line: &str, today: Date) -> Option<Date> {
    let words: Vec<String> = line.split(|c: char| c.is_whitespace() || c == ',' || c == '(' || c == ')').filter(|w| !w.is_empty()).map(str::to_lowercase).collect();
    for (i, w) in words.iter().enumerate() {
        if let Ok(d) = w.parse::<Date>() {
            return Some(d);
        }
        if let Some((m, d)) = w.split_once('/') {
            if let (Ok(m), Ok(d)) = (m.parse::<u8>(), d.trim_end_matches(|c: char| !c.is_ascii_digit()).parse::<u8>()) {
                return with_year(m, d, today);
            }
        }
        if let Some(m) = MONTHS.iter().position(|mo| w.len() >= 3 && w.starts_with(mo)) {
            let day = words.get(i + 1).and_then(|n| n.trim_end_matches(|c: char| !c.is_ascii_digit()).parse::<u8>().ok());
            if let Some(d) = day {
                return with_year(m as u8 + 1, d, today);
            }
        }
    }
    None
}

fn find_week(line: &str) -> Option<u16> {
    let lower = line.to_lowercase();
    let mut words = lower.split(|c: char| !c.is_ascii_alphanumeric()).filter(|w| !w.is_empty()).peekable();
    while let Some(w) = words.next() {
        if w == "week" || w == "wk" {
            return words.peek().and_then(|n| n.parse().ok());
        }
        if let Some(n) = w.strip_prefix("week").or_else(|| w.strip_prefix("wk")) {
            if let Ok(n) = n.parse() {
                return Some(n);
            }
        }
    }
    None
}

fn find_kind(line: &str) -> Kind {
    let l = line.to_lowercase();
    if ["exam", "midterm", "finals", "final term", "prelim"].iter().any(|k| l.contains(k)) {
        Kind::Exam
    } else if ["quiz", "long test", "seatwork"].iter().any(|k| l.contains(k)) {
        Kind::Quiz
    } else if ["project", "paper", "report", "presentation", "deadline", "submission", "due"].iter().any(|k| l.contains(k)) {
        Kind::Project
    } else {
        Kind::Lecture
    }
}

/// A pasted outline, one item per line: the week ("Week 3", "Wk3"), a date
/// ("Sep 30", "9/30", "2026-09-30") and the kind (quiz, exam, project, else a
/// lecture) are read from the line; the rest is the topic. A line that names
/// a week sets it for the lines under it too.
pub fn parse_outline(text: &str, today: Date) -> Vec<Item> {
    let mut current_week = None;
    let mut out = vec![];
    for raw in text.lines() {
        let line = raw.trim().trim_start_matches(['-', '*', '•', '·']).trim();
        if line.is_empty() {
            continue;
        }
        let week = find_week(line);
        let topic = line
            .split([':', '–', '—', '|', '\t'])
            .map(str::trim)
            .filter(|p| find_week(p).is_none() || p.split_whitespace().count() > 2)
            .collect::<Vec<_>>()
            .join(" · ");
        let topic = topic.trim_start_matches(['-', ' ']).trim().to_string();
        if week.is_some() {
            current_week = week;
            if topic.is_empty() {
                continue;
            }
        }
        out.push(Item {
            id: String::new(),
            topic: if topic.is_empty() { line.to_string() } else { topic },
            kind: find_kind(line),
            week: current_week,
            date: find_date(line, today),
            done: false,
        });
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn c(name: &str, weight: f64, score: Option<f64>) -> Component {
        Component { name: name.into(), weight, score }
    }

    #[test]
    fn pup_equivalents_step_every_three_points() {
        let got: Vec<f64> = [100.0, 97.0, 96.4, 94.0, 90.0, 85.0, 76.0, 75.0, 74.4, 40.0].map(equivalent).to_vec();
        assert_eq!(got, [1.0, 1.0, 1.25, 1.25, 1.75, 2.0, 2.75, 3.0, 5.0, 5.0]);
    }

    #[test]
    fn tally_scales_the_standing_and_solves_for_the_rest() {
        let comps = [c("Quizzes", 20.0, Some(90.0)), c("Midterm", 30.0, Some(80.0)), c("Finals", 30.0, None), c("Project", 20.0, None)];
        let t = tally(&comps, 90.0);
        assert_eq!((t.weight_total, t.scored_weight, t.earned), (100.0, 50.0, 42.0));
        assert_eq!((t.standing, t.equivalent, t.needed), (Some(84.0), Some(2.25), Some(96.0)));
        let done = tally(&[c("All", 100.0, Some(88.0))], 90.0);
        assert_eq!((done.standing, done.needed), (Some(88.0), None));
        assert_eq!(tally(&[], 90.0).standing, None);
    }

    #[test]
    fn outline_lines_become_items() {
        let today = Date::new(2026, 9, 28);
        let text = "Week 1\n- Intro to data structures\n- Arrays\nWeek 2: Linked lists\nWk3 | Quiz 1 on lists (Oct 9)\n12/18 Final Exam\nProject proposal due 2026-10-30\n\n";
        let items = parse_outline(text, today);
        let got: Vec<(&str, Kind, Option<u16>, Option<Date>)> = items.iter().map(|i| (i.topic.as_str(), i.kind, i.week, i.date)).collect();
        assert_eq!(
            got,
            [
                ("Intro to data structures", Kind::Lecture, Some(1), None),
                ("Arrays", Kind::Lecture, Some(1), None),
                ("Linked lists", Kind::Lecture, Some(2), None),
                ("Quiz 1 on lists (Oct 9)", Kind::Quiz, Some(3), Some(Date::new(2026, 10, 9))),
                ("12/18 Final Exam", Kind::Exam, Some(3), Some(Date::new(2026, 12, 18))),
                ("Project proposal due 2026-10-30", Kind::Project, Some(3), Some(Date::new(2026, 10, 30))),
            ]
        );
    }

    #[test]
    fn a_first_line_with_week_and_topic_is_kept() {
        let items = parse_outline("Week 1: Arrays\nQuiz 1 on arrays Sep 30\nMidterm exam Oct 2", Date::new(2026, 9, 28));
        assert_eq!(items.iter().map(|i| (i.topic.as_str(), i.week)).collect::<Vec<_>>(), [("Arrays", Some(1)), ("Quiz 1 on arrays Sep 30", Some(1)), ("Midterm exam Oct 2", Some(1))]);
    }

    #[test]
    fn a_month_without_a_year_rolls_into_next_year_after_the_term_turns() {
        assert_eq!(find_date("Jan 12 exam", Date::new(2026, 11, 20)), Some(Date::new(2027, 1, 12)));
        assert_eq!(find_date("Sep 1 intro", Date::new(2026, 9, 28)), Some(Date::new(2026, 9, 1)));
        assert_eq!(find_date("no date here", Date::new(2026, 9, 28)), None);
    }

    #[test]
    fn deadlines_remind_the_evening_before() {
        let item = |id: &str, topic: &str, kind: Kind, d: u8, done: bool| ("COMP 20073".to_string(), Item { id: id.into(), topic: topic.into(), kind, week: None, date: Some(Date::new(2026, 10, d)), done });
        let items = [
            item("1", "Quiz 2", Kind::Quiz, 3, false),
            item("2", "Trees", Kind::Lecture, 3, false),
            item("3", "Midterm", Kind::Exam, 2, false),
            item("4", "Old quiz", Kind::Quiz, 4, true),
            item("5", "Paper", Kind::Project, 20, false),
        ];
        let now = Moment { date: Date::new(2026, 10, 1), minute: 20 * 60 };
        let got: Vec<(String, u16, String, String)> = deadline_reminders(&items, now, 19 * 60, 7).into_iter().map(|r| (r.date.to_string(), r.minute, r.title, r.body)).collect();
        assert_eq!(got, [("2026-10-02".into(), 1140, "Quiz tomorrow".into(), "Quiz 2 · COMP 20073".into())]);
        let earlier = Moment { date: Date::new(2026, 10, 1), minute: 8 * 60 };
        assert_eq!(deadline_reminders(&items, earlier, 19 * 60, 7).len(), 2);
    }

    #[test]
    fn new_items_get_the_next_free_ids() {
        let item = |id: &str| Item { id: id.into(), topic: "t".into(), kind: Kind::Lecture, week: None, date: None, done: false };
        let mut plan = Plan { items: vec![item("3"), item(""), item("1"), item("")], ..Default::default() };
        plan.assign_ids();
        assert_eq!(plan.items.iter().map(|i| i.id.as_str()).collect::<Vec<_>>(), ["3", "4", "1", "5"]);
    }

    #[test]
    fn due_lists_undone_deadlines_in_the_window() {
        let item = |topic: &str, kind: Kind, d: u8, done: bool| ("A".to_string(), Item { id: topic.into(), topic: topic.into(), kind, week: None, date: Some(Date::new(2026, 10, d)), done });
        let items = [item("later", Kind::Exam, 20, false), item("quiz", Kind::Quiz, 3, false), item("done", Kind::Quiz, 2, true), item("talk", Kind::Lecture, 2, false), item("paper", Kind::Project, 1, false)];
        let got: Vec<String> = due(&items, Date::new(2026, 10, 1), 7).into_iter().map(|(_, i)| i.topic).collect();
        assert_eq!(got, ["paper", "quiz"]);
    }
}
