import XCTest
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
@testable import PUPSISPortal

/// W8 (security): none of this ever spawns a real `llama-server` or touches
/// the network for real. `register`/`stop`/`isHealthy`/`verifyOwnership` are
/// internal (not private) specifically so this suite can drive them with a
/// harmless stand-in `Process` (`/bin/sh`) and a fake `probe` closure —
/// exercising the free-port/API-key-file/ownership-check/termination-
/// clearing/bounded-stop logic without the real binary or a real model.
@MainActor
final class LlamaServerManagerTests: XCTestCase {

    // MARK: locateBinary — unchanged from before this fix

    func testPicksTheFirstExistingCandidate() {
        let found = LlamaServerManager.locateBinary(
            candidates: ["/nowhere/llama-server", "/opt/homebrew/bin/llama-server", "/usr/local/bin/llama-server"],
            isExecutable: { $0 == "/opt/homebrew/bin/llama-server" }
        )
        XCTAssertEqual(found, "/opt/homebrew/bin/llama-server")
    }

    func testReturnsNilWhenNoneExist() {
        let found = LlamaServerManager.locateBinary(
            candidates: ["/nowhere/llama-server", "/also-nowhere/llama-server"],
            isExecutable: { _ in false }
        )
        XCTAssertNil(found)
    }

    func testChecksCandidatesInOrder() {
        var checked: [String] = []
        _ = LlamaServerManager.locateBinary(
            candidates: ["/a", "/b", "/c"],
            isExecutable: { checked.append($0); return $0 == "/b" }
        )
        XCTAssertEqual(checked, ["/a", "/b"], "must stop at the first match rather than checking every candidate")
    }

    // MARK: pickFreePort — a real (but harmless) socket op, no llama-server involved

    func testPickFreePortReturnsAPortInTheEphemeralRange() throws {
        let port = try XCTUnwrap(LlamaServerManager.pickFreePort())
        XCTAssertGreaterThan(port, 0)
        XCTAssertLessThanOrEqual(port, 65535)
    }

