import XCTest
@testable import PUPSISPortal

/// Real, on-device MLX generation — not the mocked-`send` unit tests
/// `LlamaCppClientTests` covers. Needs an actual downloaded Qwen3.5 model
/// and a working Metal shader library, so it can only run through
/// `xcodebuild test` (`swift test`, plain SwiftPM CLI, cannot build
/// mlx-swift's Metal shaders at all — see mlx-swift/README.md's own
/// "SwiftPM (command line) cannot build the Metal shaders" note, and
/// `Scripts/make_mac_app.sh`'s matching comment). Skips rather than fails
/// when the model isn't present, so it's harmless in CI or on a machine
/// that hasn't downloaded a Qwen3.5 model yet — this is a real-hardware
/// smoke test, not a correctness gate.
final class MLXBackendDebugTests: XCTestCase {
    func testGeneratesOnRealDownloadedWeights() async throws {
        // Opt-in only — a plain `swift test` run on a machine that already
        // has Qwen3.5-2B downloaded would otherwise hit the exact same
        // "cannot build Metal shaders" crash this file exists to catch,
        // turning every ordinary local test run into a crash the moment the
        // model happens to be present. `xcodebuild test` is what actually
        // exercises this correctly; set this var by hand when doing that.
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["PUPSISPORTAL_RUN_MLX_TESTS"] == "1",
            "set PUPSISPORTAL_RUN_MLX_TESTS=1 and run via `xcodebuild test` — plain `swift test` cannot build mlx-swift's Metal shaders"
        )
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/PUPSISPortal/models/models/mlx-community/Qwen3.5-2B-4bit")
        try XCTSkipUnless(
            FileManager.default.fileExists(atPath: directory.appendingPathComponent("config.json").path),
            "Qwen3.5-2B not downloaded — run via xcodebuild test after Settings ▸ AI downloads it"
        )

        try await MLXBackend.shared.ensureLoaded(directory: directory)

        let body = try LlamaCppClient.requestBody(selection: "Say hello in exactly three words.", maxTokens: 60)
        let (data, code) = try await MLXBackend.shared.send(body)
        XCTAssertEqual(code, 200)
        XCTAssertFalse(try LlamaCppClient.parseContent(data).isEmpty)
    }
}
