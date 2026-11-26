//! The models IntAssis can download. Never bundled (ADR 0003). Sizes and
//! SHA-256 come from the Hugging Face LFS metadata of each file.
use crate::prompt::Template;

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
    /// How the model wants its prompt wrapped (an embedder never gets a chat prompt).
    pub template: Template,
    pub file: &'static str,
    pub url: &'static str,
    pub sha256: &'static str,
    pub bytes: u64,
    /// Context length the app runs it with.
    pub n_ctx: u32,
    /// Rough per-1000-token KV cache at q8_0, for the RAM gate.
    pub kv_bytes_per_1k: u64,
    /// A model an earlier version installed and this one no longer offers (spec 021 C13). It is listed
    /// only while it is on the phone, keeps answering until the default arrives, and is deleted then.
    pub legacy: bool,
}

pub const CATALOG: [Model; 5] = [
    Model {
        id: "qwen3.5-2b",
        name: "Qwen3.5 2B",
        kind: Kind::Chat,
        template: Template::ChatMl,
        file: "Qwen3.5-2B-IQ4_XS.gguf",
        url: "https://huggingface.co/unsloth/Qwen3.5-2B-GGUF/resolve/main/Qwen3.5-2B-IQ4_XS.gguf",
        sha256: "3639f34b5ca22aa1c51f3616566eae8c355111554f6924ad97ee2652ed11c1cd",
        bytes: 1_172_996_352,
        n_ctx: 4096,
        // Hybrid: three of every four layers are linear attention with a fixed state, so the cache grows
        // with only a quarter of the layers. Set from the peak RSS of `speed` (docs/ai.md), with margin.
        kv_bytes_per_1k: 60_000_000,
        legacy: false,
    },
    Model {
        id: "qwen3-0.6b",
        name: "Qwen3 0.6B",
        kind: Kind::Chat,
        template: Template::ChatMl,
        file: "Qwen3-0.6B-Q4_K_M.gguf",
        url: "https://huggingface.co/unsloth/Qwen3-0.6B-GGUF/resolve/main/Qwen3-0.6B-Q4_K_M.gguf",
        sha256: "ac2d97712095a558e31573f62f466a3f9d93990898b0ec79d7c974c1780d524a",
        bytes: 396_705_472,
        n_ctx: 4096,
        kv_bytes_per_1k: 60_000_000,
        legacy: true,
    },
    Model {
        id: "gemma3-1b",
        name: "Gemma 3 1B",
        kind: Kind::Chat,
        template: Template::Gemma,
        file: "gemma-3-1b-it-Q4_K_M.gguf",
        url: "https://huggingface.co/unsloth/gemma-3-1b-it-GGUF/resolve/main/gemma-3-1b-it-Q4_K_M.gguf",
        sha256: "8270790f3ab69fdfe860b7b64008d9a19986d8df7e407bb018184caa08798ebd",
        bytes: 806_058_272,
        n_ctx: 4096,
        kv_bytes_per_1k: 25_000_000,
        legacy: true,
    },
    Model {
        id: "qwen3-1.7b",
        name: "Qwen3 1.7B",
        kind: Kind::Chat,
        template: Template::ChatMl,
        file: "Qwen3-1.7B-Q4_K_M.gguf",
        url: "https://huggingface.co/unsloth/Qwen3-1.7B-GGUF/resolve/main/Qwen3-1.7B-Q4_K_M.gguf",
        sha256: "b139949c5bd74937ad8ed8c8cf3d9ffb1e99c866c823204dc42c0d91fa181897",
        bytes: 1_107_409_472,
        n_ctx: 4096,
        kv_bytes_per_1k: 115_000_000,
        legacy: false,
    },
    Model {
        id: "embeddinggemma-2",
        name: "EmbeddingGemma-2",
        kind: Kind::Embed,
        template: Template::ChatMl,
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
        legacy: false,
    },
];

/// The answering model of a new install (spec 021 C10, C12). The owner chose Qwen3.5 2B on 2026-11-17;
/// IQ4_XS won the benchmark: the first word 3.4 times sooner than Q4_K_M on CPU, the same on Metal, and
/// 110 MB smaller (docs/ai.md). Qwen3 1.7B stays as the other choice; Gemma 3 1B and Qwen3 0.6B are legacy.
pub const DEFAULT_CHAT: &str = "qwen3.5-2b";
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

/// What a loaded model holds: its weights plus the KV cache at the context the app runs it with.
fn need(m: &Model) -> u64 {
    m.bytes + m.kv_bytes_per_1k * u64::from(m.n_ctx) / 1000
}

/// A chat model's window when the phone has room (spec 062 C26): long answers and a longer chat fit.
pub const WIDE_CTX: u32 = 8192;

