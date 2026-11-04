//! Search over the student's notes, deck cards and syllabus text: 700-char chunks, brute-force cosine
//! (vectors are unit length, so a dot product), a 0.5 floor and a 4000-char
//! budget, as the old macOS app tuned them.
use crate::llm::Llm;
use intportal_core::store::{Source, Store, StoreError};
use std::sync::{Mutex, MutexGuard, PoisonError};

pub const CHUNK: usize = 700;
// Tuned on EmbeddingGemma-2 with crates/intportal-llm/examples/embed_eval.rs (58 questions a note
// answers, 32 that nothing answers, over 32 notes). 0.72 keeps 74% of the first and lets 6% of
// the second through (0.5, nomic's old value, let all of them through). The best balanced floor
// is 0.71, but one question sits between 0.710 and 0.712 and 0.72 starts the plateau where false
// accepts stop falling, with fewer answers invented from a near-miss note. A floor only drops the
// clearly unrelated: "ano ang pokus ng pandiwa" scores 0.82 because a note names the topic, so
// the prompt must still say "I don't know". Scores shift with the embedder: change the model,
// rerun embed_eval, change this.
pub const FLOOR: f32 = 0.72;
/// A chunk this close under `FLOOR` is a near hit. Recall at the floor is 74%, and "how long is my study block"
/// scored 0.70 against a note about 25-minute blocks: it keeps a question about the notes in scope and the
/// model sees the chunk, but it is not counted as a clear match. 0.03 is the width of the cliff in the sweep.
pub const NEAR: f32 = 0.03;
pub const BUDGET: usize = 4000;

/// What `notes::heading` calls a note with no title. It says nothing about the note, so it is "none".
const UNTITLED: &str = "Untitled note";

/// EmbeddingGemma-2 wants a task prefix on every text. A note chunk is a
/// document, titled with its source's heading ("none" when it has none).
pub fn doc_text(title: &str, chunk: &str) -> String {
    let title = title.lines().next().unwrap_or("").trim();
    format!("title: {} | text: {chunk}", if title.is_empty() || title == UNTITLED { "none" } else { title })
}

/// The student's question as a search query.
pub fn query_text(q: &str) -> String {
    format!("task: search result | query: {q}")
}

#[derive(Debug, PartialEq)]
pub struct Hit {
    pub key: String,
    pub text: String,
    pub score: f32,
}

#[derive(Debug, thiserror::Error)]
pub enum RagError {
    #[error(transparent)]
    Store(#[from] StoreError),
    #[error("embedding failed: {0}")]
    Embed(String),
}

/// Splits on blank lines, then packs paragraphs up to `CHUNK` chars; a
/// paragraph longer than that is cut at the last space before the limit.
pub fn chunk_text(text: &str) -> Vec<String> {
    let mut out: Vec<String> = vec![];
    let mut cur = String::new();
    for para in text.split("\n\n").map(str::trim).filter(|p| !p.is_empty()) {
        let mut rest = para;
        while rest.chars().count() > CHUNK {
            let cut = rest.char_indices().nth(CHUNK).map_or(rest.len(), |(i, _)| i);
            let at = rest[..cut].rfind(' ').filter(|&i| i > 0).unwrap_or(cut);
            if !cur.is_empty() {
                out.push(std::mem::take(&mut cur));
            }
            out.push(rest[..at].trim().to_string());
            rest = rest[at..].trim_start();
        }
        if cur.chars().count() + rest.chars().count() + 2 > CHUNK && !cur.is_empty() {
            out.push(std::mem::take(&mut cur));
        }
        if !cur.is_empty() {
            cur.push_str("\n\n");
        }
        cur.push_str(rest);
    }
    if !cur.is_empty() {
        out.push(cur);
    }
    out
}

/// The store is shared with every other command, so it is locked for one
/// query at a time and never while a model runs.
fn db(store: &Mutex<Store>) -> MutexGuard<'_, Store> {
    store.lock().unwrap_or_else(PoisonError::into_inner)
}

