import Foundation

/// The one place that turns "which catalog model is selected" into "is it
/// actually ready to answer." Every feature that talks to `LlamaCppClient`
/// calls one of these first. Two runtimes, one entry point: a `.gguf` entry
/// spawns `LlamaServerManager`'s `llama-server` process (no external app to
/// rely on the way `ollama serve` was, so something has to start it); an
/// `.mlx` entry loads in-process through `MLXBackend` — no process, no
/// health-check polling, just a model load.
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
        switch entry.kind {
        case .mlx:
            do {
                try await MLXBackend.shared.ensureLoaded(directory: ModelCatalog.localURL(for: entry))
                return true
            } catch {
                // Logged, not swallowed — a bare `false` here is
                // indistinguishable from "no model downloaded" to the
                // caller (`AssistantEngineError.serverUnavailable`'s message
                // only ever suggests that), which cost real time to
                // diagnose once (missing Metal Toolchain component, then a
                // too-old swift-transformers pin). `print` rather than a
                // logging framework — matches this file's existing size.
                print("MLXBackend.ensureLoaded failed for \(modelID): \(error)")
                return false
            }
        case .gguf:
            return await LlamaServerManager.shared.ensureRunning(
                .chat, modelPath: ModelCatalog.localURL(for: entry), contextSize: contextSize,
                kvQuantized: Preferences.storedKVCacheQuantized(), useGPU: Preferences.storedUseGPU()
            )
        }
    }

    static func ensureEmbedServer() async -> Bool {
        guard ModelCatalog.isDownloaded(ModelCatalog.embedModel) else { return false }
        return await LlamaServerManager.shared.ensureRunning(
            .embed, modelPath: ModelCatalog.localURL(for: ModelCatalog.embedModel),
            kvQuantized: Preferences.storedKVCacheQuantized(), useGPU: Preferences.storedUseGPU()
        )
    }
}
