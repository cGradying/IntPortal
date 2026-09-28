//! The student's notes: one per subject that carries across every week (the
//! old app's class note), and one per day. Kept on the device only.

use crate::today::Date;
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Note {
    /// `class:<subject code>` or `day:<YYYY-MM-DD>`.
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

    #[test]
    fn preview_skips_blank_lines_and_markdown_marks() {
        assert_eq!(preview("\n\n# Quiz on **Friday**\n- trees", 40), "Quiz on Friday");
        assert_eq!(preview("- `BFS` vs DFS", 40), "BFS vs DFS");
        assert_eq!(preview("   ", 40), "");
        assert_eq!(preview("Linked lists and their many uses", 12), "Linked list…");
    }
}
