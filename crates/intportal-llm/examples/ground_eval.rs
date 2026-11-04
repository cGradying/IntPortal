//! Grounding eval: the 10 controls a note answers, the 12 near-misses (a topic next to a noted one)
//! and 6 more questions nothing answers, through `assis::answer` with the three seeded notes.
//! `cargo run --release -p intportal-llm --example ground_eval -- <chat.gguf> [cpu] [rag=<embeddinggemma-2.gguf>]`
//!
//! One tab-separated `ROW` per question: model, retrieval (`all3` = every note, `rag` = EmbeddingGemma-2
//! scores over `rag::FLOOR`, top 4), id, kind (k control, c near-miss, o other), model calls, whether
//! `ground::before_model` / `ground::after_model` would replace, the heuristic label of the raw reply
//! and of the final one, the question, the raw reply, the final reply. The model's reply before the
//! check is the raw one, so one greedy run gives both numbers. The counts in docs/ai.md come from reading.
use intportal_ai::{
    assis::{self, Facts},
    ground, intent, lang,
    llm::Llm,
    prompt::{Section, Template},
    rag, reply,
};
use intportal_llm::{Device, Llama};
use serde_json::Value;

const NOTES: [&str; 3] = [
    "Inorder traversal: visit the left subtree, then the node, then the right subtree. On a BST it visits keys in sorted order.",
    "Math 101: passing is 75%. Prof. Reyes moved the quiz to Monday; it covers limits and derivatives.",
    "Finals plan (3 days): 25-minute Pomodoro blocks, review past quizzes first, sleep before the exam.",
];

/// (id, kind, question, keywords of which one must appear in a control's answer)
const QS: [(&str, char, &str, &[&str]); 28] = [
    ("k1", 'k', "ano ang inorder traversal?", &["left", "right", "kaliwa", "kanan"]),
    ("k2", 'k', "Paano ba mag-visit ng BST in order?", &["sorted", "left", "inorder", "kaliwa"]),
    ("k3", 'k', "What does inorder traversal give on a BST?", &["sorted", "order"]),
    ("k4", 'k', "Kailan ang quiz sa Math 101?", &["monday", "lunes"]),
    ("k5", 'k', "Ano ang passing sa Math 101?", &["75"]),
    ("k6", 'k', "Anong topics ang kasama sa Math quiz?", &["limit", "derivative"]),
    ("k7", 'k', "pano mag-study para sa finals?", &["pomodoro", "25", "quiz", "sleep", "tulog"]),
    ("k8", 'k', "Gaano katagal ang isang study block ko?", &["25"]),
    ("k9", 'k', "What should I review first for finals?", &["quiz"]),
    ("k10", 'k', "What will the Math 101 test by Prof. Reyes cover?", &["limit", "derivative"]),
    ("c1", 'c', "Ano ang preorder traversal?", &[]),
    ("c2", 'c', "What is postorder traversal?", &[]),
    ("c3", 'c', "Ano ang height ng binary tree?", &[]),
    ("c4", 'c', "Paano mag-delete ng node sa BST?", &[]),
    ("c5", 'c', "What is the chain rule in derivatives?", &[]),
    ("c6", 'c', "Ano ang passing mark sa Physics 101?", &[]),
    ("c7", 'c', "Gaano katagal dapat ang Pomodoro break?", &[]),
    ("c8", 'c', "What topics are on the Math 101 finals?", &[]),
    ("c9", 'c', "What is the time complexity of inorder traversal?", &[]),
    ("c10", 'c', "What is Prof. Reyes's email address?", &[]),
    ("c11", 'c', "Ilang items ang quiz sa Math 101?", &[]),
    ("c12", 'c', "Give me practice problems on limits.", &[]),
    ("o1", 'o', "Okay lang ba ako sa Math?", &[]),
    ("o2", 'o', "Ano ang grade ko sa Physics?", &[]),
    ("o3", 'o', "Anong oras ang klase ko bukas?", &[]),
    ("o4", 'o', "Kailan ang deadline ng thesis proposal?", &[]),
    ("o5", 'o', "Sino ang president ng PUP ngayon?", &[]),
    ("o6", 'o', "Magkano ang tuition sa susunod na sem?", &[]),
];

const REFUSALS: [&str; 18] = ["wala ang", "nakikita ko lang", "hindi nakasulat", "sorry, i didn", "hindi ko alam", "wala akong", "walang", "don't know", "don't have", "don't see", "can't find", "only see", "lang ang nasa", "lang ang nakikita", "wala sa", "isn't in", "makita", "wala pa"];

