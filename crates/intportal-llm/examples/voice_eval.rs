//! Voice eval (#165): 30 conversational prompts through `assis::answer` (the
//! rules first, then the model), with a fake schedule, grades and notes.
//! `cargo run --release -p intportal-llm --example voice_eval -- <chat.gguf> [cpu]`
//!
//! One tab-separated `ROW` per prompt: id, language asked, completeness check,
//! language check, model prompt tokens (0 = a rule answered), the message, the
//! reply. The checks are string heuristics; the scores in docs/ai.md come from
//! reading every reply. Greedy sampling, so a rerun gives the same replies.
use intportal_ai::{
    assis::{self, Facts},
    llm::Llm,
    prompt::Template,
};
use intportal_core::today::Date;
use intportal_llm::{Device, Llama};
use serde_json::Value;

#[derive(Clone, Copy, PartialEq)]
enum Lang {
    En,
    Fil,
    Tag,
}

struct Case {
    msg: &'static str,
    lang: Lang,
    /// Groups of alternatives, lowercase. Every group needs one hit in the reply.
    must: &'static [&'static [&'static str]],
    /// Words that mean the reply made something up.
    forbid: &'static [&'static str],
    history: &'static [(&'static str, &'static str)],
    open_note: Option<&'static str>,
}

const DUE_LINES: &str = "Quiz 2: COMP 20073, Fri 2026-10-16\nProblem Set 3: MATH 101, Mon 2026-10-19\nEssay draft: ENGL 100, Wed 2026-10-21\nMidterm exam: COMP 20073, Fri 2026-10-23";

const NOTES: [&str; 4] = [
    "Inorder traversal: visit the left subtree, then the node, then the right subtree. On a BST it visits keys in sorted order.",
    "Math 101: passing is 75%. Prof. Reyes moved the quiz to Monday; it covers limits and derivatives.",
    "Finals plan (3 days): 25-minute Pomodoro blocks, review past quizzes first, sleep before the exam.",
    "ENGL 100 essay: thesis in the first paragraph, three body paragraphs, cite two sources.",
];

const NOTE_OPEN: &str = "Inorder traversal: visit the left subtree, then the node, then the right subtree. On a BST it visits keys in sorted order.";

const DUE_ALL: &[&[&str]] = &[&["quiz 2"], &["problem set"], &["essay"], &["midterm"]];
const CLASSES_ALL: &[&[&str]] = &[&["comp 20073"], &["math 101"], &["engl 100"]];

const CASES: [Case; 30] = [
    c("hi!", Lang::En, &[], &[]),
    c("Kumusta LAR!", Lang::Fil, &[], &[]),
    c("hello po, pwede magtanong?", Lang::Tag, &[], &[]),
    h("thanks!", Lang::En, &[], &[], &[("how do I focus when studying?", "Try 25-minute Pomodoro blocks with a 5-minute break after each.")]),
    h("salamat ha", Lang::Fil, &[], &[], &[("paano mag-focus sa pag-aaral?", "Subukan mo ang 25 minutong Pomodoro, tapos 5 minutong pahinga.")]),
    c("What's due this week?", Lang::En, DUE_ALL, &[]),
    c("ano ang due ko?", Lang::Fil, DUE_ALL, &[]),
    c("ano klase ko bukas", Lang::Fil, &[], &[]),
    c("What classes do I have today?", Lang::En, CLASSES_ALL, &[]),
    c("anong klase ko ngayon", Lang::Fil, CLASSES_ALL, &[]),
    c("how are my grades?", Lang::En, &[&["86"], &["68"]], &[]),
    c("Okay lang ba ako sa Math?", Lang::Tag, &[&["86"]], &["physics", "chemistry"]),
    n("Explain this note", Lang::En, &[&["left"], &["right"], &["sorted", "order"]], &[]),
    n("ipaliwanag mo yung note na to", Lang::Fil, &[&["left", "kaliwa"], &["right", "kanan"]], &[]),
    h("ano yung kasama dun?", Lang::Fil, &[&["limit"], &["derivative"]], &[], &[("kailan ang math exam?", "Sabi ng note mo, inilipat ni Prof. Reyes ang quiz sa Lunes.")]),
    h("which of those should I do first?", Lang::En, &[&["past quizzes", "quizzes", "review"]], &[], &[("what should I study for finals?", "Start with your past quizzes, then do 25-minute Pomodoro blocks, and sleep before the exam.")]),
    c("help", Lang::En, &[], &[]),
    c("paano ba?", Lang::Fil, &[], &[]),
    c("can you check my stuff", Lang::En, &[], &[]),
    c("Please delete all my notes", Lang::En, &[&["can't", "cannot", "can not", "unable", "hindi ko", "di ko", "not able"]], &[]),
    c("Can you change my MATH 101 grade to 90?", Lang::En, &[&["can't", "cannot", "can not", "unable", "read-only", "hindi ko"]], &[]),
    c("stressed na ako sa finals", Lang::Tag, &[], &[]),
    c("I think I'm going to fail everything", Lang::En, &[], &["fail math", "failing math"]),
    c("what's the passing mark in Math 101?", Lang::En, &[&["75"]], &[]),
    c("Give me a study plan for finals", Lang::En, &[&["pomodoro", "25"], &["quiz"], &["sleep"]], &[]),
    c("Pano mag-study para sa finals?", Lang::Tag, &[&["pomodoro", "25"], &["quiz"], &["sleep", "tulog"]], &[]),
    c("What topics should I review for math, based on my notes?", Lang::En, &[&["limit"], &["derivative"]], &[]),
    c("Sino ang prof ko sa Math?", Lang::Fil, &[], &["reyes is your", "ang prof mo ay"]),
    c("Ano ang preorder traversal?", Lang::Fil, &[], &["root, left", "node, left", "ugat"]),
    c("Sino ang president ng PUP ngayon?", Lang::Fil, &[], &[]),
];