/// Embeds the sources (notes, a deck's cards, a subject's syllabus) changed
/// since their last chunks, or chunked by another model, and drops chunks
/// whose source is gone. A source the model cannot embed is skipped, so one
/// odd one never stops the rest from being found.
pub fn refresh(store: &Mutex<Store>, llm: &mut dyn Llm, model: &str) -> Result<(), RagError> {
    for src in pending(store, model)? {
        let texts = chunk_text(&src.text);
        let docs: Vec<String> = texts.iter().map(|t| doc_text(&src.title, t)).collect();
        let rows = embed_all(llm, texts, &docs);
        if rows.is_empty() {
            continue; // nothing embedded: stays stale and is tried again
        }
        db(store).replace_chunks(&src.key, src.stamp, model, &rows)?;
    }
    Ok(())
}

/// The sources `refresh` would embed: changed since their last chunks, or chunked by another model, and
/// with something to embed (a blank note stays "stale" in the store forever and must not count). Also
/// drops chunks whose source is gone. The caller asks this before loading the embedder, so a pass with
/// nothing to do never wakes the model.
pub fn pending(store: &Mutex<Store>, model: &str) -> Result<Vec<Source>, RagError> {
    let s = db(store);
    s.prune_chunks()?;
    Ok(s.stale_sources(model)?.into_iter().filter(|src| !chunk_text(&src.text).is_empty()).collect())
}

/// One call for the whole source (one model context). If it fails, each chunk is tried alone, so a
/// chunk the model refuses costs only itself and the source is no longer retried on every question.
fn embed_all(llm: &mut dyn Llm, texts: Vec<String>, docs: &[String]) -> Vec<(String, Vec<f32>)> {
    if let Ok(vecs) = llm.embed(&docs.iter().map(String::as_str).collect::<Vec<_>>()) {
        return texts.into_iter().zip(vecs).collect();
    }
    texts
        .into_iter()
        .zip(docs)
        .filter_map(|(t, d)| Some((t, llm.embed(&[d.as_str()]).ok()?.pop()?)))
        .collect()
}

/// Best chunks for `query` (best first): at least `FLOOR`, at most `k`, and
/// within `BUDGET` chars together. Refreshes stale sources first.
pub fn search(store: &Mutex<Store>, llm: &mut dyn Llm, model: &str, query: &str, k: usize) -> Result<Vec<Hit>, RagError> {
    search_from(store, llm, model, query, k, FLOOR)
}

