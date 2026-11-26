//! Card probe (spec 021 C22–C25): topic cards from a real model, with and without note passages, printed
//! with how many were kept. With `quiz`, the same topics as quiz cards (spec 062 C17–C20): how many cards kept
//! their three wrong answers, then wrong answers written for 8 plain cards in one call.
//! `cargo run --release -p intportal-llm --example cards -- <chat.gguf> [cpu] [quiz]`
use intportal_ai::{gen, prompt::Template};
use intportal_llm::{Device, Llama};

fn main() {
    let a: Vec<String> = std::env::args().collect();
    let dev = if a.iter().any(|x| x == "cpu") { Device::Cpu } else { Device::Gpu };
    let mut m = Llama::load(std::path::Path::new(a.get(1).expect("chat.gguf")), 4096, dev).expect("load");
    let topics: [(&str, Vec<String>); 4] = [
        ("binary search trees", vec!["Data Structures: in a BST every left child is smaller than its parent and every right child larger. Search, insert and delete take O(log n) when the tree is balanced.".into()]),
        ("photosynthesis", vec![]),
        ("the Philippine Revolution", vec![]),
        ("derivatives", vec!["Math 101: the power rule brings the exponent down and lowers it by one. The chain rule multiplies the outer derivative by the inner one.".into()]),
    ];
    let quiz = a.iter().any(|x| x == "quiz");
    let (mut made, mut armed) = (0, 0);
    let mut plain = vec![];
    for (topic, notes) in topics {
        let t = std::time::Instant::now();
        let o = gen::topic_cards(&mut m, Template::ChatMl, topic, &notes, 8, quiz);
        println!("== {topic} ({} notes): {} cards in {:.1}s, stopped {:?}", notes.len(), o.cards.len(), t.elapsed().as_secs_f64(), o.stopped);
        made += o.cards.len();
        for c in &o.cards {
            armed += usize::from(c.wrong.len() == 3);
            println!("  {} | {}{}", c.front, c.back, if c.wrong.is_empty() { String::new() } else { format!("\n      x {}", c.wrong.join("\n      x ")) });
            plain.push(gen::Card { wrong: vec![], ..c.clone() });
        }
    }
    if quiz {
        println!("\n{armed} of {made} quiz cards kept three wrong answers");
        let t = std::time::Instant::now();
        let w = gen::wrong_for(&mut m, Template::ChatMl, &plain[..plain.len().min(8)]).expect("wrong_for");
        println!("wrong_for: {} of {} cards got three, in {:.1}s", w.iter().filter(|x| x.len() == 3).count(), w.len(), t.elapsed().as_secs_f64());
    }
}
