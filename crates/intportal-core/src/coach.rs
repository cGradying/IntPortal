//! The coach: one short, factual nudge for Today, picked from what the app
//! already knows. It never guesses and never nags about the same thing
//! twice in a row; the student can dismiss it for the day.

use crate::deadline::Deadline;
use crate::today::{clock, Gap};
use std::collections::BTreeMap;
use serde::{Deserialize, Serialize};

/// What the coach can see right now.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct Signals {
    /// Deadlines overdue or due by tomorrow, from the one list (spec 041), soonest first.
    pub due_soon: Vec<Deadline>,
    /// Flashcards due across decks.
    pub cards_due: usize,
    pub study_streak: u32,
    /// Whether the student has reviewed any card today.
    pub studied_today: bool,
    /// Free minutes still ahead today, between classes.
    pub free_minutes: u16,
    /// The average the unposted subjects need for the target GPA, if one
    /// is set and still reachable.
    pub needed_average: Option<(f64, f64)>,
    /// Classes today still ahead.
    pub classes_left: usize,
    /// The next free gap today, in progress or ahead (spec 042 C1).
    pub gap: Option<Gap>,
    /// The soonest deadline overdue or due within three days, ready to name (C2).
    pub plan_step: Option<PlanStep>,
    /// Flashcards due per subject code.
    pub cards_by_subject: BTreeMap<String, usize>,
}

/// The deadline a plan starts with.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct PlanStep {
    pub id: String,
    pub title: String,
    /// "due tonight", "past due" (`deadline::when_word`).
    pub when: String,
    pub subject: Option<String>,
    pub url: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum Nudge {
    /// `url` opens an eMabini deadline where it lives; `overdue` when its time passed.
    Deadline { subject: String, topic: String, more: usize, overdue: bool, url: Option<String> },
    KeepStreak { streak: u32, cards: usize },
    UseTheGap { minutes: u16, cards: usize },
    CardsDue { cards: usize },
    Target { needed: f64, target: f64 },
    DayOff,
    /// One gap, one plan (spec 042 C2): the deadline first, then cards that fit.
    Plan { from: u16, to: u16, step: Option<PlanStep>, subject: Option<String>, cards: usize },
}

impl Nudge {
    /// Friendly, clear first, a little Taglish.
    pub fn line(&self) -> String {
        match self {
            Nudge::Deadline { subject, topic, overdue: true, .. } => format!("{topic} ({subject}) is past due. If it's done, mark it done."),
            Nudge::Deadline { subject, topic, more: 0, .. } => format!("{topic} ({subject}) is due by tomorrow. Kaya mo 'yan."),
            Nudge::Deadline { subject, topic, more, .. } => format!("{topic} ({subject}) and {more} more due by tomorrow. One at a time."),
            Nudge::KeepStreak { streak, cards } => format!("{streak}-day streak. {cards} {} keep it alive today.", if *cards == 1 { "card" } else { "cards" }),
            Nudge::UseTheGap { minutes, cards } => {
                format!("{} free before your next class: enough for {cards} {}.", span(*minutes), if *cards == 1 { "card" } else { "cards" })
            }
            Nudge::CardsDue { cards } => format!("{cards} {} due. About {} minutes.", if *cards == 1 { "card" } else { "cards" }, (cards / 4).max(1)),
            Nudge::Target { needed, target } => format!("For a {target:.2} this term, aim for {needed:.2} or better on what's left."),
            Nudge::DayOff => "Nothing due. Rest up, Isko.".into(),
            Nudge::Plan { from, to, step, subject, cards } => {
                let free = format!("Free {}–{}", clock(*from), clock(*to));
                let letters: String = subject.as_deref().map(|c| c.chars().take_while(|ch| ch.is_alphabetic()).collect::<String>() + " ").unwrap_or_default();
                match (step, cards) {
                    (Some(st), 0) => format!("{free}: start {} ({}).", st.title, st.when),
                    (Some(st), n) => format!("{free}: start {} ({}), then {n} {letters}cards.", st.title, st.when),
                    (None, n) => format!("{free}: {n} cards fit. Kaya mo 'yan."),
                }
            }
        }
    }

