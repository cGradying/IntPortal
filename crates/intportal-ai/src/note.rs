//! "Ask AI" inside a note: summarize it, tidy it up, explain a selection, or
//! answer a question from it. Uses only the note's own text. Returns text for
//! the student to insert or swap in; nothing is written here.
use crate::{llm::Llm, prompt::Template, reply::{self, ReplyStream}};
use serde_json::{json, Value};

/// What fits the prompt next to the instructions in a 4K window.
pub const MAX_NOTE: usize = 3000;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Mode {
    Summarize,
    Tidy,
    /// The selected words, in plain language.
    Explain,
    Ask,
}

impl Mode {
    pub fn parse(s: &str) -> Option<Mode> {
        Some(match s {
            "summarize" => Mode::Summarize,
            "tidy" => Mode::Tidy,
            "explain" => Mode::Explain,
            "ask" => Mode::Ask,
            _ => return None,
        })
    }
}

fn task(mode: Mode) -> &'static str {
    match mode {
        Mode::Summarize => "Summarize the note in 3 to 5 short bullet points, each starting with \"- \". Keep the note's own terms. Use only the note.",
        Mode::Tidy => "Rewrite the note cleanly: fix spelling and spacing, group related lines, keep every fact and the same language. Add nothing and drop nothing.",
        Mode::Explain => "Explain the selected words in plain language in 2 or 3 short sentences. Use the note for context and nothing else.",
        Mode::Ask => "Answer the question from the note only, in 1 to 3 short sentences. If the note does not say, say the note does not say.",
    }
}

/// `text` is the whole note. `selection` is required for Explain and is what
/// Tidy works on when present; `question` is required for Ask. `on_text`
/// gets the words as they are written.
pub fn run(llm: &mut dyn Llm, tpl: Template, mode: Mode, text: &str, selection: Option<&str>, question: Option<&str>, on_text: &mut dyn FnMut(&str)) -> Result<String, String> {
    let selection = selection.map(str::trim).filter(|s| !s.is_empty());
    let question = question.map(str::trim).filter(|s| !s.is_empty());
    let subject = match (mode, selection, question) {
        (Mode::Explain, None, _) => return Err("Select the words to explain first.".into()),
        (Mode::Ask, _, None) => return Err("Type a question first.".into()),
        (Mode::Tidy, Some(s), _) => s,
        _ => text.trim(),
    };
    if subject.is_empty() {
        return Err("The note is empty.".into());
    }
    if subject.chars().count() > MAX_NOTE {
        return Err("This note is too long for me to take in at once. Select part of it.".into());
    }
    let sys = format!("You are IntAssis, a calm study helper inside a student's notes (PUP, Philippines). {} Reply in the language of the note. Reply as JSON.", task(mode));
    let user = match (mode, selection, question) {
        (Mode::Explain, Some(sel), _) => format!("Note:\n{subject}\n\nSelected words: {sel}"),
        (Mode::Ask, _, Some(q)) => format!("Note:\n{subject}\n\nQuestion: {q}"),
        _ => format!("Note:\n{subject}"),
    };
    let schema: Value = json!({"type": "object", "properties": {"reply": {"type": "string"}}, "required": ["reply"]});
    let max = if mode == Mode::Tidy { 700 } else { 300 };
    let mut stream = ReplyStream::default();
    let raw = llm.generate(&tpl.wrap(&sys, &user), Some(&schema), max, &mut |piece| {
        if let Some(words) = stream.feed(piece) {
            on_text(&words);
        }
        true
    })?;
    let v: Value = reply::parse(&raw).map_err(|e| e.to_string())?;
    let out = v["reply"].as_str().unwrap_or("").trim().to_string();
    if out.is_empty() {
        return Err("the reply came back empty".into());
    }
    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::llm::FakeLlm;

    fn run_with(m: &mut FakeLlm, mode: Mode, text: &str, sel: Option<&str>, q: Option<&str>) -> Result<String, String> {
        run(m, Template::Gemma, mode, text, sel, q, &mut |_| ())
    }

    #[test]
    fn summarize_sends_the_note_and_streams_the_words() {
        let mut m = FakeLlm::new(&[r#"{"reply":"- Trees have a root\n- Height counts edges"}"#]);
        let mut seen = String::new();
        let out = run(&mut m, Template::Gemma, Mode::Summarize, "Trees: root, leaves. Height counts edges.", None, None, &mut |w| seen.push_str(w)).unwrap();
        assert_eq!(out, "- Trees have a root\n- Height counts edges");
        assert_eq!(seen, out);
        assert!(m.prompts[0].contains("Trees: root, leaves.") && m.prompts[0].contains("3 to 5 short bullet points"));
    }

    #[test]
    fn explain_and_ask_need_their_input_and_tidy_prefers_the_selection() {
        let mut m = FakeLlm::new(&[r#"{"reply":"ok"}"#, r#"{"reply":"clean"}"#]);
        assert!(run_with(&mut m, Mode::Explain, "note", None, None).is_err());
        assert!(run_with(&mut m, Mode::Ask, "note", None, Some("  ")).is_err());
        assert_eq!(run_with(&mut m, Mode::Explain, "note about heaps", Some("heaps"), None).unwrap(), "ok");
        assert!(m.prompts[0].contains("Selected words: heaps"));
        run_with(&mut m, Mode::Tidy, "whole note", Some("just this part"), None).unwrap();
        assert!(m.prompts[1].contains("just this part") && !m.prompts[1].contains("whole note"));
    }

    #[test]
    fn an_empty_or_huge_note_is_refused_before_the_model_runs() {
        let mut m = FakeLlm::new(&[]);
        assert!(run_with(&mut m, Mode::Summarize, "   ", None, None).is_err());
        assert!(run_with(&mut m, Mode::Summarize, &"x".repeat(MAX_NOTE + 1), None, None).unwrap_err().contains("Select part"));
        assert!(m.prompts.is_empty());
        assert_eq!(Mode::parse("tidy"), Some(Mode::Tidy));
        assert_eq!(Mode::parse("nope"), None);
    }
}
