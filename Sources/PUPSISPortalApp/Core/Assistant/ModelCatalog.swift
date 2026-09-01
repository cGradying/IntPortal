import Foundation
import Hub

/// The short, verified list of local chat models the app offers — not a
/// free-text field. Every entry's size was confirmed against the real HF
/// file before being added here; nothing here is a guess.
///
/// Two runtimes, one catalog: `.mlx` entries run in-process through
/// `MLXBackend` (Apple Silicon only), `.gguf` entries spawn `LlamaServerManager`'s
/// `.chat`-role `llama-server` — see `Preferences.resolvedAIClient()` and
/// `LlamaRuntime.ensureChatServer` for where that branch happens. Intel Macs
/// stay on the `.gguf` entry; there is no Intel `.mlx` runtime.
enum ModelCatalog {
    struct Entry: Identifiable, Equatable {
        enum Kind: Equatable {
            /// A single GGUF file, run by `LlamaServerManager`.
            case gguf(filename: String, url: URL)
            /// A Hugging Face repo of MLX weights (config + tokenizer +
            /// `.safetensors` shards — several files, not one), run in-process
            /// by `MLXBackend`. `repoID` is the exact HF repo id, e.g.
            /// `"mlx-community/Qwen3.5-0.8B-4bit"`.
            case mlx(repoID: String)

            var isGGUF: Bool {
                if case .gguf = self { return true }
                return false
            }
        }

        let id: String
        let label: String
        let kind: Kind
        let sizeBytes: Int64
        let description: String
        /// KV cache bytes per token of context — see each entry's own
        /// comment for how it was derived. Used only for the Settings RAM
        /// estimate (`ModelCatalog.estimatedRAMBytes`), never by the runtime
        /// itself: `llama-server` works this out from the GGUF's own
        /// metadata, and `MLXBackend` doesn't take a fixed cache budget at
        /// all. Keep in step with whatever the runtime actually does —
        /// `LlamaServerManager`'s cache-type flags for `.gguf`, a live RSS
        /// measurement for `.mlx` (see `qwen3.5-0.8b`'s comment).
        let kvCacheBytesPerToken: Int64
    }

    /// Confirmed live this session: downloaded and ran through a real
    /// `llama-server`, RSS/JSON-schema/thinking all checked directly rather
    /// than trusted from a model card.
    ///
    /// Ordering matters: `defaultID` is `entries[0].id` — Qwen3.5-0.8B-MLX
    /// leads the array on purpose, matching the decision to default there
    /// even though it hasn't run live yet (see its own comment).
    static let entries: [Entry] = [
        Entry(
            id: "qwen3.5-0.8b",
            label: "Qwen3.5-0.8B",
            kind: .mlx(repoID: "mlx-community/Qwen3.5-0.8B-4bit"),
            sizeBytes: 683_671_552, // 652MB — mlx-community/Qwen3.5-0.8B-4bit's real repo size (safetensors + tokenizer + config)
            description: "652MB · MLX, 256K context. The default on Apple Silicon — fastest, smallest of the Qwen3.5 pair.",
            // Confirmed against mlx-community/Qwen3.5-0.8B-4bit's real
            // config.json: 24 layers total, but Qwen3.5 is a hybrid
            // Gated-DeltaNet architecture — `layer_types` shows only every
            // 4th layer (6 of 24) is full attention with a real KV cache;
            // the other 18 are linear/gated-delta-net layers whose recurrent
            // state is fixed-size and does not grow with context, so they
            // contribute ~0 to this per-token figure. Full-attention layers:
            // num_key_value_heads 2, head_dim 256. At q8_0 (`MLXBackend`
            // passes `kvBits: 8`, matching the .gguf path's own
            // `--cache-type-k/v q8_0`): `2 (K+V) * 6 full-attention layers *
            // 2 KV heads * 256 head_dim * 1 byte = 6,144`. Not yet confirmed
            // by a live RSS measurement (ponytail: verify against
            // Activity Monitor once the model actually runs) — derived from
            // the real published config, not a guess, so this replaces the
            // earlier placeholder.
            kvCacheBytesPerToken: 6_144
        ),
        Entry(
            id: "qwen3.5-2b",
            label: "Qwen3.5-2B",
            kind: .mlx(repoID: "mlx-community/Qwen3.5-2B-4bit"),
            sizeBytes: 1_879_048_192, // 1.75GB — mlx-community/Qwen3.5-2B-4bit's real repo size
            description: "1.75GB · MLX, 256K context. Larger of the Qwen3.5 pair — better tool-calling and reasoning.",
            // Same layer_types/head config as qwen3.5-0.8b (only hidden_size
            // scales between the two) — identical derivation and figure, see
            // that entry's own comment.
            kvCacheBytesPerToken: 6_144
        ),
        Entry(
            id: "qwen3-1.7b",
            label: "Qwen3-1.7B",
            kind: .gguf(
                filename: "Qwen3-1.7B-Q4_K_M.gguf",
                url: URL(string: "https://huggingface.co/unsloth/Qwen3-1.7B-GGUF/resolve/main/Qwen3-1.7B-Q4_K_M.gguf")!
            ),
            sizeBytes: 1_107_409_472,
            description: "1.1GB · general chat, tools, and thinking. The Intel fallback — no MLX runtime there.",
            // KV cache bytes per token of context, at the cache type
            // `LlamaServerManager` actually launches with — q8_0 (1 byte per
            // K/V element), not llama.cpp's fp16 default (2 bytes), since
            // `--cache-type-k/v q8_0` is now always passed. Architecture-
            // specific: `2 (K+V) * layers * kvHeads * headDim * 1 byte`. From
            // Qwen3-1.7B's published config (28 layers, 8 KV heads via GQA,
            // head_dim 128): `2 * 28 * 8 * 128 * 1 = 57,344` — half the old
            // fp16 figure (114,688).
            kvCacheBytesPerToken: 57_344
        ),
    ]

