//! A subject's outline, two ways.
//!
//! 1. From text the student has (pasted, or read from a PDF): the rule-based
//!    `parse_outline` runs first, because it reads real dates exactly. Only
//!    when it finds fewer than `ENOUGH` items does the model extract the
//!    rest, and its items never replace a rule-parsed topic.
//! 2. From a course title alone: a *guide*, a week-by-week list of what such a
//!    course usually covers. It carries weeks only, never dates, and the UI
//!    labels it "Guide" so nobody mistakes it for the professor's syllabus.
use crate::{llm::Llm, prompt::Template, reply};
use intportal_core::{
    syllabus::{parse_outline, Item, Kind},
    today::Date,
};
use serde::Deserialize;
use serde_json::json;

pub const ENOUGH: usize = 4;
const TEXT_CHARS: usize = 6000;

#[derive(Deserialize)]
struct Raw {
    items: Vec<RawItem>,
}
#[derive(Deserialize)]
struct RawItem {
    topic: String,
    kind: Kind,
    week: u16,
}

fn norm(s: &str) -> String {
    s.to_lowercase().chars().filter(|c| c.is_alphanumeric()).collect()
}

fn ask(llm: &mut dyn Llm, tpl: Template, sys: &str, user: &str, weeks: u16, min: u16) -> Result<Vec<RawItem>, String> {
    let schema = json!({"type": "object", "properties": {"items": {"type": "array", "minItems": min, "maxItems": weeks * 3, "items": {"type": "object",
        "properties": {"topic": {"type": "string"}, "kind": {"enum": ["lecture", "quiz", "exam", "project"]},
        "week": {"enum": (1..=weeks).collect::<Vec<_>>()}}, "required": ["topic", "kind", "week"]}}}, "required": ["items"]});
    let raw = llm.generate(&tpl.wrap(sys, user), Some(&schema), 900, &mut |_| true)?;
    Ok(reply::parse::<Raw>(&raw).map_err(|e| e.to_string())?.items)
}

/// Keeps weeks inside the term, drops blanks and repeats, orders by week.
fn tidy(items: Vec<RawItem>, weeks: u16, mut seen: Vec<String>) -> Vec<Item> {
    let mut out: Vec<Item> = vec![];
    for r in items {
        let topic = r.topic.trim().to_string();
        if topic.is_empty() || r.week == 0 || r.week > weeks || seen.contains(&norm(&topic)) {
            continue;
        }
        seen.push(norm(&topic));
        out.push(Item { id: String::new(), topic, kind: r.kind, week: Some(r.week), date: None, done: false });
    }
    out.sort_by_key(|i| i.week);
    out
}

pub fn from_text(llm: &mut dyn Llm, tpl: Template, text: &str, today: Date, weeks: u16) -> Result<Vec<Item>, String> {
    let mut items = parse_outline(text, today);
    if items.len() >= ENOUGH {
        return Ok(items);
    }
    let sys = "You read a course syllabus and list its schedule. One item per topic, quiz, exam or project, with the week number it falls in. \
Use only what the text says; do not add typical topics. Keep the text's wording. Reply as JSON.";
    let user: String = text.chars().take(TEXT_CHARS).collect();
    let seen = items.iter().map(|i| norm(&i.topic)).collect();
    items.extend(tidy(ask(llm, tpl, sys, &user, weeks, 0)?, weeks, seen));
    Ok(items)
}

