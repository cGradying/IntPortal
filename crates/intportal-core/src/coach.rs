//! The coach: one short, factual nudge for Today, picked from what the app
//! already knows. It never guesses and never nags about the same thing
//! twice in a row; the student can dismiss it for the day.

use serde::{Deserialize, Serialize};

/// What the coach can see right now.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct Signals {
    /// Quizzes, exams and projects due today or tomorrow: (subject, topic).
    pub due_soon: Vec<(String, String)>,
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
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum Nudge {
    Deadline { subject: String, topic: String, more: usize },
    KeepStreak { streak: u32, cards: usize },
    UseTheGap { minutes: u16, cards: usize },
    CardsDue { cards: usize },
    Target { needed: f64, target: f64 },
    DayOff,
}

impl Nudge {
    /// Friendly, clear first, a little Taglish.
    pub fn line(&self) -> String {
        match self {
            Nudge::Deadline { subject, topic, more: 0 } => format!("{topic} ({subject}) is due by tomorrow. Kaya mo 'yan."),
            Nudge::Deadline { subject, topic, more } => format!("{topic} ({subject}) and {more} more due by tomorrow. One at a time."),
            Nudge::KeepStreak { streak, cards } => format!("{streak}-day streak. {cards} {} keep it alive today.", if *cards == 1 { "card" } else { "cards" }),
            Nudge::UseTheGap { minutes, cards } => {
                format!("{} free before your next class: enough for {cards} {}.", span(*minutes), if *cards == 1 { "card" } else { "cards" })
            }
            Nudge::CardsDue { cards } => format!("{cards} {} due. About {} minutes.", if *cards == 1 { "card" } else { "cards" }, (cards / 4).max(1)),
            Nudge::Target { needed, target } => format!("For a {target:.2} this term, aim for {needed:.2} or better on what's left."),
            Nudge::DayOff => "Nothing due. Rest up, Isko.".into(),
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
    let candidates = [
        s.due_soon.first().map(|(subject, topic)| Nudge::Deadline { subject: subject.clone(), topic: topic.clone(), more: s.due_soon.len() - 1 }),
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
        s.due_soon = vec![("COMP 20073".into(), "Quiz 2".into()), ("GEED 10053".into(), "Essay".into())];
        let n = pick(&s, &[]).unwrap();
        assert_eq!(n.line(), "Quiz 2 (COMP 20073) and 1 more due by tomorrow. One at a time.");
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
}
