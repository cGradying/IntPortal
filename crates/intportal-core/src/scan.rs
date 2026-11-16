//! Text read from a photo (spec 041 C19): the phone's OCR gives broken line
//! wraps, split words, stray marks and page furniture. `clean` fixes only that,
//! the same way every time, and never rewrites a word, number, code or date.
//! `S512`, `COMP 20073` and `11:59 PM` come out exactly as they went in.
use regex::Regex;
use std::{collections::HashMap, sync::OnceLock};

fn re(cell: &'static OnceLock<Regex>, p: &str) -> &'static Regex {
    cell.get_or_init(|| Regex::new(p).expect("scan pattern"))
}

/// "Page 3", "3 of 12", "- 3 -", "Page 3 of 12": page furniture, never content.
fn is_page_number(l: &str) -> bool {
    static R: OnceLock<Regex> = OnceLock::new();
    // A bare number is not matched here: it only counts at the very top or bottom of the photo.
    let marked = l.chars().any(|c| c.is_alphabetic() || "-–—/".contains(c));
    marked
        && re(
            &R,
            r"(?i)^[-–—\s]*(page\s*)?\d{1,3}(\s*(of|/)\s*\d{1,3})?[-–—\s]*$",
        )
        .is_match(l)
}

/// A bullet or a number that starts an item: the line before it never absorbs it.
fn is_item(l: &str) -> bool {
    static R: OnceLock<Regex> = OnceLock::new();
    re(&R, r"^(- |\d{1,2}[.)] |[a-zA-Z][.)] )").is_match(l)
}

/// A month, a numeric date or a time: lines that carry one stay on their own line.
fn has_date(l: &str) -> bool {
    static R: OnceLock<Regex> = OnceLock::new();
    re(&R, r"(?i)\b(jan|feb|mar|apr|may|jun|jul|aug|sep|sept|oct|nov|dec)[a-z]*\b|\b\d{1,2}[/-]\d{1,2}\b|\b\d{1,2}:\d{2}\b").is_match(l)
}

fn tidy_line(l: &str) -> String {
    static BULLET: OnceLock<Regex> = OnceLock::new();
    static SPACE: OnceLock<Regex> = OnceLock::new();
    static BEFORE: OnceLock<Regex> = OnceLock::new();
    let l: String = l
        .chars()
        .filter(|c| {
            !matches!(c, '\u{ad}' | '\u{200b}'..='\u{200d}' | '\u{feff}')
                && (!c.is_control() || *c == '\t')
        })
        .map(|c| match c {
            '‘' | '’' | '‚' | '′' => '\'',
            '“' | '”' | '„' | '″' => '"',
            c if c.is_whitespace() => ' ',
            c => c,
        })
        .collect();
    // Stray marks OCR makes of table edges and smudges, as words of their own.
    let l = l
        .split(' ')
        .filter(|w| w.is_empty() || !w.chars().all(|c| "|¦~^_`".contains(c)) || w.len() > 3)
        .collect::<Vec<_>>()
        .join(" ");
    let l = re(&SPACE, r" {2,}").replace_all(l.trim(), " ").into_owned();
    let l = re(&BULLET, r"^([•·●▪◦■□‣▸►○*]|[-–—])\s+")
        .replace(&l, "- ")
        .into_owned();
    re(&BEFORE, r"\s+([,.;!?])")
        .replace_all(&l, "$1")
        .into_owned()
}

/// The text of one photo, tidy. Blank lines stay as paragraph breaks and list
/// items stay on their own lines. Doing it twice changes nothing more.
pub fn clean(raw: &str) -> String {
    let lines: Vec<String> = raw
        .replace("\r\n", "\n")
        .replace('\r', "\n")
        .split('\n')
        .filter_map(|l| {
            let t = tidy_line(l);
            // A line that was only smudges is not a paragraph break.
            (!t.is_empty() || l.trim().is_empty()).then_some(t)
        })
        .collect();
    // Page furniture. A bare number only goes at the very top or bottom of the photo.
    let first = lines.iter().position(|l| !l.is_empty());
    let last = lines.iter().rposition(|l| !l.is_empty());
    let mut seen: HashMap<String, usize> = HashMap::new();
    for l in lines
        .iter()
        .filter(|l| l.chars().count() >= 6 && !l.starts_with("- "))
    {
        *seen.entry(l.to_lowercase()).or_default() += 1;
    }
    let lines: Vec<String> = lines
        .into_iter()
        .enumerate()
        .filter(|(i, l)| {
            let bare = !l.is_empty() && l.chars().all(|c| c.is_ascii_digit());
            let furniture = is_page_number(l)
                || (bare && l.len() <= 3 && (Some(*i) == first || Some(*i) == last))
                || seen.get(&l.to_lowercase()).is_some_and(|n| *n >= 3);
            let symbols = !l.is_empty() && !l.chars().any(char::is_alphanumeric);
            !furniture && !symbols
        })
        .map(|(_, l)| l)
        .collect();
    // ponytail: "full width" is the longest line of the photo; a ragged-right handout with one very long line joins less. Tune the 0.85 if it misjudges.
    let width = lines.iter().map(|l| l.chars().count()).max().unwrap_or(0);
    let mut out: Vec<String> = Vec::new();
    let mut blank = false;
    for l in lines {
        if l.is_empty() {
            blank = !out.is_empty();
            continue;
        }
        let join = !blank && out.last().is_some_and(|p: &String| continues(p, &l, width));
        if blank {
            out.push(String::new());
            blank = false;
        }
        match (join, out.last_mut()) {
            (true, Some(p)) => {
                if p.ends_with('-')
                    && !p.ends_with(" -")
                    && p.chars().rev().nth(1).is_some_and(char::is_alphanumeric)
                {
                    // Split by the wrap: "informa-" + "tion". A code's hyphen ("COMP-" + "20073") stays.
                    if l.starts_with(|c: char| c.is_lowercase()) {
                        p.pop();
                    }
                } else {
                    p.push(' ');
                }
                p.push_str(&l);
            }
            _ => out.push(l),
        }
    }
    out.join("\n")
}

/// Does `next` carry on the line `prev` wrapped from?
fn continues(prev: &str, next: &str, width: usize) -> bool {
    if prev.is_empty() || is_item(next) {
        return false;
    }
    let hyphenated = prev.ends_with('-')
        && !prev.ends_with(" -")
        && prev.chars().rev().nth(1).is_some_and(char::is_alphanumeric);
    if hyphenated {
        return true;
    }
    if next.starts_with(|c: char| c.is_lowercase()) {
        return true;
    }
    let ends = prev.ends_with(['.', '?', '!', ':', ';']);
    let full = prev.chars().count() * 100 >= width * 85 && prev.chars().count() >= 40;
    !ends && full && !has_date(next) && !has_date(prev)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn same(raw: &str, want: &str) {
        let got = clean(raw);
        assert_eq!(got, want, "from {raw:?}");
        assert_eq!(clean(&got), got, "cleaning twice must change nothing");
    }

    #[test]
    fn c19_wrapped_sentences_become_one_line() {
        same(
            "Submit your reflection paper on the\nreading assignment through the class\nportal before the discussion starts.",
            "Submit your reflection paper on the reading assignment through the class portal before the discussion starts.",
        );
    }

    #[test]
    fn c19_a_word_split_by_the_wrap_is_whole_again() {
        same(
            "Please bring your informa-\ntion sheet and the signed per-\nmission slip.",
            "Please bring your information sheet and the signed permission slip.",
        );
    }

    #[test]
    fn c19_a_code_split_at_its_hyphen_keeps_the_hyphen() {
        same(
            "Room: CCIS-\n402 for COMP-\n20073",
            "Room: CCIS-402 for COMP-20073",
        );
        // A dash with spaces around it is not a split word.
        same("Quiz 2 -\nNov 20", "Quiz 2 -\nNov 20");
    }

    #[test]
    fn c19_dates_times_and_codes_are_never_touched() {
        let s = "COMP 20073 Midterm Exam - Nov 20, 2026 at 11:59 PM\nS512 Lab Report due 11/25 by 5:00 PM\nIT 3O1 stays as it is";
        same(s, s);
    }

    #[test]
    fn c19_dated_lines_stay_on_their_own_lines() {
        // Long, full-width lines of a list must not run together: each is a deadline (C17).
        let s = "Quiz 2 on Chapters 1 to 3 in the lecture hall - Nov 20\nProject proposal submission through the portal - Dec 1\nFinal exam for the whole semester at the gym - Dec 15";
        same(s, s);
    }

    #[test]
    fn c19_blank_lines_and_list_items_survive() {
        same(
            "Requirements:\n\n•  Valid ID\n•  Printed form\n   that is signed\n2)  Fee of 50 pesos\n\n\n\nBring them on Monday.",
            "Requirements:\n\n- Valid ID\n- Printed form that is signed\n2) Fee of 50 pesos\n\nBring them on Monday.",
        );
    }

    #[test]
    fn c19_spaces_stray_marks_and_quotes_are_normalised() {
        same(
            "The  teacher  said  “bring   your book” , then  left .\n|  ~~ \n_____\nIt’s fine.",
            "The teacher said \"bring your book\", then left.\nIt's fine.",
        );
    }

    #[test]
    fn c19_page_numbers_and_repeated_headers_go() {
        let raw = "Polytechnic University\nCOMP 20073 Syllabus\n\nWeek 1: Intro to trees.\nPage 1 of 3\n\nPolytechnic University\nCOMP 20073 Syllabus\n\nWeek 2: Heaps.\n- 2 -\nPolytechnic University\nCOMP 20073 Syllabus\nWeek 3: Graphs.\n3";
        same(
            raw,
            "Week 1: Intro to trees.\n\nWeek 2: Heaps.\nWeek 3: Graphs.",
        );
    }

    #[test]
    fn c19_a_number_inside_the_text_is_not_a_page_number() {
        same(
            "Passing score:\n75\nExtra credit: 5",
            "Passing score:\n75\nExtra credit: 5",
        );
    }

    #[test]
    fn c19_filipino_and_taglish_pass_through() {
        let s = "Magdala ng ballpen at ID bukas.\nHuwag kalimutan ang requirements para sa quiz sa Biyernes.";
        same(s, s);
    }

    #[test]
    fn c19_empty_and_noise_give_nothing() {
        assert_eq!(clean(""), "");
        assert_eq!(clean("  \n | \n ___ \n"), "");
    }
}
