// Spike A0: load a GGUF, generate, report tokens/sec. Never wired into the app.
// Usage: s1-llama <model.gguf> [n_tokens]
use llama_cpp_2::{
    context::params::LlamaContextParams, llama_backend::LlamaBackend, llama_batch::LlamaBatch,
    model::{params::LlamaModelParams, LlamaModel}, sampling::LlamaSampler,
};
use std::{num::NonZeroU32, time::Instant};

fn main() {
    let path = std::env::args().nth(1).expect("model.gguf");
    let n: i32 = std::env::args().nth(2).and_then(|s| s.parse().ok()).unwrap_or(128);
    let backend = LlamaBackend::init().unwrap();
    let t0 = Instant::now();
    let model = LlamaModel::load_from_file(&backend, &path, &LlamaModelParams::default().with_n_gpu_layers(std::env::var("NGL").ok().and_then(|s| s.parse().ok()).unwrap_or(999))).unwrap();
    println!("load {:?}", t0.elapsed());
    let mut ctx = model
        .new_context(&backend, LlamaContextParams::default().with_n_ctx(NonZeroU32::new(2048)))
        .unwrap();
    let toks = model.vocab().tokenize(b"Explain what a GWA is to a first-year student in Taglish.", true, false);
    let mut batch = LlamaBatch::new(512, 1);
    for (i, t) in toks.iter().enumerate() {
        batch.add(*t, i as i32, &[0], i == toks.len() - 1).unwrap();
    }
    let t1 = Instant::now();
    ctx.decode(&mut batch).unwrap();
    println!("prompt {} tok in {:?}", toks.len(), t1.elapsed());
    let mut sampler = LlamaSampler::greedy();
    let mut pos = toks.len() as i32;
    let t2 = Instant::now();
    let mut out = String::new();
    for _ in 0..n {
        let tok = sampler.sample(&ctx, batch.n_tokens() - 1);
        if model.vocab().is_eog(tok) { break; }
        out.push_str(&String::from_utf8_lossy(&model.vocab().token_to_piece(tok, false, None)));
        batch.clear();
        batch.add(tok, pos, &[0], true).unwrap();
        pos += 1;
        ctx.decode(&mut batch).unwrap();
    }
    let s = t2.elapsed().as_secs_f64();
    println!("{out}\n--\n{:.1} tok/s over {:.1}s", (pos as usize - toks.len()) as f64 / s, s);
}
