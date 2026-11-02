//! What a student's own words say about a day and a class: "quiz COMP fri",
//! "Exam sa Lunes", "report on 10/24". Rules only; the model never computes
//! dates. LAR's intents and the deadline quick add (spec 041) both read these.

use crate::{model::Weekday, today::Date};

pub fn words(msg: &str) -> Vec<String> {
    msg.to_lowercase().split(|c: char| !c.is_alphanumeric()).filter(|w| !w.is_empty()).map(String::from).collect()
}

/// The one subject a message is about: its code ("MATH 101" or "math101"),
/// the letters of its code ("math"), or a word of its description
/// ("calculus"). None when it names none or more than one.
/// `subjects` is (code, description).
pub fn subject_in(msg: &str, subjects: &[(String, String)]) -> Option<String> {
    let w = words(msg);
    let squashed = w.concat();
    let letters = |code: &str| code.chars().take_while(|c| c.is_alphabetic()).collect::<String>().to_lowercase();
    let only = |hit: Vec<&String>| (hit.len() == 1).then(|| hit[0].clone());
    let key = |c: &str| c.to_lowercase().replace(' ', "");
    let hits: Vec<&String> = subjects.iter().map(|(c, _)| c).filter(|c| squashed.contains(&key(c))).collect();
    // "math 101" also contains "math1": the longer code is the one named.
    let by_code = hits.iter().copied().filter(|c| !hits.iter().any(|o| key(o) != key(c) && key(o).contains(&key(c)))).collect();
    only(by_code)
        .or_else(|| only(subjects.iter().map(|(c, _)| c).filter(|c| letters(c).len() >= 3 && w.contains(&letters(c))).collect()))
        .or_else(|| only(subjects.iter().filter(|(_, d)| words(d).iter().any(|dw| dw.chars().count() >= 5 && w.contains(dw))).map(|(c, _)| c).collect()))
}

/// A day the message names ("bukas", "tomorrow", "sa Lunes", "fri",
/// "Oct 24", "10/24"), or None when it names none or an unclear one.
pub fn resolve_when(msg: &str, today: Date) -> Option<Date> {
    when_in(msg, today).map(|(d, _)| d)
}

/// `resolve_when`, plus which whitespace-separated tokens of `msg` named the
/// day, so the quick add can drop them from the title.
pub fn when_in(msg: &str, today: Date) -> Option<(Date, Vec<usize>)> {
    let t: Vec<String> = msg.split_whitespace().map(token).collect();
    relative(&t, today).or_else(|| explicit(&t, today))
}

/// A token as a date word: lowercase, leading punctuation dropped, cut at the
/// first character that is neither a letter, a digit nor `/` ("Fri," "(Lunes)" "Monday's").
fn token(raw: &str) -> String {
    raw.to_lowercase().trim_start_matches(|c: char| !c.is_alphanumeric()).chars().take_while(|c| c.is_alphanumeric() || *c == '/').collect()
}

/// Today, tomorrow and weekdays: the first one named wins.
fn relative(t: &[String], today: Date) -> Option<(Date, Vec<usize>)> {
    for (i, x) in t.iter().enumerate() {
        let day = match x.as_str() {
            "today" | "ngayon" | "mamaya" | "tonight" => return Some((today, vec![i])),
            "tomorrow" | "bukas" | "tmrw" | "tom" => return Some((today.add_days(1), vec![i])),
            "makalawa" => return Some((today.add_days(2), vec![i])),
            "monday" | "mon" | "lunes" | "lun" => Weekday::Monday,
            "tuesday" | "tue" | "tues" | "martes" => Weekday::Tuesday,
            "wednesday" | "wed" | "miyerkules" | "miy" => Weekday::Wednesday,
            "thursday" | "thu" | "thur" | "thurs" | "huwebes" | "huw" => Weekday::Thursday,
            "friday" | "fri" | "biyernes" | "biy" => Weekday::Friday,
            "saturday" | "sat" | "sabado" | "sab" => Weekday::Saturday,
            "sunday" | "sun" => Weekday::Sunday,
            // "linggo" also means "week": only "sa linggo" is Sunday.
            "linggo" if i > 0 && t[i - 1] == "sa" => Weekday::Sunday,
            _ => continue,
        };
        let ahead = (i64::from(day.number()) - i64::from(today.weekday().number())).rem_euclid(7);
        return Some((today.add_days(if ahead == 0 { 7 } else { ahead }), vec![i]));
    }
    None
}

