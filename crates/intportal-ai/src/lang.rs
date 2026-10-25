//! The language of an open reply. Qwen3 1.7B answers a Filipino or Taglish question in English
//! unless something in the prompt shows it Filipino; an explicit "reply in Filipino" line makes it
//! loop (docs/ai.md, "Reply language"). So the prompt never asks. Three cheap techniques, each
//! switchable in a `Plan` so the eval can measure them one by one:
//! 1. `shots`: the persona's examples are only in the student's language.
//! 2. `prefill`: the assistant's turn starts inside the JSON with a short Filipino opener
//!    (`{"reply":"Sige,`) and the model continues in that language.
//! 3. `retry`: a Filipino question that still got an English reply is asked once more (measured: no
//!    gain with greedy decoding, so no model uses it).
//!
//! Whatever the plan, a reply that loops is replaced by the "ask it another way" line.
use crate::{
    assis::PROMPT_BUDGET,
    llm::Llm,
    persona,
    prompt::{build, Section, Template},
    reply::{self, ReplyStream},
};
use serde_json::{json, Value};

/// Function words that only Filipino uses (or that English never spells that way). "may", "at" and
/// "no" are left out: they are English words too.
const FIL: &[&str] = &[
    "ang", "ng", "mga", "sa", "ay", "na", "mo", "ko", "ka", "ako", "ikaw", "siya", "kami", "tayo", "natin", "namin", "nila", "niya", "ito", "iyon", "iyan", "yan", "yung", "ba", "naman", "lang", "po", "para", "kung", "kasi", "pero", "wala", "hindi", "ngayon", "bukas", "kailan", "ano", "paano", "bakit", "sino", "dito", "doon", "din", "rin", "pa", "nang", "si", "ni", "kay", "sila", "kayo", "nasa", "lahat", "isang", "ibang", "pwede", "dapat", "gusto", "kaya", "sana", "talaga", "heto",
];

/// The common English function words.
const EN: &[&str] = &[
    "the", "a", "an", "is", "are", "was", "were", "be", "to", "of", "and", "in", "on", "for", "with", "it", "this", "that", "these", "those", "you", "your", "i", "i'm", "my", "me", "we", "they", "have", "has", "had", "can", "will", "would", "should", "do", "does", "did", "not", "don't", "doesn't", "but", "or", "if", "as", "by", "from", "here", "there", "what", "which", "who", "how", "when", "where", "why", "so", "just", "about",
];

/// (Filipino, English) function words in `text`.
pub fn counts(text: &str) -> (usize, usize) {
    let low = text.to_lowercase().replace('\u{2019}', "'");
    let w: Vec<&str> = low.split(|c: char| !(c.is_alphanumeric() || c == '\'')).filter(|x| !x.is_empty()).collect();
    (w.iter().filter(|x| FIL.contains(x)).count(), w.iter().filter(|x| EN.contains(x)).count())
}

/// The reply is English: two English function words and more than twice as many as Filipino ones.
/// Taglish (English terms in Filipino sentences) is not English; neither is a one-word reply.
pub fn reads_english(text: &str) -> bool {
    let (f, e) = counts(text);
    e >= 2 && e > 2 * f
}

/// What to do about the language of an open reply.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Plan {
    /// Examples in the student's language only.
    pub shots: bool,
    /// Start a Filipino reply with an opener inside the JSON.
    pub prefill: bool,
    /// When a Filipino question got an English reply, ask once more with these (shots, prefill).
    pub retry: Option<(bool, bool)>,
}

impl Plan {
    /// What LAR did before this module: every example, no prefill, no retry.
    pub const BASELINE: Plan = Plan { shots: false, prefill: false, retry: None };

    /// What each model gets, from the measurements in docs/ai.md ("Reply language"): Qwen3 1.7B follows
    /// the examples (an opener made it commit to an answer and loop more); Gemma 3 1B needs the opener
    /// as well (15 of 24 Filipino with examples alone, 21 with both). Retrying changed nothing for either:
    /// greedy decoding answers the same prompt the same way.
    pub fn for_template(tpl: Template) -> Plan {
        match tpl {
            Template::ChatMl => Plan { shots: true, prefill: false, retry: None },
            Template::Gemma => Plan { shots: true, prefill: true, retry: None },
        }
    }
}

/// The same word three words long, three times over: the model is stuck. Qwen3 1.7B does this in
/// Filipino ("ang nangunguna na nangunguna na nangunguna") on about one question in eight.
pub fn looped(text: &str) -> bool {
    let low = text.to_lowercase();
    let w: Vec<&str> = low.split_whitespace().collect();
    w.windows(3).any(|t| w.windows(3).filter(|u| *u == t).count() >= 3)
}

/// The `{"reply":"` and opener a Filipino reply starts with.
fn prefill_for(msg: &str) -> String {
    format!("{{\"reply\":\"{}", persona::opener(msg))
}

