//! The student's notes: one per subject that carries across every week (the
//! old app's class note), and one per day. Kept on the device only.

use crate::today::Date;
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Note {
    /// `class:<subject code>`, `day:<YYYY-MM-DD>`, or `note:<id>` for a
    /// freeform note the student named.
    pub key: String,
    pub text: String,
    /// What a list shows when the key alone doesn't say enough, such as the
    /// subject's description.
    pub title: Option<String>,
    /// Unix seconds of the last edit.
    pub updated: i64,
    /// The subject a `note:` note is filed under: a code that may outlive its
    /// term. `class:` notes get theirs from the key, and `day:` notes have none.
    #[serde(default)]
    pub subject: Option<String>,
    #[serde(default)]
    pub pinned: bool,
    /// How many photos it holds. A note may hold only photos (046 C17c).
    #[serde(default)]
    pub photos: u32,
}

pub fn class_key(subject_code: &str) -> String {
    format!("class:{subject_code}")
}

pub fn day_key(date: Date) -> String {
    format!("day:{date}")
}

pub fn is_known_key(key: &str) -> bool {
    ["class:", "day:", "note:"].iter().any(|p| key.len() > p.len() && key.starts_with(p))
}

/// What a note is called in lists and exports.
pub fn heading(note: &Note) -> String {
    let title = note.title.as_deref().filter(|t| !t.trim().is_empty());
    if let Some(code) = note.key.strip_prefix("class:") {
        return match title {
            Some(t) => format!("{code} · {t}"),
            None => code.to_string(),
        };
    }
    if let Some(date) = note.key.strip_prefix("day:") {
        return format!("Day note · {date}");
    }
    title.map_or_else(|| "Untitled note".to_string(), str::to_string)
}

/// Notes as one Markdown document, each under its heading, in the order given.
pub fn markdown(notes: &[Note]) -> String {
    notes.iter().filter(|n| !n.text.trim().is_empty()).map(|n| format!("# {}\n\n{}\n", heading(n), n.text.trim_end())).collect::<Vec<_>>().join("\n")
}

/// The subject codes whose class note has words in it. Photos alone don't
/// count: the after-class prompt asks for text (046 C17d).
pub fn class_codes_with_text(notes: &[Note]) -> Vec<String> {
    notes.iter().filter(|n| !n.text.trim().is_empty()).filter_map(|n| n.key.strip_prefix("class:").map(String::from)).collect()
}

/// Pinned notes first; each group keeps the order it came in.
pub fn pinned_first(notes: &mut [Note]) {
    notes.sort_by_key(|n| !n.pinned);
}

/// A line without its checklist box. The box only counts as one after a list
/// mark, so `[x] marks the spot` keeps its words.
fn without_box(line: &str) -> &str {
    ["- [ ]", "- [x]", "- [X]"]
        .iter()
        .find_map(|b| line.strip_prefix(b).filter(|rest| rest.is_empty() || rest.starts_with(' ')))
        .unwrap_or(line)
}

/// A line without `==highlight==` marks. A mark touches its text on the inner
/// side, so `a == b` stays as written.
fn without_highlight(line: &str) -> String {
    let parts: Vec<&str> = line.split("==").collect();
    let mut out = parts[0].to_string();
    let mut open = false;
    for (i, part) in parts.iter().enumerate().skip(1) {
        let closes = open && !parts[i - 1].ends_with(' ');
        let opens = !open && !part.starts_with(' ') && !part.is_empty() && i + 1 < parts.len();
        if closes || opens {
            open = opens;
        } else {
            out.push_str("==");
        }
        out.push_str(part);
    }
    out
}

/// The first line with words in it, without Markdown heading, list, checklist,
/// highlight or emphasis marks, cut to `max` characters.
pub fn preview(text: &str, max: usize) -> String {
    let line = text
        .lines()
        .map(|l| without_box(l.trim()).trim_start_matches(['#', '-', '*', '>', ' ']).replace("**", "").replace('`', ""))
        .map(|l| without_highlight(l.trim()).trim().to_string())
        .find(|l| !l.is_empty())
        .unwrap_or_default();
    if line.chars().count() <= max {
        line
    } else {
        format!("{}…", line.chars().take(max.saturating_sub(1)).collect::<String>().trim_end())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn keys_name_what_they_belong_to() {
        assert_eq!(class_key("COMP 20073"), "class:COMP 20073");
        assert_eq!(day_key(Date::new(2026, 9, 28)), "day:2026-09-28");
    }

    fn note(key: &str, title: Option<&str>, text: &str) -> Note {
        Note { key: key.into(), text: text.into(), title: title.map(Into::into), updated: 0, subject: None, pinned: false, photos: 0 }
    }

    #[test]
    fn only_known_key_kinds_with_a_name_are_accepted() {
        assert!(is_known_key("class:COMP 20073") && is_known_key("day:2026-09-28") && is_known_key("note:9f2c"));
        assert!(!is_known_key("note:") && !is_known_key("vault:x") && !is_known_key(""));
    }

    #[test]
    fn markdown_puts_each_note_under_its_heading() {
        let notes = [
            note("class:COMP 20073", Some("Data Structures"), "Trees next week\n"),
            note("day:2026-09-28", None, "Bring laptop"),
            note("note:1", Some("Thesis ideas"), "- campus app"),
            note("note:2", Some("  "), "x"),
        ];
        assert_eq!(
            markdown(&notes),
            "# COMP 20073 · Data Structures\n\nTrees next week\n\n# Day note · 2026-09-28\n\nBring laptop\n\n# Thesis ideas\n\n- campus app\n\n# Untitled note\n\nx\n"
        );
    }

    #[test]
    fn preview_skips_blank_lines_and_markdown_marks() {
        assert_eq!(preview("\n\n# Quiz on **Friday**\n- trees", 40), "Quiz on Friday");
        assert_eq!(preview("- `BFS` vs DFS", 40), "BFS vs DFS");
        assert_eq!(preview("   ", 40), "");
        assert_eq!(preview("Linked lists and their many uses", 12), "Linked list…");
    }

    #[test]
    fn preview_strips_checklist_and_highlight() {
        assert_eq!(preview("- [ ] Buy a bluebook", 40), "Buy a bluebook");
        assert_eq!(preview("- [x] Read chapter 3", 40), "Read chapter 3");
        assert_eq!(preview("- [X] Read chapter 4", 40), "Read chapter 4");
        assert_eq!(preview("- [ ]\n- [ ] Second box", 40), "Second box", "an empty box has no words");
        assert_eq!(preview("Quiz on ==Friday== at ==8AM==", 40), "Quiz on Friday at 8AM");
        assert_eq!(preview("==Whole line==", 40), "Whole line");
    }

    #[test]
    fn preview_keeps_words_that_only_look_like_marks() {
        assert_eq!(preview("[x] marks the spot", 40), "[x] marks the spot");
        assert_eq!(preview("if a == b and c == d", 40), "if a == b and c == d");
        assert_eq!(preview("a ==", 40), "a ==");
    }

    #[test]
    fn pinned_notes_come_first_and_each_group_keeps_its_order() {
        let mut notes = [note("note:new", None, "x"), note("note:pin-new", None, "x"), note("note:old", None, "x"), note("note:pin-old", None, "x")];
        notes[1].pinned = true;
        notes[3].pinned = true;
        pinned_first(&mut notes);
        assert_eq!(notes.iter().map(|n| n.key.as_str()).collect::<Vec<_>>(), ["note:pin-new", "note:pin-old", "note:new", "note:old"]);
    }
}
