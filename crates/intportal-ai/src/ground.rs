//! A lexical check that an open reply stands on what the app showed the model. A 1B-2B model given a
//! neighbouring note ("inorder traversal" for a question on "preorder traversal") answers from the
//! neighbour and says it with confidence (docs/ai.md, "Grounding check"). Two checks, both on words:
//!
//! 1. **Coverage** (`before_model`, `after_model`): the question's key terms, the specific words it
//!    asks about, must appear somewhere in what the model saw (notes found, the open note, schedule
//!    and grades). When none does, the model is never called. When some do and some don't, a reply
//!    that is not already an honest "I don't see it" is replaced.
//! 2. **Reply support** (`after_model`): the share of the reply's content words that appear neither
//!    in the sources nor in the question. Above `MAX_UNSUPPORTED` the reply is replaced by the "ask it
//!    another way" line.
//!
//! The replacement of a missing key term says what the notes do hold (the title of the top hit) and
//! offers to look at it.
//! ponytail: words only, no meaning. A paraphrase the notes never use ("exam" for "quiz") reads as
//! missing; the `GENERIC` list and the offer in the replacement keep the cost of that low. Upgrade
//! path: score the question against each hit with the embedder.
use crate::{
    assis::{is_refusal, Facts},
    intent::is_filipino,
    lang,
    persona,
};

/// Replace a reply when more than this share of its content words is in neither the sources nor the
/// question (and at least `MIN_UNSUPPORTED` words are). Chosen on the replies of docs/ai-qwen-eval.tsv:
/// see the table in docs/ai.md.
pub const MAX_UNSUPPORTED: f32 = 0.65;
pub const MIN_UNSUPPORTED: usize = 4;

/// English and Filipino words that carry no topic: the function words of `lang`, and the words a
/// question or a reply is made of whatever it is about.
const GENERIC: &[&str] = &[
    // question and request words
    "about", "after", "again", "also", "because", "been", "before", "being", "between", "both", "come", "could", "describe", "does", "doing", "done", "each", "even", "every", "explain", "find", "first", "give", "going", "good", "have", "here", "into", "just", "know", "like", "make", "many", "more", "most", "much", "need", "only", "other", "please", "really", "right", "same", "should", "show", "some", "such", "tell", "than", "that", "their", "them", "then", "there", "these", "they", "thing", "things", "think", "this", "those", "through", "very", "want", "well", "were", "what", "when", "where", "which", "while", "will", "with", "would", "your", "yours", "mine", "mean", "means", "meant",
    // what a reply is made of
    "okay", "sure", "glad", "sorry", "maybe", "check", "looks", "seems", "able", "mention", "mentions", "write", "wrote", "remember", "next", "time", "times", "help", "helps", "start", "starts", "still", "already", "note", "notes", "student", "answer", "question", "topic", "topics", "study", "review", "plan", "kind", "part", "idea", "word", "words", "means", "called", "using", "used", "uses", "work", "works", "take", "takes", "keep", "keeps", "left", "right", "found", "says", "said", "told", "later", "today", "tomorrow", "week", "day", "days",
    // how to answer, grades and the calendar: words that ask for a shape or a number, whatever the topic
    "simple", "simply", "briefly", "detail", "details", "short", "quick", "quickly", "easy", "easily", "summary", "summarize", "summarise", "overview", "steps", "step", "example", "examples", "basic", "basics", "meaning", "grade", "grades", "score", "scores", "mark", "marks", "percent", "percentage", "exams", "tests", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday", "morning", "afternoon", "evening", "tonight", "yesterday", "lunes", "martes", "miyerkules", "huwebes", "biyernes", "sabado", "linggo",
    // Filipino
    "anong", "pano", "ilan", "saang", "sinong", "alam", "akin", "akong", "iyong", "iyo", "nito", "niyan", "niyon", "diyan", "doon", "pala", "yata", "raw", "daw", "ninyo", "sabi", "huwag", "ayaw", "nais", "kailangan", "maaari", "magagawa", "gawin", "gawa", "sige", "ayon", "okay", "tayo", "natin", "kaya", "isa-isa", "unang", "gagawin", "ramdam", "salamat", "walang", "anuman", "nandito", "kapag", "tanong", "ulit", "baka", "makita", "nakikita", "nakasulat", "isulat", "gusto", "tingnan", "tignan", "kasama", "tungkol", "gaano", "katagal", "ilang", "magkano", "ipaliwanag", "sabihin", "sagot", "sagutin", "tulong", "tulungan", "aral", "aralin", "pag-aaral", "pagsusulit", "kailan", "saan", "alin", "paano", "bakit", "mayroon", "meron", "dapat", "puwede", "pwede", "talaga", "siguro", "muna", "pagkatapos", "tapos", "bago", "habang", "dahil", "kasi", "pero", "kung", "kaya", "lahat", "iba", "ibang", "isang", "unang", "huli", "huling", "bawat", "isa", "dalawa", "tatlo", "hanggang", "mula", "noong", "ngayon", "bukas", "kanina", "kahapon", "linggo", "araw",
];