/// One short call per week: a 1B model asked for a whole term piles it all
/// into week 1. `progress(week, weeks)` returns false to stop; what exists is kept.
pub fn from_title(llm: &mut dyn Llm, tpl: Template, course: &str, weeks: u16, progress: &mut dyn FnMut(u16, u16) -> bool) -> Result<Vec<Item>, String> {
    let schema = json!({"type": "object", "properties": {"topics": {"type": "array", "minItems": 1, "maxItems": 2, "items": {"type": "string"}}}, "required": ["topics"]});
    let sys = "You draft one week of a study guide for a Philippine college course: what such a course usually covers in that week, in 1 or 2 short topic names in English (under 8 words each). \
Name a quiz or exam in the topic only if one usually falls in that week. Do not claim this is the official syllabus. Reply as JSON.";
    let mut items: Vec<Item> = vec![];
    for week in 1..=weeks {
        if !progress(week, weeks) {
            break;
        }
        let so_far: String = items.iter().map(|i| format!("- week {}: {}\n", i.week.unwrap_or(0), i.topic)).collect();
        let user = format!("Course: {course}\nTerm: {weeks} weeks. Write week {week} of {weeks}.\nAlready covered, do not repeat:\n{so_far}");
        let Ok(raw) = llm.generate(&tpl.wrap(sys, &user), Some(&schema), 300, &mut |_| true) else { continue };
        #[derive(Deserialize)]
        struct Week {
            topics: Vec<String>,
        }
        if let Ok(w) = reply::parse::<Week>(&raw) {
            let seen = items.iter().map(|i| norm(&i.topic)).collect();
            // `parse_outline` decides quiz, exam or project from the words, as it does for a pasted outline.
            let raw = w.topics.iter().filter_map(|t| parse_outline(&format!("Week {week}: {}", t.trim()), Date::new(2026, 1, 1)).pop());
            items.extend(tidy(raw.map(|i| RawItem { topic: i.topic, kind: i.kind, week }).collect(), weeks, seen));
        }
    }
    if items.is_empty() {
        return Err("no outline came back".into());
    }
    Ok(items)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::llm::FakeLlm;

    const TODAY: Date = Date { y: 2026, m: 10, d: 15 };

    #[test]
    fn enough_rule_parsed_items_skip_the_model() {
        let text = "Week 1: Intro\nWeek 2: Arrays\nWeek 3: Quiz 1\nWeek 4: Lists";
        let mut m = FakeLlm::new(&[]);
        let items = from_text(&mut m, Template::Gemma, text, TODAY, 18).unwrap();
        assert_eq!(items.len(), 4);
        assert!(m.prompts.is_empty());
    }

    #[test]
    fn the_model_fills_in_without_replacing_what_the_rules_read() {
        let raw = r#"{"items":[{"topic":"Arrays","kind":"lecture","week":2},{"topic":"Trees","kind":"lecture","week":5},{"topic":"Midterm","kind":"exam","week":99}]}"#;
        let mut m = FakeLlm::new(&[raw]);
        let items = from_text(&mut m, Template::ChatMl, "Week 2: Arrays", TODAY, 18).unwrap();
        let topics: Vec<_> = items.iter().map(|i| (i.topic.as_str(), i.week)).collect();
        assert_eq!(topics, [("Arrays", Some(2)), ("Trees", Some(5))], "duplicate dropped, week 99 dropped");
        assert!(items.iter().all(|i| i.date.is_none() || i.topic == "Arrays"));
    }

    #[test]
    fn a_guide_asks_week_by_week_keeps_partial_and_never_dates() {
        let mut m = FakeLlm::new(&[
            r#"{"topics":["Intro"]}"#,
            "garbage",
            r#"{"topics":["intro","Midterm exam"]}"#,
        ]);
        let mut seen = vec![];
        let items = from_title(&mut m, Template::Gemma, "COMP 20073 Data Structures", 3, &mut |w, _| {
            seen.push(w);
            true
        })
        .unwrap();
        assert_eq!(items.iter().map(|i| (i.topic.as_str(), i.week.unwrap())).collect::<Vec<_>>(), [("Intro", 1), ("Midterm exam", 3)], "week 2 failed, week 3 repeat dropped");
        assert!(items.iter().all(|i| i.date.is_none() && !i.done));
        assert_eq!(items[1].kind, Kind::Exam);
        assert_eq!(seen, [1, 2, 3]);
        assert!(m.prompts[2].contains("write week 3 of 3") || m.prompts[2].contains("Write week 3 of 3"));
        assert!(m.prompts[2].contains("- week 1: Intro"));
    }

    #[test]
    fn stopping_keeps_what_exists_and_nothing_at_all_is_an_error() {
        let mut m = FakeLlm::new(&[r#"{"topics":["Intro"]}"#]);
        let items = from_title(&mut m, Template::Gemma, "X", 5, &mut |w, _| w < 2).unwrap();
        assert_eq!(items.len(), 1);
        assert!(from_title(&mut FakeLlm::new(&[]), Template::Gemma, "X", 2, &mut |_, _| true).is_err());
    }
}