    static func entry(for id: String) -> Entry? {
        entries.first { $0.id == id }
    }

    static var defaultID: String { entries[0].id }

    /// Fixed padding for the runtime's own compute buffers (the
    /// activation/graph memory it allocates alongside the KV cache) — not
    /// something the model or config exposes, so this is a round, deliberately
    /// generous estimate rather than a measured figure.
    /// ponytail: flat 512MB fudge factor, not scaled per-model or per-context;
    /// revisit if a bigger model is ever added to the catalog and this stops
    /// being close enough.
    private static let computeOverheadBytes: Int64 = 512 * 1024 * 1024

    /// Rough total RSS estimate for running `entry` at `contextSize` tokens:
    /// its on-disk weights (loaded ~as-is into RAM) plus the KV cache the
    /// context length demands plus a flat compute-buffer overhead. For
    /// display only (the Settings context-size slider) — never fed back into
    /// anything that allocates memory itself.
    ///
    /// `quantizedKVCache` — every `kvCacheBytesPerToken` figure above is
    /// already calibrated at q8_0 (1 byte/element); `false` (Settings ▸
    /// Intelligence ▸ Advanced AI tuning's "Quantize KV cache" off) doubles
    /// the KV term to approximate llama.cpp's fp16 default (2 bytes/element).
    /// Only meaningful for a `.gguf` entry — `Preferences.aiKVCacheQuantized`
    /// only reaches `LlamaServerManager`'s `.gguf` launch path; an `.mlx`
    /// entry always runs at `MLXBackend`'s own fixed `kvBits: 8`, so this
    /// estimate stays q8_0 for those regardless of the toggle.
    static func estimatedRAMBytes(for entry: Entry, contextSize: Int, quantizedKVCache: Bool = true) -> Int64 {
        let kvCacheAppliesToggle = !quantizedKVCache && entry.kind.isGGUF
        let kvBytesPerToken = kvCacheAppliesToggle ? entry.kvCacheBytesPerToken * 2 : entry.kvCacheBytesPerToken
        return entry.sizeBytes + kvBytesPerToken * Int64(contextSize) + computeOverheadBytes
    }

    /// Fixed — not a picker. One small embedding model, downloaded once
    /// alongside the first chat model, running as `LlamaServerManager`'s
    /// `.embed` role for the whole life of the app. Always `.gguf` — nothing
    /// in Stage 4 of the migration plan moves embeddings to MLX.
    static let embedModel = Entry(
        id: "nomic-embed-text-v1.5",
        label: "nomic-embed-text-v1.5",
        kind: .gguf(
            filename: "nomic-embed-text-v1.5.Q4_K_M.gguf",
            url: URL(string: "https://huggingface.co/nomic-ai/nomic-embed-text-v1.5-GGUF/resolve/main/nomic-embed-text-v1.5.Q4_K_M.gguf")!
        ),
        sizeBytes: 84_106_624,
        description: "Powers note search — downloaded automatically alongside your first chat model.",
        // Unused (no context slider for the fixed embed role) — filled in for
        // `Entry`'s sake from nomic-embed-text-v1.5's own config (12 layers,
        // 12 heads, head_dim 64) at q8_0: `2 * 12 * 12 * 64 * 1 = 18,432`.
        kvCacheBytesPerToken: 18_432
    )

