//! Flashcards with spaced repetition (FSRS-5 with its published default
//! weights), plus the round-building and grading the study modes need.
//!
//! Time is Unix seconds from the caller; nothing here reads a clock.

use crate::today::Date;
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Rating {
    Again = 1,
    Hard = 2,
    Good = 3,
    Easy = 4,
}

/// What FSRS knows about one card.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub struct Memory {
    /// Unix seconds; due now or earlier means study it.
    pub due: i64,
    pub stability: f64,
    pub difficulty: f64,
    pub reps: u32,
    pub lapses: u32,
    pub last_review: Option<i64>,
}

impl Memory {
    /// A new card is due the moment it exists.
    pub fn new(now: i64) -> Memory {
        Memory { due: now, stability: 0.0, difficulty: 0.0, reps: 0, lapses: 0, last_review: None }
    }
}

const W: [f64; 19] = [
    0.40255, 1.18385, 3.173, 15.69105, 7.1949, 0.5345, 1.4604, 0.0046, 1.54575, 0.1192, 1.01925, 1.9395, 0.11, 0.29605, 2.2698, 0.2315, 2.9898, 0.51655, 0.6621,
];
const DECAY: f64 = -0.5;
const FACTOR: f64 = 19.0 / 81.0;
const DAY: i64 = 86_400;
/// A lapsed card comes back in the same session.
const RELEARN: i64 = 10 * 60;

fn init_difficulty(g: f64) -> f64 {
    (W[4] - (W[5] * (g - 1.0)).exp() + 1.0).clamp(1.0, 10.0)
}

fn retrievability(elapsed_days: f64, stability: f64) -> f64 {
    (1.0 + FACTOR * elapsed_days / stability).powf(DECAY)
}

