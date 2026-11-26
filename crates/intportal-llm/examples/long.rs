//! Long answers probe (spec 062 C23–C27): six teach-me questions through `assis::answer` at the wide window,
//! with the reply's length, whether it was cut, the time, and one Keep going where it was.
//! `cargo run --release -p intportal-llm --example long -- <chat.gguf> [cpu] [low]`
use intportal_ai::{assis, lang, prompt::Template};
use intportal_core::today::Date;
use intportal_llm::{Device, Llama};

fn main() {
    let a: Vec<String> = std::env::args().collect();
    let dev = if a.iter().any(|x| x == "cpu") { Device::Cpu } else { Device::Gpu };
    let low = a.iter().any(|x| x == "low");
    let mut m = Llama::load(std::path::Path::new(a.get(1).expect("chat.gguf")), if low { 4096 } else { 8192 }, dev).expect("load");
    let facts = assis::Facts { today: Some(Date::new(2026, 11, 26)), long_tokens: if low { lang::LONG_TOKENS_LOW } else { lang::LONG_TOKENS }, ..Default::default() };
    let qs = [
        "explain recursion step by step",
        "walk me through how to solve 2x + 3 = 11",
        "explain the difference between a stack and a queue",
        "teach me how photosynthesis works",
        "summarize the causes of the Philippine Revolution",
        "what is a stack?",
    ];
    for q in qs {
        let t = std::time::Instant::now();
        let r = assis::answer(&mut m, Template::ChatMl, &facts, &[], q);
        let dt = t.elapsed().as_secs_f64();
        match r {
            Ok(ans) => {
                println!("== {q}: {} chars, {} words, cut {} in {dt:.1}s", ans.reply.chars().count(), ans.reply.split_whitespace().count(), ans.more);
                println!("{}", ans.reply);
                if ans.more {
                    let t = std::time::Instant::now();
                    let (more, cut) = assis::more(&mut m, Template::ChatMl, q, &ans.reply, &mut |_| ()).expect("more");
                    println!("-- Keep going: +{} words, cut {cut} in {:.1}s\n{more}", more.split_whitespace().count(), t.elapsed().as_secs_f64());
                }
            }
            Err(e) => println!("== {q}: Err {e} in {dt:.1}s"),
        }
    }
}
