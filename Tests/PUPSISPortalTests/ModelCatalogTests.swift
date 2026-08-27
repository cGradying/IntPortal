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
}