/// Tagalog prefixes: a word that starts with one is Filipino, not a topic of the notes.
const TAGALOG_PREFIX: &[&str] = &["mag", "nag", "pag", "pang", "ipa", "ipag", "ika", "maka", "naka", "taga", "kina", "mapa"];

/// Lower-case word, plural and verb endings cut ("derivatives" and "derivative" are one word).
fn stem(w: &str) -> String {
    let mut w = w.to_lowercase();
    for suf in ["ies", "ing", "ed", "es", "ly", "s"] {
        if let Some(rest) = w.strip_suffix(suf) {
            if rest.chars().count() >= 4 {
                w = if suf == "ies" { format!("{rest}y") } else { rest.to_string() };
                break;
            }
        }
    }
    w
}

/// Equal, or one long common start with at most one letter left over ("minute" and "minuto").
fn same(a: &str, b: &str) -> bool {
    let shared = a.chars().zip(b.chars()).take_while(|(x, y)| x == y).count();
    a == b || (shared >= 5 && shared + 1 >= a.chars().count().min(b.chars().count()))
}

fn raw_words(text: &str) -> Vec<String> {
    text.split(|c: char| !(c.is_alphanumeric() || c == '\'')).map(|w| w.trim_matches('\'')).filter(|w| !w.is_empty()).map(String::from).collect()
}

fn stop(w: &str) -> bool {
    let low = w.to_lowercase();
    let (f, e) = lang::counts(&low);
    f + e > 0 || GENERIC.contains(&low.as_str())
}

/// A Tagalog prefix, or the first syllable said twice ("lalabas", "gagawin": a future tense).
fn tagalog(w: &str) -> bool {
    let c: Vec<char> = w.chars().collect();
    TAGALOG_PREFIX.iter().any(|p| w.starts_with(p) && c.len() > p.len() + 3) || (c.len() >= 6 && c[..2] == c[2..4])
}

/// (surface form, stem) of the words that name a topic: letters only, five or more, not generic, not
/// Filipino. Numbers and short words ("BST", "101") are not key terms; they still count as support.
fn key_terms(text: &str) -> Vec<(String, String)> {
    let mut out: Vec<(String, String)> = vec![];
    for w in raw_words(text) {
        let low = w.to_lowercase();
        if low.chars().count() < 5 || !low.chars().all(char::is_alphabetic) || stop(&low) || tagalog(&low) || out.iter().any(|(_, s)| *s == stem(&low)) {
            continue;
        }
        out.push((w, stem(&low)));
    }
    out
}

/// Every word the model was shown that a reply may use: notes found, the open note, the schedule,
/// the grades and the student's subjects.
fn support(f: &Facts) -> Vec<String> {
    let names = f.subject_names.iter().flat_map(|(c, d)| [c.as_str(), d.as_str()]);
    let parts = f.hits.iter().chain(&f.near).map(String::as_str).chain(f.open_note.as_deref()).chain(f.classes_today.iter().map(String::as_str)).chain(f.due.iter().map(String::as_str)).chain(f.standing.iter().map(String::as_str)).chain(names);
    parts.flat_map(raw_words).map(|w| stem(&w)).collect()
}

