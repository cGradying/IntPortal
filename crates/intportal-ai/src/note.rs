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
        Mode::Summarize => "Summarize the note in 3 to 5 short bullet points, each starting with \"- \". Start with the first bullet: no introduction. Keep the note's own terms. Use only the note.",
        Mode::Tidy => "Rewrite the note cleanly: fix spelling and spacing, group related lines, keep every fact and the same language. Add nothing and drop nothing. Give only the rewritten note, no introduction.",
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
        assert!(m.prompts[0].contains("Trees: root, leaves.") && m.prompts[0].contains("3 to 5 short bullet points") && m.prompts[0].contains("no introduction"));
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

    /// Records the token limit and schema; replies in the given pieces, stopping if told to.
    struct Spy {
        pieces: Vec<&'static str>,
        max_tokens: Vec<u32>,
        schemas: Vec<Option<Value>>,
    }

    impl Spy {
        fn new(pieces: &[&'static str]) -> Self {
            Self { pieces: pieces.to_vec(), max_tokens: vec![], schemas: vec![] }
        }
    }

    impl Llm for Spy {
        fn generate(&mut self, _p: &str, schema: Option<&Value>, max: u32, on_token: &mut dyn FnMut(&str) -> bool) -> Result<String, String> {
            self.max_tokens.push(max);
            self.schemas.push(schema.cloned());
            let mut out = String::new();
            for p in &self.pieces {
                out.push_str(p);
                if !on_token(p) {
                    break;
                }
            }
            Ok(out)
        }

        fn embed(&mut self, _t: &[&str]) -> Result<Vec<Vec<f32>>, String> {
            Ok(vec![])
        }
    }

    #[test]
    fn parse_knows_exactly_four_modes() {
        for (s, m) in [("summarize", Mode::Summarize), ("tidy", Mode::Tidy), ("explain", Mode::Explain), ("ask", Mode::Ask)] {
            assert_eq!(Mode::parse(s), Some(m));
        }
        for s in ["", "Tidy", "SUMMARIZE", " ask", "summary", "explain ", "translate"] {
            assert_eq!(Mode::parse(s), None, "{s:?}");
        }
    }

    // C6: Summarize and Tidy must not start with "Sure, here is".
    #[test]
    fn summarize_and_tidy_prompts_ban_an_introduction() {
        let mut m = FakeLlm::new(&[r#"{"reply":"- a"}"#, r#"{"reply":"clean"}"#, r#"{"reply":"x"}"#, r#"{"reply":"y"}"#]);
        run_with(&mut m, Mode::Summarize, "note", None, None).unwrap();
        run_with(&mut m, Mode::Tidy, "note", None, None).unwrap();
        run_with(&mut m, Mode::Explain, "note", Some("sel"), None).unwrap();
        run_with(&mut m, Mode::Ask, "note", None, Some("why?")).unwrap();
        assert!(m.prompts[0].contains("no introduction") && m.prompts[0].contains("each starting with \"- \""));
        assert!(m.prompts[1].contains("no introduction") && m.prompts[1].contains("Add nothing and drop nothing"));
        assert!(!m.prompts[2].contains("no introduction") && m.prompts[2].contains("2 or 3 short sentences"));
        assert!(m.prompts[3].contains("the note does not say"));
        for p in &m.prompts {
            assert!(p.contains("Reply in the language of the note") && p.contains("Reply as JSON"), "{p}");
        }
    }

    #[test]
    fn each_mode_sends_only_what_it_needs() {
        let mut m = FakeLlm::new(&[r#"{"reply":"1"}"#, r#"{"reply":"2"}"#, r#"{"reply":"3"}"#]);
        run_with(&mut m, Mode::Ask, "  Heaps are trees.  ", Some("ignored selection"), Some("  What is a heap?  ")).unwrap();
        assert!(m.prompts[0].contains("Note:\nHeaps are trees.\n\nQuestion: What is a heap?"), "{}", m.prompts[0]);
        assert!(!m.prompts[0].contains("ignored selection"), "Ask answers from the whole note");
        run_with(&mut m, Mode::Summarize, "Heaps.", Some("sel"), Some("q")).unwrap();
        assert!(!m.prompts[1].contains("Selected words") && !m.prompts[1].contains("Question:"));
        run_with(&mut m, Mode::Explain, "Heaps are trees.", Some("  trees "), None).unwrap();
        assert!(m.prompts[2].contains("Note:\nHeaps are trees.\n\nSelected words: trees"));
    }

    #[test]
    fn blank_selection_and_question_count_as_missing() {
        let mut m = FakeLlm::new(&[]);
        assert_eq!(run_with(&mut m, Mode::Explain, "note", Some("   \n"), None).unwrap_err(), "Select the words to explain first.");
        assert_eq!(run_with(&mut m, Mode::Ask, "note", None, None).unwrap_err(), "Type a question first.");
        assert_eq!(run_with(&mut m, Mode::Ask, "note", None, Some("\n")).unwrap_err(), "Type a question first.");
        assert_eq!(run_with(&mut m, Mode::Summarize, "\n \t", None, None).unwrap_err(), "The note is empty.");
        assert!(m.prompts.is_empty());
    }

    #[test]
    fn a_blank_selection_makes_tidy_work_on_the_whole_note() {
        let mut m = FakeLlm::new(&[r#"{"reply":"clean"}"#]);
        run_with(&mut m, Mode::Tidy, "whole note", Some("  "), None).unwrap();
        assert!(m.prompts[0].contains("Note:\nwhole note"));
    }

    #[test]
    fn the_note_limit_counts_chars_and_includes_exactly_max_note() {
        let mut m = FakeLlm::new(&[r#"{"reply":"ok"}"#, r#"{"reply":"ok"}"#]);
        assert!(run_with(&mut m, Mode::Summarize, &"x".repeat(MAX_NOTE), None, None).is_ok(), "exactly MAX_NOTE fits");
        assert!(run_with(&mut m, Mode::Summarize, &"é".repeat(MAX_NOTE), None, None).is_ok(), "3000 two-byte chars are 3000 chars");
        assert!(run_with(&mut m, Mode::Summarize, &"日".repeat(MAX_NOTE + 1), None, None).is_err());
        assert_eq!(m.prompts.len(), 2);
    }

    #[test]
    fn the_limit_ignores_surrounding_blank_space_and_applies_to_a_tidy_selection() {
        let mut m = FakeLlm::new(&[r#"{"reply":"ok"}"#, r#"{"reply":"ok"}"#]);
        let padded = format!("\n\n{}\n\n", "x".repeat(MAX_NOTE));
        assert!(run_with(&mut m, Mode::Summarize, &padded, None, None).is_ok());
        let huge = "y".repeat(MAX_NOTE * 2);
        assert!(run_with(&mut m, Mode::Tidy, "short note", Some(&huge), None).is_err(), "a selection can be too long too");
        assert!(run_with(&mut m, Mode::Tidy, &huge, Some("a short part"), None).is_ok(), "selecting part of a long note is the way out");
    }

    #[test]
    fn tidy_may_write_more_than_the_other_modes() {
        let mut m = Spy::new(&[r#"{"reply":"ok"}"#]);
        for (mode, want) in [(Mode::Tidy, 700), (Mode::Summarize, 300), (Mode::Ask, 300), (Mode::Explain, 300)] {
            run(&mut m, Template::ChatMl, mode, "note", Some("sel"), Some("q"), &mut |_| ()).unwrap();
            assert_eq!(m.max_tokens.last(), Some(&want), "{mode:?}");
        }
        let schema = m.schemas[0].as_ref().unwrap();
        assert_eq!(schema["required"][0], "reply", "the model is forced to answer in `reply`");
    }

    #[test]
    fn the_template_wraps_the_note_prompt() {
        let mut m = FakeLlm::new(&[r#"{"reply":"a"}"#, r#"{"reply":"b"}"#]);
        run(&mut m, Template::ChatMl, Mode::Summarize, "n", None, None, &mut |_| ()).unwrap();
        run(&mut m, Template::Gemma, Mode::Summarize, "n", None, None, &mut |_| ()).unwrap();
        assert!(m.prompts[0].starts_with("<|im_start|>system\n") && m.prompts[0].ends_with("</think>\n\n"));
        assert!(m.prompts[1].starts_with("<start_of_turn>user\n") && m.prompts[1].ends_with("<start_of_turn>model\n"));
    }

    // C7: the card fills word by word, and the result is trimmed text, not JSON.
    #[test]
    fn the_result_streams_and_is_trimmed() {
        let mut m = Spy::new(&["{\"reply\": \"  - one\\n", "- two ", "\"}"]);
        let mut seen: Vec<String> = vec![];
        let out = run(&mut m, Template::Gemma, Mode::Summarize, "note", None, None, &mut |w| seen.push(w.into())).unwrap();
        assert_eq!(out, "- one\n- two");
        assert_eq!(seen.concat(), "  - one\n- two ", "the card shows words as written; the final text is trimmed");
        assert!(seen.len() >= 2, "more than one update: {seen:?}");
    }

    #[test]
    fn a_reply_cut_off_mid_json_is_an_error_not_half_a_note() {
        let mut m = Spy::new(&["{\"reply\": \"- one\\n- tw"]);
        let mut seen = String::new();
        let err = run(&mut m, Template::Gemma, Mode::Summarize, "note", None, None, &mut |w| seen.push_str(w)).unwrap_err();
        assert_eq!(err, "the reply has no JSON object");
        assert_eq!(seen, "- one\n- tw", "the words so far were still streamed");
    }

    #[test]
    fn empty_or_wrong_shaped_replies_are_errors() {
        for raw in [r#"{"reply":""}"#, r#"{"reply":"   \n"}"#, r#"{"other":"x"}"#, r#"{"reply":7}"#, "{}"] {
            let mut m = FakeLlm::new(&[raw]);
            assert_eq!(run_with(&mut m, Mode::Summarize, "note", None, None).unwrap_err(), "the reply came back empty", "{raw}");
        }
        let mut m = FakeLlm::new(&["no json at all"]);
        assert_eq!(run_with(&mut m, Mode::Summarize, "note", None, None).unwrap_err(), "the reply has no JSON object");
        let mut m = FakeLlm::new(&[]);
        assert_eq!(run_with(&mut m, Mode::Summarize, "note", None, None).unwrap_err(), "no reply queued", "model errors pass through");
    }

    #[test]
    fn thinking_and_code_fences_around_the_json_are_ignored() {
        let mut m = FakeLlm::new(&["<think>hmm</think>```json\n{\"reply\":\"- fine\"}\n```"]);
        assert_eq!(run_with(&mut m, Mode::Summarize, "note", None, None).unwrap(), "- fine");
    }

    // C8: every note error is a sentence that friendly() passes through untouched.
    #[test]
    fn note_errors_are_student_sentences() {
        use crate::assis::friendly;
        let mut m = FakeLlm::new(&[]);
        for (mode, text, sel, q) in [
            (Mode::Explain, "n", None, None),
            (Mode::Ask, "n", None, None),
            (Mode::Summarize, " ", None, None),
        ] {
            let e = run_with(&mut m, mode, text, sel, q).unwrap_err();
            assert_eq!(friendly(&e, true), e);
        }
        let long = run_with(&mut m, Mode::Tidy, &"x".repeat(MAX_NOTE + 1), None, None).unwrap_err();
        assert_eq!(friendly(&long, false), long);
    }
}
