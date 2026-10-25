//! Eval for A2: how often does a model answer 20 Taglish prompts in valid
//! schema-shaped JSON, and how fast. `cargo run --release -p intportal-llm
//! --example eval -- <model.gguf> [cpu]`
//!
//! Add `open` to run the open-question set instead: Taglish questions asked
//! with seeded notes as the only facts, scored on valid JSON, grounding in the
//! right note, refusing when no note supports the question, and latency.
//! Add `full` as well to send each question through `assis::answer` (the rules
//! first, then the model) instead of straight to the model.
use intportal_ai::{assis::{self, Facts}, llm::Llm, prompt::{build, chatml, gemma, Section, Template}, reply, schema::{reply_schema, Reply}};
use intportal_llm::{Device, Llama};
use std::time::Instant;

const SYSTEM: &str = "You are IntAssis, a study helper for a Filipino college student. Answer briefly in the language the student used (English, Filipino or Taglish). Reply as JSON with `reply` and `actions`. Put an action only if the student asks you to add a note (kind add_note) or set a reminder (kind add_reminder); otherwise use an empty list.";

const FIXTURES: [&str; 20] = [
    "Ano ang GWA at paano kinukuwenta?",
    "Pa-add naman ng note: bring calculator sa Friday quiz.",
    "Pwede mo ba akong i-remind bukas about Math 101 assignment?",
    "Paano mag-study para sa finals kung 3 araw na lang?",
    "What is FSRS and why do flashcards use it?",
    "Ang hirap ng Calculus, saan ako magsisimula?",
    "Add a note that Prof. Reyes moved the exam to Monday.",
    "Ilang units ang kailangan para maging full load?",
    "Paki-explain ang difference ng mean at median, tagalog please.",
    "Remind me to submit the lab report tomorrow 8am.",
    "Kinakabahan ako sa defense namin, tips?",
    "Ano ang pwede kong gawin kung bagsak ako sa isang subject?",
    "Gawan mo ako ng short study plan para sa isang linggo.",
    "Note: group meeting sa library, 3pm.",
    "Bakit mahalaga ang sleep sa pag-aaral?",
    "Define opportunity cost in simple words.",
    "Pwede bang mag-shift ng course after 1st year?",
    "Mag-remind ka sa akin na bayaran ang tuition sa Lunes.",
    "Ano ang Pomodoro technique?",
    "Thanks! Ano pa ang pwede mong gawin?",
];


/// Three notes the student "wrote"; every open question sees all of them.
const NOTES: [&str; 3] = [
    "Inorder traversal: visit the left subtree, then the node, then the right subtree. On a BST it visits keys in sorted order.",
    "Math 101: passing is 75%. Prof. Reyes moved the quiz to Monday; it covers limits and derivatives.",
    "Finals plan (3 days): 25-minute Pomodoro blocks, review past quizzes first, sleep before the exam.",
];

/// (question, keywords of which one must appear in a grounded reply; empty = no note supports it)
const OPEN: [(&str, &[&str]); 15] = [
    ("ano ang inorder traversal?", &["left", "right"]),
    ("Paano ba mag-visit ng BST in order?", &["sorted", "left", "inorder"]),
    ("What does inorder traversal give on a BST?", &["sorted", "order"]),
    ("Kailan ang quiz sa Math 101?", &["monday", "lunes"]),
    ("Ano ang passing sa Math 101?", &["75"]),
    ("Anong topics ang kasama sa Math quiz?", &["limit", "derivative"]),
    ("pano mag-study para sa finals?", &["pomodoro", "25", "quiz", "sleep", "tulog"]),
    ("Gaano katagal ang isang study block ko?", &["25"]),
    ("Okay lang ba ako sa Math?", &[]),
    ("Ano ang grade ko sa Physics?", &[]),
    ("Anong oras ang klase ko bukas?", &[]),
    ("Ano ang preorder traversal?", &[]),
    ("Kailan ang deadline ng thesis proposal?", &[]),
    ("Sino ang president ng PUP ngayon?", &[]),
    ("Magkano ang tuition sa susunod na sem?", &[]),
];

const REFUSALS: [&str; 22] = [
    "hindi ko alam", "di ko alam", "hindi ko", "wala akong", "walang", "wala sa", "don't know", "do not know", "not sure", "no information", "doesn't say", "not familiar", "hindi ako sigurado", "don't have", "do not have",
    // the canned replies of the rules (`full` only)
    "wala pang", "wala kang", "nothing is due", "no grading", "no grades", "only see today", "klase mo lang",
];

