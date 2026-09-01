import XCTest
@testable import PUPSISPortal

/// `entriesToAdopt` is the pure decision half of `adoptBundledModels()` — the
/// same split `LlamaServerManagerTests` uses for `locateBinary`'s
/// candidates/isExecutable seam, so this stays testable without touching a
/// real bundle or Application Support.
final class ModelCatalogTests: XCTestCase {
    private let bundleDir = URL(fileURLWithPath: "/fake-bundle/Contents/Resources/models")

    /// `entries[2]` — the one `.gguf` entry, a single downloadable file.
    /// `entries[0]`/`[1]` are `.mlx` (a whole repo directory) and don't fit
    /// this file's "bundled but not yet downloaded" fixture the same way.
    private var ggufEntry: ModelCatalog.Entry { ModelCatalog.entries[2] }

    func testAdoptsAnEntryThatsBundledButNotYetDownloaded() {
        let toAdopt = ModelCatalog.entriesToAdopt(from: bundleDir, fileExists: { path in
            // Only the bundled copy exists — nothing downloaded yet.
            path == bundleDir.appendingPathComponent(ModelCatalog.localURL(for: ggufEntry).lastPathComponent).path
        })
        XCTAssertEqual(toAdopt.count, 1)
        XCTAssertEqual(toAdopt[0].destination, ModelCatalog.localURL(for: ggufEntry))
    }

    func testSkipsAnEntryAlreadyDownloaded() {
        let toAdopt = ModelCatalog.entriesToAdopt(from: bundleDir, fileExists: { path in
            path == ModelCatalog.localURL(for: ggufEntry).path
        })
        XCTAssertTrue(toAdopt.isEmpty, "already downloaded — must not re-adopt over it")
    }

    func testSkipsAnEntryWithNothingBundled() {
        // The lite build's shape: nothing exists anywhere.
        let toAdopt = ModelCatalog.entriesToAdopt(from: bundleDir, fileExists: { _ in false })
        XCTAssertTrue(toAdopt.isEmpty)
    }

    func testCoversEveryEntryAndTheFixedEmbedModel() {
        let toAdopt = ModelCatalog.entriesToAdopt(from: bundleDir, fileExists: { path in
            path.hasPrefix(bundleDir.path)
        })
        let sources = Set(toAdopt.map { $0.source.lastPathComponent })
        var expected: Set<String> = ["Qwen3.5-0.8B-4bit", "Qwen3.5-2B-4bit"]
        expected.insert(ggufEntry.kind.gguf!.filename)
        expected.insert(ModelCatalog.embedModel.kind.gguf!.filename)
        XCTAssertEqual(sources, expected)
    }

    // MARK: kvCacheBytesPerToken / estimatedRAMBytes — previously untested,
    // so a future edit (e.g. changing LlamaServerManager's cache-type
    // flags without updating these) went silently wrong. Locks in the
    // q8_0 figures: the `.gguf` runtime launches with --cache-type-k/v
    // q8_0 (1 byte/element), not llama.cpp's fp16 default (2 bytes);
    // `MLXBackend` passes the equivalent `kvBits: 8` for `.mlx` entries.

    func testQwen3KVCacheBytesPerTokenMatchesTheQ8_0FormulaNotFP16() {
        // 2 (K+V) * 28 layers * 8 KV heads (GQA) * 128 head_dim * 1 byte
        // (q8_0) = 57,344 — half the old fp16 figure (114,688).
        XCTAssertEqual(ggufEntry.kvCacheBytesPerToken, 57_344)
    }

    func testQwen35KVCacheBytesPerTokenCountsOnlyFullAttentionLayers() {
        // Hybrid Gated-DeltaNet architecture: only 6 of 24 layers are full
        // attention (num_key_value_heads 2, head_dim 256); the other 18 are
        // linear-attention layers whose fixed-size recurrent state doesn't
        // grow with context. 2 (K+V) * 6 * 2 * 256 * 1 byte (q8_0) = 6,144.
        // Both Qwen3.5 sizes share this figure (only hidden_size scales).
        XCTAssertEqual(ModelCatalog.entries[0].kvCacheBytesPerToken, 6_144)
        XCTAssertEqual(ModelCatalog.entries[1].kvCacheBytesPerToken, 6_144)
    }

    func testEstimatedRAMBytesAtTheDefaultContextSize() {
        let entry = ggufEntry
        let expected = entry.sizeBytes + entry.kvCacheBytesPerToken * Int64(Preferences.aiDefaultContextSize) + 512 * 1024 * 1024
        XCTAssertEqual(ModelCatalog.estimatedRAMBytes(for: entry, contextSize: Preferences.aiDefaultContextSize), expected)
    }

    /// The whole point of quantizing the KV cache: raising context size no
    /// longer costs 1:1 what it used to at fp16.
    func testEstimatedRAMBytesGrowthPerContextTokenMatchesQ8_0NotFP16() {
        let entry = ggufEntry
        let delta = ModelCatalog.estimatedRAMBytes(for: entry, contextSize: 2000)
            - ModelCatalog.estimatedRAMBytes(for: entry, contextSize: 1000)
        XCTAssertEqual(delta, 57_344 * 1000)
    }

    /// Settings ▸ Intelligence ▸ Advanced AI tuning's "Quantize KV cache"
    /// toggle off approximates fp16 — double the q8_0 figure — for a
    /// `.gguf` entry, since that's the one whose runtime (`LlamaServerManager`)
    /// the toggle actually reaches.
    func testEstimatedRAMBytesDoublesTheKVTermWhenNotQuantizedForGGUF() {
        let entry = ggufEntry
        let quantized = ModelCatalog.estimatedRAMBytes(for: entry, contextSize: 4096, quantizedKVCache: true)
        let unquantized = ModelCatalog.estimatedRAMBytes(for: entry, contextSize: 4096, quantizedKVCache: false)
        XCTAssertEqual(unquantized - quantized, entry.kvCacheBytesPerToken * 4096)
    }

    /// An `.mlx` entry always runs at `MLXBackend`'s own fixed q8_0 —
    /// `Preferences.aiKVCacheQuantized` doesn't reach it, so the estimate
    /// must not change when the toggle is off.
    func testEstimatedRAMBytesIgnoresTheToggleForMLX() {
        let entry = ModelCatalog.entries[0]
        let quantized = ModelCatalog.estimatedRAMBytes(for: entry, contextSize: 4096, quantizedKVCache: true)
        let unquantized = ModelCatalog.estimatedRAMBytes(for: entry, contextSize: 4096, quantizedKVCache: false)
        XCTAssertEqual(quantized, unquantized)
    }
}

private extension ModelCatalog.Entry.Kind {
    var gguf: (filename: String, url: URL)? {
        if case .gguf(let filename, let url) = self { return (filename, url) }
        return nil
    }
}
