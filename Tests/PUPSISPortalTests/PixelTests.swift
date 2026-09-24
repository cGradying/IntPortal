import SwiftUI
import XCTest
@testable import PUPSISPortal

final class PixelNotchTests: XCTestCase {
    func testCornersStepInTwiceByTwoPoints() {
        let points = PixelNotch.points(in: CGRect(x: 0, y: 0, width: 100, height: 40), step: 2)
        let expected: [(CGFloat, CGFloat)] = [
            (0, 4), (2, 4), (2, 2), (4, 2), (4, 0),
            (96, 0), (96, 2), (98, 2), (98, 4), (100, 4),
            (100, 36), (98, 36), (98, 38), (96, 38), (96, 40),
            (4, 40), (4, 38), (2, 38), (2, 36), (0, 36),
        ]
        XCTAssertEqual(points, expected.map { CGPoint(x: $0.0, y: $0.1) })
    }

    func testInsetShrinksTheOutline() {
        let path = PixelNotch().inset(by: 2).path(in: CGRect(x: 0, y: 0, width: 100, height: 40))
        XCTAssertEqual(path.boundingRect, CGRect(x: 2, y: 2, width: 96, height: 36))
    }

    func testTooSmallForNotchesFallsBackToARectangle() {
        let rect = CGRect(x: 0, y: 0, width: 6, height: 6)
        XCTAssertEqual(PixelNotch().path(in: rect), Path(rect))
    }
}

final class PixelIconTests: XCTestCase {
    func testTodayGlyphMatchesThePrototypeBitmap() {
        let cells = PixelBitmap.cells(PixelBitmap.grid(PixelIcon.Glyph.today.rows, on: "#"), in: CGSize(width: 24, height: 24))
        XCTAssertEqual(cells.count, 54)
        XCTAssertEqual(cells.first, CGRect(x: 2, y: 2, width: 2, height: 2))
    }

    func testEveryGlyphIsTwelveByTwelve() {
        for glyph in PixelIcon.Glyph.allCases {
            XCTAssertEqual(glyph.rows.count, 12, "\(glyph)")
            XCTAssertTrue(glyph.rows.allSatisfy { $0.count == 12 }, "\(glyph)")
        }
    }

    func testCellsCenterInANonSquareSize() {
        let cells = PixelBitmap.cells([[true]], in: CGSize(width: 30, height: 10))
        XCTAssertEqual(cells, [CGRect(x: 10, y: 0, width: 10, height: 10)])
    }
}

@MainActor
final class PixelSnapshotTests: XCTestCase {
    func testGalleryRendersInBothPalettesAndAtEveryScale() throws {
        let light = try Snapshot.render(ComponentGallery(scrolls: false), name: "gallery-light", palette: .registrar, scheme: .light)
        let dark = try Snapshot.render(ComponentGallery(scrolls: false), name: "gallery-dark", palette: .registrarNight, scheme: .dark)
        XCTAssertEqual(light.size, dark.size)
        for scale in [0.8, 1.4] {
            try Snapshot.render(ComponentGallery(scrolls: false), name: "gallery-\(Int(scale * 100))", palette: .registrar, scheme: .light, scale: scale)
        }
    }

    /// The ink mask is built once, so a week of stamped classes costs one
    /// noise image, not one per stamp.
    func testTwoHundredStampsRenderQuickly() throws {
        let wall = VStack {
            ForEach(0..<20, id: \.self) { _ in
                HStack { ForEach(0..<10, id: \.self) { i in Stamp(kind: Stamp.Kind.allCases[i % 3]) } }
            }
        }
        try Snapshot.render(wall, name: "stamps-warmup", palette: .registrar, scheme: .light)
        let start = Date()
        try Snapshot.render(wall, name: "stamps-200", palette: .registrar, scheme: .light)
        let elapsed = Date().timeIntervalSince(start)
        print("200 stamps rendered in \(Int(elapsed * 1000)) ms")
        XCTAssertLessThan(elapsed, 0.5)
    }
}
