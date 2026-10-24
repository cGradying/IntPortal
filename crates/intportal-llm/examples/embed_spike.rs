//! SPIKE (issue #157): nomic vs EmbeddingGemma-2 on the Taglish open set.
//! `cargo run --release -p intportal-llm --example embed_spike -- <nomic.gguf> <embeddinggemma-2.gguf>`
use intportal_ai::llm::Llm;
use intportal_llm::{Device, Llama};
use std::time::Instant;

// Three seeded notes of eval.rs split into 8 sentence chunks; the note id is the first digit group below.
const CHUNKS: [&str; 8] = [
    "Inorder traversal: visit the left subtree, then the node, then the right subtree.",
    "Inorder traversal: on a BST it visits keys in sorted order.",
    "Math 101: passing is 75%.",
    "Math 101: Prof. Reyes moved the quiz to Monday.",
    "Math 101: the quiz covers limits and derivatives.",
    "Finals plan (3 days): 25-minute Pomodoro blocks.",
    "Finals plan: review past quizzes first.",
    "Finals plan: sleep before the exam.",
];
const NOTES: [&str; 3] = [
    "Inorder traversal: visit the left subtree, then the node, then the right subtree. On a BST it visits keys in sorted order.",
    "Math 101: passing is 75%. Prof. Reyes moved the quiz to Monday; it covers limits and derivatives.",
    "Finals plan (3 days): 25-minute Pomodoro blocks, review past quizzes first, sleep before the exam.",
];
// (question, gold chunk ids; empty = unsupported)
const OPEN: [(&str, &[usize]); 15] = [
    ("ano ang inorder traversal?", &[0]),
    ("Paano ba mag-visit ng BST in order?", &[0, 1]),
    ("What does inorder traversal give on a BST?", &[1]),
    ("Kailan ang quiz sa Math 101?", &[3]),
    ("Ano ang passing sa Math 101?", &[2]),
    ("Anong topics ang kasama sa Math quiz?", &[4]),
    ("pano mag-study para sa finals?", &[5, 6, 7]),
    ("Gaano katagal ang isang study block ko?", &[5]),
    ("Okay lang ba ako sa Math?", &[]),
    ("Ano ang grade ko sa Physics?", &[]),
    ("Anong oras ang klase ko bukas?", &[]),
    ("Ano ang preorder traversal?", &[]),
    ("Kailan ang deadline ng thesis proposal?", &[]),
    ("Sino ang president ng PUP ngayon?", &[]),
    ("Magkano ang tuition sa susunod na sem?", &[]),
];

fn trunc(v: &[f32], d: usize) -> Vec<f32> {
    let t = &v[..d.min(v.len())];
    let n = t.iter().map(|x| x * x).sum::<f32>().sqrt().max(f32::EPSILON);
    t.iter().map(|x| x / n).collect()
}
fn dot(a: &[f32], b: &[f32]) -> f32 { a.iter().zip(b).map(|(x, y)| x * y).sum() }
fn med(v: &mut Vec<f32>) -> f32 { v.sort_by(|a, b| a.total_cmp(b)); v[v.len() / 2] }

/// Returns (top1 correct of 8, supported best scores, unsupported best scores).
fn score(qs: &[Vec<f32>], ds: &[Vec<f32>], gold: impl Fn(&[usize]) -> Vec<usize>, d: usize) -> (usize, Vec<f32>, Vec<f32>, Vec<String>) {
    let ds: Vec<Vec<f32>> = ds.iter().map(|v| trunc(v, d)).collect();
    let (mut ok, mut sup, mut uns, mut log) = (0, vec![], vec![], vec![]);
    for ((q, g), qv) in OPEN.iter().zip(qs) {
        let qv = trunc(qv, d);
        let s: Vec<f32> = ds.iter().map(|x| dot(&qv, x)).collect();
        let (best, bs) = s.iter().enumerate().max_by(|a, b| a.1.total_cmp(b.1)).map(|(i, v)| (i, *v)).unwrap();
        let g = gold(g);
        if g.is_empty() { uns.push(bs) } else { sup.push(bs); if g.contains(&best) { ok += 1 } }
        log.push(format!("  {:>5} top={best} {:.3} {}  {q}", if g.is_empty() { "unsup" } else if g.contains(&best) { "ok" } else { "MISS" }, bs, ""));
    }
    (ok, sup, uns, log)
}

