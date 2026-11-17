//! Flashcards, in batches, made for the study game (spec 021 C22–C25, spec 055): a term or short question
//! on the front, its meaning or answer on the back, so flash, type ("type the term" from the back) and
//! choice (wrong answers are other backs) all work. Small models lose the thread on long outputs, so ask
//! for 12, retry a failed batch at 6, drop duplicates, and keep what arrived if a later batch fails (the
//! old macOS app's rules). Every card is checked before it is kept: a back that repeats its front, gives
//! the term away, asks a question or runs long is dropped, and a "Term is ..." back is cut to its meaning.
use crate::{intent::words, llm::Llm, prompt::Template, reply};
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

/// The most words on a front and on a back (C23).
pub const FRONT_WORDS: usize = 8;
pub const BACK_WORDS: usize = 30;

/// Why a card was dropped (C24).
#[derive(Debug, PartialEq, Eq)]
pub enum Reject {
    Blank,
    /// The back says the front again: the answer is the question.
    Echo,
    /// The back names the front's term, so typing the term from the back is free.
    GivesAway,
    /// The back is a question, not an answer.
    Question,
    TooLong,
    /// A card of the prompt's own example.
    Example,
}

const SYSTEM: &str = "You write study flashcards for a card game. Each card has a front and a back.
- front: a key term, or a short question, at most 8 words.
- back: the meaning of the term or the answer to the question, one plain statement of at most 30 words. Never a question.
- The back must not repeat the front or use the front's term: \"Osmosis\" gets \"Water moving through a membrane toward the side with more dissolved substance\", not \"Osmosis is osmosis\" and not \"Osmosis is when...\".
- Write all backs in the same form, so any back could pass for the answer to another card.
- Don't start every front with the topic's name; name the thing itself.
- One fact per card, each card about something different. Plain text: no LaTeX, no markdown, write math like x^2. English. Reply as JSON.";

/// The example in the prompt, in a subject far from most decks; a card copied from it is dropped.
const EXAMPLE: [(&str, &str); 2] = [("Igneous rock", "Rock formed when melted rock cools and hardens"), ("What drives plate movement?", "Heat currents in the mantle slowly pushing the crust")];

fn example_json() -> String {
    json!({"cards": EXAMPLE.iter().map(|(f, b)| json!({"front": f, "back": b})).collect::<Vec<_>>()}).to_string()
}

fn key(front: &str) -> String {
    front.to_lowercase().chars().filter(|c| c.is_alphanumeric()).collect()
}

/// Words that carry meaning (four letters or more, or a number), for comparing a back with its front.
fn content(text: &str) -> Vec<String> {
    const SKIP: &[&str] = &["what", "which", "when", "where", "does", "that", "this", "with", "from", "into", "they", "them", "their", "there", "these", "those", "have", "been", "your", "about", "called", "known", "term", "means", "mean", "define", "explain"];
    words(text).into_iter().filter(|w| (w.chars().count() >= 4 || w.chars().all(|c| c.is_ascii_digit())) && !SKIP.contains(&w.as_str())).collect()
}

/// A front that names a thing ("Osmosis", "Binary search tree") rather than asking.
fn is_term(front: &str) -> bool {
    !front.trim_end().ends_with('?') && front.split_whitespace().count() <= 4
}

/// "Osmosis is water moving ..." is cut to "Water moving ...": the definition without the term, which is
/// what the back of a type-the-term card must be. Other backs are only trimmed.
pub fn repair(card: &Card) -> Card {
    let (front, back) = (card.front.trim().trim_end_matches(['.', ':']).to_string(), card.back.trim().to_string());
    let mut out = back.clone();
    if is_term(&front) {
        let low = back.to_lowercase();
        let term = front.to_lowercase();
        // Only "Term is …", "Term: …", "A term means …": the term as a whole word, then a link to its meaning.
        // "The root node of a tree is …" or "The revolution ended …" are left alone (and may fail `check`).
        const LINKS: [&str; 11] = [": ", " - ", " is when ", " is a ", " is an ", " is the ", " are the ", " refers to ", " means ", " is ", " are "];
        let cut = ["a ", "an ", "the ", ""].iter().find_map(|a| {
            let rest = low.strip_prefix(&format!("{a}{term}"))?;
            LINKS.iter().find(|l| rest.starts_with(*l)).map(|l| back.len() - rest.len() + l.len())
        });
        if let Some(cut) = cut {
            let mut c = back[cut..].trim_start().chars();
            if let Some(first) = c.next() {
                out = first.to_uppercase().chain(c).collect();
            }
        }
    }
    Card { front, back: out.trim().trim_end_matches('.').to_string() }
}

