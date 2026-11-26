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
    /// Three wrong answers for a quiz (spec 062 C16), or none.
    #[serde(default)]
    pub wrong: Vec<String>,
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
    let wrong = card.wrong.iter().map(|w| w.trim().trim_end_matches('.').to_string()).collect();
    Card { front, back: out.trim().trim_end_matches('.').to_string(), wrong }
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

/// Whether three wrong answers make a fair quiz (C19): each a plain statement, not the right answer or a copy
/// of it (no meaning word of its own), not another of the three, not naming the front's term, and between half and twice the right
/// answer's length in words.
pub fn wrong_ok(card: &Card) -> bool {
    let (front, back) = (card.front.trim(), card.back.trim());
    let n = back.split_whitespace().count().max(1);
    let fronts = content(front);
    // A near miss ("toward less dissolved substance") is a good wrong answer; one that says nothing the other
    // doesn't (every meaning word already in it) is a copy.
    let near = |a: &str, b: &str| {
        let (x, y) = (content(a), content(b));
        key(a) == key(b) || x.iter().all(|w| y.contains(w))
    };
    card.wrong.len() == 3
        && card.wrong.iter().enumerate().all(|(i, w)| {
            let m = w.split_whitespace().count();
            !w.trim().is_empty()
                && !w.trim_end().ends_with('?')
                && !near(w, back)
                && !card.wrong[..i].iter().any(|o| near(w, o))
                && m * 3 >= n
                && m <= n * 2 + 2
                && !(is_term(front) && !fronts.is_empty() && fronts.iter().all(|t| content(w).contains(t)))
        })
}

const QUIZ: &str = "
- wrong: three wrong answers for the same front, for a multiple-choice quiz. Each is false but believable: the same kind of thing as the back, about as long, on the same topic, and clearly different from the back and from each other. Never the front itself, never the right answer in other words, never \"none of the above\".
  Example: front \"Igneous rock\", back \"Rock formed when melted rock cools and hardens\", wrong [\"Rock formed from layers of pressed sand and mud\", \"Rock changed by heat and pressure deep underground\", \"Rock made from the shells of sea animals\"].";

/// Wrong answers for cards that have none (C20): one call for up to `WRONG_BATCH` cards, in order. A card
/// whose three fail `wrong_ok` gets none, so it still plays Choice from other backs.
pub const WRONG_BATCH: usize = 8;

pub fn wrong_for(llm: &mut dyn Llm, tpl: Template, cards: &[Card]) -> Result<Vec<Vec<String>>, String> {
    let cards = &cards[..cards.len().min(WRONG_BATCH)];
    let list: String = cards.iter().map(|c| format!("- front: {} | back: {}\n", c.front, c.back)).collect();
    let sys = format!("You write wrong answers for a multiple-choice quiz. Each card has a front and its right answer (the back). For each card, in the same order, give the front again and three wrong answers.{QUIZ}\nEnglish. Reply as JSON.");
    let schema = json!({"type": "object", "properties": {"cards": {"type": "array", "minItems": cards.len(), "maxItems": cards.len(), "items": {
        "type": "object", "properties": {"front": {"type": "string", "maxLength": 80}, "wrong": {"type": "array", "minItems": 3, "maxItems": 3, "items": {"type": "string", "maxLength": 200}}}, "required": ["front", "wrong"]}}}, "required": ["cards"]});
    let raw = llm.generate(&tpl.wrap(&sys, &format!("Cards:\n{list}")), Some(&schema), 900, &mut |_| true)?;
    #[derive(Deserialize)]
    struct One {
        #[serde(default)]
        wrong: Vec<String>,
    }
    #[derive(Deserialize)]
    struct W {
        cards: Vec<One>,
    }
    let w: W = reply::parse(&raw).map_err(|e| e.to_string())?;
    Ok(cards
        .iter()
        .enumerate()
        .map(|(i, c)| {
            let mut c = c.clone();
            c.wrong = w.cards.get(i).map(|o| o.wrong.clone()).unwrap_or_default();
            if wrong_ok(&repair(&c)) { repair(&c).wrong } else { vec![] }
        })
        .collect())
}

