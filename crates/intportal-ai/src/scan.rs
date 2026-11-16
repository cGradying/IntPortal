//! The model's pass over text read from a photo (spec 020 C15, spec 041 C19).
//! It runs on text `intportal_core::scan::clean` already tidied, fixes the OCR's
//! wrong letters and breaks, and is never trusted: an answer that changes a
//! number, code, date or month, or that is much shorter or longer, is thrown
//! away for the text it was given.
use crate::{llm::Llm, prompt::Template, reply};
use serde_json::{json, Value};
use std::time::{Duration, Instant};

/// One paragraph group per model call: what fits the prompt in a 4K window with room to write.
const CHUNK: usize = 1200;
/// Past this the pass is skipped: a long handout would hold the phone for minutes.
pub const MAX_SCAN: usize = 6000;

const TASK: &str = "The text below was read from a photo by a phone's text recognition. Fix only what the recognition got wrong: letters wrong inside words, words broken in two, stray symbols, spacing and line breaks. Do not add, remove, summarise, explain or translate anything. Keep the language exactly as written, English, Filipino or Taglish. Keep every number, code, date and time exactly as written, for example COMP 20073, S512, 11:59 PM, Nov 20. Keep list items on their own lines starting with \"- \". Reply as JSON with the fixed text in \"reply\".";

/// The digits-and-month words of a text, sorted: what the model must not change.
fn facts(s: &str) -> Vec<String> {
    let mut v: Vec<String> = s
        .split_whitespace()
        .map(|w| w.trim_matches(|c: char| !c.is_alphanumeric()))
        .filter(|w| w.chars().any(|c| c.is_ascii_digit()) || is_month(w))
        .map(str::to_lowercase)
        .collect();
    v.sort();
    v
}

fn is_month(w: &str) -> bool {
    let w = w.to_lowercase();
    ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"].iter().any(|m| w.starts_with(m) && w.len() <= 9)
}

/// Is `out` a fix of `input`, and not a rewrite?
pub fn accepts(input: &str, out: &str) -> bool {
    let (a, b) = (input.chars().count(), out.chars().count());
    b > 0 && b * 10 >= a * 7 && b * 10 <= a * 13 && facts(input) == facts(out)
}

fn fix_chunk(llm: &mut dyn Llm, tpl: Template, chunk: &str, on_token: &mut dyn FnMut() -> bool) -> Option<String> {
    let schema: Value = json!({"type": "object", "properties": {"reply": {"type": "string"}}, "required": ["reply"]});
    let max = (chunk.chars().count() / 2 + 120).clamp(200, 700) as u32;
    let raw = llm.generate(&tpl.wrap(TASK, &format!("Text:\n{chunk}")), Some(&schema), max, &mut |_| on_token()).ok()?;
    let v: Value = reply::parse(&raw).ok()?;
    let out = v["reply"].as_str()?.trim().to_string();
    accepts(chunk, &out).then_some(out)
}