fn run(name: &str, path: &str, doc_pre: &dyn Fn(&str) -> String, q_pre: &dyn Fn(&str) -> String) {
    let t = Instant::now();
    let mut m = Llama::load(path.as_ref(), 2048, Device::Gpu).unwrap();
    let load = t.elapsed();
    let mut ms = vec![];
    let emb = |m: &mut Llama, ms: &mut Vec<f64>, texts: &[String]| -> Vec<Vec<f32>> {
        texts.iter().map(|x| { let t = Instant::now(); let v = m.embed(&[x]).unwrap().pop().unwrap(); ms.push(t.elapsed().as_secs_f64() * 1000.0); v }).collect()
    };
    let _warm = emb(&mut m, &mut ms, &["warm up".to_string()]);
    ms.clear();
    let dv = emb(&mut m, &mut ms, &CHUNKS.iter().map(|c| doc_pre(c)).collect::<Vec<_>>());
    let nv = emb(&mut m, &mut ms, &NOTES.iter().map(|c| doc_pre(c)).collect::<Vec<_>>());
    let qv = emb(&mut m, &mut ms, &OPEN.iter().map(|(q, _)| q_pre(q)).collect::<Vec<_>>());
    ms.sort_by(|a, b| a.total_cmp(b));
    let dim = dv[0].len();
    println!("\n=== {name}: dim {dim}, load {:.0} ms, embed median {:.1} ms (min {:.1}, max {:.1}, n={})", load.as_secs_f64() * 1000.0, ms[ms.len() / 2], ms[0], ms[ms.len() - 1], ms.len());
    for d in [dim, 256] {
        let (ok, mut sup, mut uns, log) = score(&qv, &dv, |g| g.to_vec(), d);
        if d == dim { for l in &log { println!("{l}") } }
        // whole-note chunks (what the app does today: one chunk per short note): chunk id -> note id
        let note_of = |c: usize| [0, 0, 1, 1, 1, 2, 2, 2][c];
        let (ok3, sup3, uns3, _) = score(&qv, &nv, |g| { let mut n: Vec<usize> = g.iter().map(|&c| note_of(c)).collect(); n.dedup(); n }, d);
        if d == dim {
            let sw: Vec<String> = (50..=90).step_by(5).map(|f| { let f = f as f32 / 100.0; format!("{f:.2}: keep {}/8 leak {}/7", sup.iter().filter(|&&x| x >= f).count(), uns.iter().filter(|&&x| x >= f).count()) }).collect();
            println!("floor sweep (8 chunks, {d}d): {}", sw.join(" | "));
        }
        let (smin, umax) = (sup.iter().cloned().fold(f32::MAX, f32::min), uns.iter().cloned().fold(f32::MIN, f32::max));
        let (s3min, u3max) = (sup3.iter().cloned().fold(f32::MAX, f32::min), uns3.iter().cloned().fold(f32::MIN, f32::max));
        println!("[{d}d] 8 chunks: top1 {ok}/8; supported best min {smin:.3} med {:.3}; unsupported best max {umax:.3} med {:.3}; margin(min sup - max uns) {:+.3}", med(&mut sup), med(&mut uns), smin - umax);
        println!("[{d}d] 3 notes : top1 {ok3}/8; supported best min {s3min:.3}; unsupported best max {u3max:.3}; margin {:+.3}", s3min - u3max);
    }
}

fn main() {
    let (nomic, eg2) = (std::env::args().nth(1).expect("nomic.gguf"), std::env::args().nth(2).expect("embeddinggemma-2.gguf"));
    let only = std::env::args().nth(3).unwrap_or_default();
    if only != "eg2" { run("nomic-embed-text-v1.5 Q4_K_M", &nomic, &|d| format!("search_document: {d}"), &|q| format!("search_query: {q}")); }
    if only != "nomic" { run("EmbeddingGemma-2 Q8_0", &eg2, &|d| format!("title: none | text: {d}"), &|q| format!("task: search result | query: {q}")); }
}