fn schema() -> serde_json::Value {
    json!({"type": "object", "properties": {"cards": {"type": "array", "items": {
        "type": "object", "properties": {"front": {"type": "string", "maxLength": 80}, "back": {"type": "string", "maxLength": 200}}, "required": ["front", "back"]}}},
        "required": ["cards"]})
}

/// Flashcards from a note's or a PDF's text: only that text (C22).
/// `tpl` is the loaded model's own prompt wrapper: a Gemma model given ChatML answers badly.
pub fn cards(llm: &mut dyn Llm, tpl: Template, source: &str, want: usize, quiz: bool) -> Outcome {
    run(llm, tpl, want, quiz, &|n| format!("Write {n} flashcards from this text, using only what it says.\n\n{source}"))
}

/// Flashcards on a topic the student named in the chat (C22): the passages the note search found for it
/// first, then what the model knows about it.
pub fn topic_cards(llm: &mut dyn Llm, tpl: Template, topic: &str, passages: &[String], want: usize, quiz: bool) -> Outcome {
    let notes: String = passages.iter().map(|p| format!("- {p}\n")).collect();
    run(llm, tpl, want, quiz, &|n| {
        if notes.is_empty() {
            format!("Write {n} flashcards on {topic}, from what you know. Only facts you are sure of.")
        } else {
            format!("Write {n} flashcards on {topic}. Use these passages from the student's notes first; add what you know about {topic} only where they stop.\n\n{notes}")
        }
    })
}

/// `quiz`: once the cards are written, their wrong answers are, 8 cards per call (C17). Asking for both in
/// one call was measured slower and broke: Qwen3.5 2B took 54 to 189 s per 8 cards and ran out of tokens
/// mid-JSON in 3 of 4 topics, against about 20 s for the cards and 20 s per 8 sets of wrong answers.
fn run(llm: &mut dyn Llm, tpl: Template, want: usize, quiz: bool, ask: &dyn Fn(usize) -> String) -> Outcome {
    let mut o = write(llm, tpl, want, ask);
    if quiz {
        for part in o.cards.chunks_mut(WRONG_BATCH) {
            match wrong_for(llm, tpl, part) {
                Ok(w) => part.iter_mut().zip(w).for_each(|(c, w)| c.wrong = w),
                Err(e) => {
                    o.stopped.get_or_insert(e); // the cards are kept; the rest play Choice from other backs
                    break;
                }
            }
        }
    }
    o
}