    /// Downloaded weights live under Application Support, same convention
    /// `ScheduleStore`/`NotesStore` already use — never inside the app bundle.
    /// An `.mlx` entry's "file" here is a directory (its HF repo snapshot);
    /// `FileManager`'s existence/copy/link calls all work the same on a
    /// directory as a file, so nothing downstream needs to know which.
    static let modelsDirectory: URL = {
        let support = (try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )) ?? FileManager.default.temporaryDirectory
        let dir = support.appendingPathComponent("PUPSISPortal/models", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// The `HubApi` instance every `.mlx` entry downloads and loads through —
    /// rooted at `modelsDirectory` rather than its own default
    /// (`~/Documents/huggingface`) so an MLX repo lands in the same place
    /// every other downloaded model does, and `adoptBundledModels` can find
    /// it with a plain `fileExists` check like everything else here.
    static let hub = HubApi(downloadBase: modelsDirectory)

    static func localURL(for entry: Entry) -> URL {
        switch entry.kind {
        case .gguf(let filename, _):
            return modelsDirectory.appendingPathComponent(filename)
        case .mlx(let repoID):
            return hub.localRepoLocation(HubApi.Repo(id: repoID))
        }
    }

    static func isDownloaded(_ entry: Entry) -> Bool {
        switch entry.kind {
        case .gguf:
            return FileManager.default.fileExists(atPath: localURL(for: entry).path)
        case .mlx:
            // A repo snapshot is many files; `config.json` landing is what
            // `AutoTokenizer`/`LLMModelFactory` actually need first, and (unlike
            // the bare directory) it doesn't exist until `HubApi.snapshot`
            // has genuinely finished — a partial download never reads as done.
            return FileManager.default.fileExists(atPath: localURL(for: entry).appendingPathComponent("config.json").path)
        }
    }

    /// Downloads `entry`'s weights, reporting fractional progress the same
    /// way regardless of kind — `SettingsView.installModel` doesn't need to
    /// know a `.gguf` entry is one `URLSessionDownloadTask`
    /// (`LlamaCppClient.download`) while an `.mlx` entry is `HubApi`
    /// fetching a whole repo snapshot (config, tokenizer, `.safetensors`
    /// shards) via `swift-transformers`, already a dependency for
    /// `MLXTokenizerAdapter`.
    static func download(_ entry: Entry) -> AsyncThrowingStream<Double, Error> {
        switch entry.kind {
        case .gguf(_, let url):
            return LlamaCppClient.download(from: url, to: localURL(for: entry))
        case .mlx(let repoID):
            return AsyncThrowingStream { continuation in
                Task {
                    do {
                        _ = try await hub.snapshot(from: repoID) { progress in
                            continuation.yield(progress.fractionCompleted)
                        }
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
            }
        }
    }

    /// Where the `-with-AI` dmg ships its weights — `Contents/Resources/models/`,
    /// same convention as `Fonts/` (`Bundle.main`, a plain copy `make_mac_app.sh`
    /// places there; never `Bundle.module`, see its own doc comment on why that
    /// accessor `fatalError`s in a hand-rolled bundle). The lite build has no
    /// `models/` directory at all.
    static func bundledModelsDirectory(bundle: Bundle = .main) -> URL {
        bundle.bundleURL.appendingPathComponent("Contents/Resources/models", isDirectory: true)
    }

    /// The bundle-relative path `adoptBundledModels`/`entriesToAdopt` look for
    /// under `bundledModelsDirectory` — a filename for `.gguf`, the repo's
    /// last path component (matching what `make_mac_app.sh` would need to
    /// stage a whole directory under) for `.mlx`.
    private static func bundledRelativePath(for entry: Entry) -> String {
        switch entry.kind {
        case .gguf(let filename, _):
            return filename
        case .mlx(let repoID):
            return repoID.split(separator: "/").last.map(String.init) ?? repoID
        }
    }

    /// Which entries actually need adopting right now — pure, so it's the
    /// testable half of `adoptBundledModels()` below, same split
    /// `LlamaServerManager.locateBinary` uses for its own candidates/
    /// isExecutable seam. `nil` for an entry means "leave it alone": either
    /// already downloaded, or nothing bundled for it to adopt from.
    static func entriesToAdopt(
        from bundleDirectory: URL, fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> [(source: URL, destination: URL)] {
        (entries + [embedModel]).compactMap { entry in
            guard !fileExists(localURL(for: entry).path) else { return nil }
            let source = bundleDirectory.appendingPathComponent(bundledRelativePath(for: entry))
            guard fileExists(source.path) else { return nil }
            return (source, localURL(for: entry))
        }
    }

    /// Moves any bundled weights into the normal Application Support location
    /// (a hardlink, not a copy — instant, no extra disk, and it never mutates
    /// the signed bundle) so the rest of the app never needs to know whether a
    /// model came from a download or from the `-with-AI` dmg. Call once at
    /// launch, before anything checks `isDownloaded`.
    ///
    /// Idempotent and safe on every launch, including the lite build (nothing
    /// in `Contents/Resources/models` to adopt) and a later Sparkle update
    /// that replaces the bundle out from under an already-adopted install
    /// (`isDownloaded` is already true by then, so `entriesToAdopt` is empty).
    ///
    /// `linkItem` covers a directory (an `.mlx` entry's repo snapshot) the
    /// same as a file — APFS hardlinks a whole tree in one call — so no
    /// separate recursive-copy branch is needed here.
    static func adoptBundledModels() {
        for (source, destination) in entriesToAdopt(from: bundledModelsDirectory()) {
            do {
                try FileManager.default.linkItem(at: source, to: destination)
            } catch {
                try? FileManager.default.copyItem(at: source, to: destination)
            }
        }
    }
}
