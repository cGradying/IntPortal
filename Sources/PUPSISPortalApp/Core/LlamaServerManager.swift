import Foundation

/// Owns `llama-server`'s lifecycle so `ask_notes` never depends on the user
/// having started it by hand in a terminal, and so it never outlives the app.
/// Before this existed, nothing in the app had any relationship with the
/// process — confirmed a hand-started one still running with the app fully
/// quit. `.shared`, matching `Notifier.shared`'s existing precedent for a
/// process-wide owned resource.
@MainActor
final class LlamaServerManager {
    static let shared = LlamaServerManager()

    private static let healthURL = URL(string: "http://127.0.0.1:8080/health")!
    /// The one model `ask_notes`/`LlamaCppClient` is built against — not a
    /// setting, since there's exactly one caller and one job.
    private static let model = "LiquidAI/LFM2-1.2B-RAG-GGUF"
    private static let binaryCandidates = ["/opt/homebrew/bin/llama-server", "/usr/local/bin/llama-server"]

    private var process: Process?

    /// Starts the server if it isn't already reachable, and waits until it
    /// answers `/health` (or a timeout), so the first `ask_notes` call
    /// doesn't race a cold process. Safe to call repeatedly — a no-op once
    /// running, and a second call while one is still starting waits on the
    /// same launch rather than spawning a duplicate.
    func ensureRunning() async -> Bool {
        if await isHealthy() { return true }
        if process != nil { return await waitUntilHealthy() }

        guard let binary = Self.locateBinary() else { return false }

        let launched = Process()
        launched.executableURL = URL(fileURLWithPath: binary)
        launched.arguments = ["-hf", Self.model]
        launched.standardOutput = FileHandle.nullDevice
        launched.standardError = FileHandle.nullDevice

        do {
            try launched.run()
        } catch {
            return false
        }
        process = launched
        return await waitUntilHealthy()
    }

    /// Clean SIGTERM — llama-server shuts down on it. Called when AI is
    /// toggled off and when the app quits (`AppState`'s termination observer).
    func stop() {
        process?.terminate()
        process = nil
    }

    private func isHealthy() async -> Bool {
        var request = URLRequest(url: Self.healthURL)
        request.timeoutInterval = 2
        guard let (_, response) = try? await URLSession.shared.data(for: request) else { return false }
        return (response as? HTTPURLResponse)?.statusCode == 200
    }

    private func waitUntilHealthy(timeout: TimeInterval = 30) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await isHealthy() { return true }
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
