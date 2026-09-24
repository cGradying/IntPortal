import SwiftUI
import XCTest
@testable import PUPSISPortal

/// Every theme room has to reach the new shell, not just the older screens.
final class ThemeRolesTests: XCTestCase {
    private let rooms = ThemeChoice.allCases.filter { $0 != .auto }

    func testEveryRoomHasItsOwnRoles() {
        for room in rooms {
            let roles = room.palette(for: .light).roles
            XCTAssertNotEqual(roles, .registrar, "\(room)")
            XCTAssertNotEqual(roles, .registrarNight, "\(room)")
        }
    }

    func testDerivedRolesReadAtAA() {
        for room in rooms {
            let r = room.palette(for: .light).roles
            func contrast(_ a: Color, _ b: Color) -> Double { SRGB(a).contrast(with: SRGB(b)) }
            XCTAssertGreaterThanOrEqual(contrast(r.ink, r.sheet), 4.5, "\(room) ink on sheet")
            XCTAssertGreaterThanOrEqual(contrast(r.ink3, r.ground), 4.5, "\(room) ink3 on ground")
            XCTAssertGreaterThanOrEqual(contrast(r.onMenu, r.menuField), 4.5, "\(room) onMenu on menuField")
            XCTAssertGreaterThanOrEqual(contrast(r.onMenu2, r.menuField), 4.5, "\(room) onMenu2 on menuField")
            XCTAssertGreaterThanOrEqual(contrast(r.action, r.sheet), 4.5, "\(room) action on sheet")
            XCTAssertGreaterThanOrEqual(contrast(r.onAction, r.action), 4.5, "\(room) onAction on action")
        }
    }

    func testDarkRoomsGetDarkGround() {
        XCTAssertLessThan(SRGB(ThemeChoice.dracula.palette(for: .light).roles.ground).luminance, 0.2)
        XCTAssertGreaterThan(SRGB(ThemeChoice.ivory.palette(for: .light).roles.ground).luminance, 0.8)
    }

    func testContrastMatchesWCAG() {
        XCTAssertEqual(SRGB.white.contrast(with: .black), 21, accuracy: 0.01)
        XCTAssertEqual(SRGB(0x767676).contrast(with: .white), 4.54, accuracy: 0.01)
    }
}

/// One strip per room: a menu field, a header, a sheet, an action and a gold
/// stamp, so all fifteen can be judged side by side.
@MainActor
final class ThemeRoomsSnapshotTests: XCTestCase {
    private struct RoomStrip: View {
        let name: String
        @Environment(\.palette) private var palette
        @Environment(\.typography) private var typography

        var body: some View {
            let r = palette.roles
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("IntPortal").font(typography.display(size: 16, weight: .bold)).foregroundStyle(r.onMenu)
                    Text("Today").font(typography.reading(size: 13, weight: .semibold)).foregroundStyle(r.onMenu)
                        .padding(.horizontal, Spacing.sm).padding(.vertical, 3).background(r.menuFieldDeep)
                    Text("Schedule").font(typography.reading(size: 13)).foregroundStyle(r.onMenu2)
                    Text("Grades").font(typography.reading(size: 13)).foregroundStyle(r.onMenu2)
                    Spacer(minLength: 0)
                }
                .padding(Spacing.md)
                .frame(width: 130, height: 150, alignment: .topLeading)
                .background(r.menuField)
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text(name).font(typography.display(size: 18, weight: .bold)).foregroundStyle(r.ink)
                    Text("Tuesday, 3 classes").font(typography.reading(size: 12)).foregroundStyle(r.ink3)
                    Sheet(label: "GEED 020", meta: "6 to 9 PM") {
                        HStack(spacing: Spacing.sm) {
                            Text("Readings in Philippine History").font(typography.reading(size: 13)).foregroundStyle(r.ink2)
                            Spacer(minLength: 0)
                            Text("Online").font(typography.display(size: 11)).foregroundStyle(r.goldInk)
                                .padding(.horizontal, 6).padding(.vertical, 2).background(r.goldSoft)
                            Text("Join").font(typography.reading(size: 12, weight: .semibold)).foregroundStyle(r.onAction)
                                .padding(.horizontal, 10).padding(.vertical, 3).background(r.action)
                        }
                        .padding(Spacing.md)
                    }
                }
                .padding(Spacing.md)
                .frame(width: 420, height: 150, alignment: .topLeading)
                .background(r.ground)
            }
        }
    }

    func testAllRoomsSideBySide() throws {
        let sheet = VStack(spacing: 2) {
            ForEach(ThemeChoice.allCases, id: \.self) { room in
                let scheme: ColorScheme = room.colorScheme ?? .light
                RoomStrip(name: room.label)
                    .environment(\.palette, room.palette(for: scheme))
                    .environment(\.colorScheme, scheme)
            }
        }
        try Snapshot.render(sheet, name: "theme-rooms", palette: .registrar, scheme: .light)
    }
}
