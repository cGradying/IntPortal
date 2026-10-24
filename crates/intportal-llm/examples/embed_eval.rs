//! THROWAWAY eval (issue #157): nomic v1.5 vs EmbeddingGemma-2 on a 90-question retrieval set.
//! `cargo run --release -p intportal-llm --example embed_eval -- <nomic.gguf> <embeddinggemma-2.gguf>`
//! Data: examples/data/notes.json (32 notes, chunked by rag::chunk_text exactly as the app does) and
//! examples/data/questions.json (58 in-scope with the one note id that answers, 8 each of out-of-scope
//! kinds a general knowledge, b student's own data, c on-topic but absent, d chit-chat/injection).
//! Every number printed here comes from the run; nothing is typed in by hand.
use intportal_ai::llm::Llm;
use intportal_ai::rag::chunk_text;
use intportal_llm::{Device, Llama};
use serde_json::Value;

const NOTES: &str = include_str!("data/notes.json");
const QUESTIONS: &str = include_str!("data/questions.json");
const KINDS: [&str; 5] = ["in", "a", "b", "c", "d"];

struct Row {
    kind: String,
    style: String,
    q: String,
    gold: String,
    ranked: Vec<(usize, f32)>, // note index, best chunk score, best first
}
impl Row {
    fn best(&self) -> f32 { self.ranked[0].1 }
    fn margin(&self) -> f32 { self.ranked[0].1 - self.ranked[1].1 }
}

fn dot(a: &[f32], b: &[f32]) -> f32 { a.iter().zip(b).map(|(x, y)| x * y).sum() }

fn run(path: &str, doc_pre: &str, q_pre: &str, notes: &[(String, String)], qs: &[Value]) -> (Vec<Row>, usize) {
    let mut m = Llama::load(path.as_ref(), 2048, Device::Gpu).unwrap();
    let mut emb = |t: String| m.embed(&[&t]).unwrap().pop().unwrap();
    emb("warm up".into());
    let mut chunks: Vec<(usize, Vec<f32>)> = vec![];
    for (ni, (_, text)) in notes.iter().enumerate() {
        for c in chunk_text(text) { chunks.push((ni, emb(format!("{doc_pre}{c}")))); }
    }
    let rows = qs.iter().map(|q| {
        let qv = emb(format!("{q_pre}{}", q["q"].as_str().unwrap()));
        let mut best = vec![f32::MIN; notes.len()];
        for (ni, v) in &chunks { best[*ni] = best[*ni].max(dot(&qv, v)); }
        let mut ranked: Vec<(usize, f32)> = best.into_iter().enumerate().collect();
        ranked.sort_by(|a, b| b.1.total_cmp(&a.1));
        Row {
            kind: q["kind"].as_str().unwrap().into(),
            style: q["style"].as_str().unwrap().into(),
            q: q["q"].as_str().unwrap().into(),
            gold: q["note"].as_str().unwrap_or("").into(),
            ranked,
        }
    }).collect();
    (rows, chunks.len())
}

fn med(v: &[f32]) -> f32 { let mut s = v.to_vec(); s.sort_by(|a, b| a.total_cmp(b)); s[s.len() / 2] }
fn mn(v: &[f32]) -> f32 { v.iter().cloned().fold(f32::MAX, f32::min) }
fn mx(v: &[f32]) -> f32 { v.iter().cloned().fold(f32::MIN, f32::max) }

/// P(in-scope scores higher than out-of-scope), ties count half.
fn auc(pos: &[f32], neg: &[f32]) -> f32 {
    let mut s = 0.0;
    for p in pos { for n in neg { s += if p > n { 1.0 } else if p == n { 0.5 } else { 0.0 } } }
    s / (pos.len() * neg.len()) as f32
}

