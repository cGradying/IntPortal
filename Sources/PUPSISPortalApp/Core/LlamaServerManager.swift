import Foundation
import Security
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Owns both `llama-server` processes' lifecycle — the `.chat` role
/// (assistant/tools/quiz/note-help) and the `.embed` role (note search) — so
/// nothing in the app depends on the user having started them by hand in a
/// terminal, and neither outlives the app. One binary, two roles, two local
/// GGUF files (`ModelCatalog`); `.shared`, matching `Notifier.shared`'s
/// existing precedent for a process-wide owned resource.
///
/// **W8 (security):** each launch gets its own free loopback port and a
/// random per-launch `--api-key`, never a fixed 8080/8081 that an orphaned
/// or unrelated process could already be squatting on. A bare HTTP 200 from
/// `/health` is never trusted by itself — `waitUntilHealthy` also checks
/// `/props` (with our own key, which nothing else knows) reports the exact
/// model file we launched, and that the `Process` we hold is still the one
/// actually alive on that port, before anything is allowed to send it the
/// student's schedule/grades/notes.
@MainActor
final class LlamaServerManager {
    static let shared = LlamaServerManager()

    enum Role {
        case chat
        case embed

        /// The OpenAI-compatible path `LlamaCppClient` posts to for this role.
        var apiPath: String {
            switch self {
            case .chat: "v1/chat/completions"
            case .embed: "v1/embeddings"
            }
        }

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

    /// Everything about one role's currently-launched process — replaces
    /// what used to be four parallel dictionaries keyed by `Role`. Holding
    /// the actual `Process` is what lets `verifyOwnership` answer "is this
    /// really ours" without any network round trip: `process.isRunning` is
    /// the OS telling us our own child is still alive, no server response
    /// can spoof that.
    private struct RunningServer {
        let process: Process
        let port: Int
        let apiKey: String
        let modelPath: URL
        let contextSize: Int
        let kvQuantized: Bool
        let useGPU: Bool
    }

    private var running: [Role: RunningServer] = [:]

    /// The network transport `isHealthy`/`verifyOwnership` send through —
    /// injectable so tests can fake `/health`/`/props` responses without a
    /// real `llama-server` (or any network at all). Defaults to a plain
    /// `URLSession` request.
    private let probe: (URLRequest) async throws -> (Data, Int)

    init(probe: @escaping (URLRequest) async throws -> (Data, Int) = LlamaServerManager.realProbe) {
        self.probe = probe
    }

    private static func realProbe(_ request: URLRequest) async throws -> (Data, Int) {
        let (data, response) = try await URLSession.shared.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    /// Starts `role`'s server against `modelPath` if it isn't already
    /// reachable, and waits until it answers `/health` *and* proves it's our
    /// process serving our model (or a timeout), so the first request
    /// doesn't race a cold process — or a stranger's. Safe to call
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
        if let server = running[role], server.modelPath == modelPath, server.contextSize == contextSize,
           server.kvQuantized == kvQuantized, server.useGPU == useGPU,
           await isHealthy(role), await verifyOwnership(role) {
            return true
        }
        if let server = running[role],
           server.modelPath != modelPath || server.contextSize != contextSize
            || server.kvQuantized != kvQuantized || server.useGPU != useGPU {
            stop(role)
        }
        if running[role] != nil { return await waitUntilHealthy(role) }

        guard let binary = Self.locateBinary() else { return false }
        guard let port = Self.pickFreePort() else { return false }
        let apiKey = Self.generateAPIKey()
        let arguments = Self.launchArguments(
            role: role, modelPath: modelPath, port: port, apiKey: apiKey,
            contextSize: contextSize, kvQuantized: kvQuantized, useGPU: useGPU
        )

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
        register(
            role, process: launched, port: port, apiKey: apiKey, modelPath: modelPath,
            contextSize: contextSize, kvQuantized: kvQuantized, useGPU: useGPU
        )
        return await waitUntilHealthy(role)
    }

    /// Registers `process` (already `run()`) as `role`'s current server and
    /// arms the termination handler that clears it if the process exits on
    /// its own — a crash, an OOM kill, `killall llama-server` from a
    /// terminal — rather than only on an intentional `stop()`. Without this,
    /// an exited `Process` stayed in the table forever, and `ensureRunning`
    /// would take the "already running, just wait for health" branch on
    /// every future call, failing the full 30s timeout every single time
    /// instead of noticing the process is dead and launching a fresh one.
    /// Internal, not private: `LlamaServerManagerTests` calls this directly
    /// with a harmless stand-in process (never a real `llama-server`) to
    /// exercise the clearing behavior without spawning the real binary.
    func register(
        _ role: Role, process: Process, port: Int, apiKey: String, modelPath: URL,
        contextSize: Int, kvQuantized: Bool, useGPU: Bool
    ) {
        process.terminationHandler = { [weak self] finished in
            Task { @MainActor in self?.clearIfCurrent(role, process: finished) }
        }
        running[role] = RunningServer(
            process: process, port: port, apiKey: apiKey, modelPath: modelPath,
            contextSize: contextSize, kvQuantized: kvQuantized, useGPU: useGPU
        )
    }

    /// Only clears `role`'s slot if `process` is still the one registered —
    /// guards against a late-firing handler from an old, already-`stop()`ed
    /// process clobbering a newer relaunch's state.
    private func clearIfCurrent(_ role: Role, process: Process) {
        guard running[role]?.process === process else { return }
        running[role] = nil
    }

    /// Where `LlamaCppClient` sends `role`'s requests — `nil` when nothing is
    /// running for it, so the client fails with a clear "offline" error
    /// rather than guessing a URL.
    func endpoint(for role: Role) -> URL? {
        guard let port = running[role]?.port else { return nil }
        return URL(string: "http://127.0.0.1:\(port)/\(role.apiPath)")
    }

