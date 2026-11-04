//! Reply language eval: 24 Filipino and Taglish questions (from the out-of-scope and voice evals),
//! asked straight to the model with the three seeded notes, once per technique of `lang::Plan`.
//! `cargo run --release -p intportal-llm --example lang_eval -- <chat.gguf> [cpu] [technique ...]`
//!
//! One tab-separated `ROW` per question and technique: technique, id, language check, loop or
//! garbage check, completeness check, seconds, model calls, question, reply. The checks are string
//! heuristics; the scores in docs/ai.md come from reading every reply. Greedy sampling.
use intportal_ai::{
    lang::{self, Plan},
    llm::Llm,
    prompt::{Section, Template},
    reply,
};
use intportal_llm::{Device, Llama};
use serde_json::{json, Value};
use std::time::Instant;

const NOTES: [&str; 3] = [
    "Inorder traversal: visit the left subtree, then the node, then the right subtree. On a BST it visits keys in sorted order.",
    "Math 101: passing is 75%. Prof. Reyes moved the quiz to Monday; it covers limits and derivatives.",
    "Finals plan (3 days): 25-minute Pomodoro blocks, review past quizzes first, sleep before the exam.",
];

/// (id, question, keywords of which one must appear when a note answers it)
const QS: [(&str, &str, &[&str]); 24] = [
    ("k1", "ano ang inorder traversal?", &["left", "right", "kaliwa", "kanan"]),
    ("k2", "Paano ba mag-visit ng BST in order?", &["sorted", "left", "inorder", "kaliwa"]),
    ("k4", "Kailan ang quiz sa Math 101?", &["monday", "lunes"]),
    ("k5", "Ano ang passing sa Math 101?", &["75"]),
    ("k6", "Anong topics ang kasama sa Math quiz?", &["limit", "derivative"]),
    ("k7", "pano mag-study para sa finals?", &["pomodoro", "25", "quiz", "sleep", "tulog"]),
    ("k8", "Gaano katagal ang isang study block ko?", &["25"]),
    ("a2", "Sino ang pambansang bayani ng Pilipinas?", &[]),
    ("a4", "Sino ang sumulat ng Noli Me Tangere?", &[]),
    ("a6", "Ilang planeta ang nasa solar system?", &[]),
    ("a9", "Kailan ipinanganak si Jose Rizal?", &[]),
    ("a11", "Paano mag-solve ng quadratic equation?", &[]),
    ("c1", "Ano ang preorder traversal?", &[]),
    ("c3", "Ano ang height ng binary tree?", &[]),
    ("c4", "Paano mag-delete ng node sa BST?", &[]),
    ("c6", "Ano ang passing mark sa Physics 101?", &[]),
    ("c7", "Gaano katagal dapat ang Pomodoro break?", &[]),
    ("c11", "Ilang items ang quiz sa Math 101?", &[]),
    ("b2", "Anong oras ang klase ko sa Physics bukas?", &[]),
    ("b4", "Sino ang prof ko sa Chemistry?", &[]),
    ("b9", "Pasado ba ako sa Physics?", &[]),
    ("d1", "Hi! Kumusta ka?", &[]),
    ("d13", "Nalulungkot ako at ayoko nang mag-aral.", &[]),
    ("v1", "stressed na ako sa finals", &[]),
];

const TECHNIQUES: [(&str, Plan); 7] = [
    ("base", Plan::BASELINE),
    ("shots", Plan { shots: true, prefill: false, retry: None }),
    ("prefill", Plan { shots: false, prefill: true, retry: None }),
    ("shots+prefill", Plan { shots: true, prefill: true, retry: None }),
    ("retry-shots", Plan { shots: false, prefill: false, retry: Some((true, false)) }),
    ("retry-both", Plan { shots: false, prefill: false, retry: Some((true, true)) }),
    ("shipped", Plan::BASELINE), // replaced by `Plan::for_template` below
];

