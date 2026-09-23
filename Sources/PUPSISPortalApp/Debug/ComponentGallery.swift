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
    @State private var ring = 0
    @State private var ripples = 0
    @State private var rippleOK = true
    @State private var thinking = true

    var body: some View {
        if scrolls {
            ScrollView { page.syncRipple(trigger: ripples, ok: rippleOK, from: CGPoint(x: 40, y: 40)) }
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

            Sheet(label: "Depth", meta: "swirl · orbit · fan · thinking cube") {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    HStack(alignment: .bottom, spacing: Spacing.xl) {
                        SwirlView(time: scrolls ? nil : 12).frame(width: 96, height: 144)
                        SwirlView(lit: 0.5, cell: 6, time: scrolls ? nil : 12).frame(width: 96, height: 144)
                        VoxelOrb(thinking: thinking, size: 48)
                            .onTapGesture { thinking.toggle() }
                        VoxelOrb(thinking: false, size: 48)
                    }
                    OrbitRing(items: GalleryPortal.all, index: $ring, radius: 200) { portal, front in
                        VStack(spacing: Spacing.sm) {
                            SwirlView(lit: portal.live ? 1 : 0.15, time: scrolls ? nil : 12)
                                .frame(width: 64, height: 96)
                                .overlay(PixelNotch().strokeBorder(Color(rgb: 0x34203F), lineWidth: 6))
                            Text(portal.name).font(typography.display(size: 13)).foregroundStyle(front ? roles.ink : roles.ink3)
                        }
                    }
                    .frame(height: 170)
                    HStack(spacing: Spacing.xl) {
                        ForEach([1, 7, 23], id: \.self) { n in
                            DeckFan(count: n, tint: palette.subjectColors[1]).frame(width: 240).scaleEffect(0.6)
                        }
                    }
                    .frame(height: 190)
                    if scrolls {
                        HStack(spacing: Spacing.sm) {
                            Button("Orbit ←") { ring -= 1 }.buttonStyle(.pixelSmall)
                            Button("Orbit →") { ring += 1 }.buttonStyle(.pixelSmall)
                            Button("Sync ok") { rippleOK = true; ripples += 1 }.buttonStyle(.pixelSmall)
                            Button("Sync fails") { rippleOK = false; ripples += 1 }.buttonStyle(.pixelSmall)
                        }
                    }
                }
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
private struct GalleryPortal: Identifiable {
    let name: String
    var live = false
    var id: String { name }
    static let all = [GalleryPortal(name: "PUP SIS", live: true), GalleryPortal(name: "Locked"), GalleryPortal(name: "Locked 2"), GalleryPortal(name: "Locked 3")]
}
#endif