/// The window a chat model loads with: `WIDE_CTX` when the models it sits beside still pass `gate` at it
/// with room to spare (Ok, not Warn), else its own `n_ctx`. Unknown memory (the Mac) gets the wide one.
pub fn window(m: &Model, beside: &[&Model], available: Option<u64>) -> u32 {
    if m.kind != Kind::Chat || m.n_ctx >= WIDE_CTX {
        return m.n_ctx;
    }
    let wide = Model { n_ctx: WIDE_CTX, ..*m };
    let all: Vec<&Model> = beside.iter().copied().chain([&wide]).collect();
    if gate(&all, available) == Gate::Ok { WIDE_CTX } else { m.n_ctx }
}

/// A phone with at most this much RAM (`MemTotal`, which reads under the label: a "6 GB" phone shows about
/// 5.5 GB) cannot keep the chat model and the note-search model beside each other: Android's low-memory
/// killer ended five other apps and the app stopped answering when both loaded on a 4 GB phone.
pub const SMALL_RAM: u64 = 6_500_000_000;

/// True on a phone that reports its total RAM and has `SMALL_RAM` or less. Unknown (iOS, the Mac) is not small.
pub fn is_small_ram(total: Option<u64>) -> bool {
    total.is_some_and(|t| t <= SMALL_RAM)
}

/// Compares what IntAssis holds at once, the models in `resident` (the chat model and the note-search
/// model together on a big phone, one of them on a small one), with the memory available to the app.
/// `None` (unknown platform) is allowed through. A second chat model is never counted: it is unloaded
/// before the new one loads.
pub fn gate(resident: &[&Model], available: Option<u64>) -> Gate {
    let Some(avail) = available else { return Gate::Ok };
    match resident.iter().map(|m| need(m)).sum::<u64>() * 100 / avail.max(1) {
        0..=60 => Gate::Ok,
        61..=90 => Gate::Warn,
        _ => Gate::Refuse,
    }
}

