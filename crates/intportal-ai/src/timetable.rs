//! The model's pass over a schedule the rules couldn't read (spec 061 C12). It
//! rewrites the text as one line per meeting, `code | name | days | start-end | room`,
//! and `intportal_core::timetable` reads those lines like any other. A line with a
//! number the photo didn't have is dropped: the model may reorder, never invent.
use crate::{llm::Llm, prompt::Template, reply};
use intportal_core::timetable::{self, Found};
use serde_json::{json, Value};
use std::time::{Duration, Instant};

/// Past this the pass is skipped, the same ceiling as a scan's tidy.
pub const MAX_TEXT: usize = 4000;

const TASK: &str = "The text below was read from a photo of a class schedule by a phone's text recognition, so its table may be scrambled. List every class meeting in it, one line each, as: code | name | days | start-end | room. Days use M T W Th F S Su joined, like MWF or TTh. Times are like 7:30AM-9:00AM. Leave a part empty if the text doesn't say it. Use only what the text says: never add a class, a day or a time that is not in it. Reply as JSON with the lines in \"lines\".";

/// Every run of digits in a text.
fn numbers(s: &str) -> Vec<String> {
    s.split(|c: char| !c.is_ascii_digit()).filter(|n| !n.is_empty()).map(|n| n.trim_start_matches('0').to_string()).collect()
}

/// The text's classes as the model lists them, or none when the model is slow,
/// fumbles, or finds nothing the rules can read back.
pub fn read(llm: &mut dyn Llm, tpl: Template, text: &str, budget: Duration) -> Vec<Found> {
    let text = text.trim();
    if text.is_empty() || text.chars().count() > MAX_TEXT {
        return vec![];
    }
    let start = Instant::now();
    let schema: Value = json!({"type": "object", "properties": {"lines": {"type": "array", "items": {"type": "string"}}}, "required": ["lines"]});
    let Ok(raw) = llm.generate(&tpl.wrap(TASK, &format!("Text:\n{text}")), Some(&schema), 700, &mut |_| start.elapsed() < budget) else { return vec![] };
    let Ok(v) = reply::parse::<Value>(&raw) else { return vec![] };
    let had = numbers(text);
    let lines: Vec<String> = v["lines"]
        .as_array()
        .map(|a| a.iter().filter_map(Value::as_str).collect::<Vec<_>>())
        .unwrap_or_default()
        .into_iter()
        .filter(|l| numbers(l).iter().all(|n| n.is_empty() || had.contains(n)))
        .map(|l| l.replace('|', "  "))
        .collect();
    timetable::read(&lines)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::llm::FakeLlm;

    const LONG: Duration = Duration::from_secs(60);
    fn json(lines: &[&str]) -> String {
        serde_json::to_string(&json!({ "lines": lines })).unwrap()
    }

    #[test]
    fn c12_the_models_lines_are_read_by_the_rules() {
        let scrambled = "IT 101\nIntro to Computing\n7:30 - 9:00\nMWF\nRm 204";
        let mut m = FakeLlm::new(&[&json(&["IT 101 | Intro to Computing | MWF | 7:30AM-9:00AM | 204"])]);
        let f = read(&mut m, Template::ChatMl, scrambled, LONG);
        assert_eq!(f.len(), 1);
        assert_eq!((f[0].class.code.as_str(), f[0].class.name.as_str(), f[0].class.meetings[0].start), ("IT 101", "Intro to Computing", 450));
    }

    #[test]
    fn c12_a_line_with_a_number_the_photo_never_had_is_dropped() {
        let text = "IT 101 Intro to Computing 7:30 - 9:00 MWF";
        let mut m = FakeLlm::new(&[&json(&["IT 101 | Intro to Computing | MWF | 7:30AM-9:00AM |", "PE 2 | Dance | TTh | 1:00PM-3:00PM |"])]);
        let f = read(&mut m, Template::ChatMl, text, LONG);
        assert_eq!(f.iter().map(|f| f.class.code.as_str()).collect::<Vec<_>>(), ["IT 101"]);
    }

    #[test]
    fn c12_a_fumbled_answer_finds_nothing() {
        let mut m = FakeLlm::new(&["not json"]);
        assert!(read(&mut m, Template::ChatMl, "MWF 7:30-9:00", LONG).is_empty());
    }
}