/// Like `search` with another floor; `FLOOR - NEAR` also returns the near hits (their `score` tells them apart).
pub fn search_from(store: &Mutex<Store>, llm: &mut dyn Llm, model: &str, query: &str, k: usize, floor: f32) -> Result<Vec<Hit>, RagError> {
    refresh(store, llm, model)?;
    let q = llm.embed(&[&query_text(query)]).map_err(RagError::Embed)?.pop().unwrap_or_default();
    let mut hits: Vec<Hit> = db(store)
        .chunks(model)?
        .into_iter()
        .map(|(key, text, v)| Hit { score: q.iter().zip(&v).map(|(a, b)| a * b).sum(), key, text })
        .filter(|h| h.score >= floor)
        .collect();
    hits.sort_by(|a, b| b.score.total_cmp(&a.score));
    let mut used = 0;
    hits.retain(|h| {
        used += h.text.chars().count();
        used <= BUDGET
    });
    hits.truncate(k);
    Ok(hits)
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Embeds by topic words: dim 0 = "tree", dim 1 = "tuition".
    struct Topics(Vec<String>);
    impl Llm for Topics {
        fn generate(&mut self, _: &str, _: Option<&serde_json::Value>, _: u32, _: &mut dyn FnMut(&str) -> bool) -> Result<String, String> {
            Err("unused".into())
        }
        fn embed(&mut self, texts: &[&str]) -> Result<Vec<Vec<f32>>, String> {
            self.0.extend(texts.iter().map(|t| t.to_string()));
            Ok(texts.iter().map(|t| {
                let v = [t.matches("tree").count() as f32, t.matches("tuition").count() as f32];
                let n = (v[0] * v[0] + v[1] * v[1]).sqrt();
                if n == 0.0 { v.to_vec() } else { v.iter().map(|x| x / n).collect() }
            }).collect())
        }
    }

    #[test]
    fn chunks_pack_paragraphs_and_cut_long_ones() {
        assert_eq!(chunk_text("one\n\ntwo\n\n\n\nthree"), ["one\n\ntwo\n\nthree"]);
        let long = format!("{} {}", "a".repeat(600), "b".repeat(600));
        let c = chunk_text(&long);
        assert_eq!(c, ["a".repeat(600), "b".repeat(600)]);
        assert!(chunk_text("   ").is_empty());
        let ñ = "ñ".repeat(1500); // no space to cut at: cut on a char boundary, never mid-character
        assert!(chunk_text(&ñ).iter().all(|c| c.chars().count() <= CHUNK));
    }

    #[test]
    fn search_finds_the_matching_note_with_prefixes_and_embeds_once() {
        let store = Mutex::new(Store::in_memory().unwrap());
        db(&store).set_note("note:a", "binary tree traversal, tree height", None, 1).unwrap();
        db(&store).set_note("note:b", "tuition due Monday", Some("Cashier"), 1).unwrap();
        let mut llm = Topics(vec![]);
        let hits = search(&store, &mut llm, "m", "tree", 3).unwrap();
        assert_eq!(hits.iter().map(|h| h.key.as_str()).collect::<Vec<_>>(), ["note:a"]);
        assert!(llm.0.contains(&"task: search result | query: tree".to_string()));
        assert!(llm.0.contains(&"title: Cashier | text: tuition due Monday".to_string()), "{:?}", llm.0);
        let embedded = llm.0.len();
        search(&store, &mut llm, "m", "tuition", 3).unwrap();
        assert_eq!(llm.0.len(), embedded + 1, "only the query is embedded the second time");
    }

    #[test]
    fn a_lower_floor_also_returns_the_near_hits_with_their_scores() {
        let store = Mutex::new(Store::in_memory().unwrap());
        db(&store).set_note("note:a", "binary tree", None, 1).unwrap();
        db(&store).set_note("note:b", "tuition due Monday", None, 1).unwrap();
        let mut llm = Topics(vec![]);
        assert_eq!(keys(&search(&store, &mut llm, "m", "tree", 4).unwrap()), ["note:a"], "the floor drops the unrelated note");
        let wide = search_from(&store, &mut llm, "m", "tree", 4, FLOOR - NEAR - 1.0).unwrap();
        assert_eq!(keys(&wide), ["note:a", "note:b"]);
        assert!(wide[0].score >= FLOOR && wide[1].score < FLOOR - NEAR, "the score tells a clear hit from a near one");
    }

    #[test]
    fn prefixes_follow_embeddinggemma_2() {
        assert_eq!(doc_text("Math 101", "limits"), "title: Math 101 | text: limits");
        assert_eq!(doc_text("  ", "limits"), "title: none | text: limits");
        assert_eq!(doc_text("Untitled note", "limits"), "title: none | text: limits");
        assert_eq!(doc_text("Line one\nline two", "x"), "title: Line one | text: x", "a title is one line");
        assert_eq!(query_text("kailan ang quiz?"), "task: search result | query: kailan ang quiz?");
    }

    #[test]
    fn switching_the_embedder_makes_every_source_stale_and_replaces_the_old_rows() {
        let store = Mutex::new(Store::in_memory().unwrap());
        db(&store).set_note("note:a", "binary tree", None, 1).unwrap();
        db(&store).save_deck(&deck("d1", &[("tuition", "paid in June")])).unwrap();
        syllabus(&store, "tree basics");
        let mut llm = Topics(vec![]);
        search(&store, &mut llm, "nomic-embed-v1.5", "tree", 4).unwrap();
        assert_eq!(db(&store).chunks("nomic-embed-v1.5").unwrap().len(), 3);
        assert_eq!(db(&store).stale_sources("embeddinggemma-2").unwrap().len(), 3, "old vectors are not reusable");

        let embedded = llm.0.len();
        let hits = search(&store, &mut llm, "embeddinggemma-2", "tree", 4).unwrap();
        assert_eq!(llm.0.len(), embedded + 3 + 1, "three sources re-embedded, then the query");
        assert_eq!(keys(&hits), ["note:a", "plan:COMP 1"]);
        assert!(db(&store).chunks("nomic-embed-v1.5").unwrap().is_empty(), "the old rows are replaced, not kept beside the new");
        assert_eq!(db(&store).chunks("embeddinggemma-2").unwrap().len(), 3);
        assert!(db(&store).stale_sources("embeddinggemma-2").unwrap().is_empty());
    }

    #[test]
    fn budget_and_k_limit_the_hits() {
        let store = Mutex::new(Store::in_memory().unwrap());
        for i in 0..6 {
            db(&store).set_note(&format!("note:{i}"), &format!("tree {}", "x".repeat(690)), None, 1).unwrap(); // 695 chars each
        }
        let mut llm = Topics(vec![]);
        assert_eq!(search(&store, &mut llm, "m", "tree", 10).unwrap().len(), 5, "6 x 695 > 4000, so the sixth is dropped");
        assert_eq!(search(&store, &mut llm, "m", "tree", 3).unwrap().len(), 3);
    }

    /// Fails on any text with "bad" in it.
    struct Picky;
    impl Llm for Picky {
        fn generate(&mut self, _: &str, _: Option<&serde_json::Value>, _: u32, _: &mut dyn FnMut(&str) -> bool) -> Result<String, String> {
            Err("unused".into())
        }
        fn embed(&mut self, texts: &[&str]) -> Result<Vec<Vec<f32>>, String> {
            if texts.iter().any(|t| t.contains("bad")) { return Err("too long".into()) }
            Ok(texts.iter().map(|t| vec![t.matches("tree").count().min(1) as f32]).collect())
        }
    }

    #[test]
    fn a_note_that_cannot_be_embedded_is_skipped_not_fatal() {
        let store = Mutex::new(Store::in_memory().unwrap());
        db(&store).set_note("note:a", "bad bad bad", None, 1).unwrap();
        db(&store).set_note("note:b", "tree", None, 1).unwrap();
        let hits = search(&store, &mut Picky, "m", "tree", 3).unwrap();
        assert_eq!(hits.iter().map(|h| h.key.as_str()).collect::<Vec<_>>(), ["note:b"]);
    }

    /// Counts embed calls and fails the test if the store is locked while the model runs.
    struct Counting<'a> {
        store: &'a Mutex<Store>,
        calls: usize,
        texts: usize,
    }
    impl Llm for Counting<'_> {
        fn generate(&mut self, _: &str, _: Option<&serde_json::Value>, _: u32, _: &mut dyn FnMut(&str) -> bool) -> Result<String, String> {
            Err("unused".into())
        }
        fn embed(&mut self, texts: &[&str]) -> Result<Vec<Vec<f32>>, String> {
            assert!(self.store.try_lock().is_ok(), "the store must be free while a model embeds");
            self.calls += 1;
            self.texts += texts.len();
            Ok(texts.iter().map(|_| vec![1.0]).collect())
        }
    }

    #[test]
    fn indexing_converges_embeds_one_call_per_source_and_holds_no_store_lock() {
        let store = Mutex::new(Store::in_memory().unwrap());
        db(&store).set_note("note:a", "binary tree", None, 1).unwrap();
        db(&store).set_note("note:b", "tuition due Monday", Some("Cashier"), 1).unwrap();
        db(&store).set_note("note:blank", "  \n\n ", None, 1).unwrap();
        db(&store).save_deck(&deck("d1", &[("tuition", "paid in June")])).unwrap();
        syllabus(&store, "tree basics");
        let mut llm = Counting { store: &store, calls: 0, texts: 0 };
        refresh(&store, &mut llm, "m").unwrap();
        assert_eq!((llm.calls, llm.texts), (4, 4), "note a, note b, the deck and the plan; the blank note costs no call");
        refresh(&store, &mut llm, "m").unwrap();
        refresh(&store, &mut llm, "m").unwrap();
        assert_eq!(llm.calls, 4, "the second and third pass are no-ops");
        assert!(pending(&store, "m").unwrap().is_empty(), "the blank note stays stale in the store but is not pending, so nothing wakes the model");
    }

    #[test]
    fn a_chunk_the_model_refuses_does_not_cost_the_rest_of_its_source() {
        let store = Mutex::new(Store::in_memory().unwrap());
        let text = format!("tree {}\n\nbad {}", "a".repeat(650), "b".repeat(650));
        db(&store).set_note("note:a", &text, None, 1).unwrap();
        assert_eq!(chunk_text(&text).len(), 2);
        let hits = search(&store, &mut Picky, "m", "tree", 3).unwrap();
        assert_eq!(keys(&hits), ["note:a"], "the good chunk is found");
        assert_eq!(db(&store).chunks("m").unwrap().len(), 1);
        assert!(db(&store).stale_sources("m").unwrap().is_empty(), "so the source is not re-embedded on every question");
    }

    fn deck(id: &str, cards: &[(&str, &str)]) -> intportal_core::study::Deck {
        use intportal_core::study::{Card, Deck, Memory};
        let cards = cards.iter().map(|(f, b)| Card { id: String::new(), front: f.to_string(), back: b.to_string(), accepted: vec![], memory: Memory::new(0) }).collect();
        Deck { id: id.into(), name: "DSA".into(), subject: None, cards }
    }

    fn syllabus(store: &Mutex<Store>, topic: &str) {
        use intportal_core::syllabus::{Item, Kind, Plan};
        let plan = Plan { items: vec![Item { id: "1".into(), topic: topic.into(), kind: Kind::Lecture, week: Some(2), date: None, done: false }], ..Default::default() };
        let mut snap = intportal_core::store::Snapshot::default();
        snap.syllabus.insert("COMP 1".into(), plan);
        db(store).save(&snap).unwrap();
    }

    fn keys(hits: &[Hit]) -> Vec<&str> {
        hits.iter().map(|h| h.key.as_str()).collect()
    }

    #[test]
    fn deck_cards_and_syllabus_reach_the_hits_and_follow_edits() {
        let store = Mutex::new(Store::in_memory().unwrap());
        db(&store).save_deck(&deck("d1", &[("tuition", "paid in June")])).unwrap();
        syllabus(&store, "tree basics");
        let mut llm = Topics(vec![]);
        let tree = search(&store, &mut llm, "m", "tree", 4).unwrap();
        assert_eq!(keys(&tree), ["plan:COMP 1"]);
        assert!(tree[0].text.contains("Week 2 · Lecture: tree basics"));
        let tuition = search(&store, &mut llm, "m", "tuition", 4).unwrap();
        assert_eq!(keys(&tuition), ["card:d1"]);
        assert!(tuition[0].text.contains("tuition: paid in June"));
        let embedded = llm.0.len();
        search(&store, &mut llm, "m", "tree", 4).unwrap();
        assert_eq!(llm.0.len(), embedded + 1, "nothing changed, so only the query is embedded");

        db(&store).save_deck(&deck("d1", &[("tuition", "paid in June"), ("tree", "a tree has a root")])).unwrap();
        assert_eq!(db(&store).stale_sources("m").unwrap().iter().map(|s| s.key.as_str()).collect::<Vec<_>>(), ["card:d1"]);
        let mut both = keys(&search(&store, &mut llm, "m", "tree", 4).unwrap()).into_iter().map(String::from).collect::<Vec<_>>();
        both.sort();
        assert_eq!(both, ["card:d1", "plan:COMP 1"]);
    }

    #[test]
    fn deleting_a_deck_or_wiping_clears_their_chunks() {
        let store = Mutex::new(Store::in_memory().unwrap());
        db(&store).save_deck(&deck("d1", &[("tree", "root")])).unwrap();
        syllabus(&store, "tree basics");
        let mut llm = Topics(vec![]);
        assert_eq!(search(&store, &mut llm, "m", "tree", 4).unwrap().len(), 2);
        db(&store).delete_deck("d1").unwrap();
        assert_eq!(keys(&search(&store, &mut llm, "m", "tree", 4).unwrap()), ["plan:COMP 1"]);
        db(&store).save(&intportal_core::store::Snapshot::default()).unwrap(); // the plan is cleared
        assert!(search(&store, &mut llm, "m", "tree", 4).unwrap().is_empty(), "refresh prunes chunks of a source that is gone");
        assert!(db(&store).chunks("m").unwrap().is_empty());
        syllabus(&store, "tree basics");
        search(&store, &mut llm, "m", "tree", 4).unwrap();
        db(&store).wipe().unwrap();
        assert!(db(&store).chunks("m").unwrap().is_empty() && search(&store, &mut llm, "m", "tree", 4).unwrap().is_empty());
    }

    #[test]
    fn a_deck_that_cannot_be_embedded_is_skipped_not_fatal() {
        let store = Mutex::new(Store::in_memory().unwrap());
        db(&store).save_deck(&deck("bad", &[("bad", "bad")])).unwrap();
        syllabus(&store, "tree basics");
        let hits = search(&store, &mut Picky, "m", "tree", 4).unwrap();
        assert_eq!(keys(&hits), ["plan:COMP 1"]);
        assert_eq!(db(&store).stale_sources("m").unwrap().len(), 1, "the failed deck is retried next time");
    }
}
