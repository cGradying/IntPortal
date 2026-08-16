import XCTest
@testable import PUPSISPortal

/// `locateBinary` is the only pure sliver of `LlamaServerManager` — the
/// actual `Process`/health-check loop is integration-only, the same boundary
/// the rest of this app draws around AppKit/IO glue.
@MainActor
final class LlamaServerManagerTests: XCTestCase {
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
}
