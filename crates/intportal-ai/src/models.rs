//! The models IntAssis can download. Never bundled (ADR 0003). Sizes and
//! SHA-256 come from the Hugging Face LFS metadata of each file.

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Kind {
    Chat,
    Embed,
}

#[derive(Debug, Clone, Copy)]
pub struct Model {
    pub id: &'static str,
    pub name: &'static str,
    pub kind: Kind,
    pub file: &'static str,
    pub url: &'static str,
    pub sha256: &'static str,
    pub bytes: u64,
    /// Context length the app runs it with.
    pub n_ctx: u32,
    /// Rough per-1000-token KV cache at q8_0, for the RAM gate.
    pub kv_bytes_per_1k: u64,
}

pub const CATALOG: [Model; 4] = [
    Model {
        id: "qwen3-0.6b",
        name: "Qwen3 0.6B",
        kind: Kind::Chat,
        file: "Qwen3-0.6B-Q4_K_M.gguf",
        url: "https://huggingface.co/unsloth/Qwen3-0.6B-GGUF/resolve/main/Qwen3-0.6B-Q4_K_M.gguf",
        sha256: "ac2d97712095a558e31573f62f466a3f9d93990898b0ec79d7c974c1780d524a",
        bytes: 396_705_472,
        n_ctx: 4096,
        kv_bytes_per_1k: 60_000_000,
    },
    Model {
        id: "gemma3-1b",
        name: "Gemma 3 1B",
        kind: Kind::Chat,
        file: "gemma-3-1b-it-Q4_K_M.gguf",
        url: "https://huggingface.co/unsloth/gemma-3-1b-it-GGUF/resolve/main/gemma-3-1b-it-Q4_K_M.gguf",
        sha256: "8270790f3ab69fdfe860b7b64008d9a19986d8df7e407bb018184caa08798ebd",
        bytes: 806_058_272,
        n_ctx: 4096,
        kv_bytes_per_1k: 25_000_000,
    },
    Model {
        id: "qwen3-1.7b",
        name: "Qwen3 1.7B",
        kind: Kind::Chat,
        file: "Qwen3-1.7B-Q4_K_M.gguf",
        url: "https://huggingface.co/unsloth/Qwen3-1.7B-GGUF/resolve/main/Qwen3-1.7B-Q4_K_M.gguf",
        sha256: "b139949c5bd74937ad8ed8c8cf3d9ffb1e99c866c823204dc42c0d91fa181897",
        bytes: 1_107_409_472,
        n_ctx: 4096,
        kv_bytes_per_1k: 115_000_000,
    },
    Model {
        id: "embeddinggemma-2",
        name: "EmbeddingGemma-2",
        kind: Kind::Embed,
        file: "embeddinggemma-2-Q8_0.gguf",
        url: "https://huggingface.co/ggml-org/embeddinggemma-2-GGUF/resolve/main/embeddinggemma-2-Q8_0.gguf",
        sha256: "2188ac1deca4b77dffefd603c2776a9d76d9d74ec01841392982ebb840b09135",
        bytes: 309_855_456,
        // Peak RSS of `/usr/bin/time -l embed <gguf> <n_ctx>` (Apple Silicon, Metal or CPU alike): 518,
        // 522 and 523 MB at n_ctx 512, 1024 and 2048, against 310 MB of weights. The context barely
        // matters (4 MB across 512 to 2048); the 210 MB on top is compute buffers and the 262k-token
        // vocabulary. Kept as a per-1k figure so `gate` sees weights plus that overhead at 1024.
        n_ctx: 1024,
        kv_bytes_per_1k: 200_000_000,
    },
];

/// Picked by the A2 eval: 20/20 valid JSON and the most natural Taglish of the three (see PR #87).
pub const DEFAULT_CHAT: &str = "gemma3-1b";
pub const EMBED: &str = "embeddinggemma-2";

/// The embedder before EmbeddingGemma-2 (nomic-embed-text v1.5, 84 MB). It is no
/// longer in the catalog; its file is deleted when the new embedder lands or the
/// student removes IntAssis, so nobody keeps 84 MB nothing reads.
pub const LEGACY_EMBED_FILES: [&str; 1] = ["nomic-embed-text-v1.5.Q4_K_M.gguf"];

pub fn find(id: &str) -> Option<&'static Model> {
    CATALOG.iter().find(|m| m.id == id)
}

#[derive(Debug, PartialEq, Eq)]
pub enum Gate {
    Ok,
    /// Fits, but over 60% of the memory the app may still use.
    Warn,
    /// Over 90%: loading would get the app killed.
    Refuse,
}

/// Compares what loading `m` needs (weights plus KV cache) with the memory
/// available to the app. `None` (unknown platform) is allowed through.
pub fn gate(m: &Model, available: Option<u64>) -> Gate {
    let Some(avail) = available else { return Gate::Ok };
    let need = m.bytes + m.kv_bytes_per_1k * u64::from(m.n_ctx) / 1000;
    match need * 100 / avail.max(1) {
        0..=60 => Gate::Ok,
        61..=90 => Gate::Warn,
        _ => Gate::Refuse,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ids_are_unique_and_hashes_look_like_sha256() {
        for (i, m) in CATALOG.iter().enumerate() {
            assert!(m.sha256.len() == 64 && m.sha256.bytes().all(|b| b.is_ascii_hexdigit()), "{}", m.id);
            assert!(m.url.ends_with(m.file), "{}", m.id);
            assert_eq!(find(m.id).unwrap().file, m.file);
            assert!(CATALOG[i + 1..].iter().all(|o| o.id != m.id));
        }
        assert!(find("nope").is_none());
        assert_eq!(find(DEFAULT_CHAT).unwrap().kind, Kind::Chat);
        assert_eq!(find(EMBED).unwrap().kind, Kind::Embed);
    }

    #[test]
    fn the_embedder_is_embeddinggemma_2_and_nomic_is_only_a_file_to_clean_up() {
        let m = find(EMBED).unwrap();
        assert_eq!((m.id, m.file, m.bytes, m.kind), ("embeddinggemma-2", "embeddinggemma-2-Q8_0.gguf", 309_855_456, Kind::Embed));
        assert_eq!(CATALOG.len(), 4);
        assert!(CATALOG.iter().all(|c| !LEGACY_EMBED_FILES.contains(&c.file) && !c.id.contains("nomic")));
    }

    #[test]
    fn gate_warns_over_60_and_refuses_over_90_percent() {
        let m = find("qwen3-1.7b").unwrap(); // 1.107 GB + 4 x 115 MB = 1.567 GB
        assert_eq!(gate(m, Some(4_000_000_000)), Gate::Ok); // 39%
        assert_eq!(gate(m, Some(2_000_000_000)), Gate::Warn); // 78%
        assert_eq!(gate(m, Some(1_700_000_000)), Gate::Refuse); // 92%
        assert_eq!(gate(m, None), Gate::Ok);
    }
}