/// One attempt. Returns the raw JSON the model wrote (prefill included).
#[allow(clippy::too_many_arguments)]
fn attempt(llm: &mut dyn Llm, tpl: Template, style: Option<&str>, sections: &[Section], msg: &str, fil: bool, (shots, prefill): (bool, bool), schema: &Value, on_text: &mut dyn FnMut(&str)) -> Result<String, String> {
    let system = if shots { persona::system(style, fil) } else { persona::system_all(style) };
    let prompt = tpl.wrap(&build(&system, sections, PROMPT_BUDGET), &format!("Student: {msg}"));
    let mut stream = ReplyStream::default();
    let mut show = |piece: &str| {
        if let Some(words) = stream.feed(piece) {
            on_text(&words);
        }
        true
    };
    if prefill && fil {
        let start = prefill_for(msg);
        show(&start); // the opener is already written: the chat shows it at once
        llm.generate_prefilled(&prompt, &start, Some(schema), 300, &mut show)
    } else {
        llm.generate(&prompt, Some(schema), 300, &mut show)
    }
}

fn reply_of(raw: &str) -> String {
    reply::parse::<Value>(raw).ok().and_then(|v| v["reply"].as_str().map(String::from)).unwrap_or_default()
}

/// The model's raw JSON for an open question, in the student's language as far as `plan` can make it.
/// The words of the first attempt stream to `on_text`; a retry streams nothing (the chat replaces
/// the streamed words with the final reply).
#[allow(clippy::too_many_arguments)]
pub fn open_reply(llm: &mut dyn Llm, tpl: Template, plan: Plan, style: Option<&str>, sections: &[Section], msg: &str, fil: bool, schema: &Value, on_text: &mut dyn FnMut(&str)) -> Result<String, String> {
    let mut raw = attempt(llm, tpl, style, sections, msg, fil, (plan.shots, plan.prefill), schema, on_text)?;
    if let Some(again) = plan.retry.filter(|_| fil && reads_english(&reply_of(&raw))) {
        // A failed retry keeps the first answer: English beats an error.
        raw = attempt(llm, tpl, style, sections, msg, fil, again, schema, &mut |_| ()).ok().filter(|r| !reply_of(r).is_empty()).unwrap_or(raw);
    }
    // Words that go round in a circle are not an answer; ask for the question another way.
    if looped(&reply_of(&raw)) {
        return Ok(json!({"reply": persona::line(persona::Line::Retry, fil, msg)}).to_string());
    }
    Ok(raw)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::llm::FakeLlm;
    use serde_json::json;

    const PLAN: Plan = Plan { shots: true, prefill: false, retry: Some((true, true)) };

    fn schema() -> Value {
        json!({"type": "object", "properties": {"reply": {"type": "string"}}, "required": ["reply"]})
    }

    fn ask(llm: &mut FakeLlm, plan: Plan, msg: &str, fil: bool) -> (String, String) {
        let sections = [Section { title: "From the student's notes", body: "- Math 101: passing is 75%.\n", priority: 7 }];
        let mut shown = String::new();
        let raw = open_reply(llm, Template::ChatMl, plan, None, &sections, msg, fil, &schema(), &mut |w| shown.push_str(w)).unwrap();
        (reply_of(&raw), shown)
    }

    #[test]
    fn english_and_filipino_replies_are_told_apart() {
        assert!(reads_english("Preorder traversal is when you visit the node first."));
        assert!(reads_english("I don't see that in your notes."));
        assert!(!reads_english("Ang passing sa Math 101 ay 75%."));
        assert!(!reads_english("Ang quiz sa Math 101 ay on Monday, covers limits at derivatives."), "Taglish is not English");
        assert!(!reads_english("75%") && !reads_english(""), "too short to say");
        assert_eq!(counts("Ang quiz ay bukas, the end"), (3, 1));
    }

    #[test]
    fn a_filipino_question_sees_only_filipino_examples_and_an_english_one_only_english() {
        let mut m = FakeLlm::new(&[r#"{"reply":"ok"}"#, r#"{"reply":"ok"}"#, r#"{"reply":"ok"}"#]);
        ask(&mut m, Plan { shots: true, prefill: false, retry: None }, "magkano ang tuition ko?", true);
        ask(&mut m, Plan { shots: true, prefill: false, retry: None }, "how much is my tuition?", false);
        ask(&mut m, Plan::BASELINE, "magkano ang tuition ko?", true);
        let (fil, en, base) = (&m.prompts[0], &m.prompts[1], &m.prompts[2]);
        assert!(fil.contains("salamat po") && fil.contains("Ramdam kita") && !fil.contains("thanks LAR") && !fil.contains("adviser's email"));
        assert!(en.contains("thanks LAR") && en.contains("adviser's email") && !en.contains("salamat po") && !en.contains("Ramdam kita"));
        assert!(base.contains("salamat po") && base.contains("thanks LAR"), "the baseline keeps both");
        assert!(!fil.to_lowercase().contains("reply in filipino") && !fil.to_lowercase().contains("answer in filipino"), "that line made Qwen loop");
    }

    #[test]
    fn a_filipino_reply_starts_with_an_opener_the_model_continues_and_the_chat_shows_it_once() {
        let mut m = FakeLlm::new(&[r#" ang passing ay 75%."}"#]);
        let msg = "ano ang passing sa Math 101?";
        let (reply, shown) = ask(&mut m, Plan::for_template(Template::Gemma), msg, true);
        let opener = persona::opener(msg);
        assert!(m.prompts[0].ends_with(&format!("{{\"reply\":\"{opener}")), "the assistant's turn is already open: {}", &m.prompts[0][m.prompts[0].len() - 40..]);
        assert_eq!(reply, format!("{opener} ang passing ay 75%."));
        assert_eq!(shown, reply, "the opener is shown at once and never again");
    }

    #[test]
    fn each_model_gets_the_plan_it_was_measured_with() {
        assert_eq!(Plan::for_template(Template::ChatMl), Plan { shots: true, prefill: false, retry: None });
        assert_eq!(Plan::for_template(Template::Gemma), Plan { shots: true, prefill: true, retry: None });
    }

    #[test]
    fn a_reply_that_goes_round_in_circles_becomes_the_ask_again_line() {
        let stuck = "Ang height ay nangunguna sa tree. Ang height ay nangunguna sa tree. Ang height ay nangunguna sa tree. Ang height ay nangunguna";
        assert!(looped(stuck) && !looped("Ang inorder traversal ay kaliwa, node, kanan. Sa BST, sorted ang keys."));
        assert!(!looped("Mercury, Venus, Earth, Mars, Jupiter, Saturn, Uranus, Neptune."), "a list is not a loop");
        let mut m = FakeLlm::new(&[&json!({"reply": stuck}).to_string()]);
        let (reply, _) = ask(&mut m, Plan { shots: true, prefill: false, retry: None }, "ano ang height ng tree?", true);
        assert!(persona::lines(persona::Line::Retry, true).contains(&reply.as_str()), "{reply}");
        let mut m = FakeLlm::new(&[&json!({"reply": stuck.replace("Ang", "The")}).to_string()]);
        let (reply, _) = ask(&mut m, Plan::BASELINE, "what is the height of a tree?", false);
        assert!(persona::lines(persona::Line::Retry, false).contains(&reply.as_str()), "{reply}");
    }

    #[test]
    fn no_prefill_for_an_english_question_or_when_it_is_off() {
        let mut m = FakeLlm::new(&[r#"{"reply":"It is 75%."}"#, r#"{"reply":"Ang passing ay 75%."}"#]);
        ask(&mut m, Plan::for_template(Template::Gemma), "what is the passing mark?", false);
        ask(&mut m, Plan { shots: true, prefill: false, retry: None }, "ano ang passing?", true);
        assert!(m.prompts.iter().all(|p| !p.contains("{\"reply\":\"")), "no JSON in the assistant's turn");
    }

    #[test]
    fn a_filipino_question_answered_in_english_is_asked_once_more_and_the_new_answer_wins() {
        let mut m = FakeLlm::new(&[r#"{"reply":"The passing mark is 75%, as your note says."}"#, r#" ang passing mark ay 75%."}"#]);
        let msg = "ano ang passing mark?";
        let (reply, shown) = ask(&mut m, PLAN, msg, true);
        assert_eq!(m.prompts.len(), 2);
        assert!(!m.prompts[0].contains("{\"reply\":\""), "the first try had no prefill");
        assert!(m.prompts[1].ends_with(persona::opener(msg)), "the second has the opener");
        assert_eq!(reply, format!("{} ang passing mark ay 75%.", persona::opener(msg)));
        assert!(shown.contains("The passing mark"), "the first try streamed; the chat swaps in the final reply");
        assert!(!shown.contains("ang passing mark ay"), "the retry streams nothing");
    }

    #[test]
    fn nothing_is_retried_when_the_reply_is_filipino_the_question_is_english_or_the_retry_fails() {
        let mut m = FakeLlm::new(&[r#"{"reply":"Ang passing ay 75%."}"#]);
        assert_eq!(ask(&mut m, PLAN, "ano ang passing?", true).0, "Ang passing ay 75%.");
        assert_eq!(m.prompts.len(), 1);
        let mut m = FakeLlm::new(&[r#"{"reply":"It is 75%, per your note."}"#]);
        ask(&mut m, PLAN, "what is the passing mark?", false);
        assert_eq!(m.prompts.len(), 1);
        // The retry errors (nothing queued): the English answer stays, it is not lost.
        let mut m = FakeLlm::new(&[r#"{"reply":"The passing mark is 75%, as your note says."}"#]);
        assert_eq!(ask(&mut m, PLAN, "ano ang passing mark?", true).0, "The passing mark is 75%, as your note says.");
        assert_eq!(m.prompts.len(), 2);
    }
}