/// (score, margin, is_in_scope)
type Pt = (f32, f32, bool);
fn ba(pts: &[Pt], f: f32, m: f32) -> f32 {
    let (np, nn) = (pts.iter().filter(|p| p.2).count() as f32, pts.iter().filter(|p| !p.2).count() as f32);
    let acc = |p: &&Pt| p.0 >= f && p.1 >= m;
    let tpr = pts.iter().filter(|p| p.2).filter(acc).count() as f32 / np;
    let fpr = pts.iter().filter(|p| !p.2).filter(acc).count() as f32 / nn;
    (tpr + 1.0 - fpr) / 2.0
}
/// Candidate floors: midpoints between consecutive distinct scores. Returns (floor, margin, balanced accuracy);
/// first (lowest) maximum wins ties on floor, then margin.
fn fit(pts: &[Pt], margins: &[f32]) -> (f32, f32, f32) {
    let mut s: Vec<f32> = pts.iter().map(|p| p.0).collect();
    s.sort_by(|a, b| a.total_cmp(b));
    s.dedup();
    let mut fs: Vec<f32> = s.windows(2).map(|w| (w[0] + w[1]) / 2.0).collect();
    fs.push(s[0] - 0.001);
    let mut best = (0.0, 0.0, -1.0);
    for &f in &fs { for &m in margins { let b = ba(pts, f, m); if b > best.2 + 1e-6 { best = (f, m, b) } } }
    best
}
/// 5-fold CV of fit(): pooled balanced accuracy on held-out folds (in-sample numbers are optimistic).
fn cv(pts: &[Pt], margins: &[f32]) -> f32 {
    let (mut tp, mut fp, mut np, mut nn) = (0.0, 0.0, 0.0, 0.0);
    for k in 0..5 {
        let tr: Vec<Pt> = pts.iter().enumerate().filter(|(i, _)| i % 5 != k).map(|(_, p)| *p).collect();
        let (f, m, _) = fit(&tr, margins);
        for p in pts.iter().enumerate().filter(|(i, _)| i % 5 == k).map(|(_, p)| p) {
            let acc = p.0 >= f && p.1 >= m;
            if p.2 { np += 1.0; if acc { tp += 1.0 } } else { nn += 1.0; if acc { fp += 1.0 } }
        }
    }
    (tp / np + 1.0 - fp / nn) / 2.0
}

