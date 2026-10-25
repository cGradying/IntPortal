//! Compact eval suite (#167): the cases of `intportal_ai::evalset` through
//! `assis::answer` (the rules first, then the model) on a real chat model.
//! `cargo run --release -p intportal-llm --example suite -- <chat.gguf> [cpu]`
//!
//! One tab-separated `CASE` line per case (id, kind, verdict, model calls,
//! seconds, the question, the reply) to read by hand, one line per kind, then
//! one `SUITE` line. Exits non-zero unless every hard kind (own data,
//! injection, homework, harmful) passes in full and the overall score is at
//! least 80% or no worse than this model's entry in data/suite-baseline.json.
//! Greedy sampling, so a rerun gives the same replies.
use intportal_ai::{
    evalset::{self, Kind, CASES},
    prompt::Template,
};
use intportal_llm::{Device, Llama};
use serde_json::Value;
use std::{process::ExitCode, time::Instant};

/// {"<model>": {"pass": n, "of": total}}, updated by hand after a run that was read through.
const BASELINE: &str = include_str!("data/suite-baseline.json");

fn main() -> ExitCode {
    let path = std::env::args().nth(1).expect("model.gguf");
    let device = if std::env::args().any(|a| a == "cpu") { Device::Cpu } else { Device::Gpu };
    let mut m = Llama::load(path.as_ref(), 4096, device).unwrap();
    let (name, tpl) = if path.contains("gemma") {
        ("gemma3-1b".to_string(), Template::Gemma)
    } else if path.contains("qwen") {
        ("qwen3-1.7b".to_string(), Template::ChatMl)
    } else {
        (std::path::Path::new(&path).file_stem().map_or(path.clone(), |s| s.to_string_lossy().into_owned()), Template::ChatMl)
    };
    let mut per_kind = vec![(0usize, 0usize); Kind::ALL.len()];
    for c in &CASES {
        let t = Instant::now();
        let (reply, calls) = evalset::ask(&mut m, tpl, c);
        let secs = t.elapsed().as_secs_f64();
        let verdict = evalset::score(c, &reply, calls);
        let k = Kind::ALL.iter().position(|k| *k == c.kind).unwrap();
        per_kind[k].1 += 1;
        per_kind[k].0 += verdict.is_ok() as usize;
        println!("CASE\t{}\t{}\t{}\t{calls}\t{secs:.1}\t{}\t{}", c.id, c.kind.name(), verdict.err().map_or("ok".to_string(), |e| format!("FAIL {e}")), c.q, reply.replace('\n', " / "));
    }
    println!();
    for (k, (p, n)) in Kind::ALL.iter().zip(&per_kind) {
        println!("{:<10} {p}/{n}{}", k.name(), if k.hard() { "  (hard)" } else { "" });
    }
    let passes: usize = per_kind.iter().map(|x| x.0).sum();
    let total = CASES.len();
    let hard_failures: usize = Kind::ALL.iter().zip(&per_kind).filter(|(k, _)| k.hard()).map(|(_, (p, n))| n - p).sum();
    let baseline: Option<usize> = serde_json::from_str::<Value>(BASELINE)
        .ok()
        .and_then(|b| b[&name].as_object().cloned())
        .filter(|b| b["of"].as_u64() == Some(total as u64))
        .and_then(|b| b["pass"].as_u64().map(|p| p as usize));
    let ok = evalset::gate(passes, total, hard_failures, baseline);
    println!(
        "SUITE {name} pass {passes}/{total} ({:.0}%) hard failures {hard_failures} baseline {} -> {}",
        passes as f64 * 100.0 / total as f64,
        baseline.map_or("none".to_string(), |b| b.to_string()),
        if ok { "PASS" } else { "FAIL" }
    );
    if ok { ExitCode::SUCCESS } else { ExitCode::FAILURE }
}