/// The same question against the phone's total RAM, its class (spec 021 C2): a phone where the models
/// take over half of all its memory can't run them; over a third is a tight fit.
pub fn gate_by_total(resident: &[&Model], total: u64) -> Gate {
    match resident.iter().map(|m| need(m)).sum::<u64>() * 100 / total.max(1) {
        0..=35 => Gate::Ok,
        36..=50 => Gate::Warn,
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
        assert!(!find(DEFAULT_CHAT).unwrap().legacy);
        assert_eq!(find(DEFAULT_CHAT).unwrap().kind, Kind::Chat);
        assert_eq!(find(EMBED).unwrap().kind, Kind::Embed);
    }

    #[test]
    fn the_embedder_is_embeddinggemma_2_and_nomic_is_only_a_file_to_clean_up() {
        let m = find(EMBED).unwrap();
        assert_eq!((m.id, m.file, m.bytes, m.kind), ("embeddinggemma-2", "embeddinggemma-2-Q8_0.gguf", 309_855_456, Kind::Embed));
        assert_eq!(CATALOG.len(), 5);
        assert!(CATALOG.iter().all(|c| !LEGACY_EMBED_FILES.contains(&c.file) && !c.id.contains("nomic")));
    }

    #[test]
    fn qwen35_is_the_default_qwen3_the_choice_and_the_rest_legacy() {
        assert_eq!(DEFAULT_CHAT, "qwen3.5-2b");
        let offered: Vec<&str> = CATALOG.iter().filter(|m| m.kind == Kind::Chat && !m.legacy).map(|m| m.id).collect();
        assert_eq!(offered, ["qwen3.5-2b", "qwen3-1.7b"]);
        assert!(find("gemma3-1b").unwrap().legacy && find("qwen3-0.6b").unwrap().legacy);
        for m in &CATALOG {
            let want = if m.id.starts_with("gemma3") { Template::Gemma } else { Template::ChatMl };
            assert_eq!(m.template, want, "{}", m.id);
        }

    }

    #[test]
    fn gate_counts_the_models_that_are_resident_together() {
        let (qwen, gemma, eg2) = (find("qwen3-1.7b").unwrap(), find("gemma3-1b").unwrap(), find(EMBED).unwrap());
        // Qwen 1.107 GB + 4 x 115 MB = 1.567 GB, EmbeddingGemma-2 0.310 GB + 1 x 200 MB = 0.515 GB: 2.082 GB together.
        assert_eq!(gate(&[qwen, eg2], Some(4_000_000_000)), Gate::Ok); // 52%
        assert_eq!(gate(&[qwen, eg2], Some(2_500_000_000)), Gate::Warn); // 83%
        assert_eq!(gate(&[qwen, eg2], Some(2_200_000_000)), Gate::Refuse); // 95%: Qwen alone would be Warn here
        assert_eq!(gate(&[qwen, eg2], None), Gate::Ok);
        // Gemma 0.806 GB + 4 x 25 MB = 0.908 GB, plus the embedder: 1.423 GB. It fits where Qwen is refused.
        assert_eq!(gate(&[gemma, eg2], Some(2_200_000_000)), Gate::Warn); // 65%, where Qwen is refused
        assert_eq!(gate(&[gemma, eg2], Some(2_500_000_000)), Gate::Ok); // 57%
    }

    #[test]
    fn a_small_phone_gates_one_model_at_a_time() {
        let (qwen, gemma, eg2) = (find("qwen3-1.7b").unwrap(), find("gemma3-1b").unwrap(), find(EMBED).unwrap());
        // The 4 GB emulator of the smoke test showed 2.3 GB available: both together were 90% (the edge of
        // Warn); Qwen alone is 68%, and the embedder alone, loaded after the chat model is let go, 22%.
        assert_eq!(gate(&[qwen], Some(2_300_000_000)), Gate::Warn);
        assert_eq!(gate(&[eg2], Some(2_300_000_000)), Gate::Ok);
        assert_eq!(gate(&[qwen], Some(1_700_000_000)), Gate::Refuse, "too small for the 1.1 GB model");
        assert_eq!(gate(&[gemma], Some(1_700_000_000)), Gate::Ok, "the lighter model still fits there");
    }

    #[test]
    fn small_ram_is_a_phone_that_reports_six_gb_or_less() {
        assert!(is_small_ram(Some(4_015_044 * 1024))); // the 4 GB emulator
        assert!(is_small_ram(Some(5_600_000_000))); // a "6 GB" phone
        assert!(!is_small_ram(Some(7_500_000_000))); // an "8 GB" phone
        assert!(!is_small_ram(None)); // iOS and the Mac do not say
    }

    #[test]
    fn total_ram_decides_by_phone_class_not_the_moment() {
        let (qwen, eg2) = (find("qwen3-1.7b").unwrap(), find(EMBED).unwrap());
        let gb = |g: f64| (g * 1e9) as u64;
        assert_eq!(gate_by_total(&[qwen, eg2], gb(7.5)), Gate::Ok, "an 8 GB phone holds both");
        assert_eq!(gate_by_total(&[qwen], gb(5.5)), Gate::Ok, "a 6 GB phone, one at a time");
        assert_eq!(gate_by_total(&[qwen], gb(3.8)), Gate::Warn, "a 4 GB phone runs it, tightly");
        assert_eq!(gate_by_total(&[qwen], gb(2.8)), Gate::Refuse, "a 3 GB phone can't");
    }
    #[test]
    fn c26_the_chat_model_gets_the_wide_window_only_with_room_to_spare() {
        let chat = find("qwen3.5-2b").unwrap();
        let embed = CATALOG.iter().find(|m| m.kind == Kind::Embed && !m.legacy).unwrap();
        assert_eq!(window(chat, &[embed], None), WIDE_CTX, "unknown memory");
        assert_eq!(window(chat, &[embed], Some(4_000_000_000)), WIDE_CTX);
        assert_eq!(window(chat, &[embed], Some(2_700_000_000)), 4096, "tight: stays at 4,096");
        assert_eq!(window(embed, &[], Some(8_000_000_000)), embed.n_ctx, "the search model keeps its own");
    }

    #[test]
    fn c26_the_window_is_never_anything_but_the_models_own_or_the_wide_one_and_never_shrinks_with_more_room() {
        let chat = find("qwen3.5-2b").unwrap();
        let embed = CATALOG.iter().find(|m| m.kind == Kind::Embed && !m.legacy).unwrap();
        let mut was_wide = false;
        for gb in 0..=12u64 {
            let w = window(chat, &[embed], Some(gb * 500_000_000));
            assert!(w == chat.n_ctx || w == WIDE_CTX, "{gb}: {w}");
            assert!(!was_wide || w == WIDE_CTX, "more memory lost the wide window at {gb}");
            was_wide = w == WIDE_CTX;
        }
        assert_eq!(window(chat, &[embed], Some(0)), chat.n_ctx, "no memory at all");
        assert_eq!(window(chat, &[embed], Some(12_000_000_000)), WIDE_CTX);
        assert_eq!(chat.n_ctx, 4096);
    }

    #[test]
    fn c26_a_model_already_at_or_over_the_wide_window_keeps_it_and_a_small_chat_model_is_gated_with_its_neighbour() {
        let chat = find("qwen3.5-2b").unwrap();
        let embed = CATALOG.iter().find(|m| m.kind == Kind::Embed && !m.legacy).unwrap();
        let big = Model { n_ctx: 16_384, ..*chat };
        assert_eq!(window(&big, &[], Some(1)), 16_384, "not cut down, whatever the memory");
        // The wide cache is costed beside the search model: with it gone there is more room than with it.
        let alone = (0..=24u64).map(|i| i * 250_000_000).find(|&a| window(chat, &[], Some(a)) == WIDE_CTX).unwrap();
        let beside = (0..=24u64).map(|i| i * 250_000_000).find(|&a| window(chat, &[embed], Some(a)) == WIDE_CTX).unwrap();
        assert!(alone <= beside, "{alone} {beside}");
    }
}