    func testPickFreePortCanBeRebound() throws {
        // The whole point: the port is released (not left open) so
        // llama-server can bind it a moment later.
        let port = try XCTUnwrap(LlamaServerManager.pickFreePort())
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        defer { close(fd) }
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = UInt16(port).bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        let result = withUnsafePointer(to: &addr) { pointer -> Int32 in
            // Darwin.bind, qualified: XCTestCase inherits NSObject, whose
            // Cocoa-bindings `bind(_:to:withKeyPath:options:)` otherwise
            // shadows the global socket `bind` here (only in this test
            // class — LlamaServerManager itself isn't an NSObject).
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        XCTAssertEqual(result, 0, "pickFreePort must close its probe socket, not hold the port open")
    }

    // MARK: generateAPIKey — never a fixed/shared key

    func testGenerateAPIKeyIsHexOfTheRequestedLength() {
        let key = LlamaServerManager.generateAPIKey(byteCount: 24)
        XCTAssertEqual(key.count, 48)
        XCTAssertTrue(key.allSatisfy { $0.isHexDigit })
    }

    func testGenerateAPIKeyDiffersEveryCall() {
        XCTAssertNotEqual(LlamaServerManager.generateAPIKey(), LlamaServerManager.generateAPIKey())
    }

    // MARK: writeAPIKeyFile / removeAPIKeyFile — the key never touches argv

    func testWriteAPIKeyFileWritesThePrivateFileWithTheExactKey() throws {
        let file = try LlamaServerManager.writeAPIKeyFile("deadbeef-test-key")
        addTeardownBlock { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }

        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "deadbeef-test-key")
        let permissions = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600, "the key file must be 0600 — private to this user only")
    }

    func testWriteAPIKeyFileUsesAFreshDirectoryEveryCall() throws {
        let first = try LlamaServerManager.writeAPIKeyFile("a")
        let second = try LlamaServerManager.writeAPIKeyFile("b")
        addTeardownBlock {
            try? FileManager.default.removeItem(at: first.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: second.deletingLastPathComponent())
        }
        XCTAssertNotEqual(first.deletingLastPathComponent(), second.deletingLastPathComponent())
    }

    // MARK: launchArguments — never the old fixed 8080/8081, never the raw key, always our host/port/key-file

    func testLaunchArgumentsCarryThePickedPortAndKeyFileNotAFixedPortOrTheRawKey() {
        let args = LlamaServerManager.launchArguments(
            role: .chat, modelPath: URL(fileURLWithPath: "/models/Qwen3-1.7B-Q4_K_M.gguf"),
            port: 54321, apiKeyFile: URL(fileURLWithPath: "/tmp/fake-key-dir/key"),
            contextSize: 4096, kvQuantized: true, useGPU: true
        )
        XCTAssertEqual(Self.value(after: "--port", in: args), "54321")
        XCTAssertEqual(Self.value(after: "--api-key-file", in: args), "/tmp/fake-key-dir/key")
        XCTAssertFalse(args.contains("--api-key"), "the key itself must never be a bare argv entry — that's the whole point of --api-key-file")
        XCTAssertFalse(args.contains("8080"), "must never fall back to the old hardcoded chat port")
    }

    func testLaunchArgumentsAlwaysPassAnExplicitLoopbackHost() {
        let args = LlamaServerManager.launchArguments(
            role: .chat, modelPath: URL(fileURLWithPath: "/m.gguf"),
            port: 1, apiKeyFile: URL(fileURLWithPath: "/tmp/k"),
            contextSize: 4096, kvQuantized: true, useGPU: true
        )
        XCTAssertEqual(Self.value(after: "--host", in: args), "127.0.0.1")
    }

    func testLaunchArgumentsOmitCacheQuantizationFlagsWhenDisabled() {
        let args = LlamaServerManager.launchArguments(
            role: .chat, modelPath: URL(fileURLWithPath: "/m.gguf"),
            port: 1, apiKeyFile: URL(fileURLWithPath: "/tmp/k"),
            contextSize: 4096, kvQuantized: false, useGPU: true
        )
        XCTAssertFalse(args.contains("--cache-type-k"))
    }

    func testLaunchArgumentsAddCPUOnlyFlagWhenGPUDisabled() {
        let args = LlamaServerManager.launchArguments(
            role: .embed, modelPath: URL(fileURLWithPath: "/m.gguf"),
            port: 1, apiKeyFile: URL(fileURLWithPath: "/tmp/k"),
            contextSize: 2048, kvQuantized: true, useGPU: false
        )
        XCTAssertEqual(Self.value(after: "-ngl", in: args), "0")
        XCTAssertTrue(args.contains("--embedding"), "role.extraArguments must still be appended")
    }

    private static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    // MARK: propsMatchExpectedModel — the ownership check's pure core

    func testPropsMatchExpectedModelWhenFilenamesAgree() {
        let json = Data(#"{"model_path":"/Users/me/Library/Application Support/PUPSISPortal/models/Qwen3-1.7B-Q4_K_M.gguf"}"#.utf8)
        XCTAssertTrue(LlamaServerManager.propsMatchExpectedModel(json, expectedFilename: "Qwen3-1.7B-Q4_K_M.gguf"))
    }

    func testPropsMatchExpectedModelRejectsADifferentModel() {
        // The exact scenario W8 exists for: something else is listening on
        // this port/answering our probe, serving a different model.
        let json = Data(#"{"model_path":"/opt/homebrew/models/some-other-model.gguf"}"#.utf8)
        XCTAssertFalse(LlamaServerManager.propsMatchExpectedModel(json, expectedFilename: "Qwen3-1.7B-Q4_K_M.gguf"))
    }

    func testPropsMatchExpectedModelRejectsMalformedJSON() {
        XCTAssertFalse(LlamaServerManager.propsMatchExpectedModel(Data("not json".utf8), expectedFilename: "x.gguf"))
    }

    // MARK: isHealthy / verifyOwnership — the async decision logic, via a fake probe

    private func fakeProcess(_ arguments: [String]) throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = arguments
        try process.run()
        return process
    }

    func testVerifyOwnershipTrueWhenProcessAliveAndPropsMatch() async throws {
        let modelPath = URL(fileURLWithPath: "/models/Qwen3-1.7B-Q4_K_M.gguf")
        let process = try fakeProcess(["-c", "sleep 5"])
        defer { process.terminate() }
        let manager = LlamaServerManager(probe: { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
            let json = Data(#"{"model_path":"\#(modelPath.path)"}"#.utf8)
            return (json, 200)
        })
        manager.register(
            .chat, process: process, port: 41111, apiKey: "test-key", modelPath: modelPath,
            contextSize: 4096, kvQuantized: true, useGPU: true
        )
        let ok = await manager.verifyOwnership(.chat)
        XCTAssertTrue(ok)
    }

    func testVerifyOwnershipFalseWhenPropsReportADifferentModel() async throws {
        // A foreign/orphaned process happens to be listening on our picked
        // port and answers 200 — must still be rejected.
        let modelPath = URL(fileURLWithPath: "/models/Qwen3-1.7B-Q4_K_M.gguf")
        let process = try fakeProcess(["-c", "sleep 5"])
        defer { process.terminate() }
        let manager = LlamaServerManager(probe: { _ in
            (Data(#"{"model_path":"/somewhere/unrelated.gguf"}"#.utf8), 200)
        })
        manager.register(
            .chat, process: process, port: 41112, apiKey: "test-key", modelPath: modelPath,
            contextSize: 4096, kvQuantized: true, useGPU: true
        )
        let ok = await manager.verifyOwnership(.chat)
        XCTAssertFalse(ok)
    }

    func testVerifyOwnershipFalseWhenOurProcessAlreadyExited() async throws {
        let modelPath = URL(fileURLWithPath: "/models/Qwen3-1.7B-Q4_K_M.gguf")
        let process = try fakeProcess(["-c", "exit 0"])
        process.waitUntilExit()
        // A probe that would say yes if it were even consulted — proves the
        // isRunning check short-circuits before any network round trip.
        let manager = LlamaServerManager(probe: { _ in
            (Data(#"{"model_path":"\#(modelPath.path)"}"#.utf8), 200)
        })
        manager.register(
            .chat, process: process, port: 41113, apiKey: "test-key", modelPath: modelPath,
            contextSize: 4096, kvQuantized: true, useGPU: true
        )
        let ok = await manager.verifyOwnership(.chat)
        XCTAssertFalse(ok, "a process that already exited on its own must never be trusted, even if something answers on its old port")
    }

    func testIsHealthyFalseWhenNothingRegistered() async {
        let manager = LlamaServerManager(probe: { _ in XCTFail("must not probe when nothing is registered"); return (Data(), 200) })
        let ok = await manager.isHealthy(.chat)
        XCTAssertFalse(ok)
    }

    func testEnsureRunningReturnsTrueWithoutSpawningWhenAlreadyHealthyAndVerified() async throws {
        // The success path never touches locateBinary/Process() at all —
        // proves ensureRunning trusts an existing registration once both
        // isHealthy and verifyOwnership agree, exactly like production.
        let modelPath = URL(fileURLWithPath: "/models/Qwen3-1.7B-Q4_K_M.gguf")
        let process = try fakeProcess(["-c", "sleep 5"])
        defer { process.terminate() }
        let manager = LlamaServerManager(probe: { request in
            if request.url?.path == "/props" {
                return (Data(#"{"model_path":"\#(modelPath.path)"}"#.utf8), 200)
            }
            return (Data(), 200)
        })
        manager.register(
            .chat, process: process, port: 41114, apiKey: "test-key", modelPath: modelPath,
            contextSize: 4096, kvQuantized: true, useGPU: true
        )
        let ok = await manager.ensureRunning(.chat, modelPath: modelPath, contextSize: 4096, kvQuantized: true, useGPU: true)
        XCTAssertTrue(ok)
    }

    // MARK: register + termination handler — the "exited Process never cleared" fix

    func testRegisterClearsTheSlotWhenTheProcessExitsOnItsOwn() async throws {
        let manager = LlamaServerManager()
        let process = try fakeProcess(["-c", "exit 0"])
        manager.register(
            .chat, process: process, port: 41115, apiKey: "test-key",
            modelPath: URL(fileURLWithPath: "/m.gguf"), contextSize: 4096, kvQuantized: true, useGPU: true
        )
        XCTAssertNotNil(manager.endpoint(for: .chat))

        let deadline = Date().addingTimeInterval(3)
        while manager.endpoint(for: .chat) != nil, Date() < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertNil(manager.endpoint(for: .chat), "an exited process must clear itself, or ensureRunning would wait the full 30s health timeout against a corpse forever")
    }

    func testRegisterClearsTheAPIKeyFileWhenTheProcessExitsBeforeEverBecomingHealthy() async throws {
        // A crash during startup — before waitUntilHealthy's own cleanup
        // ever ran — must not leave the key file behind forever.
        let manager = LlamaServerManager()
        let process = try fakeProcess(["-c", "exit 1"])
        let keyFile = try LlamaServerManager.writeAPIKeyFile("test-key")
        manager.register(
            .chat, process: process, port: 41117, apiKey: "test-key", apiKeyFileURL: keyFile,
            modelPath: URL(fileURLWithPath: "/m.gguf"), contextSize: 4096, kvQuantized: true, useGPU: true
        )

        let deadline = Date().addingTimeInterval(3)
        while FileManager.default.fileExists(atPath: keyFile.path), Date() < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: keyFile.path), "an exited process must not leave its key file behind")
    }

    func testRegisterDoesNotClearANewerRelaunchWhenAnOldHandlerFiresLate() async throws {
        // Guards clearIfCurrent's identity check: stop()ping the old process
        // and registering a new one under the same role must not let the old
        // process's late-firing handler wipe the new registration.
        let manager = LlamaServerManager()
        let oldProcess = try fakeProcess(["-c", "sleep 5"])
        manager.register(
            .chat, process: oldProcess, port: 1, apiKey: "old",
            modelPath: URL(fileURLWithPath: "/old.gguf"), contextSize: 4096, kvQuantized: true, useGPU: true
        )
        await manager.stop(.chat) // clears oldProcess's handler before terminating it — see production comment

        let newProcess = try fakeProcess(["-c", "sleep 5"])
        defer { newProcess.terminate() }
        manager.register(
            .chat, process: newProcess, port: 2, apiKey: "new",
            modelPath: URL(fileURLWithPath: "/new.gguf"), contextSize: 4096, kvQuantized: true, useGPU: true
        )
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(manager.apiKey(for: .chat), "new", "a stale handler must never clobber a newer relaunch's registration")
    }

    // MARK: stop — async, bounded wait for actual exit, not a blocking busy-wait

    func testStopWaitsForActualExitAndClearsStateWithoutBlockingTheMainThread() async throws {
        // Regression: stop(_:) used to busy-wait with a blocking usleep on
        // @MainActor, freezing the whole UI for up to 2s per role. Proving
        // it no longer blocks: a concurrent Task on the same actor gets to
        // run interleaved with the wait, which a real thread-block couldn't
        // allow.
        let manager = LlamaServerManager()
        let process = try fakeProcess(["-c", "sleep 30"])
        manager.register(
            .chat, process: process, port: 41116, apiKey: "test-key",
            modelPath: URL(fileURLWithPath: "/m.gguf"), contextSize: 4096, kvQuantized: true, useGPU: true
        )

        let interleaved = Counter()
        let ticker = Task { @MainActor in
            while !Task.isCancelled {
                await interleaved.increment()
                try? await Task.sleep(for: .milliseconds(10))
            }
        }

        let start = Date()
        await manager.stop(.chat)
        let elapsed = Date().timeIntervalSince(start)
        ticker.cancel()

        XCTAssertFalse(process.isRunning, "stop() must actually wait for the SIGTERM to take effect, not just fire terminate() and return")
        XCTAssertLessThan(elapsed, 3, "the wait must be bounded")
        XCTAssertNil(manager.endpoint(for: .chat))
        let ticks = await interleaved.value
        XCTAssertGreaterThan(ticks, 0, "another @MainActor task must be able to run while stop() waits — proves it yields instead of blocking")
    }

    func testStopDeletesTheAPIKeyFile() async throws {
        let manager = LlamaServerManager()
        let process = try fakeProcess(["-c", "sleep 30"])
        let keyFile = try LlamaServerManager.writeAPIKeyFile("test-key")
        manager.register(
            .chat, process: process, port: 41118, apiKey: "test-key", apiKeyFileURL: keyFile,
            modelPath: URL(fileURLWithPath: "/m.gguf"), contextSize: 4096, kvQuantized: true, useGPU: true
        )
        await manager.stop(.chat)
        XCTAssertFalse(FileManager.default.fileExists(atPath: keyFile.path))
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: keyFile.deletingLastPathComponent().path),
            "the whole per-launch key directory must go, not just the file"
        )
    }

    func testStopOnAnUnregisteredRoleIsANoOp() async {
        let manager = LlamaServerManager()
        await manager.stop(.embed) // must not crash/hang with nothing registered
        XCTAssertNil(manager.endpoint(for: .embed))
    }

    // MARK: terminateWithoutWaiting — the app-quit path, fire-and-forget

    func testTerminateWithoutWaitingSignalsEveryRunningRoleAndClearsState() throws {
        let manager = LlamaServerManager()
        let chatProcess = try fakeProcess(["-c", "sleep 30"])
        let embedProcess = try fakeProcess(["-c", "sleep 30"])
        manager.register(
            .chat, process: chatProcess, port: 1, apiKey: "a",
            modelPath: URL(fileURLWithPath: "/m.gguf"), contextSize: 4096, kvQuantized: true, useGPU: true
        )
        manager.register(
            .embed, process: embedProcess, port: 2, apiKey: "b",
            modelPath: URL(fileURLWithPath: "/e.gguf"), contextSize: 4096, kvQuantized: true, useGPU: true
        )

        let start = Date()
        manager.terminateWithoutWaiting()
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertLessThan(elapsed, 0.5, "must return immediately — no waiting for exit at app quit")
        XCTAssertNil(manager.endpoint(for: .chat))
        XCTAssertNil(manager.endpoint(for: .embed))
        // The SIGTERM was still sent even though we didn't wait for it.
        Thread.sleep(forTimeInterval: 0.3)
        XCTAssertFalse(chatProcess.isRunning)
        XCTAssertFalse(embedProcess.isRunning)
    }
}

private actor Counter {
    private(set) var value = 0
    func increment() { value += 1 }
}
