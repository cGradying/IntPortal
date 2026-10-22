//! Flashcards from text, in batches. Small models lose the thread on long
//! outputs, so ask for 12, retry a failed batch at 6, drop duplicates, and
//! keep what arrived if a later batch fails (the old macOS app's rules).
use crate::{llm::Llm, prompt::chatml, reply};
use serde::Deserialize;
use serde_json::json;

#[derive(Debug, Clone, PartialEq, Deserialize)]
pub struct Card {
    pub front: String,
    pub back: String,
}

#[derive(Deserialize)]
struct Batch {
    cards: Vec<Card>,
}

#[derive(Debug, PartialEq)]
pub struct Outcome {
    pub cards: Vec<Card>,
    /// Why generation stopped before `want`, if it did.
    pub stopped: Option<String>,
}

const SYSTEM: &str = "You write study flashcards from the student's text. Each card has a short question or term on the front and a short answer on the back. Use the language of the text. Reply as JSON.";

fn key(front: &str) -> String {
    front.to_lowercase().chars().filter(|c| c.is_alphanumeric()).collect()
}

pub fn cards(llm: &mut dyn Llm, source: &str, want: usize) -> Outcome {
    let schema = json!({"type": "object", "properties": {"cards": {"type": "array", "items": {
        "type": "object", "properties": {"front": {"type": "string", "maxLength": 160}, "back": {"type": "string", "maxLength": 240}}, "required": ["front", "back"]}}},
        "required": ["cards"]});
    let (mut out, mut seen) = (Vec::<Card>::new(), std::collections::HashSet::new());
    let mut size = 12;
    while out.len() < want {
        let n = size.min(want - out.len());
        let avoid: String = out.iter().map(|c| format!("- {}\n", c.front)).collect();
        let user = format!("Write {n} flashcards from this text.\n\n{source}\n\nAlready written, do not repeat:\n{avoid}");
        let parsed = llm
            .generate(&chatml(SYSTEM, &user), Some(&schema), 1024, &mut |_| true)
            .and_then(|raw| reply::parse::<Batch>(&raw).map_err(|e| e.to_string()));
        match parsed {
            Ok(b) => {
                let before = out.len();
                for c in b.cards {
                    if !c.front.trim().is_empty() && !c.back.trim().is_empty() && seen.insert(key(&c.front)) && out.len() < want {
                        out.push(c);
                    }
                }
                if out.len() == before {
                    return Outcome { cards: out, stopped: Some("no new cards".into()) };
                }
            }
            Err(_) if size > 6 => size = 6,
            Err(e) => return Outcome { cards: out, stopped: Some(e) },
        }
    }
    Outcome { cards: out, stopped: None }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::llm::FakeLlm;

    fn batch(fronts: &[&str]) -> String {
        let cards: Vec<_> = fronts.iter().map(|f| json!({"front": f, "back": "b"})).collect();
        json!({"cards": cards}).to_string()
    }

    #[test]
    fn dedupes_and_stops_at_want() {
        let mut m = FakeLlm::new(&[&batch(&["What is a tree?", "what is a TREE", "Define heap"])]);
        let o = cards(&mut m, "text", 2);
        assert_eq!(o.cards.iter().map(|c| c.front.as_str()).collect::<Vec<_>>(), ["What is a tree?", "Define heap"]);
        assert_eq!(o.stopped, None);
    }

    #[test]
    fn a_failed_batch_retries_at_six_and_keeps_partial_results() {
        let mut m = FakeLlm::new(&["garbage", &batch(&["a", "b"]), "garbage", "garbage"]);
        let o = cards(&mut m, "text", 20);
        assert_eq!(o.cards.len(), 2, "kept what arrived");
        assert!(o.stopped.is_some());
        assert!(m.prompts[0].contains("Write 12 flashcards"));
        assert!(m.prompts[1].contains("Write 6 flashcards"), "retry at 6");
        assert!(m.prompts[2].contains("Write 6 flashcards") && m.prompts[2].contains("- a\n- b"), "later batches list what exists");
    }

    #[test]
    fn a_short_batch_is_followed_by_another_until_want_is_met() {
        let mut m = FakeLlm::new(&[&batch(&["a", "b", "c"]), &batch(&["c", "d", "e", "f", "g", "h"])]);
        let o = cards(&mut m, "text", 8);
        assert_eq!(o.cards.len(), 8);
        assert_eq!(o.stopped, None);
        assert!(m.prompts[1].contains("Write 5 flashcards"), "asks only for what is missing");
    }

    #[test]
    fn a_batch_of_only_repeats_ends_the_run() {
        let mut m = FakeLlm::new(&[&batch(&["a"]), &batch(&["A"])]);
        assert_eq!(cards(&mut m, "t", 5).stopped.as_deref(), Some("no new cards"));
    }
}