const fn c(msg: &'static str, lang: Lang, must: &'static [&'static [&'static str]], forbid: &'static [&'static str]) -> Case {
    Case { msg, lang, must, forbid, history: &[], open_note: None }
}
const fn h(msg: &'static str, lang: Lang, must: &'static [&'static [&'static str]], forbid: &'static [&'static str], history: &'static [(&'static str, &'static str)]) -> Case {
    Case { msg, lang, must, forbid, history, open_note: None }
}
const fn n(msg: &'static str, lang: Lang, must: &'static [&'static [&'static str]], forbid: &'static [&'static str]) -> Case {
    Case { msg, lang, must, forbid, history: &[], open_note: Some(NOTE_OPEN) }
}

fn facts() -> Facts {
    Facts {
        today: Some(Date::new(2026, 10, 15)),
        classes_today: vec!["COMP 20073 Data Structures, 9:00 AM to 10:30 AM".into(), "MATH 101 Mathematics, 1:00 PM to 2:30 PM".into(), "ENGL 100 English, 4:00 PM to 5:30 PM".into()],
        due: DUE_LINES.lines().map(String::from).collect(),
        standing: vec!["MATH 101: 86% so far, needs 70% on the rest for 75%".into(), "COMP 20073: 68% so far, needs 82% on the rest for 75%".into()],
        hits: NOTES.iter().map(|s| s.to_string()).collect(),
        subjects: vec!["COMP 20073".into(), "MATH 101".into(), "ENGL 100".into()],
        subject_names: vec![("COMP 20073".into(), "Data Structures".into()), ("MATH 101".into(), "Mathematics".into()), ("ENGL 100".into(), "English".into())],
        ..Facts::default()
    }
}

/// Counts the prompt tokens of every model call: a prompt that cannot fit is
/// refused with its token count, before any context is made.
struct Counting<'a> {
    inner: &'a mut Llama,
    tokens: Vec<usize>,
    /// What the model wrote last, shown when the reply cannot be parsed.
    raw: String,
}

impl Llm for Counting<'_> {
    fn generate(&mut self, prompt: &str, schema: Option<&Value>, max_tokens: u32, on_token: &mut dyn FnMut(&str) -> bool) -> Result<String, String> {
        let probe = self.inner.generate(prompt, None, u32::MAX / 2, &mut |_| false).unwrap_err();
        let n = probe.split_whitespace().nth(2).and_then(|x| x.parse().ok()).unwrap_or(0);
        self.tokens.push(n);
        let out = self.inner.generate(prompt, schema, max_tokens, on_token);
        self.raw = out.clone().unwrap_or_default();
        out
    }
    fn generate_prefilled(&mut self, prompt: &str, prefill: &str, schema: Option<&Value>, max_tokens: u32, on_token: &mut dyn FnMut(&str) -> bool) -> Result<String, String> {
        let out = self.inner.generate_prefilled(prompt, prefill, schema, max_tokens, on_token);
        self.raw = out.clone().unwrap_or_default();
        out
    }
    fn embed(&mut self, texts: &[&str]) -> Result<Vec<Vec<f32>>, String> {
        self.inner.embed(texts)
    }
}

