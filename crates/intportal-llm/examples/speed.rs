//! Speed probe (spec 021 C12, C26): time to the first token and decode speed on a prompt the size of a
//! real LAR turn (persona, facts, two note passages, a question), three runs after one warm-up.
//! `cargo run --release -p intportal-llm --example speed -- <chat.gguf> [cpu] [threads=N]`
use intportal_ai::{llm::Llm, prompt::Template};
use intportal_llm::{Device, Llama};
use std::time::Instant;

const SYSTEM: &str = "You are LAR, a friendly study buddy inside IntPortal, a student app for PUP. Answer in clear, warm English, briefly. Use the student's data below when it answers the question. If the data does not say, use what you know and say it is from what you know. Never invent the student's own rooms, grades, deadlines or professors.\n\nToday: Monday, 17 November 2026, 9:40 AM.\nClasses today: MATH 101 Calculus 1 at 10:30 AM in S510 (Prof. Reyes); COMP 201 Data Structures at 1:00 PM online; ENG 102 Purposive Communication at 4:00 PM in N203.\nDue soon: COMP 201 lab 4 (linked lists) due Wednesday 11:59 PM; MATH 101 quiz 3 on derivatives Friday.\nGrades this term: MATH 101 midterm 1.75; COMP 201 midterm 1.50; ENG 102 midterm 2.00.\n\nFrom the student's notes:\n[Class note, COMP 201] A linked list stores nodes; each node holds a value and a pointer to the next node. Insertion at the head is O(1); search is O(n). A doubly linked list also points back, so removal given a node is O(1).\n[Day note, Nov 14] Derivative rules to review: power rule, product rule, quotient rule, chain rule. The chain rule multiplies the outer derivative by the inner derivative.";
const ASKS: [&str; 3] = [
    "What's the difference between a singly and doubly linked list, and when would I use each?",
    "Explain the chain rule with one example, I have a quiz on Friday.",
    "What should I study first today?",
];

fn main() {
    let a: Vec<String> = std::env::args().collect();
    let path = a.get(1).expect("chat.gguf");
    let dev = if a.iter().any(|x| x == "cpu") { Device::Cpu } else { Device::Gpu };
    let t = Instant::now();
    let mut m = Llama::load(std::path::Path::new(path), 4096, dev).expect("load");
    println!("load {:.2}s", t.elapsed().as_secs_f64());
    let (mut ttfts, mut tps) = (vec![], vec![]);
    for (i, q) in std::iter::once(&ASKS[0]).chain(ASKS.iter()).enumerate() {
        let prompt = Template::ChatMl.wrap(SYSTEM, q);
        let (start, mut first, mut n) = (Instant::now(), None, 0u32);
        let out = m
            .generate(&prompt, None, 160, &mut |_| {
                first.get_or_insert_with(|| start.elapsed().as_secs_f64());
                n += 1;
                true
            })
            .expect("generate");
        let total = start.elapsed().as_secs_f64();
        let f = first.unwrap_or(total);
        let rate = (n.saturating_sub(1)) as f64 / (total - f).max(1e-3);
        if i == 0 {
            println!("warm-up done");
            continue;
        }
        println!("ROW first={f:.2}s rate={rate:.1}tok/s n={n} reply={:?}", out.chars().take(160).collect::<String>());
        ttfts.push(f);
        tps.push(rate);
    }
    let avg = |v: &[f64]| v.iter().sum::<f64>() / v.len() as f64;
    println!("SUMMARY first={:.2}s rate={:.1}tok/s", avg(&ttfts), avg(&tps));
}