/// Counts the model calls, so a retry shows.
struct Spy<'a>(&'a mut Llama, usize);
impl Llm for Spy<'_> {
    fn generate(&mut self, p: &str, s: Option<&Value>, n: u32, f: &mut dyn FnMut(&str) -> bool) -> Result<String, String> {
        self.1 += 1;
        self.0.generate(p, s, n, f)
    }
    fn generate_prefilled(&mut self, p: &str, pre: &str, s: Option<&Value>, n: u32, f: &mut dyn FnMut(&str) -> bool) -> Result<String, String> {
        self.1 += 1;
        self.0.generate_prefilled(p, pre, s, n, f)
    }
    fn embed(&mut self, t: &[&str]) -> Result<Vec<Vec<f32>>, String> {
        self.0.embed(t)
    }
}

/// A word trigram three times over, a reply that ran to the limit, or characters of another script.
fn looped(text: &str) -> bool {
    let low = text.to_lowercase();
    let w: Vec<&str> = low.split_whitespace().collect();
    let repeated = w.windows(3).any(|t| w.windows(3).filter(|u| *u == t).count() >= 3);
    repeated || text.chars().count() >= 590 || text.chars().any(|c| (c as u32) > 0x2E80)
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    let path = args.get(1).expect("model.gguf").clone();
    let device = if args.iter().any(|a| a == "cpu") { Device::Cpu } else { Device::Gpu };
    let want: Vec<&String> = args.iter().skip(2).filter(|a| *a != "cpu").collect();
    let mut m = Llama::load(path.as_ref(), 4096, device).unwrap();
    let tpl = if path.contains("gemma") { Template::Gemma } else { Template::ChatMl };
    let hits: String = NOTES.iter().map(|n| format!("- {n}\n")).collect();
    let sections = [Section { title: "From the student's notes", body: &hits, priority: 7 }];
    let schema = json!({"type": "object", "properties": {"reply": {"type": "string", "maxLength": 600}}, "required": ["reply"]});
    for (name, plan) in TECHNIQUES.iter().map(|(n, p)| (n, if *n == "shipped" { Plan::for_template(tpl) } else { *p })).filter(|(n, _)| want.is_empty() || want.iter().any(|w| w == n)) {
        let (mut in_lang, mut loops, mut complete, mut retried, mut secs) = (0, 0, 0, 0, vec![]);
        for (id, q, kw) in QS {
            let mut spy = Spy(&mut m, 0);
            let t = Instant::now();
            let raw = lang::open_reply(&mut spy, tpl, plan, None, &sections, q, true, &schema, &mut |_| ());
            let s = t.elapsed().as_secs_f64();
            let calls = spy.1;
            let text = raw.as_ref().ok().and_then(|r| reply::parse::<Value>(r).ok()).and_then(|v| v["reply"].as_str().map(String::from)).unwrap_or_default();
            let f = lang::counts(&text).0;
            let e = lang::counts(&text).1;
            let lang_ok = f >= 2 && f >= e;
            let lp = looped(&text);
            let low = text.to_lowercase();
            let done = !text.is_empty() && text.trim_end().ends_with(['.', '?', '!', ')', '"']) && (kw.is_empty() || kw.iter().any(|k| low.contains(k)));
            in_lang += lang_ok as usize;
            loops += lp as usize;
            complete += done as usize;
            retried += (calls > 1) as usize;
            secs.push(s);
            println!("ROW\t{name}\t{id}\t{}\t{}\t{}\t{s:.2}\t{calls}\t{q}\t{}", if lang_ok { "fil" } else { "EN?" }, if lp { "LOOP" } else { "-" }, if done { "ok" } else { "INCOMPLETE" }, text.replace('\n', " / "));
        }
        secs.sort_by(f64::total_cmp);
        println!("SUM\t{path}\t{name}\tin-language {in_lang}/24\tloops {loops}\tcomplete {complete}/24\tretried {retried}\tmedian {:.2}s\tmax {:.2}s", secs[12], secs[23]);
    }
}
