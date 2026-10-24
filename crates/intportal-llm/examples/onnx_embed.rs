//! SPIKE (#157 route B), not for main. Retrieval over the `eval open` notes and
//! questions with either nomic (GGUF, the app's path) or EmbeddingGemma-2 ONNX.
//!   onnx_embed nomic <nomic.gguf>
//!   onnx_embed onnx <model-dir> <q4|q4f16|quantized> <cpu|coreml> [threads]
use intportal_ai::{llm::Llm, rag::chunk_text};
use intportal_llm::{Device, Llama};
use ort::{ep, session::Session, value::Tensor};
use std::time::Instant;
use tokenizers::Tokenizer;

const NOTES: [&str; 3] = [
    "Inorder traversal: visit the left subtree, then the node, then the right subtree. On a BST it visits keys in sorted order.",
    "Math 101: passing is 75%. Prof. Reyes moved the quiz to Monday; it covers limits and derivatives.",
    "Finals plan (3 days): 25-minute Pomodoro blocks, review past quizzes first, sleep before the exam.",
];
// (question, supporting note index or none)
const OPEN: [(&str, Option<usize>); 15] = [
    ("ano ang inorder traversal?", Some(0)),
    ("Paano ba mag-visit ng BST in order?", Some(0)),
    ("What does inorder traversal give on a BST?", Some(0)),
    ("Kailan ang quiz sa Math 101?", Some(1)),
    ("Ano ang passing sa Math 101?", Some(1)),
    ("Anong topics ang kasama sa Math quiz?", Some(1)),
    ("pano mag-study para sa finals?", Some(2)),
    ("Gaano katagal ang isang study block ko?", Some(2)),
    ("Okay lang ba ako sa Math?", None),
    ("Ano ang grade ko sa Physics?", None),
    ("Anong oras ang klase ko bukas?", None),
    ("Ano ang preorder traversal?", None),
    ("Kailan ang deadline ng thesis proposal?", None),
    ("Sino ang president ng PUP ngayon?", None),
    ("Magkano ang tuition sa susunod na sem?", None),
];

struct Onnx {
    session: Session,
    tok: Tokenizer,
    inputs: Vec<String>,
    dummy: bool, // CoreML EP rejects zero-row inputs, so feed one unused row
}

