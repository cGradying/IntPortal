import SwiftUI
import XCTest
@testable import PUPSISPortal

/// Spec 10's three UI touch points, each a plain view over values — same
/// contract as `LandingSnapshotTests`' `stage(_:)`.
@MainActor
final class CampusSnapshotTests: XCTestCase {
    // MARK: Sign-in panel live line

    private func panel(studentNumber: String, learned: [String: String] = [:]) -> some View {
        SignInPanel(
            existing: Credentials(studentNumber: studentNumber, birthMonth: 3, birthDay: 14, birthYear: 2007, password: ""),
            signingIn: false, failure: nil, campusOverride: nil, learnedCampusCodes: learned,
            onSave: { _ in true }
        )
    }

    func testSignInPanelCampusLineForEveryState() throws {
        for (name, view) in [
            ("campus-mn", AnyView(panel(studentNumber: "2026-00000-MN-0"))),
            ("campus-tg", AnyView(panel(studentNumber: "2026-00000-TG-0"))),
            ("campus-partial", AnyView(panel(studentNumber: "2026-000"))),
            ("campus-learned", AnyView(panel(studentNumber: "2026-00000-TG-0", learned: ["TG": "Taguig"]))),
        ] {
            try Snapshot.render(view, name: name, palette: .registrar, scheme: .light)
            try Snapshot.render(view, name: "\(name)-dark", palette: .registrarNight, scheme: .dark)
        }
    }

    // MARK: Sidebar footer chip

    private func sidebar(campus: CampusResolution) -> some View {
        Sidebar(
            selection: .today, studentNumber: "2026-00000-MN-0",
            sync: SyncStatus(line: "sis8 · updated 3 hr. ago", failed: false), campus: campus,
            onSelect: { _ in }, onRetry: {}, dragArea: false
        )
        .frame(width: 236, height: 500)
    }

    func testSidebarChipReadsCampus() throws {
        let known = sidebar(campus: .known(Campus(code: "MN", name: "Sta. Mesa", region: "Manila")))
        try Snapshot.render(known, name: "sidebar-chip", palette: .registrar, scheme: .light)
        try Snapshot.render(known, name: "sidebar-chip-dark", palette: .registrarNight, scheme: .dark)
        // No chip until a code resolves — must not render a dangling badge.
        try Snapshot.render(sidebar(campus: .unknownCode("TG")), name: "sidebar-chip-unknown", palette: .registrar, scheme: .light)
    }

    // MARK: Hub tag

    private func hub(liveSubtitle: String) -> some View {
        LandingStage(
            phase: .hub, time: 12, ring: .constant(0), liveSubtitle: liveSubtitle,
            signedInAs: "2026-00000-MN-0", existing: nil,
            onSave: { _ in true }, onSelect: { _ in }, onSwitchAccount: {}, onSettings: {}
        )
        .frame(width: 1280, height: 800)
    }

    func testHubTagReadsCampusAndHost() throws {
        Shaders.library = Shaders.load(from: .module)
        defer { Shaders.library = nil }
        let image = try Snapshot.render(hub(liveSubtitle: "Sta. Mesa · via sis8"), name: "hub-tag", palette: .registrarNight, scheme: .dark)
        XCTAssertEqual(image.size, CGSize(width: 1280, height: 800))
    }
}
