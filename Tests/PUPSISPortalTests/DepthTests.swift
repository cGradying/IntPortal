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

    func testWeekTurnFacesMeetAtNinetyDegrees() {
        XCTAssertEqual(WeekTurn.angle(offset: 0), 0)
        XCTAssertEqual(WeekTurn.angle(offset: 1), 90)
        XCTAssertEqual(WeekTurn.angle(offset: -1), -90)
        XCTAssertEqual(WeekTurn.angle(offset: 0.5) - WeekTurn.angle(offset: -0.5), 90)
    }

    func testDepthPushMirrorsForwardAndBack() {
        XCTAssertEqual(DepthPushFace.scale(depth: 0), 1)
        XCTAssertEqual(DepthPushFace.scale(depth: 1), 1.04, accuracy: 1e-9)
        XCTAssertEqual(DepthPushFace.scale(depth: -1), 0.96, accuracy: 1e-9)
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
        let week = { (label: String, tint: Color) in
            Text(label).font(.system(size: 28, weight: .bold)).frame(width: 300, height: 180).background(tint)
        }
        try Snapshot.render(
            ZStack {
                week("Sep 21", .orange).modifier(WeekTurnFace(offset: -0.5, width: 300))
                week("Sep 28", .teal).modifier(WeekTurnFace(offset: 0.5, width: 300))
            }.frame(width: 420, height: 240),
            name: "turn-mid", palette: .registrar, scheme: .light)
        try Snapshot.render(
            HStack(spacing: 40) {
                week("back", .gray).modifier(DepthPushFace(depth: -0.5))
                week("front", .gray).modifier(DepthPushFace(depth: 0.5))
            }.padding(40),
            name: "push-mid", palette: .registrar, scheme: .light)
        Shaders.library = nil
        try Snapshot.render(SwirlView(time: 12).frame(width: 120, height: 180), name: "swirl-fallback", palette: .registrar, scheme: .dark)
    }
}
