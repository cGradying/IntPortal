//! A study note made from the chat itself (spec 062 C1–C6): "make a note of what we talked about". One model
//! call writes a title, a subject and bullets from the chat; the rules then drop any bullet carrying a number,
//! a date or a code the chat never said. Nothing is written here: the chat shows a card and Save writes it.
use crate::{intent::words, llm::Llm, prompt::Template, reply};
use serde::Deserialize;
use serde_json::{json, Value};

/// Characters of chat the note is made from, newest first (C3).
pub const CHAT_BUDGET: usize = 6000;
/// The one call's limit (C4).
pub const NOTE_TOKENS: u32 = 500;
const MAX_BULLETS: usize = 12;
const TITLE_WORDS: usize = 8;
/// The title used when the model's names something the chat never said.
pub const FALLBACK_TITLE: &str = "Notes from our chat";

#[derive(Debug, PartialEq)]
pub struct ChatNote {
    pub title: String,
    pub subject: Option<String>,
    /// "- " bullets, one per line.
    pub text: String,
    /// Older turns didn't fit the budget.
    pub partial: bool,
}

#[derive(Deserialize)]
struct Raw {
    title: String,
    #[serde(default)]
    subject: String,
    bullets: Vec<String>,
}

const SYSTEM: &str = "Turn the chat below between a student and LAR, their study helper, into one study note.
- title: what the note is about, at most 8 words.
- subject: the student's subject it belongs to, or \"none\".
- bullets: 3 to 12 short points with the facts, terms, steps and numbers the chat gave, in the chat's own words.
Use only what the chat says: add nothing, and leave out greetings and small talk. Write the points as facts, never about the chat, LAR or the student (not \"we talked about\", not \"LAR said\"). Plain text, English. Reply as JSON.";

/// The chat as "Student: … / LAR: …" lines, oldest first, cut from the oldest end to `budget` characters.
/// The flag is true when a turn was left out.
fn transcript(chat: &[(String, String)], budget: usize) -> (String, bool) {
    let mut kept: Vec<String> = vec![];
    let mut used = 0;
    for (me, lar) in chat.iter().rev() {
        let pair = format!("Student: {me}\nLAR: {lar}\n");
        let n = pair.chars().count();
        if used + n > budget {
            break;
        }
        used += n;
        kept.push(pair);
    }
    let partial = kept.len() < chat.len();
    kept.reverse();
    (kept.concat(), partial)
}

/// The runs of digits in `s`: "2026-10-16" is 2026, 10 and 16; "comp20073" is 20073.
fn numbers(s: &str) -> Vec<&str> {
    s.split(|c: char| !c.is_ascii_digit()).filter(|n| !n.is_empty()).collect()
}

/// Every number in `text` (a date's parts, a course code's number) is a whole number the chat said (C6):
/// a 20 the chat never said doesn't pass because the chat said 2026.
fn grounded(text: &str, chat: &[&str]) -> bool {
    numbers(text).iter().all(|n| chat.contains(n))
}

/// A bullet about the chat rather than the subject ("LAR explained the formula", "The student asked for an
/// example"): the prompt says not to, and Qwen3.5 2B wrote one in 3 of 10 chats anyway.
fn about_the_chat(text: &str) -> bool {
    const META: &[&str] = &["lar", "student", "students", "chat", "conversation", "asked", "discussed", "explained"];
    words(text).iter().any(|w| META.contains(&w.as_str()))
}

fn schema(subjects: &[String]) -> Value {
    let mut subs: Vec<&str> = subjects.iter().map(String::as_str).collect();
    subs.push("none");
    json!({"type": "object", "properties": {
        "title": {"type": "string", "maxLength": 80},
        "subject": {"enum": subs},
        "bullets": {"type": "array", "items": {"type": "string", "maxLength": 200}, "minItems": 1, "maxItems": MAX_BULLETS},
    }, "required": ["title", "subject", "bullets"]})
}

/// None when nothing grounded is left, so the caller says it couldn't make one.
pub fn make(llm: &mut dyn Llm, tpl: Template, chat: &[(String, String)], subjects: &[String]) -> Result<Option<ChatNote>, String> {
    let (said, partial) = transcript(chat, CHAT_BUDGET);
    if said.is_empty() {
        return Ok(None);
    }
    let raw = llm.generate(&tpl.wrap(SYSTEM, &format!("Chat:\n{said}")), Some(&schema(subjects)), NOTE_TOKENS, &mut |_| true)?;
    let r: Raw = reply::parse(&raw).map_err(|e| e.to_string())?;
    let heard = numbers(&said);
    let bullets: Vec<String> = r
        .bullets
        .iter()
        .map(|b| b.trim().trim_start_matches(['-', '*', '•', ' ']).trim().to_string())
        .filter(|b| !b.is_empty() && grounded(b, &heard) && !about_the_chat(b))
        .take(MAX_BULLETS)
        .collect();
    if bullets.is_empty() {
        return Ok(None);
    }
    let title: String = r.title.split_whitespace().take(TITLE_WORDS).collect::<Vec<_>>().join(" ").trim_end_matches(['.', ':']).to_string();
    let title = if title.is_empty() || !grounded(&title, &heard) { FALLBACK_TITLE.to_string() } else { title };
    let subject = Some(r.subject).filter(|s| subjects.contains(s));
    Ok(Some(ChatNote { title, subject, text: bullets.iter().map(|b| format!("- {b}")).collect::<Vec<_>>().join("\n"), partial }))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::llm::FakeLlm;

    fn pair(me: &str, lar: &str) -> (String, String) {
        (me.into(), lar.into())
    }

    #[test]
    fn makes_a_titled_note_of_bullets_from_the_chat() {
        let chat = [pair("what is a heap?", "A heap is a tree where each parent is at least as big as its children. Insert is O(log n).")];
        let mut m = FakeLlm::new(&[r#"{"title":"Heaps","subject":"COMP 20073","bullets":["- A tree where each parent is at least as big as its children","Insert is O(log n)"]}"#]);
        let note = make(&mut m, Template::ChatMl, &chat, &["COMP 20073".into()]).unwrap().unwrap();
        assert_eq!(note, ChatNote { title: "Heaps".into(), subject: Some("COMP 20073".into()), text: "- A tree where each parent is at least as big as its children\n- Insert is O(log n)".into(), partial: false });
        assert_eq!(m.prompts.len(), 1, "one model call (C4)");
        assert!(m.prompts[0].contains("Student: what is a heap?\nLAR: A heap is"));
    }

    #[test]
    fn a_bullet_with_a_number_the_chat_never_said_is_dropped() {
        let chat = [pair("when is the quiz?", "Your quiz is on Friday at 9.")];
        let mut m = FakeLlm::new(&[r#"{"title":"Quiz 3 on Friday","subject":"none","bullets":["Quiz on Friday at 9","Worth 20% of the grade"]}"#]);
        let note = make(&mut m, Template::ChatMl, &chat, &[]).unwrap().unwrap();
        assert_eq!(note.text, "- Quiz on Friday at 9");
        assert_eq!(note.title, FALLBACK_TITLE, "the title named a 3 the chat never said");
        assert_eq!(note.subject, None);
    }

    #[test]
    fn a_bullet_about_the_chat_itself_is_dropped() {
        let chat = [pair("power rule?", "The derivative of x^n is n times x^(n-1).")];
        let mut m = FakeLlm::new(&[r#"{"title":"Power rule","subject":"none","bullets":["The derivative of x^n is n times x^(n-1)","LAR explained the formula","The student asked for an example"]}"#]);
        assert_eq!(make(&mut m, Template::ChatMl, &chat, &[]).unwrap().unwrap().text, "- The derivative of x^n is n times x^(n-1)");
    }

    #[test]
    fn nothing_grounded_left_is_no_note() {
        let chat = [pair("hi", "Hello!")];
        let mut m = FakeLlm::new(&[r#"{"title":"Greeting","subject":"none","bullets":["Room 302"]}"#]);
        assert_eq!(make(&mut m, Template::ChatMl, &chat, &[]).unwrap(), None);
        assert_eq!(make(&mut FakeLlm::new(&[]), Template::ChatMl, &[], &[]).unwrap(), None, "no chat, no call");
    }

    #[test]
    fn a_long_chat_keeps_its_newest_turns_and_says_so() {
        let old = pair(&"old ".repeat(2000), "x");
        let new = pair("newest question", "newest answer");
        let (said, partial) = transcript(&[old, new], CHAT_BUDGET);
        assert!(partial);
        assert_eq!(said, "Student: newest question\nLAR: newest answer\n");
        let mut m = FakeLlm::new(&[r#"{"title":"T","subject":"none","bullets":["newest answer"]}"#]);
        let chat = [pair(&"old ".repeat(2000), "x"), pair("newest question", "newest answer")];
        assert!(make(&mut m, Template::ChatMl, &chat, &[]).unwrap().unwrap().partial);
    }

    fn note_of(raw: &str, chat: &[(String, String)], subjects: &[String]) -> Result<Option<ChatNote>, String> {
        make(&mut FakeLlm::new(&[raw]), Template::ChatMl, chat, subjects)
    }

    #[test]
    fn the_transcript_takes_a_turn_that_fits_the_budget_exactly_and_drops_one_char_over() {
        let t = pair("q", "a"); // "Student: q\nLAR: a\n" = 19 chars
        let n = "Student: q\nLAR: a\n".chars().count();
        assert_eq!(transcript(std::slice::from_ref(&t), n), ("Student: q\nLAR: a\n".into(), false));
        assert_eq!(transcript(std::slice::from_ref(&t), n - 1), (String::new(), true));
        assert_eq!(transcript(&[t.clone(), t.clone()], n * 2 - 1).0.chars().count(), n, "only the newest of two fits");
        assert_eq!(transcript(&[], 10), (String::new(), false));
    }

    #[test]
    fn the_transcript_counts_characters_not_bytes_and_stops_at_the_first_turn_that_does_not_fit() {
        let wide = pair("é", "ñ"); // 2-byte chars: counted as one each
        let n = "Student: é\nLAR: ñ\n".chars().count();
        assert!(!transcript(std::slice::from_ref(&wide), n).1);
        let big = pair(&"x".repeat(100), "y");
        let small = pair("s", "t");
        // newest small fits, the big one before it does not, and the small one before the big is not reached
        let (said, partial) = transcript(&[small.clone(), big, small], 60);
        assert!(partial);
        assert_eq!(said, "Student: s\nLAR: t\n");
    }

    #[test]
    fn a_chat_over_the_budget_in_one_turn_makes_no_call() {
        let chat = [pair(&"x".repeat(CHAT_BUDGET), "y")];
        let mut m = FakeLlm::new(&[]);
        assert_eq!(make(&mut m, Template::ChatMl, &chat, &[]).unwrap(), None);
        assert!(m.prompts.is_empty());
    }

    #[test]
    fn grounded_matches_a_course_code_with_or_without_its_space() {
        let chat = [pair("what class?", "It is comp20073 on Monday.")];
        let n = note_of(r#"{"title":"Class","subject":"none","bullets":["Class is COMP 20073 on Monday"]}"#, &chat, &[]).unwrap().unwrap();
        assert_eq!(n.text, "- Class is COMP 20073 on Monday");
        let chat = [pair("what class?", "It is COMP 20073 on Monday.")];
        let n = note_of(r#"{"title":"Class","subject":"none","bullets":["Class is comp20073"]}"#, &chat, &[]).unwrap().unwrap();
        assert_eq!(n.text, "- Class is comp20073");
    }

    #[test]
    fn a_bullet_with_a_wrong_date_or_code_is_dropped_but_a_said_one_stays() {
        let chat = [pair("exam?", "The exam is on 2026-10-16 for COMP 20073. Bring 2 pencils.")];
        let raw = r#"{"title":"Exam","subject":"none","bullets":["Exam on 2026-10-16","Exam on 2026-10-17","Course COMP 20074","Bring 2 pencils","Bring 9 pencils","No digits at all here"]}"#;
        let n = note_of(raw, &chat, &[]).unwrap().unwrap();
        assert_eq!(n.text, "- Exam on 2026-10-16\n- Bring 2 pencils\n- No digits at all here");
    }

    #[test]
    fn a_number_that_is_only_part_of_a_longer_chat_number_is_not_said() {
        let chat = [pair("year?", "It is 2026.")];
        assert_eq!(note_of(r#"{"title":"Year","subject":"none","bullets":["The room is 20","It is 2026"]}"#, &chat, &[]).unwrap().unwrap().text, "- It is 2026");
    }

    #[test]
    fn about_the_chat_catches_each_meta_word_and_leaves_subject_words_alone() {
        for b in ["LAR said hello", "The Student must review", "students learn", "In this chat we saw", "A conversation about trees", "He asked why", "They discussed trees", "Explained the proof"] {
            assert!(about_the_chat(b), "{b}");
        }
        for b in ["A heap is a tree", "Larynx is part of the throat", "Chatter is noise", "Ask the professor"] {
            assert!(!about_the_chat(b), "{b}");
        }
    }

    #[test]
    fn a_title_over_eight_words_is_cut_and_loses_its_trailing_dot_or_colon() {
        let chat = [pair("trees", "one two three four five six seven eight nine ten")];
        let raw = r#"{"title":"one two three four five six seven eight nine ten","subject":"none","bullets":["one two three"]}"#;
        assert_eq!(note_of(raw, &chat, &[]).unwrap().unwrap().title, "one two three four five six seven eight");
        let raw = r#"{"title":"Heaps:","subject":"none","bullets":["a heap"]}"#;
        let chat = [pair("heaps", "a heap is a tree")];
        assert_eq!(note_of(raw, &chat, &[]).unwrap().unwrap().title, "Heaps");
    }

    #[test]
    fn a_blank_title_falls_back() {
        let chat = [pair("heaps", "a heap is a tree")];
        for t in ["", "   "] {
            let raw = format!(r#"{{"title":"{t}","subject":"none","bullets":["a heap is a tree"]}}"#);
            assert_eq!(note_of(&raw, &chat, &[]).unwrap().unwrap().title, FALLBACK_TITLE, "{t:?}");
        }
    }

    #[test]
    fn a_subject_not_in_the_list_is_none_and_one_in_the_list_is_kept() {
        let chat = [pair("heaps", "a heap is a tree")];
        let subs = vec!["COMP 20073".to_string()];
        let mk = |s: &str| note_of(&format!(r#"{{"title":"Heaps","subject":"{s}","bullets":["a heap is a tree"]}}"#), &chat, &subs).unwrap().unwrap().subject;
        assert_eq!(mk("MATH 101"), None);
        assert_eq!(mk("none"), None);
        assert_eq!(mk(""), None);
        assert_eq!(mk("comp 20073"), None, "must match the list exactly");
        assert_eq!(mk("COMP 20073"), Some("COMP 20073".into()));
        let no_subject_key = note_of(r#"{"title":"Heaps","bullets":["a heap is a tree"]}"#, &chat, &subs).unwrap().unwrap();
        assert_eq!(no_subject_key.subject, None, "subject may be missing");
    }

    #[test]
    fn bullet_markers_and_spaces_are_trimmed_and_empty_bullets_dropped() {
        let chat = [pair("heaps", "a heap is a tree. b is c. d is e. f is g.")];
        let raw = r#"{"title":"Heaps","subject":"none","bullets":["- a heap is a tree","* b is c","• d is e","  -  * f is g  ","-","  ","*"]}"#;
        assert_eq!(note_of(raw, &chat, &[]).unwrap().unwrap().text, "- a heap is a tree\n- b is c\n- d is e\n- f is g");
    }

    #[test]
    fn at_most_twelve_bullets_are_kept() {
        let said: String = (1..=15).map(|i| format!("fact{} ", ["a","b","c","d","e","f","g","h","i","j","k","l","m","n","o"][i - 1])).collect();
        let chat = [pair("facts", &said)];
        let bullets: Vec<String> = ["a","b","c","d","e","f","g","h","i","j","k","l","m","n","o"].iter().map(|x| format!("\"fact{x}\"")).collect();
        let raw = format!(r#"{{"title":"Facts","subject":"none","bullets":[{}]}}"#, bullets.join(","));
        let n = note_of(&raw, &chat, &[]).unwrap().unwrap();
        assert_eq!(n.text.lines().count(), 12);
        assert!(n.text.ends_with("- factl"));
    }

    #[test]
    fn malformed_json_or_a_missing_field_is_an_error_not_a_note() {
        let chat = [pair("heaps", "a heap is a tree")];
        for raw in ["not json at all", "", r#"{"title":"Heaps"}"#, r#"{"title":"Heaps","subject":"none","bullets":"a heap"}"#, r#"{"subject":"none","bullets":["a heap is a tree"]}"#] {
            assert!(note_of(raw, &chat, &[]).is_err(), "{raw}");
        }
    }

    #[test]
    fn the_call_sends_the_schema_and_the_token_limit() {
        let chat = [pair("heaps", "a heap is a tree")];
        let s = schema(&["COMP 20073".to_string()]);
        assert_eq!(s["properties"]["subject"]["enum"], json!(["COMP 20073", "none"]));
        assert_eq!(s["properties"]["bullets"]["maxItems"], 12);
        assert_eq!(NOTE_TOKENS, 500);
        let mut m = FakeLlm::new(&[r#"{"title":"Heaps","subject":"none","bullets":["a heap is a tree"]}"#]);
        make(&mut m, Template::ChatMl, &chat, &[]).unwrap();
        assert_eq!(m.prompts.len(), 1);
    }
}
