//! Card probe (spec 021 C22–C25): topic cards from a real model, with and without note passages, printed
//! with how many were kept. `cargo run --release -p intportal-llm --example cards -- <chat.gguf> [cpu]`
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
    for (topic, notes) in topics {
        let t = std::time::Instant::now();
        let o = gen::topic_cards(&mut m, Template::ChatMl, topic, &notes, 8);
        println!("== {topic} ({} notes): {} cards in {:.1}s, stopped {:?}", notes.len(), o.cards.len(), t.elapsed().as_secs_f64(), o.stopped);
        for c in &o.cards {
            println!("  {} | {}", c.front, c.back);
        }
    }
}