/// The card's memory after the student rates it at `now`.
pub fn review(m: &Memory, rating: Rating, now: i64) -> Memory {
    let g = rating as u8 as f64;
    let (stability, difficulty) = if m.reps == 0 {
        (W[rating as usize - 1].max(0.1), init_difficulty(g))
    } else {
        let d = m.difficulty + -W[6] * (g - 3.0) * (10.0 - m.difficulty) / 9.0;
        let d = (W[7] * init_difficulty(4.0) + (1.0 - W[7]) * d).clamp(1.0, 10.0);
        let elapsed = (now - m.last_review.unwrap_or(now)).max(0) as f64 / DAY as f64;
        let s = m.stability;
        let s = if elapsed < 1.0 {
            s * (W[17] * (g - 3.0 + W[18])).exp()
        } else {
            let r = retrievability(elapsed, s);
            if rating == Rating::Again {
                (W[11] * m.difficulty.powf(-W[12]) * ((s + 1.0).powf(W[13]) - 1.0) * (W[14] * (1.0 - r)).exp()).min(s)
            } else {
                let hard = if rating == Rating::Hard { W[15] } else { 1.0 };
                let easy = if rating == Rating::Easy { W[16] } else { 1.0 };
                s * (1.0 + W[8].exp() * (11.0 - m.difficulty) * s.powf(-W[9]) * ((W[10] * (1.0 - r)).exp() - 1.0) * hard * easy)
            }
        };
        (s.max(0.1), d)
    };
    // At the default 90% retention the next interval equals the stability.
    let due = if rating == Rating::Again { now + RELEARN } else { now + (stability.round().clamp(1.0, 36_500.0) as i64) * DAY };
    Memory {
        due,
        stability,
        difficulty,
        reps: m.reps + 1,
        lapses: m.lapses + u32::from(rating == Rating::Again && m.reps > 0),
        last_review: Some(now),
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Card {
    pub id: String,
    pub front: String,
    pub back: String,
    /// Other right answers for typed recall.
    #[serde(default)]
    pub accepted: Vec<String>,
    pub memory: Memory,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Deck {
    pub id: String,
    pub name: String,
    /// The subject code it belongs to, if any.
    pub subject: Option<String>,
    pub cards: Vec<Card>,
}

impl Deck {
    /// Numbers new cards (empty id) after the highest id in the deck and
    /// makes them due at `now`.
    pub fn settle_new_cards(&mut self, now: i64) {
        let first = self.cards.iter().filter_map(|c| c.id.parse::<u32>().ok()).max().map_or(1, |n| n + 1);
        for (n, card) in (first..).zip(self.cards.iter_mut().filter(|c| c.id.is_empty())) {
            card.id = n.to_string();
            card.memory = Memory::new(now);
        }
    }

    pub fn due(&self, now: i64) -> usize {
        self.cards.iter().filter(|c| c.memory.due <= now).count()
    }
}

/// The streak counts calendar days with at least one review.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct Stats {
    pub streak: u32,
    pub last_day: Option<Date>,
    pub reviews_today: u32,
    pub total_reviews: u32,
}

pub fn count_review(s: &Stats, today: Date) -> Stats {
    let (streak, reviews_today) = match s.last_day {
        Some(d) if d == today => (s.streak, s.reviews_today + 1),
        Some(d) if d.add_days(1) == today => (s.streak + 1, 1),
        _ => (1, 1),
    };
    Stats { streak, last_day: Some(today), reviews_today, total_reviews: s.total_reviews + 1 }
}

/// The streak as of `today`: it lapses once a whole day passes unstudied.
pub fn current_streak(s: &Stats, today: Date) -> u32 {
    match s.last_day {
        Some(d) if d == today || d.add_days(1) == today => s.streak,
        _ => 0,
    }
}

/// Cards pasted as one per line, "front - back": the first " - ", " – ",
/// tab, " = " or ": " splits the line. Lines without one are skipped.
pub fn parse_cards(text: &str) -> Vec<(String, String)> {
    text.lines()
        .filter_map(|line| {
            let line = line.trim();
            ["\t", " - ", " – ", " — ", " = ", ": "]
                .iter()
                .filter_map(|sep| line.find(sep).map(|i| (i, sep.len())))
                .min_by_key(|(i, _)| *i)
                .map(|(i, n)| (line[..i].trim().to_string(), line[i + n..].trim().to_string()))
        })
        .filter(|(f, b)| !f.is_empty() && !b.is_empty())
        .collect()
}

fn normalize(s: &str) -> String {
    s.split_whitespace().collect::<Vec<_>>().join(" ").to_lowercase().trim_end_matches(['.', '!', '?']).to_string()
}

/// Typed recall is graded strictly: the front or an accepted answer,
/// ignoring case, extra spaces and a final period. A near miss counts
/// wrong; predictable beats forgiving.
pub fn is_correct(typed: &str, card: &Card) -> bool {
    let t = normalize(typed);
    !t.is_empty() && std::iter::once(&card.front).chain(&card.accepted).any(|a| normalize(a) == t)
}

/// Up to `count` other cards' backs, different from this card's, as wrong
/// options for a multiple-choice round. `seed` rotates which ones.
pub fn distractors(cards: &[Card], index: usize, count: usize, seed: usize) -> Vec<String> {
    let own = normalize(&cards[index].back);
    let mut seen = vec![own];
    let mut out = vec![];
    let n = cards.len();
    for k in 1..n {
        let back = &cards[(index + seed + k) % n].back;
        let key = normalize(back);
        if !seen.contains(&key) {
            seen.push(key);
            out.push(back.clone());
            if out.len() == count {
                break;
            }
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    const T0: i64 = 1_790_000_000;

    fn card(front: &str, back: &str) -> Card {
        Card { id: front.into(), front: front.into(), back: back.into(), accepted: vec![], memory: Memory::new(T0) }
    }

    fn days(m: &Memory, from: i64) -> f64 {
        (m.due - from) as f64 / DAY as f64
    }

    #[test]
    fn a_new_card_starts_from_the_default_weights() {
        let good = review(&Memory::new(T0), Rating::Good, T0);
        assert_eq!((good.stability, days(&good, T0), good.reps), (3.173, 3.0, 1));
        assert!((good.difficulty - 5.2825).abs() < 1e-3, "{}", good.difficulty);
        let spans: Vec<f64> = [Rating::Hard, Rating::Good, Rating::Easy].map(|r| days(&review(&Memory::new(T0), r, T0), T0)).to_vec();
        assert_eq!(spans, [1.0, 3.0, 16.0]);
        let again = review(&Memory::new(T0), Rating::Again, T0);
        assert_eq!((again.due - T0, again.lapses), (600, 0));
    }

    #[test]
    fn remembering_on_time_spaces_the_card_further_out() {
        let first = review(&Memory::new(T0), Rating::Good, T0);
        let second = review(&first, Rating::Good, first.due);
        let third = review(&second, Rating::Good, second.due);
        assert!(days(&second, first.due) > 3.0 * 2.0, "{}", days(&second, first.due));
        assert!(days(&third, second.due) > days(&second, first.due));
        let easy = review(&first, Rating::Easy, first.due);
        let hard = review(&first, Rating::Hard, first.due);
        assert!(easy.stability > second.stability && second.stability > hard.stability);
        assert!(easy.difficulty < second.difficulty && second.difficulty < hard.difficulty);
    }

    #[test]
    fn forgetting_counts_a_lapse_and_shrinks_stability() {
        let first = review(&Memory::new(T0), Rating::Good, T0);
        let second = review(&first, Rating::Good, first.due);
        let lapse = review(&second, Rating::Again, second.due);
        assert_eq!((lapse.lapses, lapse.due - second.due), (1, 600));
        assert!(lapse.stability < second.stability);
        assert!(lapse.difficulty > second.difficulty);
    }

    #[test]
    fn the_streak_counts_consecutive_days() {
        let d = |n: u8| Date::new(2026, 10, n);
        let s = count_review(&Stats::default(), d(1));
        let s = count_review(&s, d(1));
        assert_eq!((s.streak, s.reviews_today, s.total_reviews), (1, 2, 2));
        let s = count_review(&s, d(2));
        assert_eq!((s.streak, s.reviews_today), (2, 1));
        assert_eq!([current_streak(&s, d(2)), current_streak(&s, d(3)), current_streak(&s, d(4))], [2, 2, 0]);
        assert_eq!(count_review(&s, d(5)).streak, 1);
    }

    #[test]
    fn pasted_lines_become_cards() {
        let got = parse_cards("Stack - LIFO list\nQueue: FIFO list\nno separator here\nBig-O\t growth rate\n - empty front\nHash = key to slot");
        let pairs: Vec<(&str, &str)> = got.iter().map(|(f, b)| (f.as_str(), b.as_str())).collect();
        assert_eq!(pairs, [("Stack", "LIFO list"), ("Queue", "FIFO list"), ("Big-O", "growth rate"), ("Hash", "key to slot")]);
    }

    #[test]
    fn typed_answers_match_the_front_or_an_accepted_answer() {
        let mut c = card("Binary search tree", "Left smaller, right larger");
        c.accepted.push("BST".into());
        assert!(is_correct("  binary SEARCH tree. ", &c));
        assert!(is_correct("bst", &c));
        assert!(!is_correct("binary tree", &c));
        assert!(!is_correct("", &c));
    }

    #[test]
    fn distractors_are_other_distinct_backs() {
        let cards = [card("a", "1"), card("b", "2"), card("c", "2"), card("d", "1 "), card("e", "3")];
        assert_eq!(distractors(&cards, 0, 3, 0), ["2", "3"]);
        assert_eq!(distractors(&cards, 4, 2, 0), ["1", "2"]);
    }
}