fn has(words: &[String], stem: &str) -> bool {
    words.iter().any(|w| same(w, stem))
}

/// The question's key terms that none of the sources has.
pub fn missing_terms(msg: &str, f: &Facts) -> Vec<String> {
    let sup = support(f);
    key_terms(msg).into_iter().filter(|(_, s)| !has(&sup, s)).map(|(w, _)| w).collect()
}

/// (share, words) of the reply's content words that are in neither the sources nor the question.
/// Filipino words are left out: the sources are mostly English and a Filipino reply is not invented
/// by saying "kaliwa".
pub fn unsupported(reply: &str, msg: &str, f: &Facts) -> (f32, Vec<String>) {
    let (mut sup, ask) = (support(f), raw_words(msg));
    sup.extend(ask.iter().map(|w| stem(w)));
    let content: Vec<String> = raw_words(reply)
        .into_iter()
        .filter(|w| {
            let low = w.to_lowercase();
            w.chars().all(char::is_numeric) || (low.chars().count() >= 4 && !stop(&low) && !tagalog(&low))
        })
        .collect();
    let bad: Vec<String> = content.iter().filter(|w| !has(&sup, &stem(w))).cloned().collect();
    (if content.is_empty() { 0.0 } else { bad.len() as f32 / content.len() as f32 }, bad)
}

/// "Inorder traversal: visit the left…" is about "Inorder traversal".
fn title(hit: &str) -> String {
    match hit.split_once(':') {
        Some((t, _)) if !t.trim().is_empty() && t.chars().count() <= 50 && !t.contains('\n') => t.trim().to_string(),
        _ => hit.split_whitespace().take(4).collect::<Vec<_>>().join(" "),
    }
}

/// "I only see Inorder traversal in your notes, not preorder", in the student's language.
fn near_miss(f: &Facts, msg: &str, missing: &[String]) -> String {
    let fil = is_filipino(msg);
    let joined = missing.iter().take(2).cloned().collect::<Vec<_>>().join(if fil { " at " } else { " or " });
    match f.hits.iter().chain(&f.near).next().map(|h| title(h)).filter(|t| !t.is_empty()) {
        Some(have) => persona::near_miss(&have, &joined, fil, msg),
        None => persona::line(persona::Line::NoData, fil, msg),
    }
}

/// Before the model runs: notes were found, the question has key terms, and not one of them is in
/// anything the model would see. The answer is the replacement, and the model is never called.
pub fn before_model(f: &Facts, msg: &str) -> Option<String> {
    let keys = key_terms(msg);
    let missing = missing_terms(msg, f);
    ((!f.hits.is_empty() || !f.near.is_empty()) && !keys.is_empty() && missing.len() == keys.len()).then(|| near_miss(f, msg, &missing))
}