    /// Stable per nudge and day, so a dismissal holds until something changes.
    pub fn key(&self) -> String {
        match self {
            Nudge::Deadline { topic, .. } => format!("deadline:{topic}"),
            Nudge::KeepStreak { streak, .. } => format!("streak:{streak}"),
            Nudge::UseTheGap { .. } => "gap".into(),
            Nudge::CardsDue { .. } => "cards".into(),
            Nudge::Target { target, .. } => format!("target:{target:.2}"),
            Nudge::DayOff => "rest".into(),
            Nudge::Plan { from, .. } => format!("plan:{from}"),
        }
    }
}

fn span(m: u16) -> String {
    match (m / 60, m % 60) {
        (0, m) => format!("{m}m"),
        (h, 0) => format!("{h}h"),
        (h, m) => format!("{h}h {m}m"),
    }
}

/// The one nudge worth saying, most urgent first: a deadline, then a streak
/// about to lapse, then a free gap that fits the due cards, then cards due,
/// then the grade target. `dismissed` holds the keys the student waved off
/// today.
pub fn pick(s: &Signals, dismissed: &[String]) -> Option<Nudge> {
    let cards_fit = |minutes: u16| usize::from(minutes / 30 * 8).min(s.cards_due);
    // C2–C5: while a gap of 30 minutes or more is ahead, it gets one plan.
    let plan = s.gap.filter(|g| g.minutes >= 30).and_then(|g| {
        let step = s.plan_step.clone();
        let subject = step.as_ref().and_then(|p| p.subject.clone()).filter(|c| s.cards_by_subject.get(c).is_some_and(|n| *n > 0));
        let pool = subject.as_ref().map_or(s.cards_due, |c| s.cards_by_subject[c]);
        let time = if step.is_some() { g.minutes / 2 } else { g.minutes };
        let cards = usize::from(time / 30 * 8).min(pool);
        (step.is_some() || cards > 0).then(|| Nudge::Plan { from: g.from, to: g.to, subject: subject.filter(|_| cards > 0), step, cards })
    });
    let candidates = [
        plan,
        s.due_soon.first().map(|d| Nudge::Deadline { subject: d.label().into(), topic: d.title.clone(), more: s.due_soon.len() - 1, overdue: d.overdue, url: d.url.clone() }),
        (s.study_streak > 0 && !s.studied_today && s.cards_due > 0).then(|| Nudge::KeepStreak { streak: s.study_streak, cards: s.cards_due.min(5) }),
        (s.free_minutes >= 30 && s.cards_due > 0 && s.classes_left > 0).then(|| Nudge::UseTheGap { minutes: s.free_minutes, cards: cards_fit(s.free_minutes) }),
        (s.cards_due > 0).then_some(Nudge::CardsDue { cards: s.cards_due }),
        s.needed_average.map(|(needed, target)| Nudge::Target { needed, target }),
        (s.due_soon.is_empty() && s.cards_due == 0 && s.classes_left == 0).then_some(Nudge::DayOff),
    ];
    candidates.into_iter().flatten().find(|n| !dismissed.contains(&n.key()))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sig() -> Signals {
        Signals { cards_due: 12, study_streak: 4, free_minutes: 90, classes_left: 2, ..Default::default() }
    }

    #[test]
    fn a_deadline_comes_first() {
        let mut s = sig();
        s.due_soon = vec![due("COMP 20073", "Quiz 2", false), due("GEED 10053", "Essay", false)];
        let n = pick(&s, &[]).unwrap();
        assert_eq!(n.line(), "Quiz 2 (COMP 20073) and 1 more due by tomorrow. One at a time.");
    }

    #[test]
    fn an_overdue_mabini_deadline_is_a_nudge_not_a_rest_day() {
        let s = Signals { due_soon: vec![due("Purposive Communication", "Reflection", true)], ..Default::default() };
        assert_eq!(pick(&s, &[]).unwrap().line(), "Reflection (Purposive Communication) is past due. If it's done, mark it done.");
    }

    fn due(label: &str, title: &str, overdue: bool) -> Deadline {
        use crate::deadline::{Due, Source};
        let date = crate::today::Date::new(2026, 11, 4);
        Deadline { id: title.into(), source: Source::Mabini, subject: None, course: Some(label.into()), title: title.into(), kind: crate::syllabus::Kind::Project, due: Due::Day(date), overdue, url: None }
    }

    #[test]
    fn a_streak_at_risk_beats_a_free_gap() {
        assert_eq!(pick(&sig(), &[]).unwrap().line(), "4-day streak. 5 cards keep it alive today.");
        let mut s = sig();
        s.studied_today = true;
        assert_eq!(pick(&s, &[]).unwrap().line(), "1h 30m free before your next class: enough for 12 cards.");
        s.free_minutes = 45;
        assert_eq!(pick(&s, &[]), Some(Nudge::UseTheGap { minutes: 45, cards: 8 }));
    }

    #[test]
    fn dismissing_moves_on_to_the_next_nudge() {
        let mut s = sig();
        s.studied_today = true;
        s.needed_average = Some((1.75, 1.5));
        let skip = ["gap".to_string(), "cards".to_string()];
        assert_eq!(pick(&s, &skip).unwrap().line(), "For a 1.50 this term, aim for 1.75 or better on what's left.");
    }

    #[test]
    fn a_clear_day_says_rest() {
        let s = Signals::default();
        assert_eq!(pick(&s, &[]).unwrap().line(), "Nothing due. Rest up, Isko.");
        assert_eq!(pick(&s, &["rest".into()]), None);
    }

    fn step(subject: Option<&str>) -> PlanStep {
        PlanStep { id: "mab:7".into(), title: "Lab 4".into(), when: "due tonight".into(), subject: subject.map(Into::into), url: None }
    }

    fn gapped() -> Signals {
        let mut s = sig();
        s.gap = Some(Gap { from: 780, to: 900, minutes: 120 });
        s.cards_by_subject = BTreeMap::from([("COMP 20073".to_string(), 10)]);
        s
    }

    #[test]
    fn c2_plan_picks_soonest_deadline_then_subject_cards() {
        let mut s = gapped();
        s.plan_step = Some(step(Some("COMP 20073")));
        assert_eq!(pick(&s, &[]), Some(Nudge::Plan { from: 780, to: 900, step: Some(step(Some("COMP 20073"))), subject: Some("COMP 20073".into()), cards: 10 }), "half of 2h fits 16, the subject has 10");
    }

    #[test]
    fn c3_plan_lines() {
        let mut s = gapped();
        s.plan_step = Some(step(Some("COMP 20073")));
        assert_eq!(pick(&s, &[]).unwrap().line(), "Free 1PM–3PM: start Lab 4 (due tonight), then 10 COMP cards.");
        s.plan_step = None;
        assert_eq!(pick(&s, &[]).unwrap().line(), "Free 1PM–3PM: 12 cards fit. Kaya mo 'yan.");
        s.cards_due = 0;
        s.plan_step = Some(step(None));
        assert_eq!(pick(&s, &[]).unwrap().line(), "Free 1PM–3PM: start Lab 4 (due tonight).");
    }

    #[test]
    fn c5_plan_outranks_deadline_while_gap_ahead() {
        let mut s = gapped();
        s.due_soon = vec![due("COMP 20073", "Lab 4", false)];
        s.plan_step = Some(step(Some("COMP 20073")));
        assert!(matches!(pick(&s, &[]), Some(Nudge::Plan { .. })));
        assert!(matches!(pick(&s, &["plan:780".into()]), Some(Nudge::Deadline { .. })), "dismissed for this gap");
    }

    #[test]
    fn c5_no_gap_keeps_old_nudges() {
        let mut s = sig();
        s.gap = Some(Gap { from: 780, to: 800, minutes: 20 });
        s.due_soon = vec![due("COMP 20073", "Lab 4", false)];
        assert!(matches!(pick(&s, &[]), Some(Nudge::Deadline { .. })));
    }
}
