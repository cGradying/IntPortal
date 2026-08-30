import Foundation

/// The short, verified list of local chat models the app offers — not a
/// free-text field. Every entry's size was confirmed against the real HF
/// file before being added here; nothing here is a guess. Sits alongside
/// `LlamaServerManager`'s `.chat` role — whichever entry `Preferences.aiModel`
/// names is what that role's `llama-server` is launched with.
enum ModelCatalog {
    struct Entry: Identifiable, Equatable {
        let id: String
        let label: String
        let filename: String
        let url: URL
        let sizeBytes: Int64
        let description: String
        /// KV cache bytes per token of context, at the cache type
        /// `LlamaServerManager` actually launches with — q8_0 (1 byte per
        /// K/V element), not llama.cpp's fp16 default (2 bytes), since
        /// `--cache-type-k/v q8_0` is now always passed. Architecture-
        /// specific: `2 (K+V) * layers * kvHeads * headDim * 1 byte`. From
        /// Qwen3-1.7B's published config (28 layers, 8 KV heads via GQA,
        /// head_dim 128): `2 * 28 * 8 * 128 * 1 = 57,344` — half the old
        /// fp16 figure (114,688). Used only for the Settings RAM estimate
        /// (`ModelCatalog.estimatedRAMBytes`), not by `llama-server` itself
        /// — it works this out on its own from the GGUF's real metadata.
        /// Keep this in step with `LlamaServerManager`'s actual cache-type
        /// flags — a change there without a matching change here makes the
        /// Settings slider's RAM estimate wrong, silently.
        let kvCacheBytesPerToken: Int64
    }

    /// Confirmed live this session: downloaded and ran through a real
    /// `llama-server`, RSS/JSON-schema/thinking all checked directly rather
    /// than trusted from a model card.
    static let entries: [Entry] = [
        Entry(
            id: "qwen3-1.7b",
            label: "Qwen3-1.7B",
            filename: "Qwen3-1.7B-Q4_K_M.gguf",
            url: URL(string: "https://huggingface.co/unsloth/Qwen3-1.7B-GGUF/resolve/main/Qwen3-1.7B-Q4_K_M.gguf")!,
            sizeBytes: 1_107_409_472,
            description: "1.1GB · general chat, tools, and thinking. The default — runs comfortably on any Mac.",
            kvCacheBytesPerToken: 57_344
        ),
    ]

    static func entry(for id: String) -> Entry? {
        entries.first { $0.id == id }
    }

    static var defaultID: String { entries[0].id }

    /// Fixed padding for `llama-server`'s own compute buffers (the
    /// activation/graph memory it allocates alongside the KV cache) — not
    /// something the GGUF or config exposes, so this is a round, deliberately
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
    static func estimatedRAMBytes(for entry: Entry, contextSize: Int) -> Int64 {
        entry.sizeBytes + entry.kvCacheBytesPerToken * Int64(contextSize) + computeOverheadBytes
    }

    /// Fixed — not a picker. One small embedding model, downloaded once
    /// alongside the first chat model, running as `LlamaServerManager`'s
    /// `.embed` role for the whole life of the app.
    static let embedModel = Entry(
        id: "nomic-embed-text-v1.5",
        label: "nomic-embed-text-v1.5",
        filename: "nomic-embed-text-v1.5.Q4_K_M.gguf",
        url: URL(string: "https://huggingface.co/nomic-ai/nomic-embed-text-v1.5-GGUF/resolve/main/nomic-embed-text-v1.5.Q4_K_M.gguf")!,
        sizeBytes: 84_106_624,
        description: "Powers note search — downloaded automatically alongside your first chat model.",
        // Unused (no context slider for the fixed embed role) — filled in for
        // `Entry`'s sake from nomic-embed-text-v1.5's own config (12 layers,
        // 12 heads, head_dim 64) at q8_0: `2 * 12 * 12 * 64 * 1 = 18,432`.
        kvCacheBytesPerToken: 18_432
    )

    /// Downloaded weights live under Application Support, same convention
    /// `ScheduleStore`/`NotesStore` already use — never inside the app bundle.
    static let modelsDirectory: URL = {
        let support = (try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )) ?? FileManager.default.temporaryDirectory
        let dir = support.appendingPathComponent("PUPSISPortal/models", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static func localURL(for entry: Entry) -> URL {
        modelsDirectory.appendingPathComponent(entry.filename)
    }

    static func isDownloaded(_ entry: Entry) -> Bool {
        FileManager.default.fileExists(atPath: localURL(for: entry).path)
    }

    /// Where the `-with-AI` dmg ships its weights — `Contents/Resources/models/`,
    /// same convention as `Fonts/` (`Bundle.main`, a plain copy `make_mac_app.sh`
    /// places there; never `Bundle.module`, see its own doc comment on why that
    /// accessor `fatalError`s in a hand-rolled bundle). The lite build has no
    /// `models/` directory at all.
    static func bundledModelsDirectory(bundle: Bundle = .main) -> URL {
        bundle.bundleURL.appendingPathComponent("Contents/Resources/models", isDirectory: true)
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
            let source = bundleDirectory.appendingPathComponent(entry.filename)
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
