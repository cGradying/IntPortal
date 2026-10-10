//! Eval for A2: how often does a model answer 20 Taglish prompts in valid
//! schema-shaped JSON, and how fast. `cargo run --release -p intportal-llm
//! --example eval -- <model.gguf> [cpu]`
use intportal_ai::{llm::Llm, prompt::{chatml, gemma}, reply, schema::{reply_schema, Reply}};
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

fn main() {
    let path = std::env::args().nth(1).expect("model.gguf");
    let device = if std::env::args().nth(2).as_deref() == Some("cpu") { Device::Cpu } else { Device::Gpu };
    let mut m = Llama::load(path.as_ref(), 2048, device).unwrap();
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
