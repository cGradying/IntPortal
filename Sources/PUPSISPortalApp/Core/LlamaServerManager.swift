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

    private static let binaryCandidates = ["/opt/homebrew/bin/llama-server", "/usr/local/bin/llama-server"]

    private var processes: [Role: Process] = [:]

    /// Starts `role`'s server against `modelPath` if it isn't already
    /// reachable, and waits until it answers `/health` (or a timeout), so
    /// the first request doesn't race a cold process. Safe to call
    /// repeatedly — a no-op once running, and a second call while one is
    /// still starting waits on the same launch rather than spawning a
    /// duplicate.
    ///
    /// Switching `.chat` models (a different `modelPath` than what's already
    /// running), or changing `contextSize`, restarts the process —
    /// `llama-server` serves one model at one context length for its whole
    /// lifetime, there's no in-place swap of either. `contextSize` only
    /// matters for `.chat` (`Preferences.aiContextSize`); `.embed` passes its
    /// own fixed default since embedding requests are one short chunk at a
    /// time, never the long context a chat/RAG turn needs.
    func ensureRunning(_ role: Role, modelPath: URL, contextSize: Int = Preferences.aiDefaultContextSize) async -> Bool {
        if await isHealthy(role), currentModelPath[role] == modelPath, currentContextSize[role] == contextSize {
            return true
        }
        if currentModelPath[role] != modelPath || currentContextSize[role] != contextSize { stop(role) }
        if processes[role] != nil { return await waitUntilHealthy(role) }

        guard let binary = Self.locateBinary() else { return false }

        let launched = Process()
        launched.executableURL = URL(fileURLWithPath: binary)
        launched.arguments = [
            "-m", modelPath.path, "--port", String(role.port), "--ctx-size", String(contextSize),
        ] + role.extraArguments
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
        return await waitUntilHealthy(role)
    }

    /// Tracks which model (and context size) each role's currently-running
    /// process was started with, so `ensureRunning` knows to restart rather
    /// than reuse when the user switches `Preferences.aiModel` or
    /// `Preferences.aiContextSize`.
    private var currentModelPath: [Role: URL] = [:]
    private var currentContextSize: [Role: Int] = [:]

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
