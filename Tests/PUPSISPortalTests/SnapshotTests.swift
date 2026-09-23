import AppKit
import SwiftUI
import XCTest
@testable import PUPSISPortal

/// Renders a view to PNG without launching the app. Set
/// `INTPORTAL_SNAPSHOT_DIR` to keep the files; without it the render still
/// runs and must still produce an image.
@MainActor
enum Snapshot {
    @discardableResult
    static func render<V: View>(
        _ view: V, name: String, palette: Palette, scheme: ColorScheme, scale uiScale: Double = 1
    ) throws -> NSImage {
        FontLibrary.registerBundledFonts(in: .module)
        let renderer = ImageRenderer(content: view
            .environment(\.palette, palette)
            .environment(\.typography, Typography(.system, scale: uiScale))
            .environment(\.uiScale, uiScale)
            .environment(\.colorScheme, scheme))
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.nsImage, "\(name) rendered nothing")
        if let dir = ProcessInfo.processInfo.environment["INTPORTAL_SNAPSHOT_DIR"] {
            let rep = try XCTUnwrap(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
            let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
        return image
    }
}

/// Every Registrar role as a labelled swatch, plus both faces.
private struct TokenSheet: View {
    @Environment(\.palette) private var palette
    @Environment(\.typography) private var typography

    var body: some View {
        let r = palette.roles
        let swatches: [(String, Color)] = [
            ("menuField", r.menuField), ("menuFieldDeep", r.menuFieldDeep), ("menuFieldHover", r.menuFieldHover),
            ("onMenu", r.onMenu), ("onMenu2", r.onMenu2), ("action", r.action), ("actionHover", r.actionHover),
            ("actionSoft", r.actionSoft), ("actionInk", r.actionInk), ("onAction", r.onAction), ("gold", r.gold), ("goldInk", r.goldInk),
            ("goldSoft", r.goldSoft), ("ground", r.ground), ("sheet", r.sheet), ("sunk", r.sunk), ("line", r.line),
            ("line2", r.line2), ("ink", r.ink), ("ink2", r.ink2), ("ink3", r.ink3), ("good", r.good), ("bad", r.bad),
        ]
        VStack(alignment: .leading, spacing: Spacing.lg) {
            Text("The Portal and the Registrar").font(typography.display(size: 28, weight: .bold))
            Text("Pixelify Sans carries identity: COMP 002 · 9:00 AM · GPA 1.23")
                .font(typography.display(size: 16))
            Text("Source Sans 3 carries reading. Notes, descriptions and IntAssis replies stay in the body face.")
                .font(.custom("Source Sans 3", size: 15 * typography.scale))
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(96), spacing: Spacing.sm), count: 6), spacing: Spacing.sm) {
                ForEach(swatches, id: \.0) { name, color in
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Rectangle().fill(color).frame(height: 36).overlay(Rectangle().stroke(r.line2))
                        Text(name).font(.system(size: 10 * typography.scale))
                        Text(color.hex ?? "?").font(.system(size: 10 * typography.scale, design: .monospaced))
                    }
                    .foregroundStyle(r.ink2)
                }
            }
        }
        .padding(Spacing.xxl)
        .frame(width: 700 * typography.scale)
        .background(r.ground)
        .foregroundStyle(r.ink)
    }
}

@MainActor
final class SnapshotTests: XCTestCase {
    func testTokenSheetRendersInBothRegistrarPalettes() throws {
        let light = try Snapshot.render(TokenSheet(), name: "tokens-light", palette: .registrar, scheme: .light)
        let dark = try Snapshot.render(TokenSheet(), name: "tokens-dark", palette: .registrarNight, scheme: .dark)
        XCTAssertGreaterThan(light.size.height, 200)
        XCTAssertEqual(light.size, dark.size)
    }

    func testTypeScalesGrowWithUIScale() throws {
        let sizes = try [0.8, 1.0, 1.4].map { scale in
            try Snapshot.render(TokenSheet(), name: "type-scale-\(Int(scale * 100))", palette: .registrar, scheme: .light, scale: scale).size
        }
        XCTAssertLessThan(sizes[0].width, sizes[1].width)
        XCTAssertLessThan(sizes[1].width, sizes[2].width)
    }
}

/// Settings' "Force Reduce Motion" has to reach every view, not just Settings.
@MainActor
final class ReduceMotionTests: XCTestCase {
    private final class Seen { var value: Bool? }

    private struct Probe: View {
        @Environment(\.reduceMotion) private var reduceMotion
        let seen: Seen
        var body: some View {
            seen.value = reduceMotion
            return Color.clear.frame(width: 1, height: 1)
        }
    }

    private func observed(forced: Bool) -> Bool? {
        let seen = Seen()
        _ = ImageRenderer(content: Probe(seen: seen).reduceMotion(forced: forced)).nsImage
        return seen.value
    }

    func testForcedSettingReducesMotionWithSystemSettingOff() {
        XCTAssertEqual(observed(forced: true), true)
    }

    func testSystemSettingAloneDecidesWhenNotForced() {
        XCTAssertEqual(observed(forced: false), NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }
}
