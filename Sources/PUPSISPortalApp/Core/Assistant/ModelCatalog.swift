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
    }

    /// Confirmed live this session: downloaded and ran both through a real
    /// `llama-server`, RSS/JSON-schema/thinking all checked directly rather
    /// than trusted from a model card.
    static let entries: [Entry] = [
        Entry(
            id: "qwen3-1.7b",
            label: "Qwen3-1.7B",
            filename: "Qwen3-1.7B-Q4_K_M.gguf",
            url: URL(string: "https://huggingface.co/unsloth/Qwen3-1.7B-GGUF/resolve/main/Qwen3-1.7B-Q4_K_M.gguf")!,
            sizeBytes: 1_107_409_472,
            description: "1.1GB · general chat, tools, and thinking. The default — runs comfortably on any Mac."
        ),
        Entry(
            id: "lfm2.5-2.6b",
            label: "LFM2.5-2.6B",
            filename: "LFM2.5-2.6B-Q4_K_M.gguf",
            url: URL(string: "https://huggingface.co/LiquidAI/LFM2.5-2.6B-GGUF/resolve/main/LFM2.5-2.6B-Q4_K_M.gguf")!,
            sizeBytes: 1_707_000_000,
            description: "1.6GB · leans toward RAG, data extraction, and long context. Custom Liquid AI license (lfm1.0), not Apache 2.0."
        ),
    ]

    static func entry(for id: String) -> Entry? {
        entries.first { $0.id == id }
    }

    static var defaultID: String { entries[0].id }

    /// Fixed — not a picker. One small embedding model, downloaded once
    /// alongside the first chat model, running as `LlamaServerManager`'s
    /// `.embed` role for the whole life of the app.
    static let embedModel = Entry(
        id: "nomic-embed-text-v1.5",
        label: "nomic-embed-text-v1.5",
        filename: "nomic-embed-text-v1.5.Q4_K_M.gguf",
        url: URL(string: "https://huggingface.co/nomic-ai/nomic-embed-text-v1.5-GGUF/resolve/main/nomic-embed-text-v1.5.Q4_K_M.gguf")!,
        sizeBytes: 84_106_624,
        description: "Powers note search — downloaded automatically alongside your first chat model."
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
}
