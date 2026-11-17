//! One question at a time through `assis::answer` on a real model, with the eval's facts and no notes
//! found: what LAR says, and whether it says it from what it knows (spec 021 C15, C16).
//! `cargo run --release -p intportal-llm --example ask -- <chat.gguf> "question" ["question" ...]`
use intportal_ai::{assis, evalset, prompt::Template};
use intportal_llm::{Device, Llama};

fn main() {
    let a: Vec<String> = std::env::args().collect();
    let mut m = Llama::load(std::path::Path::new(a.get(1).expect("chat.gguf")), 4096, Device::Gpu).expect("load");
    for q in &a[2..] {
        let t = std::time::Instant::now();
        let r = assis::answer(&mut m, Template::ChatMl, &evalset::facts(&[], &[]), &[], q).expect("answer");
        println!("Q {q}\nA ({:.1}s, {:?}, known {}) {}\n", t.elapsed().as_secs_f64(), r.route, r.known, r.reply);
    }
}
