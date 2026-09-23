import SwiftUI

/// What the sidebar's footer says about the last sync.
struct SyncStatus: Equatable {
    var line: String
    var failed: Bool
}

/// The SIS's maroon menu field: the portal glyph and wordmark, the screens in
/// two groups, Settings, and the student's sync status at the foot. A plain
/// view over values, so it renders the same in snapshots as in the app.
struct Sidebar: View {
    let selection: Destination
    var busy = false
    let studentNumber: String
    let sync: SyncStatus
    var updateVersion: String?
    let onSelect: (Destination) -> Void
    let onSettings: () -> Void
    let onRetry: () -> Void
    var onUpdate: () -> Void = {}
    @Environment(\.palette) private var palette
    @Environment(\.typography) private var typography

    var body: some View {
        let roles = palette.roles
        VStack(alignment: .leading, spacing: 14) {
            WindowDragArea().frame(height: 26)
            HStack(spacing: 10) {
                PortalGlyph(busy: busy)
                VStack(alignment: .leading, spacing: 3) {
                    Text("IntPortal").font(typography.display(size: 21, weight: .bold)).foregroundStyle(roles.onMenu)
                    Text("PUP SIS · Student Module").font(typography.reading(size: 11.5)).foregroundStyle(roles.onMenu2)
                }
            }
            .padding(.horizontal, 4)

            VStack(alignment: .leading, spacing: 1) {
                section("Main")
                ForEach(Destination.allCases.filter { !$0.isStudy }) { item($0) }
                section("Study")
                ForEach(Destination.allCases.filter(\.isStudy)) { item($0) }
                section("System")
                SidebarItem(title: "Settings", glyph: .gear, selected: false, action: onSettings)
            }

            Spacer(minLength: 0)
            footer
        }
        .padding(.horizontal, Spacing.md)
        .padding(.bottom, Spacing.md)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(roles.menuField)
    }

    private func section(_ title: String) -> some View {
        Text(title.uppercased())
            .font(typography.display(size: 11))
            .tracking(1.3)
            .foregroundStyle(palette.roles.onMenu2)
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .padding(.bottom, 4)
            .accessibilityAddTraits(.isHeader)
    }

    private func item(_ destination: Destination) -> some View {
        SidebarItem(title: destination.title, glyph: destination.glyph, selected: selection == destination) {
            onSelect(destination)
        }
    }

    private var footer: some View {
        let roles = palette.roles
        return VStack(alignment: .leading, spacing: 9) {
            Text(studentNumber)
                .font(typography.display(size: 12))
                .foregroundStyle(roles.onMenu)
                .monospacedDigit()
            HStack(spacing: 7) {
                Rectangle()
                    .fill(sync.failed ? roles.bad : roles.good)
                    .frame(width: 6, height: 6)
                if sync.failed {
                    Button(sync.line, action: onRetry).buttonStyle(.plain)
                } else {
                    Text(sync.line)
                }
            }
            .font(typography.reading(size: 12.5))
            .foregroundStyle(roles.onMenu2)
            if let updateVersion {
                Button("v\(updateVersion) available", action: onUpdate)
                    .buttonStyle(.plain)
                    .font(typography.display(size: 12))
                    .foregroundStyle(roles.gold)
            }
        }
        .padding(.horizontal, 6)
        .padding(.top, 10)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(roles.onMenu2.opacity(0.3))
                .frame(height: 1)
        }
    }
}

private struct SidebarItem: View {
    let title: String
    let glyph: PixelIcon.Glyph
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.palette) private var palette
    @Environment(\.typography) private var typography
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        let roles = palette.roles
        Button(action: action) {
            HStack(spacing: 10) {
                PixelIcon(glyph, size: 24).foregroundStyle(selected ? roles.gold : roles.onMenu2)
                Text(title).font(typography.reading(size: 14.5, weight: .semibold))
                Spacer(minLength: 0)
            }
            .foregroundStyle(roles.onMenu)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(selected ? roles.menuFieldDeep : hovering ? roles.menuFieldHover : .clear, in: PixelNotch())
            .contentShape(PixelNotch())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
