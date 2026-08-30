import XCTest
@testable import PUPSISPortal

/// `entriesToAdopt` is the pure decision half of `adoptBundledModels()` — the
/// same split `LlamaServerManagerTests` uses for `locateBinary`'s
/// candidates/isExecutable seam, so this stays testable without touching a
/// real bundle or Application Support.
final class ModelCatalogTests: XCTestCase {
    private let bundleDir = URL(fileURLWithPath: "/fake-bundle/Contents/Resources/models")

    func testAdoptsAnEntryThatsBundledButNotYetDownloaded() {
        let toAdopt = ModelCatalog.entriesToAdopt(from: bundleDir, fileExists: { path in
            // Only the bundled copy exists — nothing downloaded yet.
            path == bundleDir.appendingPathComponent(ModelCatalog.entries[0].filename).path
        })
        XCTAssertEqual(toAdopt.count, 1)
        XCTAssertEqual(toAdopt[0].destination, ModelCatalog.localURL(for: ModelCatalog.entries[0]))
    }

    func testSkipsAnEntryAlreadyDownloaded() {
        let toAdopt = ModelCatalog.entriesToAdopt(from: bundleDir, fileExists: { path in
            path == ModelCatalog.localURL(for: ModelCatalog.entries[0]).path
        })
        XCTAssertTrue(toAdopt.isEmpty, "already downloaded — must not re-adopt over it")
    }

    func testSkipsAnEntryWithNothingBundled() {
        // The lite build's shape: nothing exists anywhere.
        let toAdopt = ModelCatalog.entriesToAdopt(from: bundleDir, fileExists: { _ in false })
        XCTAssertTrue(toAdopt.isEmpty)
    }

    func testCoversBothTheChatEntryAndTheFixedEmbedModel() {
        let toAdopt = ModelCatalog.entriesToAdopt(from: bundleDir, fileExists: { path in
            path.hasPrefix(bundleDir.path)
        })
        let filenames = Set(toAdopt.map { $0.source.lastPathComponent })
        XCTAssertEqual(filenames, Set(ModelCatalog.entries.map(\.filename) + [ModelCatalog.embedModel.filename]))
    }

    // MARK: kvCacheBytesPerToken / estimatedRAMBytes — previously untested,
    // so a future edit (e.g. changing LlamaServerManager's cache-type
    // flags without updating these) went silently wrong. Locks in the
    // q8_0 figures: LlamaServerManager launches with --cache-type-k/v
    // q8_0 (1 byte/element), not llama.cpp's fp16 default (2 bytes).

    func testQwen3KVCacheBytesPerTokenMatchesTheQ8_0FormulaNotFP16() {
        // 2 (K+V) * 28 layers * 8 KV heads (GQA) * 128 head_dim * 1 byte
        // (q8_0) = 57,344 — half the old fp16 figure (114,688).
        XCTAssertEqual(ModelCatalog.entries[0].kvCacheBytesPerToken, 57_344)
    }

    func testEmbedModelKVCacheBytesPerTokenMatchesTheQ8_0Formula() {
        // 2 * 12 layers * 12 heads * 64 head_dim * 1 byte (q8_0) = 18,432.
        XCTAssertEqual(ModelCatalog.embedModel.kvCacheBytesPerToken, 18_432)
    }

    func testEstimatedRAMBytesAtTheDefaultContextSize() {
        let entry = ModelCatalog.entries[0]
        let expected = entry.sizeBytes + entry.kvCacheBytesPerToken * Int64(Preferences.aiDefaultContextSize) + 512 * 1024 * 1024
        XCTAssertEqual(ModelCatalog.estimatedRAMBytes(for: entry, contextSize: Preferences.aiDefaultContextSize), expected)
    }

    /// The whole point of quantizing the KV cache: raising context size no
    /// longer costs 1:1 what it used to at fp16.
    func testEstimatedRAMBytesGrowthPerContextTokenMatchesQ8_0NotFP16() {
        let entry = ModelCatalog.entries[0]
        let delta = ModelCatalog.estimatedRAMBytes(for: entry, contextSize: 2000)
            - ModelCatalog.estimatedRAMBytes(for: entry, contextSize: 1000)
        XCTAssertEqual(delta, 57_344 * 1000)
    }
}