/// After the model wrote `reply`: replaced when it answers a question whose key term the sources do
/// not have, or when too much of it is in neither the sources nor the question. A reply that already
/// says "I don't see it" stays.
pub fn after_model(f: &Facts, msg: &str, reply: &str) -> Option<String> {
    if (f.hits.is_empty() && f.near.is_empty()) || reply.split_inclusive(['.', '!', '?']).next().is_some_and(is_refusal) {
        return None;
    }
    let missing = missing_terms(msg, f);
    if !missing.is_empty() {
        return Some(near_miss(f, msg, &missing));
    }
    // The topic is in the notes but the words are not: the reply is made up or garbled, and saying "I only
    // see X, not Y" would be false. Ask for the question again.
    let (share, bad) = unsupported(reply, msg, f);
    (share > MAX_UNSUPPORTED && bad.len() >= MIN_UNSUPPORTED).then(|| persona::line(persona::Line::Retry, is_filipino(msg), msg))
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    const NOTES: [&str; 3] = [
        "Inorder traversal: visit the left subtree, then the node, then the right subtree. On a BST it visits keys in sorted order.",
        "Math 101: passing is 75%. Prof. Reyes moved the quiz to Monday; it covers limits and derivatives.",
        "Finals plan (3 days): 25-minute Pomodoro blocks, review past quizzes first, sleep before the exam.",
    ];

    fn facts(hits: &[&str]) -> Facts {
        Facts { today: Some(intportal_core::today::Date::new(2026, 10, 15)), hits: hits.iter().map(|s| s.to_string()).collect(), subject_names: vec![("MATH 101".into(), "Mathematics".into())], ..Facts::default() }
    }

    fn all3() -> Facts {
        facts(&NOTES)
    }

    /// (id, question) of the 10 controls a note answers and the 12 near-misses of the out-of-scope eval.
    const CONTROLS: [(&str, &str); 10] = [
        ("k1", "ano ang inorder traversal?"),
        ("k2", "Paano ba mag-visit ng BST in order?"),
        ("k3", "What does inorder traversal give on a BST?"),
        ("k4", "Kailan ang quiz sa Math 101?"),
        ("k5", "Ano ang passing sa Math 101?"),
        ("k6", "Anong topics ang kasama sa Math quiz?"),
        ("k7", "pano mag-study para sa finals?"),
        ("k8", "Gaano katagal ang isang study block ko?"),
        ("k9", "What should I review first for finals?"),
        ("k10", "What will the Math 101 test by Prof. Reyes cover?"),
    ];
    const NEAR: [(&str, &str); 12] = [
        ("c1", "Ano ang preorder traversal?"),
        ("c2", "What is postorder traversal?"),
        ("c3", "Ano ang height ng binary tree?"),
        ("c4", "Paano mag-delete ng node sa BST?"),
        ("c5", "What is the chain rule in derivatives?"),
        ("c6", "Ano ang passing mark sa Physics 101?"),
        ("c7", "Gaano katagal dapat ang Pomodoro break?"),
        ("c8", "What topics are on the Math 101 finals?"),
        ("c9", "What is the time complexity of inorder traversal?"),
        ("c10", "What is Prof. Reyes's email address?"),
        ("c11", "Ilang items ang quiz sa Math 101?"),
        ("c12", "Give me practice problems on limits."),
    ];

    fn ask(f: &Facts, q: &str, canned: &[&str]) -> (String, usize) {
        let mut m = crate::llm::FakeLlm::new(canned);
        let a = crate::assis::answer(&mut m, crate::prompt::Template::ChatMl, f, &[], q).unwrap();
        (a.reply, m.prompts.len())
    }

    // The chat: the check sits in `assis::answer`, before the model and after it.
    #[test]
    fn through_the_chat_a_zero_coverage_question_skips_the_model_and_a_near_miss_is_replaced() {
        let f = all3();
        let (r, calls) = ask(&f, "Ano ang height ng binary tree?", &[]);
        assert_eq!(calls, 0, "the model is never called");
        assert!(r.contains("Inorder traversal") && r.contains("height") && is_filipino(&r), "{r}");
        let (r, calls) = ask(&f, "What is the chain rule in derivatives?", &[r#"{"reply":"The chain rule differentiates a composition of functions."}"#]);
        assert_eq!(calls, 1);
        assert!(r.contains("Inorder traversal") && r.contains("chain") && !is_filipino(&r), "the top hit is named: {r}");
    }

    #[test]
    fn through_the_chat_every_control_keeps_its_grounded_answer() {
        let good = [
            "Inorder traversal visits the left subtree, then the node, then the right subtree.",
            "Visit the left subtree, the node, then the right subtree, and the keys come out sorted.",
            "It gives the keys in sorted order.",
            "Prof. Reyes moved the quiz to Monday.",
            "Passing in Math 101 is 75%.",
            "The quiz covers limits and derivatives.",
            "Review past quizzes first, then do 25-minute Pomodoro blocks, and sleep before the exam.",
            "A study block is 25 minutes, a Pomodoro.",
            "Review your past quizzes first.",
            "It covers limits and derivatives.",
        ];
        let f = all3();
        for ((id, q), reply) in CONTROLS.iter().zip(good) {
            let (r, _) = ask(&f, q, &[&json!({"reply": reply}).to_string()]);
            assert!(!r.contains("only see") && !r.contains("lang ang nasa"), "{id} was refused: {r}");
        }
    }

    #[test]
    fn key_terms_are_the_topic_words_of_a_question() {
        let k = |q: &str| key_terms(q).into_iter().map(|(w, _)| w).collect::<Vec<_>>();
        assert_eq!(k("Ano ang preorder traversal?"), ["preorder", "traversal"]);
        assert_eq!(k("Paano mag-delete ng node sa BST?"), ["delete"]);
        assert_eq!(k("Gaano katagal ang isang study block ko?"), ["block"], "study and katagal are generic");
        assert!(k("Pwede mo ba akong tulungan sa pagsusulit?").is_empty(), "all Filipino function or generic words");
    }

    #[test]
    fn a_question_none_of_whose_terms_the_notes_have_never_reaches_the_model() {
        let r = before_model(&all3(), "Ano ang height ng binary tree?").expect("height, binary and tree are in no note");
        assert!(r.contains("Inorder traversal") && r.contains("height"), "{r}");
        assert!(persona::lines(persona::Line::NoData, true).iter().all(|l| *l != r), "it names what the notes hold");
        // English asks get English words, Filipino asks Filipino words.
        assert!(!is_filipino(&before_model(&all3(), "What is the height of a binary tree?").unwrap()));
        assert!(is_filipino(&r), "{r}");
    }

    #[test]
    fn a_question_with_a_term_the_notes_have_goes_to_the_model_and_a_partial_miss_is_caught_after() {
        let f = all3();
        assert_eq!(before_model(&f, "Ano ang preorder traversal?"), None, "traversal is in a note");
        let r = after_model(&f, "Ano ang preorder traversal?", "Preorder traversal is when you visit the left subtree first, then the node, then the right subtree.").unwrap();
        assert!(r.contains("Inorder traversal") && r.contains("preorder"), "{r}");
    }

    #[test]
    fn no_hits_or_no_key_terms_means_nothing_to_check() {
        assert_eq!(before_model(&facts(&[]), "Ano ang height ng binary tree?"), None);
        assert_eq!(after_model(&facts(&[]), "Ano ang height ng binary tree?", "The height is the longest path."), None);
        assert_eq!(before_model(&all3(), "salamat po"), None);
    }

    #[test]
    fn grounded_answers_pass_and_the_controls_are_never_refused() {
        let good = [
            ("k1", "Inorder traversal visits the left subtree, then the node, then the right subtree. On a BST that gives the keys in sorted order."),
            ("k4", "Sabi ng note mo, inilipat ni Prof. Reyes ang quiz sa Monday."),
            ("k5", "Passing sa Math 101 ay 75%."),
            ("k6", "Ang quiz sa Math 101 ay tungkol sa limits at derivatives."),
            ("k7", "Gumamit ng 25-minute Pomodoro blocks, review mo muna ang past quizzes, at matulog bago ang exam."),
            ("k8", "25 minutes ang isang Pomodoro block mo."),
            ("k10", "It covers limits and derivatives, per your note."),
        ];
        let f = all3();
        for (id, q) in CONTROLS {
            assert_eq!(before_model(&f, q), None, "{id} reaches the model");
            if let Some((_, r)) = good.iter().find(|(i, _)| *i == id) {
                assert_eq!(after_model(&f, q, r), None, "{id} is a grounded answer: {r}");
            }
        }
    }

    #[test]
    fn an_invented_answer_is_replaced_and_an_honest_one_is_kept() {
        let f = all3();
        let q = "Sino ang prof ko sa Chemistry?";
        let honest = "Hindi ko nakikita ang prof mo sa Chemistry sa notes mo.";
        assert_eq!(after_model(&f, q, honest), None);
        let invented = "Prof. Santiago teaches Chemistry in Laboratory Building, room 204, every Thursday afternoon, according to the department.";
        let r = after_model(&f, q, invented).expect("Santiago, laboratory, building, thursday, afternoon, department are in no source");
        assert!(r.contains("Inorder traversal"), "{r}");
    }

    #[test]
    fn the_unsupported_share_counts_content_words_not_in_sources_or_question() {
        let f = all3();
        let (share, bad) = unsupported("The capital of France is Paris.", "What is the capital of France?", &f);
        assert_eq!(bad, ["Paris"]);
        assert!(share > 0.0 && share < 1.0);
        let (share, _) = unsupported("Visit the left subtree, then the node, then the right subtree.", "ano ang inorder traversal?", &f);
        assert_eq!(share, 0.0);
        assert_eq!(unsupported("", "q", &f), (0.0, vec![]));
    }

    #[test]
    fn stems_match_plurals_and_long_prefixes_only() {
        assert!(same(&stem("derivatives"), &stem("derivative")));
        assert!(same(&stem("quizzes"), &stem("quizz")) || stem("quizzes") == "quizz");
        assert!(!same(&stem("preorder"), &stem("inorder")));
        assert!(!same("tree", "subtree"));
        assert!(same("minute", "minuto") && !same("preorder", "inorder") && !same("derivative", "derivation"));
        assert_eq!(title("Math 101: passing is 75%."), "Math 101");
        assert_eq!(title("a long note without any title in front of it"), "a long note without");
    }

    /// Paraphrases a note answers that no calibration set held: the check must leave them to the model.
    #[test]
    fn held_out_paraphrases_of_answerable_questions_are_not_refused_before_or_after() {
        let qs = [
            "Can you explain inorder traversal in simple words?",
            "ipaliwanag mo nga ang inorder traversal",
            "Summarize my Math 101 note briefly",
            "Ano ang passing grade ng Math 101?",
            "What are the steps of inorder traversal?",
            "Is the quiz on Monday or Tuesday?",
            "Magkano ang passing percentage sa Math 101?",
            "How long is one Pomodoro block?",
            "Anong dapat kong i-review bago mag-finals?",
            "When did Prof. Reyes move the quiz?",
            "Ano ang unang gagawin ko para sa finals?",
            "Anong topics ang lalabas sa quiz ni Prof. Reyes?",
            "What does a BST give you when you visit it in order?",
            "Give me a quick summary of my finals plan",
            "Ilang minuto ang isang Pomodoro?",
            "Sino ang nag-move ng quiz?",
        ];
        let f = all3();
        let refused: Vec<_> = qs.iter().filter(|q| before_model(&f, q).is_some() || !missing_terms(q, &f).is_empty()).collect();
        assert!(refused.is_empty(), "false refusals: {refused:?}");
    }

    #[test]
    fn calibration_on_the_recorded_replies() {
        // docs/ai-qwen-eval.tsv: model, condition, id, kind, lang, path, question, raw reply, final reply
        let tsv = include_str!("../../../docs/ai-qwen-eval.tsv");
        let f = all3();
        let (mut controls, mut refused, mut near, mut caught) = (0, vec![], 0, vec![]);
        for row in tsv.lines().skip(1).map(|l| l.split('\t').collect::<Vec<_>>()).filter(|r| r[1] == "all3" && r[5] == "model") {
            let (model, id, raw) = (row[0], row[2], row[7]);
            let q = row[6];
            let replaced = before_model(&f, q).or_else(|| after_model(&f, q, raw)).is_some();
            if row[3] == "k" {
                controls += 1;
                if replaced {
                    refused.push(format!("{model} {id}"));
                }
            } else if row[3] == "c" {
                near += 1;
                if replaced {
                    caught.push(format!("{model} {id}"));
                }
            }
            let (share, _) = unsupported(raw, q, &f);
            println!("{model}\t{id}\t{share:.2}\t{replaced}\t{}", raw.chars().take(60).collect::<String>());
        }
        println!("controls {controls}, refused {refused:?}; near-misses {near}, replaced {caught:?}");
        assert!(refused.is_empty(), "false refusals: {refused:?}");
        assert!(caught.len() >= 14, "{caught:?}");
        let _ = (CONTROLS, NEAR);
    }
}