/// Whether a (repaired) card is fit for the game.
pub fn check(card: &Card) -> Result<(), Reject> {
    let (front, back) = (card.front.trim(), card.back.trim());
    if front.is_empty() || back.is_empty() || content(back).is_empty() {
        return Err(Reject::Blank);
    }
    if EXAMPLE.iter().any(|(f, b)| key(f) == key(front) || key(b) == key(back)) {
        return Err(Reject::Example);
    }
    if front.split_whitespace().count() > FRONT_WORDS + 4 || back.split_whitespace().count() > BACK_WORDS {
        return Err(Reject::TooLong);
    }
    if back.ends_with('?') {
        return Err(Reject::Question);
    }
    let (f, b) = (content(front), content(back));
    // The back says nothing the front doesn't: "What is a stack?" / "A stack".
    if key(front) == key(back) || (!b.is_empty() && b.iter().filter(|w| f.contains(w)).count() * 10 >= b.len() * 7) {
        return Err(Reject::Echo);
    }
    if is_term(front) && !f.is_empty() && f.iter().all(|w| b.contains(w)) {
        return Err(Reject::GivesAway);
    }
    Ok(())
}

fn schema() -> serde_json::Value {
    json!({"type": "object", "properties": {"cards": {"type": "array", "items": {
        "type": "object", "properties": {"front": {"type": "string", "maxLength": 80}, "back": {"type": "string", "maxLength": 200}}, "required": ["front", "back"]}}},
        "required": ["cards"]})
}

/// Flashcards from a note's or a PDF's text: only that text (C22).
/// `tpl` is the loaded model's own prompt wrapper: a Gemma model given ChatML answers badly.
pub fn cards(llm: &mut dyn Llm, tpl: Template, source: &str, want: usize) -> Outcome {
    run(llm, tpl, want, &|n| format!("Write {n} flashcards from this text, using only what it says.\n\n{source}"))
}

/// Flashcards on a topic the student named in the chat (C22): the passages the note search found for it
/// first, then what the model knows about it.
pub fn topic_cards(llm: &mut dyn Llm, tpl: Template, topic: &str, passages: &[String], want: usize) -> Outcome {
    let notes: String = passages.iter().map(|p| format!("- {p}\n")).collect();
    run(llm, tpl, want, &|n| {
        if notes.is_empty() {
            format!("Write {n} flashcards on {topic}, from what you know. Only facts you are sure of.")
        } else {
            format!("Write {n} flashcards on {topic}. Use these passages from the student's notes first; add what you know about {topic} only where they stop.\n\n{notes}")
        }
    })
}

