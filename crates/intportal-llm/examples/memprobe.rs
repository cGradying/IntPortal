//! Peak memory of chat-only, embedder-only and both loaded: `/usr/bin/time -l memprobe <chat|embed|both|embed-then-chat> <chat.gguf> <embed.gguf> [threads]`
use intportal_ai::llm::Llm;
use intportal_llm::{Device, Llama};
use std::time::Instant;

fn rss_mb() -> u64 {
    let out = std::process::Command::new("ps").args(["-o", "rss=", "-p", &std::process::id().to_string()]).output().unwrap();
    String::from_utf8_lossy(&out.stdout).trim().parse::<u64>().unwrap_or(0) / 1024
}

fn main() {
    let a: Vec<String> = std::env::args().collect();
    let (mode, chat, emb) = (a[1].as_str(), a[2].as_str(), a[3].as_str());
    let t = Instant::now();
    let note = "Binary trees: inorder, preorder and postorder traversal. Height is the longest path to a leaf. ".repeat(7);
    let docs: Vec<String> = (0..12).map(|i| format!("title: Note {i} | text: {note}")).collect();
    let docs: Vec<&str> = docs.iter().map(String::as_str).collect();
    let prompt = "<|im_start|>system\nYou are LAR.<|im_end|>\n<|im_start|>user\n".to_string() + &"Tell me about trees. ".repeat(150) + "<|im_end|>\n<|im_start|>assistant\n";
    let mut e = None;
    let mut c = None;
    if mode == "embed" || mode == "both" || mode == "embed-then-chat" {
        e = Some(Llama::load(emb.as_ref(), 1024, Device::Cpu).unwrap());
        println!("embedder loaded {:?} rss {} MB", t.elapsed(), rss_mb());
        let t = Instant::now();
        e.as_mut().unwrap().embed(&docs).unwrap();
        println!("embedded 12 chunks {:?} rss {} MB", t.elapsed(), rss_mb());
        if mode == "embed-then-chat" { e = None; println!("embedder dropped rss {} MB", rss_mb()); }
    }
    if mode == "chat" || mode == "both" || mode == "embed-then-chat" {
        let t = Instant::now();
        c = Some(Llama::load(chat.as_ref(), 4096, Device::Cpu).unwrap());
        println!("chat loaded {:?} rss {} MB", t.elapsed(), rss_mb());
        let t = Instant::now();
        let mut n = 0;
        c.as_mut().unwrap().generate(&prompt, None, 16, &mut |_| { n += 1; true }).unwrap();
        println!("generate 16 tokens after ~600-token prompt {:?} ({n} pieces) rss {} MB", t.elapsed(), rss_mb());
    }
    drop((e, c));
}
