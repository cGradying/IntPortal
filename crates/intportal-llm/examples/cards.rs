//! Card probe (spec 021 C22–C25): topic cards from a real model, with and without note passages, printed
//! with how many were kept. With `quiz`, the same topics as quiz cards (spec 062 C17–C20, 063 C15–C17): how
//! many cards kept their three wrong answers, every wrong answer the model wrote with the rule that dropped
//! it, the time per batch of wrong answers, then wrong answers written for 8 plain cards in one call.
//! `cargo run --release -p intportal-llm --example cards -- <chat.gguf> [cpu] [quiz]`
use intportal_ai::{gen, llm::Llm, prompt::Template};
use intportal_llm::{Device, Llama};
use std::collections::BTreeMap;

/// The model, with every reply and its time kept, so the probe can show what the rules threw away.
struct Rec {
    m: Llama,
    log: Vec<(String, String, f64)>,
}

impl Llm for Rec {
    fn generate(&mut self, prompt: &str, schema: Option<&serde_json::Value>, max: u32, on: &mut dyn FnMut(&str) -> bool) -> Result<String, String> {
        let t = std::time::Instant::now();
        let r = self.m.generate(prompt, schema, max, on)?;
        self.log.push((prompt.into(), r.clone(), t.elapsed().as_secs_f64()));
        Ok(r)
    }
    fn embed(&mut self, texts: &[&str]) -> Result<Vec<Vec<f32>>, String> {
        self.m.embed(texts)
    }
}

/// The wrong answers each card got in the wrong-answer replies logged, in card order, as the model wrote them.
fn raw_sets(log: &[(String, String, f64)]) -> Vec<Vec<serde_json::Value>> {
    log.iter()
        .filter(|(p, _, _)| p.contains("wrong answers for a multiple-choice"))
        .flat_map(|(_, r, _)| {
            let v: serde_json::Value = serde_json::from_str(r).unwrap_or_default();
            v["cards"].as_array().cloned().unwrap_or_default().into_iter().map(|c| c["wrong"].as_array().cloned().unwrap_or_default())
        })
        .collect()
}

/// A change as the app makes it, with the change shown, or why it could not be made.
fn applied(back: &str, w: serde_json::Value) -> (String, Option<String>) {
    let shown = format!("[{} -> {}] ", w["change"].as_str().unwrap_or(""), w["to"].as_str().unwrap_or(""));
    match serde_json::from_value::<gen::Wrong>(w).ok().and_then(|x| x.answer(back.trim())) {
        Some(a) => (shown, Some(a)),
        None => (shown, None),
    }
}

fn main() {
    let a: Vec<String> = std::env::args().collect();
    let dev = if a.iter().any(|x| x == "cpu") { Device::Cpu } else { Device::Gpu };
    let m = Llama::load(std::path::Path::new(a.get(1).expect("chat.gguf")), 4096, dev).expect("load");
    let mut m = Rec { m, log: vec![] };
    let topics: [(&str, Vec<String>); 4] = [
        ("binary search trees", vec!["Data Structures: in a BST every left child is smaller than its parent and every right child larger. Search, insert and delete take O(log n) when the tree is balanced.".into()]),
        ("photosynthesis", vec![]),
        ("the Philippine Revolution", vec![]),
        ("derivatives", vec!["Math 101: the power rule brings the exponent down and lowers it by one. The chain rule multiplies the outer derivative by the inner one.".into()]),
    ];
    let quiz = a.iter().any(|x| x == "quiz");
    let (mut made, mut armed) = (0, 0);
    let mut faults: BTreeMap<&str, usize> = BTreeMap::new();
    let mut plain = vec![];
    for (topic, notes) in topics {
        let t = std::time::Instant::now();
        let from = m.log.len();
        let o = gen::topic_cards(&mut m, Template::ChatMl, topic, &notes, 8, quiz);
        println!("== {topic} ({} notes): {} cards in {:.1}s, stopped {:?}", notes.len(), o.cards.len(), t.elapsed().as_secs_f64(), o.stopped);
        let batches: Vec<String> = m.log[from..].iter().filter(|(p, _, _)| p.contains("wrong answers for a multiple-choice")).map(|x| format!("{:.1}s", x.2)).collect();
        if quiz {
            println!("   wrong-answer batches: {}", batches.join(", "));
        }
        let raw = raw_sets(&m.log[from..]);
        made += o.cards.len();
        for (i, c) in o.cards.iter().enumerate() {
            armed += usize::from(c.wrong.len() == 3);
            println!("  {} | {}  [{}]", c.front, c.back, if c.wrong.len() == 3 { "kept" } else { "dropped" });
            if quiz {
                let mut asked = gen::Card { wrong: vec![], ..c.clone() };
                let mut shown = vec![];
                for w in raw.get(i).cloned().unwrap_or_default() {
                    let (s, a) = applied(&c.back, w);
                    match a {
                        Some(a) => {
                            asked.wrong.push(a);
                            shown.push(s);
                        }
                        None => println!("      - {s} <- not in the back"),
                    }
                }
                let asked = gen::repair(&asked);
                let mut kept = vec![];
                for (w, s) in asked.wrong.iter().zip(&shown) {
                    let f = if kept.len() == 3 { Some("not needed") } else { gen::wrong_fault(&asked, w, &kept) };
                    if f.is_none() {
                        kept.push(w.clone());
                    }
                    *faults.entry(f.unwrap_or("fair")).or_default() += 1;
                    println!("      {} {s}{w}{}", if c.wrong.contains(w) { "x" } else { "-" }, f.map(|f| format!("  <- {f}")).unwrap_or_default());
                }
            }
            plain.push(gen::Card { wrong: vec![], ..c.clone() });
        }
    }
    if quiz {
        println!("\n{armed} of {made} quiz cards kept three wrong answers");
        println!("each wrong answer, by the first rule it fails: {faults:?}");
        let t = std::time::Instant::now();
        let w = gen::wrong_for(&mut m, Template::ChatMl, &plain[..plain.len().min(8)]).expect("wrong_for");
        println!("wrong_for: {} of {} cards got three, in {:.1}s", w.iter().filter(|x| x.len() == 3).count(), w.len(), t.elapsed().as_secs_f64());
        for (c, w) in plain.iter().zip(&w).filter(|(_, w)| !w.is_empty()) {
            println!("  {} | {}\n      x {}", c.front, c.back, w.join("\n      x "));
        }
    }
}
