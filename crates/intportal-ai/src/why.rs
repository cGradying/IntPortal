//! "Why?" after a wrong flashcard answer: one or two sentences on why the
//! right answer is right, and a memory hook. Uses only the card and, when the
//! student has one, their own note excerpt.
use crate::{llm::Llm, prompt::Template, reply};
use serde::Deserialize;
use serde_json::json;

#[derive(Debug, Deserialize, PartialEq)]
pub struct Why {
    pub why: String,
    pub tip: String,
}

pub fn explain(llm: &mut dyn Llm, tpl: Template, front: &str, back: &str, typed: &str, note: Option<&str>) -> Result<Why, String> {
    let sys = "You are IntAssis, a kind study helper. The student got a flashcard wrong. In `why`, explain in 1-2 short sentences why the correct answer is right, without scolding. \
In `tip`, give one short way to remember it. Use only the card and the note excerpt. Reply in the language of the card. Reply as JSON.";
    let note = note.map(|n| format!("\nFrom the student's note:\n{}", n.chars().take(800).collect::<String>())).unwrap_or_default();
    let user = format!("Card front: {front}\nCorrect answer: {back}\nThe student answered: {typed}{note}");
    let schema = json!({"type": "object", "properties": {"why": {"type": "string"}, "tip": {"type": "string"}}, "required": ["why", "tip"]});
    let raw = llm.generate(&tpl.wrap(sys, &user), Some(&schema), 200, &mut |_| true)?;
    let w: Why = reply::parse(&raw).map_err(|e| e.to_string())?;
    if w.why.trim().is_empty() {
        return Err("the explanation came back empty".into());
    }
    Ok(w)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::llm::FakeLlm;

    #[test]
    fn asks_with_the_card_and_the_wrong_answer() {
        let mut m = FakeLlm::new(&[r#"{"why":"A heap keeps the smallest on top.","tip":"Heap = hill top."}"#]);
        let w = explain(&mut m, Template::Gemma, "Min-heap root?", "The smallest item", "the largest", Some("heaps: root is min")).unwrap();
        assert_eq!(w.tip, "Heap = hill top.");
        let p = &m.prompts[0];
        assert!(p.contains("Correct answer: The smallest item") && p.contains("The student answered: the largest") && p.contains("heaps: root is min"));
    }

    #[test]
    fn an_empty_explanation_is_an_error() {
        let mut m = FakeLlm::new(&[r#"{"why":" ","tip":"x"}"#]);
        assert!(explain(&mut m, Template::ChatMl, "f", "b", "t", None).is_err());
    }
}