const MONTHS: [&[&str]; 12] = [
    &["jan", "january", "enero"],
    &["feb", "february", "pebrero"],
    &["mar", "march", "marso"],
    &["apr", "april", "abril"],
    &["may", "mayo"],
    &["jun", "june", "hunyo"],
    &["jul", "july", "hulyo"],
    &["aug", "august", "agosto"],
    &["sep", "sept", "september", "setyembre"],
    &["oct", "october", "oktubre"],
    &["nov", "november", "nobyembre"],
    &["dec", "december", "disyembre"],
];

fn month(w: &str) -> Option<u8> {
    MONTHS.iter().position(|names| names.contains(&w)).map(|i| i as u8 + 1)
}

fn valid(y: i32, m: u8, d: u8) -> Option<Date> {
    let x = Date::new(y, m, d);
    ((1..=12).contains(&m) && d >= 1 && Date::from_days(x.days()) == x).then_some(x)
}

/// The next `m`/`d` from today on; a day already past this year is next year's.
fn upcoming(m: u8, d: u8, today: Date) -> Option<Date> {
    valid(today.y, m, d).and_then(|x| if x < today { valid(today.y + 1, m, d) } else { Some(x) })
}

/// "Oct 24", "24 Oct", "10/24", "10/24/2026". A month word counts only
/// next to a day number, so "may quiz" is not May.
fn explicit(t: &[String], today: Date) -> Option<(Date, Vec<usize>)> {
    let day = |i: usize| t.get(i).and_then(|w| w.parse::<u8>().ok());
    for (i, w) in t.iter().enumerate() {
        if w.contains('/') {
            let p: Vec<&str> = w.split('/').collect();
            let n = |k: usize| p.get(k).and_then(|x| x.parse::<i32>().ok());
            let found = match (p.len(), n(0), n(1), n(2)) {
                (2, Some(m), Some(d), _) => upcoming(m as u8, d as u8, today),
                (3, Some(m), Some(d), Some(y)) => valid(if y < 100 { 2000 + y } else { y }, m as u8, d as u8),
                _ => None,
            };
            if let Some(x) = found {
                return Some((x, vec![i]));
            }
        }
        if let Some(m) = month(w) {
            if let Some(x) = day(i + 1).and_then(|d| upcoming(m, d, today)) {
                return Some((x, vec![i, i + 1]));
            }
            if let Some(x) = i.checked_sub(1).and_then(day).and_then(|d| upcoming(m, d, today)) {
                return Some((x, vec![i - 1, i]));
            }
        }
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;

    const TUE: Date = Date { y: 2026, m: 11, d: 3 };

    #[test]
    fn short_weekdays_and_filipino() {
        for (msg, want) in [("quiz COMP fri", 6), ("Exam sa Lunes", 9), ("due Wed.", 4), ("(Thu) report", 5), ("sab", 7), ("tue", 10)] {
            assert_eq!(resolve_when(msg, TUE), Some(Date::new(2026, 11, want)), "{msg}");
        }
    }

    #[test]
    fn month_and_numeric_dates() {
        assert_eq!(when_in("report on 11/24", TUE), Some((Date::new(2026, 11, 24), vec![2])));
        assert_eq!(when_in("Lab 4 due Nov 20", TUE), Some((Date::new(2026, 11, 20), vec![3, 4])));
        assert_eq!(resolve_when("essay, 5 Dec", TUE), Some(Date::new(2026, 12, 5)));
        assert_eq!(resolve_when("final project 1/15", TUE), Some(Date::new(2027, 1, 15)), "a past day this year is next year's");
        assert_eq!(resolve_when("thesis 2/1/2027", TUE), Some(Date::new(2027, 2, 1)));
        assert_eq!(resolve_when("quiz on 2/30", TUE), None, "no such day");
    }

    #[test]
    fn a_month_word_needs_a_day() {
        assert_eq!(resolve_when("may quiz tayo", TUE), None);
        assert_eq!(resolve_when("May 24 recital", TUE), Some(Date::new(2027, 5, 24)));
    }

    #[test]
    fn a_relative_day_beats_a_number() {
        assert_eq!(resolve_when("May 2 quizzes bukas", TUE), Some(Date::new(2026, 11, 4)));
    }
}