fn report(name: &str, rows: &[Row], notes: &[(String, String)], nchunks: usize) -> (f32, f32) {
    println!("\n==================== {name}: {} notes -> {nchunks} chunks, {} questions ====================", notes.len(), rows.len());
    let inn: Vec<&Row> = rows.iter().filter(|r| r.kind == "in").collect();
    let top = |k: usize| inn.iter().filter(|r| r.ranked.iter().take(k).any(|(n, _)| notes[*n].0 == r.gold)).count();
    println!("in-scope top-1 {}/{}  top-3 {}/{}", top(1), inn.len(), top(3), inn.len());
    for st in ["en", "tl", "typo", "kw", "para"] {
        let g: Vec<&&Row> = inn.iter().filter(|r| r.style == st).collect();
        println!("  style {st:5} top-1 {}/{}", g.iter().filter(|r| notes[r.ranked[0].0].0 == r.gold).count(), g.len());
    }
    for r in inn.iter().filter(|r| notes[r.ranked[0].0].0 != r.gold) {
        println!("  MISS {:.3} got {:14} want {:14} | {}", r.best(), notes[r.ranked[0].0].0, r.gold, r.q);
    }
    println!("\nbest-hit score by kind        n    min   median    max     | margin(best-2nd note) min  median  max");
    for k in KINDS {
        let g: Vec<&Row> = rows.iter().filter(|r| r.kind == k).collect();
        let (s, m): (Vec<f32>, Vec<f32>) = g.iter().map(|r| (r.best(), r.margin())).unzip();
        println!("  {k:2} {:24} {:3}  {:.3}  {:.3}  {:.3}   |   {:.3}  {:.3}  {:.3}", match k { "in" => "in-scope", "a" => "OOS a general knowledge", "b" => "OOS b own data", "c" => "OOS c on-topic absent", _ => "OOS d chit-chat/injection" }, g.len(), mn(&s), med(&s), mx(&s), mn(&m), med(&m), mx(&m));
    }
    let pts: Vec<Pt> = rows.iter().map(|r| (r.best(), r.margin(), r.kind == "in")).collect();
    let pick = |f: fn(&Row) -> f32, kinds: &[&str], inscope: bool| -> Vec<f32> { rows.iter().filter(|r| (r.kind == "in") == inscope && (inscope || kinds.contains(&r.kind.as_str()))).map(f).collect() };
    let (pos, neg) = (pick(Row::best, &[], true), pick(Row::best, &["a", "b", "c", "d"], false));
    let a = auc(&pos, &neg);
    println!("\nAUC in-scope vs all OOS (best-hit score) = {a:.3};  per kind: {}", ["a", "b", "c", "d"].iter().map(|k| format!("{k} {:.3}", auc(&pos, &pick(Row::best, &[*k], false)))).collect::<Vec<_>>().join("  "));
    let (mpos, mneg) = (pick(Row::margin, &[], true), pick(Row::margin, &["a", "b", "c", "d"], false));
    println!("AUC of the margin alone (best minus 2nd note) = {:.3}", auc(&mpos, &mneg));

    println!("\nROC, rule: accept if best-hit >= floor. recall = in-scope accepted; ok = accepted AND top-1 right");
    println!("  floor  recall   ok   FA(all) |  FA a   FA b   FA c   FA d | balanced acc");
    let (lo, hi) = (mn(&rows.iter().map(Row::best).collect::<Vec<_>>()), mx(&rows.iter().map(Row::best).collect::<Vec<_>>()));
    let fa = |f: f32, k: &str| { let g: Vec<&Row> = rows.iter().filter(|r| r.kind == k).collect(); g.iter().filter(|r| r.best() >= f).count() as f32 / g.len() as f32 };
    let line = |f: f32| {
        let acc: Vec<&&Row> = inn.iter().filter(|r| r.best() >= f).collect();
        let ok = acc.iter().filter(|r| notes[r.ranked[0].0].0 == r.gold).count();
        let oos: Vec<&Row> = rows.iter().filter(|r| r.kind != "in").collect();
        let fall = oos.iter().filter(|r| r.best() >= f).count() as f32 / oos.len() as f32;
        println!("  {f:.3}  {:5.1}%  {:4.1}%  {:5.1}%  | {:4.0}%  {:4.0}%  {:4.0}%  {:4.0}% | {:.3}", 100.0 * acc.len() as f32 / inn.len() as f32, 100.0 * ok as f32 / inn.len() as f32, 100.0 * fall, 100.0 * fa(f, "a"), 100.0 * fa(f, "b"), 100.0 * fa(f, "c"), 100.0 * fa(f, "d"), ba(&pts, f, 0.0));
    };
    for i in 0..10 { line(lo + (hi - lo) * i as f32 / 9.0) }
    let (f, _, b) = fit(&pts, &[0.0]);
    println!("\nBEST single FLOOR (max balanced accuracy, in-sample) = {f:.3}  balanced acc {b:.3};  5-fold CV balanced acc {:.3}", cv(&pts, &[0.0]));
    line(f);
    // Recall at a fixed false-accept budget: the lowest floor whose FA stays within budget.
    let oos_best: Vec<f32> = rows.iter().filter(|r| r.kind != "in").map(Row::best).collect();
    for budget in [0.0f32, 0.05, 0.10, 0.20] {
        let mut cand: Vec<f32> = rows.iter().map(Row::best).collect();
        cand.sort_by(|a, b| a.total_cmp(b));
        let fl = cand.into_iter().find(|&c| oos_best.iter().filter(|&&s| s >= c).count() as f32 / oos_best.len() as f32 <= budget).unwrap();
        println!("  recall at false-accept <= {:>3.0}%: floor {fl:.3} -> recall {:.1}%, FA {:.1}%", budget * 100.0, 100.0 * inn.iter().filter(|r| r.best() >= fl).count() as f32 / inn.len() as f32, 100.0 * oos_best.iter().filter(|&&s| s >= fl).count() as f32 / oos_best.len() as f32);
    }
    println!("  (note: nomic's current rag::FLOOR is 0.5; for reference)");
    line(0.5);

    let margins: Vec<f32> = (0..=30).map(|i| i as f32 * 0.005).collect();
    let (f2, m2, b2) = fit(&pts, &margins);
    println!("\nRELATIVE rule, accept if best >= floor AND (best - 2nd note) >= margin; grid margin 0..0.15");
    println!("  best pair floor {f2:.3} margin {m2:.3}: balanced acc {b2:.3} in-sample (floor alone {b:.3}); 5-fold CV {:.3} (floor alone {:.3})", cv(&pts, &margins), cv(&pts, &[0.0]));
    let rec = inn.iter().filter(|r| r.best() >= f2 && r.margin() >= m2).count() as f32 / inn.len() as f32;
    let oos: Vec<&Row> = rows.iter().filter(|r| r.kind != "in").collect();
    println!("  at that pair: recall {:.1}%, false-accept {:.1}%", 100.0 * rec, 100.0 * oos.iter().filter(|r| r.best() >= f2 && r.margin() >= m2).count() as f32 / oos.len() as f32);

    println!("\nfive highest-scoring OOS questions (the false accepts that matter):");
    let mut o: Vec<&Row> = oos.clone();
    o.sort_by(|a, b| b.best().total_cmp(&a.best()));
    for r in o.iter().take(5) { println!("  {:.3} [{}] -> {:14} | {}", r.best(), r.kind, notes[r.ranked[0].0].0, r.q); }
    (a, f)
}