struct Spy<'a>(&'a mut Llama, usize, String);
impl Llm for Spy<'_> {
    fn generate(&mut self, p: &str, s: Option<&Value>, n: u32, f: &mut dyn FnMut(&str) -> bool) -> Result<String, String> {
        self.1 += 1;
        let out = self.0.generate(p, s, n, f)?;
        self.2 = out.clone();
        Ok(out)
    }
    fn generate_prefilled(&mut self, p: &str, pre: &str, s: Option<&Value>, n: u32, f: &mut dyn FnMut(&str) -> bool) -> Result<String, String> {
        self.1 += 1;
        let out = self.0.generate_prefilled(p, pre, s, n, f)?;
        self.2 = out.clone();
        Ok(out)
    }
    fn embed(&mut self, t: &[&str]) -> Result<Vec<Vec<f32>>, String> {
        self.0.embed(t)
    }
}

/// Heuristic label, corrected by hand afterwards.
fn label(kind: char, want: &[&str], text: &str) -> &'static str {
    let low = text.to_lowercase();
    let refused = REFUSALS.iter().any(|r| low.contains(r));
    match (kind, refused) {
        ('k', true) => "FALSE_REFUSAL",
        ('k', false) => if want.iter().any(|k| low.contains(k)) { "ANSWERED" } else { "MISSED" },
        (_, true) => "REFUSED",
        _ => "INVENTED",
    }
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    let path = args.get(1).expect("model.gguf").clone();
    let device = if args.iter().any(|a| a == "cpu") { Device::Cpu } else { Device::Gpu };
    let mut m = Llama::load(path.as_ref(), 4096, device).unwrap();
    let mut embedder = args.iter().find_map(|a| a.strip_prefix("rag=")).map(|p| Llama::load(p.as_ref(), 1024, device).unwrap());
    let (tpl, name) = if path.contains("gemma") { (Template::Gemma, "gemma3-1b") } else { (Template::ChatMl, "qwen3-1.7b") };
    let cond = if embedder.is_some() { "rag" } else { "all3" };
    let docs: Vec<String> = NOTES.iter().map(|n| rag::doc_text("", n)).collect();
    let doc_vecs = embedder.as_mut().map(|e| e.embed(&docs.iter().map(String::as_str).collect::<Vec<_>>()).unwrap());
    for (id, kind, q, want) in QS {
        let hits: Vec<String> = match (&mut embedder, &doc_vecs) {
            (Some(e), Some(dv)) => {
                let qv = e.embed(&[&rag::query_text(q)]).unwrap().pop().unwrap();
                let mut sc: Vec<(f32, usize)> = dv.iter().enumerate().map(|(i, d)| (d.iter().zip(&qv).map(|(a, b)| a * b).sum(), i)).collect();
                sc.sort_by(|a, b| b.0.total_cmp(&a.0));
                sc.iter().filter(|(s, _)| *s >= rag::FLOOR).take(4).map(|(_, i)| NOTES[*i].to_string()).collect()
            }
            _ => NOTES.iter().map(|n| n.to_string()).collect(),
        };
        let facts = Facts {
            today: Some(intportal_core::today::Date::new(2026, 10, 15)),
            hits,
            subject_names: vec![("MATH 101".into(), "Mathematics".into())],
            ..Facts::default()
        };
        let mut spy = Spy(&mut m, 0, String::new());
        let t = std::time::Instant::now();
        let text = assis::answer(&mut spy, tpl, &facts, &[], q).map(|a| a.reply).unwrap_or_else(|e| format!("ERROR {e}"));
        let secs = t.elapsed().as_secs_f64();
        let calls = spy.1;
        let pre = ground::before_model(&facts, q).is_some();
        let mut raw = reply::parse::<Value>(&spy.2).ok().and_then(|v| v["reply"].as_str().map(String::from)).unwrap_or_default();
        if pre {
            // The check answered without the model; ask it anyway, to count what it would have invented.
            let body: String = facts.hits.iter().map(|h| format!("- {h}\n")).collect();
            let sections = [Section { title: "From the student's notes", body: &body, priority: 7 }];
            let schema = serde_json::json!({"type": "object", "properties": {"reply": {"type": "string", "maxLength": 600}}, "required": ["reply"]});
            let out = lang::open_reply(&mut m, tpl, lang::Plan::for_template(tpl), None, &sections, q, intent::is_filipino(q), &schema, &mut |_| ());
            raw = out.ok().and_then(|r| reply::parse::<Value>(&r).ok()).and_then(|v| v["reply"].as_str().map(String::from)).unwrap_or_default();
        }
        let post = !raw.is_empty() && ground::after_model(&facts, q, &raw).is_some();
        println!(
            "ROW\t{name}\t{cond}\t{id}\t{kind}\t{calls}\t{secs:.2}\t{}\t{}\t{}\t{}\t{q}\t{}\t{}",
            if pre { "PRE" } else { "-" },
            if post { "POST" } else { "-" },
            if calls == 0 && !pre { "rule".to_string() } else { label(kind, want, &raw).to_string() },
            label(kind, want, &text),
            raw.replace('\n', " / "),
            text.replace('\n', " / ")
        );
    }
}
