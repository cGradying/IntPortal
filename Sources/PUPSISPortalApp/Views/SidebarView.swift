import SwiftUI

/// The navigation sidebar. Kept deliberately quiet: a small wordmark up top,
/// the three content views with room to breathe, and Settings pinned to the
/// bottom — the standard macOS split of "where to go" from "how it's set up".
///
/// The sidebar's material is system-provided (see the `liquid-glass` skill), so
/// nothing here hand-rolls glass; this is structure, spacing, and type only.
struct SidebarView: View {
    @Binding var selection: SidebarItem
    @Environment(\.palette) private var palette

    /// Settings lives at the bottom, apart from the content destinations.
    private static let primary: [SidebarItem] = [.schedule, .today, .grades]

    var body: some View {
        List(selection: $selection) {
            Section {
                ForEach(Self.primary) { item in
                    Label(item.title, systemImage: item.symbol)
                        .font(.body)
                        // A little height so the rows don't clump at the top.
                        .padding(.vertical, 3)
                        .tag(item)
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .top, spacing: 0) { wordmark }
        .safeAreaInset(edge: .bottom, spacing: 0) { settingsRow }
    }

    /// The app's anchor, so the nav doesn't float at the very top edge.
    private var wordmark: some View {
        HStack(spacing: 8) {
            Image(systemName: "graduationcap.fill")
                .font(.system(size: 15))
                .foregroundStyle(palette.accent)
            Text("PUPSIS Portal")
                .font(.system(.headline, design: .serif))
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    /// Pinned Settings. A plain button rather than a `List` row so it can sit at
    /// the bottom; `.selection` gives it the same highlight the native rows use
    /// when it's the one that's active.
    private var settingsRow: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.5)
            Button { selection = .settings } label: {
                Label(SidebarItem.settings.title, systemImage: SidebarItem.settings.symbol)
                    .font(.body)
                    .foregroundStyle(selection == .settings ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                    .background(
                        selection == .settings ? AnyShapeStyle(.selection) : AnyShapeStyle(.clear),
                        in: .rect(cornerRadius: 6)
                    )
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
        }
    }
}
