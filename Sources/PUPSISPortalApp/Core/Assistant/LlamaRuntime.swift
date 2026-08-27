import Foundation

/// The one place that turns "which catalog model is selected" into "is its
/// `llama-server` actually up." Every feature that talks to `LlamaCppClient`
/// calls one of these first — there's no external app to rely on the way
/// `ollama serve` was; this app owns both processes' lifecycle
/// (`LlamaServerManager`), so something has to start them on first use.
///
/// Takes a bare `modelID: String` rather than `Preferences` itself — matches
/// the existing convention (`AssistantEngine`/`CardGenerator`/etc. already
/// take `model: String`, not a `Preferences` dependency), and keeps these
/// components trivially testable via their own injected `ensureServerRunning`
/// closures rather than this enum directly.
@MainActor
enum LlamaRuntime {
    static func ensureChatServer(modelID: String, contextSize: Int = Preferences.storedContextSize()) async -> Bool {
        guard let entry = ModelCatalog.entry(for: modelID), ModelCatalog.isDownloaded(entry) else { return false }
        return await LlamaServerManager.shared.ensureRunning(.chat, modelPath: ModelCatalog.localURL(for: entry), contextSize: contextSize)
    }

    static func ensureEmbedServer() async -> Bool {
        guard ModelCatalog.isDownloaded(ModelCatalog.embedModel) else { return false }
        return await LlamaServerManager.shared.ensureRunning(.embed, modelPath: ModelCatalog.localURL(for: ModelCatalog.embedModel))
    }
}
