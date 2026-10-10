//! Search over the student's notes: 700-char chunks, brute-force cosine
//! (vectors are unit length, so a dot product), a 0.35 floor and a 4000-char
//! budget, as the old macOS app tuned them.
use crate::llm::Llm;
use intportal_core::store::{Store, StoreError};

pub const CHUNK: usize = 700;
pub const FLOOR: f32 = 0.35;
pub const BUDGET: usize = 4000;

#[derive(Debug, PartialEq)]
pub struct Hit {
    pub note_key: String,
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

/// Embeds the notes edited since their last chunks, or chunked by another model.
pub fn refresh(store: &Store, llm: &mut dyn Llm, model: &str) -> Result<(), RagError> {
    for note in store.stale_notes(model)? {
        let texts = chunk_text(&note.text);
        let docs: Vec<String> = texts.iter().map(|t| format!("search_document: {t}")).collect();
        let vecs = llm.embed(&docs.iter().map(String::as_str).collect::<Vec<_>>()).map_err(RagError::Embed)?;
        store.replace_chunks(&note.key, note.updated, model, &texts.into_iter().zip(vecs).collect::<Vec<_>>())?;
    }
    Ok(())
}

/// Best chunks for `query` (best first): at least `FLOOR`, at most `k`, and
/// within `BUDGET` chars together. Refreshes stale notes first.
pub fn search(store: &Store, llm: &mut dyn Llm, model: &str, query: &str, k: usize) -> Result<Vec<Hit>, RagError> {
    refresh(store, llm, model)?;
    let q = llm.embed(&[&format!("search_query: {query}")]).map_err(RagError::Embed)?.pop().unwrap_or_default();
    let mut hits: Vec<Hit> = store
        .chunks(model)?
        .into_iter()
        .map(|(note_key, text, v)| Hit { score: q.iter().zip(&v).map(|(a, b)| a * b).sum(), note_key, text })
        .filter(|h| h.score >= FLOOR)
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
        let store = Store::in_memory().unwrap();
        store.set_note("note:a", "binary tree traversal, tree height", None, 1).unwrap();
        store.set_note("note:b", "tuition due Monday", None, 1).unwrap();
        let mut llm = Topics(vec![]);
        let hits = search(&store, &mut llm, "m", "tree", 3).unwrap();
        assert_eq!(hits.iter().map(|h| h.note_key.as_str()).collect::<Vec<_>>(), ["note:a"]);
        assert!(llm.0.contains(&"search_query: tree".to_string()));
        assert!(llm.0.iter().any(|t| t.starts_with("search_document: tuition")));
        let embedded = llm.0.len();
        search(&store, &mut llm, "m", "tuition", 3).unwrap();
        assert_eq!(llm.0.len(), embedded + 1, "only the query is embedded the second time");
    }

    #[test]
    fn budget_and_k_limit_the_hits() {
        let store = Store::in_memory().unwrap();
        for i in 0..6 {
            store.set_note(&format!("note:{i}"), &format!("tree {}", "x".repeat(690)), None, 1).unwrap(); // 695 chars each
        }
        let mut llm = Topics(vec![]);
        assert_eq!(search(&store, &mut llm, "m", "tree", 10).unwrap().len(), 5, "6 x 695 > 4000, so the sixth is dropped");
        assert_eq!(search(&store, &mut llm, "m", "tree", 3).unwrap().len(), 3);
    }
}
