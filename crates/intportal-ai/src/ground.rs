//! Whether the notes cover a question: its key terms, the specific words it asks about, against what the
//! model is shown (notes found, the open note, schedule and grades). Until spec 021 a question the notes
//! didn't cover was refused here; now the model answers it from what it knows and the chat says so
//! (`Answer::known`, C15 and C16). A 1B-2B model given a neighbouring note ("inorder" for a question on
//! "preorder") would otherwise pass a guess off as the student's note.
//! ponytail: words only, no meaning. A paraphrase the notes never use ("exam" for "quiz") reads as
//! uncovered, which only costs a "from what I know" label. Upgrade path: score the question against each
//! hit with the embedder.
use crate::{assis::Facts, lang};

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

#[cfg(test)]
mod tests {
    use super::*;

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



    // The chat (spec 021 C15, C16): a question the notes don't cover reaches the model, which answers from
    // what it knows, and the answer is marked `known`; `missing_terms` decides it, nothing is refused.
    #[test]
    fn through_the_chat_an_uncovered_question_reaches_the_model_and_is_marked_known() {
        let f = all3();
        let mut m = crate::llm::FakeLlm::new(&[r#"{"reply":"A tree's height is the longest path from the root to a leaf."}"#, r#"{"reply":"Inorder visits left, node, right."}"#]);
        let a = crate::assis::answer(&mut m, crate::prompt::Template::ChatMl, &f, &[], "Ano ang height ng binary tree?").unwrap();
        assert_eq!((m.prompts.len(), a.known, a.cited), (1, true, false), "{a:?}");
        let b = crate::assis::answer(&mut m, crate::prompt::Template::ChatMl, &f, &[], "What does inorder traversal visit first?").unwrap();
        assert_eq!((b.known, b.cited), (false, true), "the note covers it: {b:?}");
    }

    #[test]
    fn stems_match_plurals_and_long_prefixes_only() {
        assert!(same(&stem("derivatives"), &stem("derivative")));
        assert!(same(&stem("quizzes"), &stem("quizz")) || stem("quizzes") == "quizz");
        assert!(!same(&stem("preorder"), &stem("inorder")));
        assert!(!same("tree", "subtree"));
        assert!(same("minute", "minuto") && !same("preorder", "inorder") && !same("derivative", "derivation"));
    }
}