fn run(llm: &mut dyn Llm, tpl: Template, want: usize, ask: &dyn Fn(usize) -> String) -> Outcome {
    let system = format!("{SYSTEM}\nExample of the form (a different subject, never copy it): {}", example_json());
    let (mut out, mut seen) = (Vec::<Card>::new(), std::collections::HashSet::new());
    let (mut size, mut strict) = (12, false);
    while out.len() < want {
        let n = size.min(want - out.len());
        let avoid: String = out.iter().map(|c| format!("- {}\n", c.front)).collect();
        let stricter = if strict { "\nLast time every back repeated its front or gave the term away. Each back must say what the front means in other words." } else { "" };
        let user = format!("{}{stricter}\n\nAlready written, do not repeat:\n{avoid}", ask(n));
        let parsed = llm
            .generate(&tpl.wrap(&system, &user), Some(&schema()), 1024, &mut |_| true)
            .and_then(|raw| reply::parse::<Batch>(&raw).map_err(|e| e.to_string()));
        match parsed {
            Ok(b) => {
                let before = out.len();
                let fit: Vec<Card> = b.cards.iter().map(repair).filter(|c| check(c).is_ok()).collect();
                let all_failed = !b.cards.is_empty() && fit.is_empty();
                for c in fit {
                    if seen.insert(key(&c.front)) && out.len() < want {
                        out.push(c);
                    }
                }
                if out.len() == before {
                    // Every card failed its check: once more with the reason spelled out (C24), then stop.
                    // Only repeats of cards already made end the run at once.
                    if all_failed && !strict {
                        strict = true;
                        continue;
                    }
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
        let cards: Vec<_> = fronts.iter().map(|f| json!({"front": f, "back": "Something worth remembering for the quiz"})).collect();
        json!({"cards": cards}).to_string()
    }

    #[test]
    fn dedupes_and_stops_at_want() {
        let mut m = FakeLlm::new(&[&batch(&["What is a tree?", "what is a TREE", "Define heap"])]);
        let o = cards(&mut m, Template::ChatMl, "text", 2);
        assert_eq!(o.cards.iter().map(|c| c.front.as_str()).collect::<Vec<_>>(), ["What is a tree?", "Define heap"]);
        assert_eq!(o.stopped, None);
    }

    #[test]
    fn a_failed_batch_retries_at_six_and_keeps_partial_results() {
        let mut m = FakeLlm::new(&["garbage", &batch(&["a", "b"]), "garbage", "garbage"]);
        let o = cards(&mut m, Template::ChatMl, "text", 20);
        assert_eq!(o.cards.len(), 2, "kept what arrived");
        assert!(o.stopped.is_some());
        assert!(m.prompts[0].contains("Write 12 flashcards"));
        assert!(m.prompts[1].contains("Write 6 flashcards"), "retry at 6");
        assert!(m.prompts[2].contains("Write 6 flashcards") && m.prompts[2].contains("- a\n- b"), "later batches list what exists");
    }

    #[test]
    fn a_short_batch_is_followed_by_another_until_want_is_met() {
        let mut m = FakeLlm::new(&[&batch(&["a", "b", "c"]), &batch(&["c", "d", "e", "f", "g", "h"])]);
        let o = cards(&mut m, Template::ChatMl, "text", 8);
        assert_eq!(o.cards.len(), 8);
        assert_eq!(o.stopped, None);
        assert!(m.prompts[1].contains("Write 5 flashcards"), "asks only for what is missing");
    }

    #[test]
    fn each_model_gets_its_own_template() {
        let mut gemma = FakeLlm::new(&[&batch(&["a"])]);
        cards(&mut gemma, Template::Gemma, "text", 1);
        assert!(gemma.prompts[0].starts_with("<start_of_turn>user\n") && !gemma.prompts[0].contains("<|im_start|>"), "{}", gemma.prompts[0]);
        let mut qwen = FakeLlm::new(&[&batch(&["a"])]);
        cards(&mut qwen, Template::ChatMl, "text", 1);
        assert!(qwen.prompts[0].starts_with("<|im_start|>system\n") && qwen.prompts[0].ends_with("<think>\n\n</think>\n\n"));
    }

    #[test]
    fn a_batch_of_only_repeats_ends_the_run() {
        let mut m = FakeLlm::new(&[&batch(&["a"]), &batch(&["A"])]);
        assert_eq!(cards(&mut m, Template::ChatMl, "t", 5).stopped.as_deref(), Some("no new cards"));
    }

    fn card(front: &str, back: &str) -> Card {
        Card { front: front.into(), back: back.into() }
    }

    #[test]
    fn the_answer_is_never_the_question() {
        // The owner's bug: "the answer itself was the question itself".
        assert_eq!(check(&card("What is a stack?", "A stack")), Err(Reject::Echo));
        assert_eq!(check(&card("Binary trees", "Binary trees")), Err(Reject::Echo));
        assert_eq!(check(&card("What does a compiler do?", "What a compiler does")), Err(Reject::Echo));
        assert_eq!(check(&card("Recursion", "Recursion is when a function uses recursion")), Err(Reject::GivesAway), "unrepaired, the term gives the answer away");
        assert_eq!(check(&card("Recursion", "What is a function calling itself?")), Err(Reject::Question));
        assert_eq!(check(&card("Recursion", " ")), Err(Reject::Blank));
        assert_eq!(check(&card("Recursion", &"word ".repeat(31))), Err(Reject::TooLong));
        assert_eq!(check(&card("Igneous rock", "Something else entirely here")), Err(Reject::Example));
        assert_eq!(check(&card("Recursion", "A function that calls itself on a smaller input")), Ok(()));
        assert_eq!(check(&card("What does a stack remove first?", "The item added last")), Ok(()));
    }

    #[test]
    fn a_term_is_back_is_cut_to_its_meaning() {
        assert_eq!(repair(&card("Osmosis", "Osmosis is the movement of water through a membrane.")).back, "Movement of water through a membrane");
        assert_eq!(repair(&card("Stack", "A stack is a list where the last item in is the first out")).back, "List where the last item in is the first out");
        assert_eq!(repair(&card("Recursion", "Recursion: a function calling itself")).back, "A function calling itself");
        assert_eq!(repair(&card("What is a heap?", "A heap is a tree.")).back, "A heap is a tree", "a question's back is only trimmed");
        assert_eq!(check(&repair(&card("Osmosis", "Osmosis is water moving through a membrane"))), Ok(()));
        // Seen on Qwen3.5 2B: the term inside a longer phrase, or as the start of a longer word, is not cut.
        assert_eq!(repair(&card("Root node", "The root node of a BST is the first node inserted")).back, "The root node of a BST is the first node inserted");
        assert_eq!(repair(&card("Revolution end", "The revolution ended in 1898")).back, "The revolution ended in 1898");
        assert_eq!(check(&repair(&card("Root node", "The root node of a BST is the first node inserted"))), Err(Reject::GivesAway));
    }

    #[test]
    fn bad_cards_are_dropped_and_a_batch_that_is_all_bad_is_asked_once_more_strictly() {
        let bad = json!({"cards": [{"front": "Binary trees", "back": "Binary trees"}, {"front": "Heap", "back": "Heap"}]}).to_string();
        let good = json!({"cards": [{"front": "Heap", "back": "Tree where each parent beats its children"}]}).to_string();
        let mut m = FakeLlm::new(&[&bad, &good]);
        let o = cards(&mut m, Template::ChatMl, "text", 1);
        assert_eq!(o.cards, [card("Heap", "Tree where each parent beats its children")]);
        assert!(m.prompts[1].contains("Last time every back repeated its front"), "the retry says why");
        let mut m = FakeLlm::new(&[&bad, &bad]);
        assert_eq!(cards(&mut m, Template::ChatMl, "text", 3).stopped.as_deref(), Some("no new cards"), "only once");
    }

    #[test]
    fn topic_cards_draw_on_the_notes_first_and_the_model_otherwise() {
        let one = json!({"cards": [{"front": "Mitosis", "back": "Cell division that makes two identical cells"}]}).to_string();
        let mut m = FakeLlm::new(&[&one, &one]);
        topic_cards(&mut m, Template::ChatMl, "cell division", &["Bio note: mitosis makes two identical cells".into()], 1);
        assert!(m.prompts[0].contains("cell division") && m.prompts[0].contains("mitosis makes two identical cells") && m.prompts[0].contains("passages from the student's notes first"));
        topic_cards(&mut m, Template::ChatMl, "cell division", &[], 1);
        assert!(m.prompts[1].contains("from what you know") && !m.prompts[1].contains("passages"));
        assert!(!m.prompts[1].contains("Topic: "), "the old 'Topic: X as the text' prompt is gone");
    }

    #[test]
    fn note_cards_use_only_the_text_and_the_prompt_shows_the_game_form() {
        let mut m = FakeLlm::new(&[&batch(&["a"])]);
        cards(&mut m, Template::ChatMl, "Photosynthesis makes sugar from light.", 1);
        let p = &m.prompts[0];
        assert!(p.contains("using only what it says") && p.contains("Photosynthesis makes sugar") && p.contains("at most 8 words") && p.contains("Never a question"));
        assert!(p.contains("Igneous rock"), "the example of the form");
    }
}
