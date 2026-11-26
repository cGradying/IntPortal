//! Long answers probe (spec 062 C23–C27): six teach-me questions through `assis::answer` at the wide window,
//! with the reply's length, whether it was cut, the time, and one Keep going where it was.
//! `gate` (spec 063 C18–C19): at the 4,096 window (400 tokens), the first 5 answers cut at their limit, each
//! with Keep going up to twice, and for each continuation whether it repeats a full sentence already written
//! or restarts (opens with the answer's own first words). The texts print in full for a hand read.
//! `cargo run --release -p intportal-llm --example long -- <chat.gguf> [cpu] [low] [gate]`
use intportal_ai::{assis, lang, prompt::Template};
use intportal_core::today::Date;
use intportal_llm::{Device, Llama};

fn main() {
    let a: Vec<String> = std::env::args().collect();
    let dev = if a.iter().any(|x| x == "cpu") { Device::Cpu } else { Device::Gpu };
    let gate = a.iter().any(|x| x == "gate");
    let low = gate || a.iter().any(|x| x == "low");
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
    if gate {
        return gate_run(&mut m, &facts);
    }
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

/// Lower-case words, for comparing sentences whatever their punctuation.
fn norm(s: &str) -> String {
    s.to_lowercase().split(|c: char| !c.is_alphanumeric()).filter(|w| !w.is_empty()).collect::<Vec<_>>().join(" ")
}

/// Sentences and list lines of at least 5 words, normalized.
fn sentences(text: &str) -> Vec<String> {
    text.split(['.', '!', '?', '\n']).map(norm).filter(|s| s.split(' ').count() >= 5).collect()
}

fn gate_run(m: &mut Llama, facts: &assis::Facts) {
    let qs = [
        "summarize the causes of the Philippine Revolution",
        "explain in detail how a compiler turns code into a program",
        "teach me how TCP connects and sends data, step by step",
        "explain in detail how the French Revolution unfolded",
        "walk me through every stage of mitosis in detail",
        "explain in detail how vaccines train the immune system",
        "teach me the history of the Roman Empire in detail",
    ];
    let (mut cut_answers, mut restarts, mut repeats, mut parts, mut mid) = (0, 0, 0, 0, 0);
    for q in qs {
        if cut_answers == 5 {
            break;
        }
        let t = std::time::Instant::now();
        let ans = match assis::answer(m, Template::ChatMl, facts, &[], q) {
            Ok(a) => a,
            Err(e) => {
                println!("== {q}: Err {e}");
                continue;
            }
        };
        println!("== {q}: {} words, cut {} in {:.1}s\n{}", ans.reply.split_whitespace().count(), ans.more, t.elapsed().as_secs_f64(), ans.reply);
        if !ans.more {
            continue;
        }
        cut_answers += 1;
        let opening: String = norm(&ans.reply).split(' ').take(5).collect::<Vec<_>>().join(" ");
        let mut text = ans.reply.clone();
        for n in 1..=2 {
            let t = std::time::Instant::now();
            let (more, cut) = match assis::more(m, Template::ChatMl, q, &text, &mut |_| ()) {
                Ok(x) => x,
                Err(e) => {
                    println!("-- Keep going {n}: Err {e}");
                    break;
                }
            };
            parts += 1;
            let had = sentences(&text);
            let repeated: Vec<String> = sentences(&more).into_iter().filter(|s| had.contains(s)).collect();
            let restarted = norm(&more).contains(&opening);
            // The app puts a space between a cut and its continuation; a word cut in half then reads as two.
            let midword = text.ends_with(char::is_alphanumeric) && more.starts_with(char::is_alphanumeric);
            mid += usize::from(midword);
            restarts += usize::from(restarted);
            repeats += usize::from(!repeated.is_empty());
            println!("-- Keep going {n}: +{} words, cut {cut} in {:.1}s, restarts {restarted}, mid-word {midword}, repeats {:?}\n[{}]{more}", more.split_whitespace().count(), t.elapsed().as_secs_f64(), repeated, text.chars().rev().take(40).collect::<Vec<_>>().into_iter().rev().collect::<String>());
            text.push_str(&more);
            if !cut {
                break;
            }
        }
    }
    println!("\n{cut_answers} cut answers, {parts} continuations: {restarts} restart, {repeats} repeat a full sentence, {mid} continue a word cut in half");
}
