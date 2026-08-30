import Foundation

/// Owns both `llama-server` processes' lifecycle — the `.chat` role
/// (assistant/tools/quiz/note-help, port 8080) and the `.embed` role (note
/// search, port 8081) — so nothing in the app depends on the user having
/// started them by hand in a terminal, and neither outlives the app. One
/// binary, two roles, two local GGUF files (`ModelCatalog`); `.shared`,
/// matching `Notifier.shared`'s existing precedent for a process-wide owned
/// resource.
@MainActor
final class LlamaServerManager {
    static let shared = LlamaServerManager()

    enum Role {
        case chat
        case embed

        var port: Int {
            switch self {
            case .chat: 8080
            case .embed: 8081
            }
        }

        var healthURL: URL { URL(string: "http://127.0.0.1:\(port)/health")! }

        /// `.embed` needs `--embedding` (restricts the process to the
        /// embedding use case; llama.cpp refuses `/v1/embeddings` without it
        /// on a plain chat build) plus a pooling strategy — `mean`, the
        /// convention nomic-embed-text's own docs use. `.chat` needs
        /// `--jinja` for its chat template (tool schema, thinking) to apply
        /// at all.
        var extraArguments: [String] {
            switch self {
            case .chat: ["--jinja"]
            case .embed: ["--embedding", "--pooling", "mean"]
            }
        }
    }

    // Bundled first: the `-with-AI` dmg ships its own static, universal
    // llama-server at `Contents/MacOS/llama-server` — a Homebrew copy
    // (possibly a different, incompatible version) must never win over it.
    // The lite build has no such file, so this candidate just never matches
    // and Homebrew's own path is used, unchanged from before.
    private static let binaryCandidates = [
        Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/llama-server").path,
        "/opt/homebrew/bin/llama-server",
        "/usr/local/bin/llama-server",
    ]

    private var processes: [Role: Process] = [:]

    /// Starts `role`'s server against `modelPath` if it isn't already
    /// reachable, and waits until it answers `/health` (or a timeout), so
    /// the first request doesn't race a cold process. Safe to call
    /// repeatedly — a no-op once running, and a second call while one is
    /// still starting waits on the same launch rather than spawning a
    /// duplicate.
    ///
    /// Switching `.chat` models (a different `modelPath` than what's already
    /// running), changing `contextSize`, or flipping `kvQuantized`/`useGPU`,
    /// restarts the process — `llama-server` serves one model at one context
    /// length with one set of launch flags for its whole lifetime, there's no
    /// in-place change to any of them. `contextSize`/`kvQuantized`/`useGPU`
    /// only matter for `.chat` (`Preferences.aiContextSize`/
    /// `aiKVCacheQuantized`/`aiUseGPU`); `.embed` passes its own fixed
    /// defaults since embedding requests are one short chunk at a time, never
    /// the long context a chat/RAG turn needs.
    func ensureRunning(
        _ role: Role, modelPath: URL, contextSize: Int = Preferences.aiDefaultContextSize,
        kvQuantized: Bool = true, useGPU: Bool = true
    ) async -> Bool {
        if await isHealthy(role), currentModelPath[role] == modelPath, currentContextSize[role] == contextSize,
           currentKVQuantized[role] == kvQuantized, currentUseGPU[role] == useGPU {
            return true
        }
        if currentModelPath[role] != modelPath || currentContextSize[role] != contextSize
            || currentKVQuantized[role] != kvQuantized || currentUseGPU[role] != useGPU {
            stop(role)
        }
        if processes[role] != nil { return await waitUntilHealthy(role) }

        guard let binary = Self.locateBinary() else { return false }

        var arguments = ["-m", modelPath.path, "--port", String(role.port), "--ctx-size", String(contextSize)]
        if kvQuantized {
            // KV cache quantized to q8_0 (1 byte/element) instead of
            // llama.cpp's fp16 default (2 bytes/element) — roughly halves
            // the RAM `--ctx-size` tokens cost, so raising context no
            // longer means raising RAM 1:1. Same GGUF, same disk footprint,
            // no model change. `ModelCatalog.Entry.kvCacheBytesPerToken` is
            // calibrated to this — if these flags ever change, that needs
            // updating too or the Settings RAM estimate goes wrong.
            arguments += ["--cache-type-k", "q8_0", "--cache-type-v", "q8_0"]
        }
        if !useGPU {
            // Forces CPU-only — off by default, a debugging knob for
            // isolating whether a slowdown or crash is GPU-related.
            arguments += ["-ngl", "0"]
        }
        arguments += role.extraArguments

        let launched = Process()
        launched.executableURL = URL(fileURLWithPath: binary)
        launched.arguments = arguments
        launched.standardOutput = FileHandle.nullDevice
        launched.standardError = FileHandle.nullDevice

        do {
            try launched.run()
        } catch {
            return false
        }
        processes[role] = launched
        currentModelPath[role] = modelPath
        currentContextSize[role] = contextSize
        currentKVQuantized[role] = kvQuantized
        currentUseGPU[role] = useGPU
        return await waitUntilHealthy(role)
    }

    /// Tracks which model (context size, KV quantization, GPU offload) each
    /// role's currently-running process was started with, so `ensureRunning`
    /// knows to restart rather than reuse when any of them changes.
    private var currentModelPath: [Role: URL] = [:]
    private var currentContextSize: [Role: Int] = [:]
    private var currentKVQuantized: [Role: Bool] = [:]
    private var currentUseGPU: [Role: Bool] = [:]

    /// Clean SIGTERM — llama-server shuts down on it. Called when AI is
    /// toggled off and when the app quits (`AppState`'s termination observer).
    func stop() {
        stop(.chat)
        stop(.embed)
    }

    private func stop(_ role: Role) {
        processes[role]?.terminate()
        processes[role] = nil
        currentModelPath[role] = nil
        currentContextSize[role] = nil
        currentKVQuantized[role] = nil
        currentUseGPU[role] = nil
    }

    private func isHealthy(_ role: Role) async -> Bool {
        var request = URLRequest(url: role.healthURL)
        request.timeoutInterval = 2
        guard let (_, response) = try? await URLSession.shared.data(for: request) else { return false }
        return (response as? HTTPURLResponse)?.statusCode == 200
    }

    private func waitUntilHealthy(_ role: Role, timeout: TimeInterval = 30) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await isHealthy(role) { return true }
            try? await Task.sleep(for: .milliseconds(500))
        }
        return false
    }

    /// Pure and injectable so binary discovery is testable without touching
    /// the real filesystem.
    static func locateBinary(
        candidates: [String] = binaryCandidates,
        isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) -> String? {
        candidates.first(where: isExecutable)
    }
}