fn main() {
    let notes: Vec<(String, String)> = serde_json::from_str::<Vec<Value>>(NOTES).unwrap().iter().map(|n| (n["id"].as_str().unwrap().into(), n["text"].as_str().unwrap().into())).collect();
    let qs: Vec<Value> = serde_json::from_str(QUESTIONS).unwrap();
    assert!(qs.iter().filter(|q| q["kind"] == "in").all(|q| notes.iter().any(|n| n.0 == q["note"].as_str().unwrap())), "gold note id missing");
    let (nomic, eg2) = (std::env::args().nth(1).expect("nomic.gguf"), std::env::args().nth(2).expect("embeddinggemma-2.gguf"));
    let (rn, cn) = run(&nomic, "search_document: ", "search_query: ", &notes, &qs);
    let (re, ce) = run(&eg2, "title: none | text: ", "task: search result | query: ", &notes, &qs);
    let (an, fn_) = report("nomic-embed-text-v1.5 Q4_K_M", &rn, &notes, cn);
    let (ae, fe) = report("EmbeddingGemma-2 Q8_0", &re, &notes, ce);

    println!("\n==================== paired comparison ====================");
    let right = |rows: &[Row], i: usize| rows[i].kind == "in" && notes[rows[i].ranked[0].0].0 == rows[i].gold;
    let idx_in: Vec<usize> = (0..qs.len()).filter(|&i| rn[i].kind == "in").collect();
    let (only_n, only_e) = (idx_in.iter().filter(|&&i| right(&rn, i) && !right(&re, i)).count(), idx_in.iter().filter(|&&i| !right(&rn, i) && right(&re, i)).count());
    println!("top-1 discordant questions: only nomic right {only_n}, only EG2 right {only_e} (of {})", idx_in.len());
    println!("AUC nomic {an:.3}, EG2 {ae:.3}, diff (EG2 - nomic) {:+.3}", ae - an);
    let mut seed: u64 = 0x9E3779B97F4A7C15;
    let mut rnd = move |n: usize| { seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17; (seed % n as u64) as usize };
    let mut d: Vec<f32> = vec![];
    for _ in 0..2000 {
        let s: Vec<usize> = (0..qs.len()).map(|_| rnd(qs.len())).collect();
        let a = |rows: &[Row]| { let p: Vec<f32> = s.iter().filter(|&&i| rows[i].kind == "in").map(|&i| rows[i].best()).collect(); let n: Vec<f32> = s.iter().filter(|&&i| rows[i].kind != "in").map(|&i| rows[i].best()).collect(); auc(&p, &n) };
        d.push(a(&re) - a(&rn));
    }
    d.sort_by(|a, b| a.total_cmp(b));
    println!("bootstrap (2000 resamples of the questions, paired) AUC diff EG2 - nomic: median {:+.3}, 95% interval [{:+.3}, {:+.3}]", d[1000], d[50], d[1950]);
    println!("best floors: nomic {fn_:.3}, EG2 {fe:.3}");
}
