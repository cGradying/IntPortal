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
    notes.iter().map(|n| format!("# {}\n\n{}\n", heading(n), n.text.trim_end())).collect::<Vec<_>>().join("\n")
}

/// The first line with words in it, without Markdown heading, list or
/// emphasis marks, cut to `max` characters.
pub fn preview(text: &str, max: usize) -> String {
    let line = text
        .lines()
        .map(|l| l.trim().trim_start_matches(['#', '-', '*', '>', ' ']).replace("**", "").replace('`', ""))
        .map(|l| l.trim().to_string())
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
        Note { key: key.into(), text: text.into(), title: title.map(Into::into), updated: 0 }
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
}