fn markers(text: &str) -> (usize, usize) {
    const FIL: [&str; 24] = ["ang", "ng", "mo", "ko", "sa", "ay", "na", "lang", "ba", "naman", "para", "ito", "iyon", "yung", "wala", "ka", "ako", "tayo", "po", "kung", "kasi", "mga", "natin", "heto"];
    const EN: [&str; 20] = ["the", "you", "your", "is", "are", "to", "and", "of", "for", "it", "this", "that", "with", "i", "i'm", "have", "here", "can", "let", "what"];
    let low = text.to_lowercase();
    let w: Vec<&str> = low.split(|c: char| !(c.is_alphanumeric() || c == '\'')).filter(|x| !x.is_empty()).collect();
    (w.iter().filter(|x| FIL.contains(x)).count(), w.iter().filter(|x| EN.contains(x)).count())
}

fn main() {
    let path = std::env::args().nth(1).expect("model.gguf");
    let device = if std::env::args().any(|a| a == "cpu") { Device::Cpu } else { Device::Gpu };
    let mut m = Llama::load(path.as_ref(), 4096, device).unwrap();
    // The persona alone, in this model's tokens (a prompt that cannot fit is refused with its count).
    let alone = format!("{}\n\nStudent: hi", intportal_ai::persona::system_all(None));
    let probe = m.generate(&alone, None, u32::MAX / 2, &mut |_| false).unwrap_err();
    println!("persona system text: {} chars, {}", alone.chars().count(), probe.split(" does not fit").next().unwrap_or(""));
    let tpl = if path.contains("gemma") { Template::Gemma } else { Template::ChatMl };
    let (mut full, mut lang_ok, mut model_calls) = (0, 0, vec![]);
    for (i, case) in CASES.iter().enumerate() {
        let mut f = facts();
        f.open_note = case.open_note.map(String::from);
        // No note hits when a note is open and the question is about it: the app searches only open questions anyway.
        let history: Vec<(String, String)> = case.history.iter().map(|(a, b)| (a.to_string(), b.to_string())).collect();
        let mut counting = Counting { inner: &mut m, tokens: vec![], raw: String::new() };
        let t = std::time::Instant::now();
        let reply = assis::answer(&mut counting, tpl, &f, &history, case.msg).map(|a| a.reply).unwrap_or_else(|e| format!("ERROR {e}"));
        let secs = t.elapsed().as_secs_f64();
        let tokens = counting.tokens.first().copied().unwrap_or(0);
        let reply = if reply.starts_with("ERROR") { format!("{reply} | raw: {:?}", counting.raw) } else { reply };
        if tokens > 0 {
            model_calls.push(tokens);
        }
        let low = reply.to_lowercase();
        let has_all = case.must.iter().all(|g| g.iter().any(|k| low.contains(k))) && !case.forbid.iter().any(|k| low.contains(k));
        let (fil, en) = markers(&reply);
        let lang = match case.lang {
            Lang::En => fil <= en || fil == 0,
            Lang::Fil => fil >= 1 && fil >= en,
            Lang::Tag => fil >= 1,
        };
        full += has_all as usize;
        lang_ok += lang as usize;
        println!("ROW\t{}\t{}\t{}\t{}\t{tokens}\t{secs:.1}\t{}\t{}", i + 1, ["en", "fil", "tag"][case.lang as usize], if has_all { "ok" } else { "MISSING" }, if lang { "ok" } else { "LANG?" }, case.msg, reply.replace('\n', " / "));
    }
    model_calls.sort_unstable();
    println!(
        "\n{path}\ncomplete {full}/30, language {lang_ok}/30, model calls {} with prompt tokens min {} median {} max {}",
        model_calls.len(),
        model_calls.first().copied().unwrap_or(0),
        model_calls.get(model_calls.len() / 2).copied().unwrap_or(0),
        model_calls.last().copied().unwrap_or(0)
    );
}
