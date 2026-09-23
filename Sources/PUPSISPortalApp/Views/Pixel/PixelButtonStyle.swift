import SwiftUI

/// Buttons in the display face with notched corners. Primary is the one
/// action color; secondary is a sheet with a 2pt control border. Focus is an
/// inset 2pt action ring, since an outer ring would be clipped by the notch.
struct PixelButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary }
    var kind: Kind
    var small = false

    func makeBody(configuration: Configuration) -> some View {
        Face(configuration: configuration, kind: kind, small: small)
    }

    private struct Face: View {
        let configuration: Configuration
        let kind: Kind
        let small: Bool
        @Environment(\.palette) private var palette
        @Environment(\.typography) private var typography
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            let roles = palette.roles
            let pressed = configuration.isPressed
            configuration.label
                .font(typography.display(size: small ? 13 : 14))
                .padding(.horizontal, small ? 10 : 14)
                .padding(.vertical, small ? 4 : 7)
                .foregroundStyle(kind == .primary ? roles.onAction : roles.ink)
                .background(
                    kind == .primary ? (pressed ? roles.actionHover : roles.action) : (pressed ? roles.sunk : roles.sheet),
                    in: PixelNotch()
                )
                .overlay(PixelNotch().strokeBorder(kind == .primary ? .clear : roles.line2, lineWidth: 2))
                .overlay(PixelNotch().inset(by: 2).strokeBorder(isFocused ? roles.action : .clear, lineWidth: 2))
                .opacity(isEnabled ? 1 : 0.5)
                .contentShape(PixelNotch())
        }
    }
}

extension ButtonStyle where Self == PixelButtonStyle {
    static var pixelPrimary: PixelButtonStyle { PixelButtonStyle(kind: .primary) }
    static var pixelSecondary: PixelButtonStyle { PixelButtonStyle(kind: .secondary) }
    static var pixelSmall: PixelButtonStyle { PixelButtonStyle(kind: .secondary, small: true) }
}
