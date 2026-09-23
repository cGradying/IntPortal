#if DEBUG
import SwiftUI

/// Every Pixel component on one scrolling page, for snapshots and live checks.
/// Opened with `-IntPortalScreen gallery` in Debug builds.
struct ComponentGallery: View {
    @Environment(\.palette) private var palette
    @Environment(\.typography) private var typography
    /// Off for snapshots: `ImageRenderer` draws nothing inside a ScrollView.
    var scrolls = true
    @State private var landing = 0

    var body: some View {
        if scrolls {
            ScrollView { page }
                .frame(minWidth: 900, minHeight: 600)
                .background(palette.roles.ground)
        } else {
            page.frame(width: 900).background(palette.roles.ground)
        }
    }

    private var page: some View {
        let roles = palette.roles
        return VStack(alignment: .leading, spacing: Spacing.xl) {
            Text("Pixel components").font(typography.display(size: 28, weight: .bold))

            Sheet(label: "Buttons", meta: "primary · secondary · small") {
                HStack(spacing: Spacing.sm) {
                    Button("Login now") {}.buttonStyle(.pixelPrimary)
                    Button("Refresh") {}.buttonStyle(.pixelSecondary)
                    Button("Mark done") {}.buttonStyle(.pixelSmall)
                    Button("Disabled") {}.buttonStyle(.pixelPrimary).disabled(true)
                }
                .padding(Spacing.lg)
            }

            Sheet(label: "Stamps", meta: "click to replay the thunk") {
                HStack(spacing: Spacing.lg) {
                    ForEach(Stamp.Kind.allCases, id: \.self) { kind in
                        Stamp(kind: kind, landing: landing)
                    }
                    Stamp(kind: .vacant, small: true, landing: landing)
                }
                .padding(Spacing.lg)
                .contentShape(Rectangle())
                .onTapGesture { landing += 1 }
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel("Replay stamps")
            }

            Sheet(label: "Icons", meta: "12 and 24 point") {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    ForEach([CGFloat(12), 24], id: \.self) { size in
                        HStack(spacing: Spacing.md) {
                            ForEach(PixelIcon.Glyph.allCases, id: \.self) { glyph in
                                PixelIcon(glyph, size: size)
                            }
                        }
                    }
                }
                .foregroundStyle(roles.ink2)
                .padding(Spacing.lg)
            }

            HStack(alignment: .top, spacing: Spacing.lg) {
                Sheet(label: "This term", meta: "inline") {
                    Text("Sheets on the page are flat: a hairline and the ground behind them.")
                        .font(typography.reading(size: 15))
                        .padding(Spacing.lg)
                }
                Sheet(label: "IntAssis", meta: "floating", floating: true) {
                    Text("Floating layers get the dark edge, a top highlight and a soft shadow.")
                        .font(typography.reading(size: 15))
                        .padding(Spacing.lg)
                }
            }
        }
        .padding(Spacing.xxl)
        .foregroundStyle(roles.ink)
}
}
#endif
