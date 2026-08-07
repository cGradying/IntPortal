import SwiftUI

/// Liquid Glass is macOS 26 only. These wrappers apply it where available and
/// fall back to a plain material (or a bordered button) on older macOS, so the
/// app builds and runs on macOS 14+ — the glass look simply degrades, it doesn't
/// break the build. Every glass call in the app goes through one of these so the
/// `#available` fork lives in exactly one place.
extension View {
    /// A glass chrome panel in the given shape; `.regularMaterial` below 26.
    @ViewBuilder
    func glassPanel(in shape: some Shape) -> some View {
        if #available(macOS 26, *) {
            glassEffect(.regular, in: shape)
        } else {
            background(.regularMaterial, in: shape)
        }
    }

    func glassPanel(cornerRadius: CGFloat) -> some View {
        glassPanel(in: RoundedRectangle(cornerRadius: cornerRadius))
    }

    func glassCapsule() -> some View {
        glassPanel(in: Capsule())
    }

    /// Tinted glass — used only by the now-line. Below 26, the tint becomes a
    /// plain capsule fill so the marker still reads.
    @ViewBuilder
    func glassTintedCapsule(_ tint: Color) -> some View {
        if #available(macOS 26, *) {
            glassEffect(.regular.tint(tint), in: .capsule)
        } else {
            background(tint, in: Capsule())
        }
    }

    /// `.glass` button on 26, `.bordered` below.
    @ViewBuilder
    func glassButton() -> some View {
        if #available(macOS 26, *) {
            buttonStyle(.glass)
        } else {
            buttonStyle(.bordered)
        }
    }

    /// `.glassProminent` button on 26, `.borderedProminent` below.
    @ViewBuilder
    func glassProminentButton() -> some View {
        if #available(macOS 26, *) {
            buttonStyle(.glassProminent)
        } else {
            buttonStyle(.borderedProminent)
        }
    }
}