impl Onnx {
    fn embed1(&mut self, text: &str) -> Result<Vec<f32>, String> {
        let enc = self.tok.encode(text, true).map_err(|e| e.to_string())?;
        let ids: Vec<i64> = enc.get_ids().iter().map(|&i| i as i64).collect();
        let n = ids.len();
        let mut inputs: Vec<(String, ort::session::SessionInputValue<'_>)> = vec![];
        for name in &self.inputs {
            if name.ends_with("_features") {
                // text only: no image/video/audio tokens, so a [0, 512] tensor
                inputs.push((name.clone(), Tensor::from_array(if self.dummy { ([1usize, 512], vec![0f32; 512]) } else { ([0usize, 512], vec![]) }).map_err(|e| e.to_string())?.into()));
                continue;
            }
            let data: Vec<i64> = match name.as_str() {
                "input_ids" => ids.clone(),
                "attention_mask" => vec![1; n],
                "position_ids" => (0..n as i64).collect(),
                other => return Err(format!("unknown model input {other}")),
            };
            inputs.push((name.clone(), Tensor::from_array(([1usize, n], data)).map_err(|e| e.to_string())?.into()));
        }
        let out = self.session.run(inputs).map_err(|e| e.to_string())?;
        let v = &out["sentence_embedding"];
        let flat: Vec<f32> = match v.try_extract_tensor::<f32>() {
            Ok((_, d)) => d.to_vec(),
            Err(_) => v.try_extract_tensor::<half::f16>().map_err(|e| e.to_string())?.1.iter().map(|x| x.to_f32()).collect(),
        };
        if flat.iter().any(|x| !x.is_finite()) {
            return Err("NaN/inf in output".into());
        }
        let norm = flat.iter().map(|x| x * x).sum::<f32>().sqrt().max(f32::EPSILON);
        Ok(flat.iter().map(|x| x / norm).collect())
    }
}

impl Llm for Onnx {
    fn generate(&mut self, _: &str, _: Option<&serde_json::Value>, _: u32, _: &mut dyn FnMut(&str) -> bool) -> Result<String, String> {
        Err("embed only".into())
    }
    fn embed(&mut self, texts: &[&str]) -> Result<Vec<Vec<f32>>, String> {
        texts.iter().map(|t| self.embed1(t)).collect()
    }
}

fn main() {
    let a: Vec<String> = std::env::args().collect();
    let t = Instant::now();
    let (mut m, name, doc_p, q_p): (Box<dyn Llm>, String, &str, &str) = match a[1].as_str() {
        "nomic" => (Box::new(Llama::load(a[2].as_ref(), 2048, if a.get(3).is_some() { Device::Cpu } else { Device::Gpu }).unwrap()), format!("nomic-{}", if a.get(3).is_some() { "cpu" } else { "metal" }), "search_document: ", "search_query: "),
        "onnx" => {
            let dir = std::path::Path::new(&a[2]);
            let (variant, epn) = (a[3].as_str(), a[4].as_str());
            let env = ort::environment::init().build().unwrap();
            let mut b = Session::builder(&env).unwrap();
            if let Some(th) = a.get(5) {
                b = b.with_intra_threads(th.parse().unwrap()).unwrap();
            }
            if epn == "coreml" || epn == "coreml-ml" {
                let mut c = ep::CoreML::default();
                if epn == "coreml-ml" {
                    c = c.with_model_format(ep::coreml::ModelFormat::MLProgram);
                }
                b = b.with_execution_providers([c.build()]).unwrap();
            } else {
                b = b.with_auto_device(ort::session::builder::AutoDevicePolicy::PreferCPU).unwrap();
            }
            let session = b.commit_from_file(dir.join(format!("onnx/model_{variant}.onnx"))).unwrap();
            let inputs: Vec<String> = session.inputs().iter().map(|i| i.name().to_string()).collect();
            eprintln!("inputs {:?}", session.inputs().iter().map(|i| format!("{} {:?}", i.name(), i.dtype())).collect::<Vec<_>>());
            eprintln!("outputs {:?}", session.outputs().iter().map(|i| format!("{} {:?}", i.name(), i.dtype())).collect::<Vec<_>>());
            let tok = Tokenizer::from_file(dir.join("tokenizer.json")).unwrap();
            let t2 = tok.encode("title: none | text: hello", true).unwrap();
            eprintln!("sample ids {:?}", t2.get_ids());
            (Box::new(Onnx { session, tok, inputs, dummy: epn.starts_with("coreml") }), format!("eg2-{variant}-{epn}"), "title: none | text: ", "task: search result | query: ")
        }
        _ => panic!("nomic|onnx"),
    };
    println!("load {:.2}s", t.elapsed().as_secs_f64());

    if std::env::var("README").is_ok() {
        // the model card's own example: expected Mars 0.854, Saturn 0.783, Jupiter 0.752, Venus 0.684
        let q = m.embed(&["task: search result | query: Which planet is known as the Red Planet?"]).unwrap().pop().unwrap();
        for d in ["Venus is often called Earth's twin because of its similar size and proximity.", "Mars, known for its reddish appearance, is often referred to as the Red Planet.", "Jupiter, the largest planet in our solar system, has a prominent red spot.", "Saturn, famous for its rings, is sometimes mistaken for the Red Planet."] {
            let v = m.embed(&[&format!("title: none | text: {d}")]).unwrap().pop().unwrap();
            println!("README {:.3} {}", q.iter().zip(&v).map(|(a, b)| a * b).sum::<f32>(), &d[..20]);
        }
    }
    let mut texts = vec![];
    let mut owner = vec![];
    for (i, n) in NOTES.iter().enumerate() {
        for c in chunk_text(n) {
            texts.push(format!("{doc_p}{c}"));
            owner.push(i);
        }
    }
    let docs = m.embed(&texts.iter().map(String::as_str).collect::<Vec<_>>()).unwrap();
    println!("dim {}", docs[0].len());
    if let Ok(p) = std::env::var("DUMP") {
        std::fs::write(p, docs.iter().flatten().flat_map(|x| x.to_le_bytes()).collect::<Vec<u8>>()).unwrap();
    }
    let (mut ok, mut n_sup) = (0, 0);
    let (mut sup, mut uns) = (vec![], vec![]);
    for (q, want) in OPEN {
        let qv = m.embed(&[&format!("{q_p}{q}")]).unwrap().pop().unwrap();
        let sc: Vec<f32> = docs.iter().map(|d| d.iter().zip(&qv).map(|(a, b)| a * b).sum()).collect();
        let (bi, bs) = sc.iter().enumerate().max_by(|x, y| x.1.total_cmp(y.1)).map(|(i, s)| (i, *s)).unwrap();
        let note = owner[bi];
        match want {
            Some(w) => {
                n_sup += 1;
                ok += (note == w) as usize;
                sup.push(bs);
            }
            None => uns.push(bs),
        }
        println!("{} best {bs:.3} note {note} (want {want:?}) {q}", if want.is_none() { "unsup" } else if want == Some(note) { "ok   " } else { "WRONG" });
    }
    let (smin, umax) = (sup.iter().cloned().fold(f32::MAX, f32::min), uns.iter().cloned().fold(f32::MIN, f32::max));
    let mean = |v: &Vec<f32>| v.iter().sum::<f32>() / v.len() as f32;
    let pairs = sup.iter().map(|s| uns.iter().filter(|u| s > u).count()).sum::<usize>();
    println!("pairs supported>unsupported {pairs}/{}", sup.len() * uns.len());
    println!("RESULT {name}: top1 {ok}/{n_sup}; supported best min {smin:.3} mean {:.3}; unsupported best max {umax:.3} mean {:.3}; margin(min sup - max unsup) {:.3}", mean(&sup), mean(&uns), smin - umax);

    // ms per embed: single texts, 3 rounds over docs+questions after one warm-up
    let all: Vec<String> = texts.iter().cloned().chain(OPEN.iter().map(|(q, _)| format!("{q_p}{q}"))).collect();
    m.embed(&[&all[0]]).unwrap();
    let t = Instant::now();
    for _ in 0..3 {
        for s in &all {
            m.embed(&[s.as_str()]).unwrap();
        }
    }
    println!("TIMING {name}: {:.1} ms/embed (batch 1, {} texts x3)", t.elapsed().as_secs_f64() * 1000.0 / (3 * all.len()) as f64, all.len());
}
