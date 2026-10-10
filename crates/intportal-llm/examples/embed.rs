//! Does the embedding model rank notes sensibly? `cargo run --release -p
//! intportal-llm --example embed -- <nomic.gguf>`
use intportal_ai::llm::Llm;
use intportal_llm::{Device, Llama};

fn main() {
    let path = std::env::args().nth(1).expect("embedding model.gguf");
    let mut m = Llama::load(path.as_ref(), 2048, Device::Gpu).unwrap();
    let docs = [
        "Binary trees: inorder, preorder and postorder traversal. Height is the longest path to a leaf.",
        "Tuition payment is due on Monday at the cashier. Bring the assessment form.",
        "Pagsusulit sa Calculus sa Biyernes: derivatives, chain rule, limits.",
        "Group meeting sa library, 3pm, para sa thesis defense.",
    ];
    let dv = m.embed(&docs.iter().map(|d| format!("search_document: {d}")).collect::<Vec<_>>().iter().map(String::as_str).collect::<Vec<_>>()).unwrap();
    for q in ["how do I traverse a tree", "kailan ang bayad sa tuition", "ano ang sakop ng Calculus quiz", "what time is the thesis meeting"] {
        let qv = &m.embed(&[&format!("search_query: {q}")]).unwrap()[0];
        let scores: Vec<f32> = dv.iter().map(|d| d.iter().zip(qv).map(|(a, b)| a * b).sum()).collect();
        let best = scores.iter().enumerate().max_by(|a, b| a.1.total_cmp(b.1)).unwrap().0;
        println!("{q:40} -> doc {best} {:?}", scores.iter().map(|s| (s * 100.0).round() / 100.0).collect::<Vec<_>>());
    }
}
