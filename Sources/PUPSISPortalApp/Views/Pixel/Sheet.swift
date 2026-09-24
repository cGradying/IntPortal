import SwiftUI

/// A record sheet: white panel, 1pt hairline, notched corners, and a header
/// strip with an uppercase label on the left and quiet meta on the right.
/// `floating` adds the macOS 27 depth (dark edge, top highlight, soft
/// shadow) for things that sit above the page, never for inline sheets.
struct Sheet<Content: View>: View {
    let label: String
    var meta: String?
    var floating = false
    @ViewBuilder let content: Content
    @Environment(\.palette) private var palette
    @Environment(\.typography) private var typography

    var body: some View {
        let roles = palette.roles
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Spacing.md) {
                Text(label.uppercased())
                    .font(typography.display(size: 14))
                    .tracking(0.84)
                    .foregroundStyle(roles.ink2)
                Spacer(minLength: 0)
                if let meta {
                    Text(meta).font(typography.reading(size: 13)).foregroundStyle(roles.ink3)
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, 11)
            Rectangle().fill(roles.line).frame(height: 1)
            content
        }
        .background(roles.sheet, in: PixelNotch())
        .overlay(PixelNotch().strokeBorder(roles.line, lineWidth: 1))
        .modifier(FloatingDepth(on: floating))
    }
}

/// macOS 27's depth on a floating layer: a darkened outer edge, a bright
/// 1pt highlight along the top, and a soft shadow underneath.
struct FloatingDepth: ViewModifier {
    let on: Bool
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        if on {
            content
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Color.white.opacity(scheme == .dark ? 0.14 : 0.6))
                        .frame(height: 1)
                        .padding(.horizontal, 4)
                        .padding(.top, 1)
                }
                .overlay(PixelNotch().inset(by: -1).stroke(Color.black.opacity(scheme == .dark ? 0.6 : 0.2), lineWidth: 1))
                .shadow(color: .black.opacity(scheme == .dark ? 0.65 : 0.28), radius: 20, y: 18)
        } else {
            content
        }
    }
}

extension View {
    func floatingDepth(_ on: Bool = true) -> some View { modifier(FloatingDepth(on: on)) }
}