fn write(llm: &mut dyn Llm, tpl: Template, want: usize, ask: &dyn Fn(usize) -> String) -> Outcome {
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
                let fit: Vec<Card> = b
                    .cards
                    .iter()
                    .map(repair)
                    .filter(|c| check(c).is_ok())
                    .collect();
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
        let o = cards(&mut m, Template::ChatMl, "text", 2, false);
        assert_eq!(o.cards.iter().map(|c| c.front.as_str()).collect::<Vec<_>>(), ["What is a tree?", "Define heap"]);
        assert_eq!(o.stopped, None);
    }

    #[test]
    fn a_failed_batch_retries_at_six_and_keeps_partial_results() {
        let mut m = FakeLlm::new(&["garbage", &batch(&["a", "b"]), "garbage", "garbage"]);
        let o = cards(&mut m, Template::ChatMl, "text", 20, false);
        assert_eq!(o.cards.len(), 2, "kept what arrived");
        assert!(o.stopped.is_some());
        assert!(m.prompts[0].contains("Write 12 flashcards"));
        assert!(m.prompts[1].contains("Write 6 flashcards"), "retry at 6");
        assert!(m.prompts[2].contains("Write 6 flashcards") && m.prompts[2].contains("- a\n- b"), "later batches list what exists");
    }

    #[test]
    fn a_short_batch_is_followed_by_another_until_want_is_met() {
        let mut m = FakeLlm::new(&[&batch(&["a", "b", "c"]), &batch(&["c", "d", "e", "f", "g", "h"])]);
        let o = cards(&mut m, Template::ChatMl, "text", 8, false);
        assert_eq!(o.cards.len(), 8);
        assert_eq!(o.stopped, None);
        assert!(m.prompts[1].contains("Write 5 flashcards"), "asks only for what is missing");
    }

    #[test]
    fn each_model_gets_its_own_template() {
        let mut gemma = FakeLlm::new(&[&batch(&["a"])]);
        cards(&mut gemma, Template::Gemma, "text", 1, false);
        assert!(gemma.prompts[0].starts_with("<start_of_turn>user\n") && !gemma.prompts[0].contains("<|im_start|>"), "{}", gemma.prompts[0]);
        let mut qwen = FakeLlm::new(&[&batch(&["a"])]);
        cards(&mut qwen, Template::ChatMl, "text", 1, false);
        assert!(qwen.prompts[0].starts_with("<|im_start|>system\n") && qwen.prompts[0].ends_with("<think>\n\n</think>\n\n"));
    }

    #[test]
    fn a_batch_of_only_repeats_ends_the_run() {
        let mut m = FakeLlm::new(&[&batch(&["a"]), &batch(&["A"])]);
        assert_eq!(cards(&mut m, Template::ChatMl, "t", 5, false).stopped.as_deref(), Some("no new cards"));
    }

    fn card(front: &str, back: &str) -> Card {
        Card { front: front.into(), back: back.into(), wrong: vec![] }
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
        let o = cards(&mut m, Template::ChatMl, "text", 1, false);
        assert_eq!(o.cards, [card("Heap", "Tree where each parent beats its children")]);
        assert!(m.prompts[1].contains("Last time every back repeated its front"), "the retry says why");
        let mut m = FakeLlm::new(&[&bad, &bad]);
        assert_eq!(cards(&mut m, Template::ChatMl, "text", 3, false).stopped.as_deref(), Some("no new cards"), "only once");
    }

    #[test]
    fn topic_cards_draw_on_the_notes_first_and_the_model_otherwise() {
        let one = json!({"cards": [{"front": "Mitosis", "back": "Cell division that makes two identical cells"}]}).to_string();
        let mut m = FakeLlm::new(&[&one, &one]);
        topic_cards(&mut m, Template::ChatMl, "cell division", &["Bio note: mitosis makes two identical cells".into()], 1, false);
        assert!(m.prompts[0].contains("cell division") && m.prompts[0].contains("mitosis makes two identical cells") && m.prompts[0].contains("passages from the student's notes first"));
        topic_cards(&mut m, Template::ChatMl, "cell division", &[], 1, false);
        assert!(m.prompts[1].contains("from what you know") && !m.prompts[1].contains("passages"));
        assert!(!m.prompts[1].contains("Topic: "), "the old 'Topic: X as the text' prompt is gone");
    }

    #[test]
    fn note_cards_use_only_the_text_and_the_prompt_shows_the_game_form() {
        let mut m = FakeLlm::new(&[&batch(&["a"])]);
        cards(&mut m, Template::ChatMl, "Photosynthesis makes sugar from light.", 1, false);
        let p = &m.prompts[0];
        assert!(p.contains("using only what it says") && p.contains("Photosynthesis makes sugar") && p.contains("at most 8 words") && p.contains("Never a question"));
        assert!(p.contains("Igneous rock"), "the example of the form");
    }
    fn quiz(front: &str, back: &str, wrong: &[&str]) -> Card {
        Card { front: front.into(), back: back.into(), wrong: wrong.iter().map(|w| w.to_string()).collect() }
    }

    #[test]
    fn c19_wrong_answers_must_be_fair() {
        let back = "Water moving through a membrane toward more dissolved substance";
        assert!(wrong_ok(&quiz("Osmosis", back, &["Sugar moving out of a cell using energy", "Gas spreading evenly through open air", "Salt crystals forming as water dries up"])));
        assert!(!wrong_ok(&quiz("Osmosis", back, &["Sugar moving out of a cell", "Gas spreading through air"])), "three, not two");
        assert!(!wrong_ok(&quiz("Osmosis", back, &["Water moving through a membrane toward dissolved substance", "Gas spreading evenly through open air", "Salt crystals forming as water dries up"])), "a copy of the right answer");
        assert!(!wrong_ok(&quiz("Osmosis", back, &["Gas spreading evenly through open air", "Gas spreading evenly through the open air", "Salt crystals forming as water dries up"])), "two of the three the same");
        assert!(wrong_ok(&quiz("Osmosis", back, &["Water moving through a membrane toward less dissolved substance", "Water moving away from more dissolved substance", "Water staying still on both sides of a membrane"])), "near misses are fair");
        assert!(!wrong_ok(&quiz("Osmosis", back, &["No", "Gas spreading evenly through open air", "Salt crystals forming as water dries up"])), "far too short");
        assert!(!wrong_ok(&quiz("Osmosis", back, &["Osmosis of sugar out of a cell", "Gas spreading evenly through open air", "Salt crystals forming as water dries up"])), "names the term");
        assert!(!wrong_ok(&quiz("Osmosis", back, &["Is it gas spreading through open air?", "Gas spreading evenly through open air", "Salt crystals forming as water dries up"])), "a question");
    }

    #[test]
    fn c17_a_quiz_writes_the_cards_then_their_wrong_answers_eight_per_call() {
        let cards = json!({"cards": [{"front": "Osmosis", "back": "Water moving through a membrane toward more dissolved substance"},
            {"front": "Diffusion", "back": "Particles spreading from crowded to less crowded places"}]}).to_string();
        let wrong = json!({"cards": [{"front": "Osmosis", "wrong": ["Sugar moving out of a cell using energy", "Gas spreading evenly through open air", "Salt crystals forming as water dries up"]},
            {"front": "Diffusion", "wrong": ["x", "y", "z"]}]}).to_string();
        let mut m = FakeLlm::new(&[&cards, &wrong]);
        let o = cards_fn(&mut m, 2, true);
        assert_eq!(o.cards.len(), 2);
        assert_eq!(o.cards[0].wrong.len(), 3);
        assert!(o.cards[1].wrong.is_empty(), "unfair wrong answers are dropped, the card stays");
        assert_eq!(m.prompts.len(), 2, "one call for the cards, one for 8 sets of wrong answers");
        // Wrong answers that fail to come back leave the cards as they are.
        let mut m = FakeLlm::new(&[&cards, "garbage"]);
        let o = cards_fn(&mut m, 2, true);
        assert_eq!((o.cards.len(), o.cards[0].wrong.len()), (2, 0));
        assert!(o.stopped.is_some());
    }

    fn cards_fn(m: &mut FakeLlm, want: usize, quiz: bool) -> Outcome {
        cards(m, Template::ChatMl, "text", want, quiz)
    }

    #[test]
    fn c20_wrong_answers_for_old_cards_come_in_one_call_per_eight() {
        let old: Vec<Card> = (0..10).map(|i| quiz(&format!("Term {i}"), "Water moving through a membrane toward more dissolved substance", &[])).collect();
        let w = json!(["Sugar moving out of a cell using energy", "Gas spreading evenly through open air", "Salt crystals forming as water dries up"]);
        let reply = json!({"cards": (0..8).map(|i| json!({"front": "t", "wrong": if i == 1 { json!(["a", "b", "c"]) } else { w.clone() }})).collect::<Vec<_>>()}).to_string();
        let mut m = FakeLlm::new(&[&reply]);
        let got = wrong_for(&mut m, Template::ChatMl, &old).unwrap();
        assert_eq!(got.len(), 8, "one batch is 8");
        assert_eq!(got[0].len(), 3);
        assert!(got[1].is_empty(), "an unfair set is none");
        assert_eq!(m.prompts.len(), 1);
    }

    // Spec 062 C19, C20, C17 (part C tests).
    const RIGHT: &str = "Water moving through a membrane toward more dissolved substance";
    const FAIR: [&str; 3] = ["Sugar moving out of a cell using energy", "Gas spreading evenly through open air", "Salt crystals forming as water dries up"];

    #[test]
    fn c19_a_wrong_answer_is_a_third_to_twice_the_right_ones_length() {
        let back = "Rock formed when melted rock cools"; // 6 words
        let pad = ["Sand layers", "Gas drifting through open air", "Salt crystals forming as water dries"];
        assert!(wrong_ok(&quiz("Igneous", back, &pad)), "two words against six is a third: fair");
        let one = ["Sand", pad[1], pad[2]];
        assert!(!wrong_ok(&quiz("Igneous", back, &one)), "one word against six is under a third");
        let twelve = "Sand and mud pressed together in thin layers under a deep quiet";
        assert_eq!(twelve.split_whitespace().count(), 12);
        assert!(wrong_ok(&quiz("Igneous", back, &[twelve, pad[1], pad[2]])), "twice as long is fair");
        let sixteen = "Sand and mud pressed together in thin layers under a deep quiet sea for many long years";
        assert!(sixteen.split_whitespace().count() > 14);
        assert!(!wrong_ok(&quiz("Igneous", back, &[sixteen, pad[1], pad[2]])), "far longer than twice");
    }

    #[test]
    fn c19_a_wrong_answer_that_only_repeats_the_right_ones_words_is_a_copy() {
        // Every meaning word of the wrong one is already in the right one: it adds nothing, so it is the answer reworded.
        let shorter = ["Water moving through membrane", FAIR[1], FAIR[2]];
        assert!(!wrong_ok(&quiz("Osmosis", RIGHT, &shorter)), "a subset of the right answer's words");
        let reordered = ["Dissolved substance more toward membrane a through moving water", FAIR[1], FAIR[2]];
        assert!(!wrong_ok(&quiz("Osmosis", RIGHT, &reordered)), "the same words in another order");
        let one_new_word = ["Water moving through a membrane toward more dissolved sugar", FAIR[1], FAIR[2]];
        assert!(wrong_ok(&quiz("Osmosis", RIGHT, &one_new_word)), "one word of its own makes it a near miss");
        assert!(!wrong_ok(&quiz("Osmosis", RIGHT, &["   ", FAIR[1], FAIR[2]])), "blank");
    }

    #[test]
    fn c19_the_three_are_exactly_three_and_none_is_a_copy_of_another() {
        let mut four = FAIR.to_vec();
        four.push("Dust settling slowly on a still shelf");
        assert!(!wrong_ok(&quiz("Osmosis", RIGHT, &four)), "four is not three");
        assert!(!wrong_ok(&quiz("Osmosis", RIGHT, &[])), "none");
        // A later answer whose every meaning word an earlier one already holds is out, whatever its case.
        let later = [FAIR[0], "Gas spreading evenly through open air today", "GAS, spreading EVENLY through open air!"];
        assert!(!wrong_ok(&quiz("Osmosis", RIGHT, &later)));
    }

    #[test]
    fn c19_a_front_that_names_a_thing_must_not_be_named_in_a_wrong_answer_but_a_question_front_has_no_term() {
        let back = "Tree where every node has at most two children";
        let ok = ["List where each item points to the next", "Table that maps keys to stored values", "Queue where the first item in is first out"];
        assert!(wrong_ok(&quiz("Binary tree", back, &ok)));
        let names = ["A binary tree stores items in a sorted list", ok[1], ok[2]];
        assert!(!wrong_ok(&quiz("Binary tree", back, &names)), "both words of the term");
        let half = ["A tree of rooms in a large old house", ok[1], ok[2]];
        assert!(wrong_ok(&quiz("Binary tree", back, &half)), "one word of a two-word term is not naming it");
        assert!(wrong_ok(&quiz("What is a binary tree?", back, &names)), "a question front names no term");
    }

    #[test]
    fn c20_a_card_left_with_fewer_than_three_keeps_none() {
        let old: Vec<Card> = (0..3).map(|i| quiz(&format!("Term {i}"), RIGHT, &[])).collect();
        let reply = json!({"cards": [
            {"front": "a", "wrong": FAIR},
            {"front": "b", "wrong": [FAIR[0], FAIR[1]]},
            {"front": "c", "wrong": [FAIR[0], FAIR[1], FAIR[0]]},
        ]}).to_string();
        let got = wrong_for(&mut FakeLlm::new(&[&reply]), Template::ChatMl, &old).unwrap();
        assert_eq!(got[0].len(), 3);
        assert!(got[1].is_empty(), "two is none, not two");
        assert!(got[2].is_empty(), "a repeat inside the set drops all three, not just the repeat");
        assert!(old.iter().all(|c| c.wrong.is_empty()), "the cards passed in are not changed");
    }

    #[test]
    fn c20_a_card_the_model_skipped_gets_none_and_the_others_still_get_theirs() {
        let old: Vec<Card> = (0..3).map(|i| quiz(&format!("Term {i}"), RIGHT, &[])).collect();
        let reply = json!({"cards": [{"front": "a", "wrong": FAIR}, {"front": "b", "wrong": FAIR}]}).to_string();
        let got = wrong_for(&mut FakeLlm::new(&[&reply]), Template::ChatMl, &old).unwrap();
        assert_eq!(got.len(), 3, "one answer per card asked, in order");
        assert_eq!((got[0].len(), got[1].len(), got[2].len()), (3, 3, 0));
        let noset = json!({"cards": [{"front": "a"}]}).to_string();
        assert_eq!(wrong_for(&mut FakeLlm::new(&[&noset]), Template::ChatMl, &old[..1]).unwrap(), [Vec::<String>::new()], "a card with no wrong key");
    }

    #[test]
    fn c20_only_the_first_eight_cards_go_in_one_call_and_the_prompt_lists_them_in_order() {
        let old: Vec<Card> = (0..12).map(|i| quiz(&format!("Term {i}"), RIGHT, &[])).collect();
        let reply = json!({"cards": (0..8).map(|_| json!({"front": "t", "wrong": FAIR})).collect::<Vec<_>>()}).to_string();
        let mut m = FakeLlm::new(&[&reply]);
        let got = wrong_for(&mut m, Template::ChatMl, &old).unwrap();
        assert_eq!(got.len(), WRONG_BATCH);
        assert_eq!(WRONG_BATCH, 8);
        assert_eq!(m.prompts[0].matches("- front: ").count(), 8);
        assert!(m.prompts[0].contains("- front: Term 7 |") && !m.prompts[0].contains("Term 8"));
        assert!(m.prompts[0].find("Term 0").unwrap() < m.prompts[0].find("Term 1").unwrap());
        let fewer = wrong_for(&mut FakeLlm::new(&[&json!({"cards": [{"front": "t", "wrong": FAIR}]}).to_string()]), Template::ChatMl, &old[..1]).unwrap();
        assert_eq!(fewer.len(), 1, "no padding up to eight");
    }

    #[test]
    fn c20_the_kept_wrong_answers_are_trimmed_and_lose_their_full_stop() {
        let old = [quiz("Osmosis", RIGHT, &[])];
        let spaced: Vec<String> = FAIR.iter().map(|w| format!("  {w}.  ")).collect();
        let reply = json!({"cards": [{"front": "Osmosis", "wrong": spaced}]}).to_string();
        let got = wrong_for(&mut FakeLlm::new(&[&reply]), Template::ChatMl, &old).unwrap();
        assert_eq!(got[0], FAIR);
    }

    #[test]
    fn c20_a_reply_that_is_not_json_is_an_error_the_caller_can_keep_the_cards_through() {
        let old = [quiz("Osmosis", RIGHT, &[])];
        assert!(wrong_for(&mut FakeLlm::new(&["garbage"]), Template::ChatMl, &old).is_err());
        assert!(wrong_for(&mut FakeLlm::new(&[]), Template::ChatMl, &old).is_err(), "the model failing");
    }

    /// `n` cards whose backs pass `check`, and the reply that writes them.
    fn written(n: usize) -> String {
        let names = ["alpha", "beta", "gamma", "delta", "epsilon", "zeta", "eta", "theta", "iota", "kappa"];
        let cards: Vec<_> = names[..n].iter().map(|x| json!({"front": format!("Topic {x}"), "back": format!("Something worth remembering for the quiz {x}")})).collect();
        json!({"cards": cards}).to_string()
    }
    fn armed(n: usize) -> String {
        let back = "Something worth remembering for the quiz alpha";
        assert_eq!(back.split_whitespace().count(), 7);
        json!({"cards": (0..n).map(|_| json!({"front": "t", "wrong": ["Sugar leaving a living cell", "Gas drifting through open air", "Salt forming as water dries"]})).collect::<Vec<_>>()}).to_string()
    }

    #[test]
    fn c17_ten_quiz_cards_are_written_in_one_call_then_armed_in_a_call_of_eight_and_a_call_of_two() {
        let (cards_reply, a, b) = (written(10), armed(8), armed(2));
        let mut m = FakeLlm::new(&[&cards_reply, &a, &b]);
        let o = cards_fn(&mut m, 10, true);
        assert_eq!(o.stopped, None);
        assert_eq!(o.cards.len(), 10);
        assert!(o.cards.iter().all(|c| c.wrong.len() == 3), "every card is armed");
        assert_eq!(m.prompts.len(), 3);
        assert!(m.prompts[0].contains("Write 10 flashcards") && !m.prompts[0].contains("wrong answers for a multiple-choice"), "cards first");
        assert!(m.prompts[1].contains("wrong answers for a multiple-choice") && m.prompts[1].matches("- front: ").count() == 8);
        assert!(m.prompts[2].matches("- front: ").count() == 2 && m.prompts[2].contains("Topic iota") && m.prompts[2].contains("Topic kappa"));
        assert!(!m.prompts[2].contains("Topic alpha"), "the second call holds only the cards left");
    }

    #[test]
    fn c17_without_quiz_no_wrong_answers_are_asked_for() {
        let cards_reply = written(3);
        let mut m = FakeLlm::new(&[&cards_reply]);
        let o = cards_fn(&mut m, 3, false);
        assert_eq!((o.cards.len(), m.prompts.len()), (3, 1));
        assert!(o.cards.iter().all(|c| c.wrong.is_empty()));
    }

    #[test]
    fn c17_when_a_later_batch_of_wrong_answers_fails_the_cards_and_earlier_sets_are_kept() {
        let (cards_reply, a) = (written(10), armed(8));
        let mut m = FakeLlm::new(&[&cards_reply, &a, "garbage"]);
        let o = cards_fn(&mut m, 10, true);
        assert_eq!(o.cards.len(), 10, "all ten cards stay");
        assert_eq!(o.cards.iter().filter(|c| c.wrong.len() == 3).count(), 8);
        assert!(o.cards[8].wrong.is_empty() && o.cards[9].wrong.is_empty());
        assert!(o.stopped.is_some(), "the student is told it stopped");
        let mut m = FakeLlm::new(&[&cards_reply]);
        let o = cards_fn(&mut m, 10, true);
        assert_eq!(o.cards.len(), 10, "the model failing on the first set keeps the cards too");
        assert!(o.cards.iter().all(|c| c.wrong.is_empty()) && o.stopped.is_some());
        assert_eq!(m.prompts.len(), 2, "it stops asking after the first failure");
    }

    #[test]
    fn c17_topic_cards_arm_a_quiz_the_same_way() {
        let (cards_reply, a) = (written(2), armed(2));
        let mut m = FakeLlm::new(&[&cards_reply, &a]);
        let o = topic_cards(&mut m, Template::ChatMl, "cells", &[], 2, true);
        assert_eq!(o.cards.len(), 2);
        assert!(o.cards.iter().all(|c| c.wrong.len() == 3));
    }
}
