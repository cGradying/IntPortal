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

/// Lower-case letters and digits, so "COMP 20073" and "comp20073" match.
fn norm(s: &str) -> String {
    s.chars().filter(|c| c.is_alphanumeric()).flat_map(char::to_lowercase).collect()
}

/// Every word of `text` that holds a digit (a number, a date, a course code's number) is in the chat (C6).
fn grounded(text: &str, chat: &str) -> bool {
    words(text).iter().filter(|w| w.chars().any(|c| c.is_ascii_digit())).all(|w| chat.contains(&norm(w)))
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
    let heard = norm(&said);
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
}