/// `text` tidied by the model, piece by piece. A piece the model fumbles, or that
/// arrives after `budget` has run out, stays as it was; if no piece changed, the
/// text comes back unchanged. Nothing here fails: the worst case is `text` itself.
pub fn tidy(llm: &mut dyn Llm, tpl: Template, text: &str, budget: Duration) -> String {
    let text = text.trim();
    if text.is_empty() || text.chars().count() > MAX_SCAN {
        return text.to_string();
    }
    let start = Instant::now();
    let mut alive = || start.elapsed() < budget;
    // ponytail: a single paragraph over CHUNK is left alone; split it by lines if handouts need it.
    let mut groups: Vec<String> = Vec::new();
    for p in text.split("\n\n") {
        match groups.last_mut() {
            Some(g) if g.chars().count() + p.chars().count() < CHUNK => {
                g.push_str("\n\n");
                g.push_str(p);
            }
            _ => groups.push(p.to_string()),
        }
    }
    let fixed: Vec<String> = groups
        .into_iter()
        .map(|g| if g.chars().count() > CHUNK || !alive() { g } else { fix_chunk(llm, tpl, &g, &mut alive).unwrap_or(g) })
        .collect();
    fixed.join("\n\n")
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::llm::FakeLlm;

    const NOW: Duration = Duration::from_secs(60);

    fn json(s: &str) -> String {
        json!({ "reply": s }).to_string()
    }

    #[test]
    fn c15_a_fixed_word_is_taken() {
        let input = "Subrnit the reflecti0n paper by Nov 20 at 11:59 PM for COMP 20073.";
        let want = "Submit the reflection paper by Nov 20 at 11:59 PM for COMP 20073.";
        // The model also fixed the letter-for-digit "0" in a word: that changes a digit, so it is refused.
        let mut m = FakeLlm::new(&[&json(want)]);
        assert_eq!(tidy(&mut m, Template::ChatMl, input, NOW), input);
        let input = "Subrnit the reflection paper by Nov 20 at 11:59 PM for COMP 20073.";
        let mut m = FakeLlm::new(&[&json(want)]);
        assert_eq!(tidy(&mut m, Template::ChatMl, input, NOW), want);
        assert!(m.prompts[0].contains("Subrnit the reflection paper") && m.prompts[0].contains("Do not add, remove, summarise"));
    }

    #[test]
    fn c15_a_changed_number_code_date_or_month_is_refused() {
        let input = "Quiz 2 on Nov 20 at 11:59 PM, room S512, COMP 20073.";
        for bad in ["Quiz 2 on Nov 21 at 11:59 PM, room S512, COMP 20073.", "Quiz 2 on Nov 20 at 11:59 PM, room S521, COMP 20073.", "Quiz 2 on Dec 20 at 11:59 PM, room S512, COMP 20073.", "Quiz 2 on Nov 20 at 11:59 PM, room S512, COMP 20073 and 2.", "Quiz 2 on Nov 20 at 11:59 PM, room S512."] {
            assert!(!accepts(input, bad), "{bad}");
        }
        assert!(accepts(input, "Quiz 2 on Nov 20 at 11:59 PM,  room S512, COMP 20073"));
    }

    #[test]
    fn c15_a_much_shorter_or_longer_answer_is_refused() {
        let input = "Bring your ballpen and ID to the exam room on time, please.";
        assert!(!accepts(input, "Bring your ballpen."));
        assert!(!accepts(input, &format!("{input} Also, remember to review the chapters and sleep early the night before.")));
        assert!(!accepts(input, ""));
        assert!(accepts(input, "Bring your ballpen and ID to the exam room on time please."));
    }

    #[test]
    fn c15_a_reply_that_is_not_json_or_an_error_leaves_the_text() {
        let input = "Magdala ng ballpen at ID bukas.";
        let mut m = FakeLlm::new(&["Sure! Here is the text."]);
        assert_eq!(tidy(&mut m, Template::ChatMl, input, NOW), input);
        let mut m = FakeLlm::new(&[]);
        assert_eq!(tidy(&mut m, Template::ChatMl, input, NOW), input);
    }

    #[test]
    fn c15_long_text_goes_in_pieces_and_a_bad_piece_keeps_its_own_text() {
        let a = format!("Frist paragraph. {}", "word ".repeat(150));
        let b = format!("Second paragraph. {}", "term ".repeat(150));
        let (a, b) = (a.trim().to_string(), b.trim().to_string());
        let text = format!("{a}\n\n{b}");
        let fixed_a = a.replacen("Frist", "First", 1);
        let mut m = FakeLlm::new(&[&json(&fixed_a), &json("Gone.")]);
        assert_eq!(tidy(&mut m, Template::ChatMl, &text, NOW), format!("{fixed_a}\n\n{b}"));
        assert_eq!(m.prompts.len(), 2);
    }

    #[test]
    fn c15_a_text_too_long_or_a_spent_budget_never_reaches_the_model() {
        let mut m = FakeLlm::new(&[&json("x")]);
        let long = "a ".repeat(MAX_SCAN);
        assert_eq!(tidy(&mut m, Template::ChatMl, &long, NOW), long.trim());
        assert_eq!(tidy(&mut m, Template::ChatMl, "Short text here.", Duration::ZERO), "Short text here.");
        assert!(m.prompts.is_empty());
    }
}