    /// The bearer token `LlamaCppClient` must send with `role`'s requests —
    /// the same one this launch passed `llama-server` via `--api-key`.
    func apiKey(for role: Role) -> String? { running[role]?.apiKey }

    /// Clean SIGTERM, then a bounded wait for actual exit — llama-server
    /// shuts down on it, but the old fire-and-forget `terminate()` returned
    /// immediately, so a caller that spawns right after quitting couldn't
    /// tell whether the port was really free yet. Called when AI is toggled
    /// off and when the app quits (`AppState`'s termination observer).
    func stop() {
        stop(.chat)
        stop(.embed)
    }

    /// Bounded wait timeout for `stop(_:)` — generous enough for a clean
    /// SIGTERM shutdown, short enough that app quit / toggling AI off never
    /// hangs the main thread noticeably.
    private static let stopWaitTimeout: TimeInterval = 2

    /// Internal, not private, so `LlamaServerManagerTests` can drive it
    /// directly against a registered stand-in process.
    func stop(_ role: Role) {
        guard let server = running.removeValue(forKey: role) else { return }
        // Clear the handler first — this is the intentional-stop path, no
        // need for it to also fire and race clearIfCurrent a second time.
        server.process.terminationHandler = nil
        guard server.process.isRunning else { return }
        server.process.terminate()
        let deadline = Date().addingTimeInterval(Self.stopWaitTimeout)
        while server.process.isRunning, Date() < deadline {
            usleep(50_000)
        }
    }

    /// Internal, not private, so `LlamaServerManagerTests` can exercise the
    /// health/ownership decision logic directly against a registered
    /// stand-in process and a fake `probe`, without racing `waitUntilHealthy`'s
    /// 30s loop on the failure path.
    func isHealthy(_ role: Role) async -> Bool {
        guard let server = running[role] else { return false }
        guard let (_, code) = try? await probe(Self.request(path: "health", server: server)) else { return false }
        return code == 200
    }

    /// The belt-and-suspenders half of W8: a 200 from `/health` alone proves
    /// *something* is listening on the port we picked, not that it's the
    /// `llama-server` we launched with the model we expect. `process.isRunning`
    /// confirms our own child is still alive (no network round trip can spoof
    /// this); `/props`, sent with our own per-launch key, confirms it's
    /// reporting the exact GGUF file we started it with. Internal, not
    /// private — see `isHealthy`'s own note on why.
    func verifyOwnership(_ role: Role) async -> Bool {
        guard let server = running[role], server.process.isRunning else { return false }
        guard let (data, code) = try? await probe(Self.request(path: "props", server: server)), code == 200 else {
            return false
        }
        return Self.propsMatchExpectedModel(data, expectedFilename: server.modelPath.lastPathComponent)
    }

    private static func request(path: String, server: RunningServer) -> URLRequest {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(server.port)/\(path)")!)
        request.timeoutInterval = 2
        request.setValue("Bearer \(server.apiKey)", forHTTPHeaderField: "Authorization")
        return request
    }

    /// Pure so it's directly testable against fixture JSON — llama-server's
    /// `/props` reports the loaded GGUF as `model_path`, the full path we
    /// passed via `-m`. Compares just the filename rather than the whole
    /// path since `modelPath` here is our own catalog-derived URL, and
    /// llama.cpp may report it resolved/normalized.
    static func propsMatchExpectedModel(_ data: Data, expectedFilename: String) -> Bool {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let modelPath = json["model_path"] as? String
        else { return false }
        return URL(fileURLWithPath: modelPath).lastPathComponent == expectedFilename
    }

    private func waitUntilHealthy(_ role: Role, timeout: TimeInterval = 30) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await isHealthy(role), await verifyOwnership(role) { return true }
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

    /// The launch arguments for `role` — pure so the port/API-key wiring is
    /// directly assertable in a test without spawning anything. Never a
    /// hardcoded `--port 8080`/`8081`.
    static func launchArguments(
        role: Role, modelPath: URL, port: Int, apiKey: String,
        contextSize: Int, kvQuantized: Bool, useGPU: Bool
    ) -> [String] {
        var arguments = [
            "-m", modelPath.path, "--port", String(port), "--api-key", apiKey,
            "--ctx-size", String(contextSize),
        ]
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
        return arguments
    }

    /// A random per-launch bearer token so only this app — never an orphaned
    /// prior launch, nor an unrelated process someone else started on the
    /// same port — can be mistaken for the server we just spawned. 24 bytes
    /// (48 hex chars) from the system CSPRNG.
    static func generateAPIKey(byteCount: Int = 24) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed: \(status)")
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    /// Binds a TCP socket to 127.0.0.1:0 (the OS assigns a free ephemeral
    /// port), reads that port back, then closes the socket so `llama-server`
    /// can bind it — the standard "find a free port" trick. There is an
    /// inherent, unavoidable TOCTOU race between the close here and
    /// `llama-server`'s own bind a moment later; combined with the
    /// per-launch API key and `/props` ownership check above, a collision
    /// landing on an unrelated listener is caught rather than trusted blindly.
    /// ponytail: no retry-on-EADDRINUSE loop — a second port collision in the
    /// same launch is vanishingly unlikely on loopback; add one if it's ever
    /// observed in practice.
    static func pickFreePort() -> Int? {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")

        let bindResult = withUnsafePointer(to: &addr) { pointer -> Int32 in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                bind(fd, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else { return nil }

        var actual = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &actual) { pointer -> Int32 in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                getsockname(fd, sockaddrPointer, &length)
            }
        }
        guard nameResult == 0 else { return nil }
        return Int(UInt16(bigEndian: actual.sin_port))
    }
}