fn open(m: &mut Llama, path: &str, full: bool) {
    let schema = serde_json::json!({"type": "object", "properties": {"reply": {"type": "string"}}, "required": ["reply"]});
    let hits: String = NOTES.iter().map(|n| format!("- {n}\n")).collect();
    let system = build(&intportal_ai::persona::system(None), &[Section { title: "From the student's notes", body: &hits, priority: 7 }], 7000);
    let (mut valid, mut grounded, mut refused) = (0, 0, 0);
    let (mut lat, mut n_grounded, mut n_refuse) = (vec![], 0, 0);
    for (q, want) in OPEN {
        let user = format!("Student: {q}");
        let prompt = if path.contains("gemma") { gemma(&system, &user) } else { chatml(&system, &user) };
        let t = Instant::now();
        let parsed = if full {
            let facts = Facts {
                today: Some(intportal_core::today::Date::new(2026, 10, 15)),
                hits: NOTES.iter().map(|n| n.to_string()).collect(),
                subject_names: vec![("MATH 101".into(), "Mathematics".into())],
                ..Facts::default()
            };
            let tpl = if path.contains("gemma") { Template::Gemma } else { Template::ChatMl };
            assis::answer(m, tpl, &facts, &[], q).map(|a| serde_json::json!({"reply": a.reply}))
        } else {
            m.generate(&prompt, Some(&schema), 300, &mut |_| true).map_err(|e| e.to_string()).and_then(|o| reply::parse::<serde_json::Value>(&o).map_err(|e| e.to_string()))
        };
        lat.push(t.elapsed().as_secs_f64());
        let Some(text) = parsed.as_ref().ok().and_then(|v| v["reply"].as_str()) else {
            println!("FAIL {q}: {parsed:?}");
            if want.is_empty() { n_refuse += 1 } else { n_grounded += 1 }
            continue;
        };
        valid += 1;
        let low = text.to_lowercase();
        let verdict = if want.is_empty() {
            n_refuse += 1;
            let ok = REFUSALS.iter().any(|r| low.contains(r));
            refused += ok as usize;
            if ok { "refused " } else { "INVENTED" }
        } else {
            n_grounded += 1;
            let ok = want.iter().any(|k| low.contains(k));
            grounded += ok as usize;
            if ok { "grounded" } else { "MISSED  " }
        };
        println!("{verdict} {q}\n         -> {text}");
    }
    lat.sort_by(f64::total_cmp);
    println!(
        "\n{path}\nvalid JSON {valid}/{}, grounded {grounded}/{n_grounded}, refusals {refused}/{n_refuse}, median latency {:.1}s (max {:.1}s)",
        OPEN.len(),
        lat[lat.len() / 2],
        lat[lat.len() - 1]
    );
}

fn main() {
    let path = std::env::args().nth(1).expect("model.gguf");
    let device = if std::env::args().any(|a| a == "cpu") { Device::Cpu } else { Device::Gpu };
    let mut m = Llama::load(path.as_ref(), 2048, device).unwrap();
    if std::env::args().any(|a| a == "open") {
        return open(&mut m, &path, std::env::args().any(|a| a == "full"));
    }
    let schema = reply_schema(&["add_note", "add_reminder"]);
    let (mut valid, mut tokens) = (0, 0usize);
    let t0 = Instant::now();
    for q in FIXTURES {
        let out = m.generate(&if path.contains("gemma") { gemma(SYSTEM, q) } else { chatml(SYSTEM, q) }, Some(&schema), 256, &mut |_| {
            tokens += 1;
            true
        });
        match out.map_err(|e| e.to_string()).and_then(|o| reply::parse::<Reply>(&o).map_err(|e| e.to_string())) {
            Ok(r) => {
                valid += 1;
                println!("ok   {q}\n     -> {} {:?}", r.reply, r.actions);
            }
            Err(e) => println!("FAIL {q}: {e}"),
        }
    }
    let s = t0.elapsed().as_secs_f64();
    println!("\n{valid}/20 valid, {:.1} tok/s overall ({tokens} chunks in {s:.1}s)", tokens as f64 / s);
}
