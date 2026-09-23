import Metal
import SwiftUI
import XCTest
@testable import PUPSISPortal

final class DepthMathTests: XCTestCase {
    func testDeckFanWidensWithTheDueCount() {
        XCTAssertEqual(DeckFan.angles(count: 1), [0])
        let seven = DeckFan.angles(count: 7)
        XCTAssertEqual(seven.first!, -26, accuracy: 1e-9)
        XCTAssertEqual(seven.last!, 26, accuracy: 1e-9)
        let many = DeckFan.angles(count: 23)
        XCTAssertEqual(many.count, 23)
        XCTAssertEqual(many.last!, 74, accuracy: 1e-9)
        XCTAssertEqual(DeckFan.angles(count: 40).count, DeckFan.maxCards)
        XCTAssertEqual(DeckFan.angles(count: 40).last!, 75, accuracy: 1e-9)
    }

    func testOrbitRingPlacesTheIndexedPortalInFront() {
        let front = OrbitPlacement.pose(slot: 0, angle: 0, count: 3)
        XCTAssertEqual(front.x, 0, accuracy: 1e-9)
        XCTAssertEqual(front.z, 1, accuracy: 1e-9)
        XCTAssertEqual(front.scale, 1, accuracy: 1e-9)
        let right = OrbitPlacement.pose(slot: 1, angle: 0, count: 3)
        XCTAssertEqual(right.x, sin(2 * .pi / 3), accuracy: 1e-9)
        XCTAssertEqual(right.z, -0.5, accuracy: 1e-9)
        XCTAssertEqual(OrbitPlacement.pose(slot: 1, angle: 1, count: 3).z, 1, accuracy: 1e-9)
        XCTAssertEqual(OrbitRing<GalleryItem, EmptyView>.wrap(-1, 3), 2)
    }

    func testFailedSyncStopsShortAndSettles() {
        XCTAssertEqual(SyncRipple.reach(1, ok: true), 1)
        XCTAssertEqual(SyncRipple.reach(0.4, ok: false), 0.28, accuracy: 1e-9)
        XCTAssertLessThan(SyncRipple.reach(1, ok: false), 0.3)
    }

    private struct GalleryItem: Identifiable { let id: Int }
}

final class ShaderLoadTests: XCTestCase {
    func testEveryShaderCompilesIntoTheModuleLibrary() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "default", withExtension: "metallib"))
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let names = try device.makeLibrary(URL: url).functionNames
        for name in ["portalSwirl", "pixelate", "syncRipple"] {
            XCTAssertTrue(names.contains(name), "\(name) missing from \(names)")
        }
    }

    func testLibraryLoadsFromTheModuleBundle() {
        XCTAssertNotNil(Shaders.load(from: .module))
    }
}

@MainActor
final class DepthSnapshotTests: XCTestCase {
    func testDepthGalleryRenders() throws {
        Shaders.library = Shaders.load(from: .module)
        try Snapshot.render(ComponentGallery(scrolls: false), name: "depth-light", palette: .registrar, scheme: .light)
        try Snapshot.render(ComponentGallery(scrolls: false), name: "depth-dark", palette: .registrarNight, scheme: .dark)
        try Snapshot.render(SwirlView(time: 12).frame(width: 120, height: 180), name: "swirl", palette: .registrar, scheme: .dark)
        Shaders.library = nil
        try Snapshot.render(SwirlView(time: 12).frame(width: 120, height: 180), name: "swirl-fallback", palette: .registrar, scheme: .dark)
    }
}
