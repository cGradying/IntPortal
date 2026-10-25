//! Does the embedding model rank notes sensibly? `cargo run --release -p
//! intportal-llm --example embed -- <embeddinggemma-2-Q8_0.gguf> [n_ctx] [cpu]`
//! (`/usr/bin/time -l` on it gives the peak memory the models.rs gate numbers come from)
use intportal_ai::{llm::Llm, rag};
use intportal_llm::{Device, Llama};

fn main() {
    let path = std::env::args().nth(1).expect("embedding model.gguf");
    let n_ctx = std::env::args().nth(2).and_then(|n| n.parse().ok()).unwrap_or(1024);
    let device = if std::env::args().nth(3).as_deref() == Some("cpu") { Device::Cpu } else { Device::Gpu };
    let mut m = Llama::load(path.as_ref(), n_ctx, device).unwrap();
    let docs = [
        "Binary trees: inorder, preorder and postorder traversal. Height is the longest path to a leaf.",
        "Tuition payment is due on Monday at the cashier. Bring the assessment form.",
        "Pagsusulit sa Calculus sa Biyernes: derivatives, chain rule, limits.",
        "Group meeting sa library, 3pm, para sa thesis defense.",
    ];
    let dv = m.embed(&docs.iter().map(|d| rag::doc_text("", d)).collect::<Vec<_>>().iter().map(String::as_str).collect::<Vec<_>>()).unwrap();
    for q in ["how do I traverse a tree", "kailan ang bayad sa tuition", "ano ang sakop ng Calculus quiz", "what time is the thesis meeting"] {
        let qv = &m.embed(&[&rag::query_text(q)]).unwrap()[0];
        let scores: Vec<f32> = dv.iter().map(|d| d.iter().zip(qv).map(|(a, b)| a * b).sum()).collect();
        let best = scores.iter().enumerate().max_by(|a, b| a.1.total_cmp(b.1)).unwrap().0;
        println!("{q:40} -> doc {best} {:?}", scores.iter().map(|s| (s * 100.0).round() / 100.0).collect::<Vec<_>>());
    }
}
