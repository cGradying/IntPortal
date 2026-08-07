import SwiftUI

/// Liquid Glass is macOS 26 only. These wrappers apply it where available and
/// fall back to a plain material (or a bordered button) on older macOS, so the
/// app builds and runs on macOS 14+ — the glass look simply degrades, it doesn't
/// break the build. Every glass call in the app goes through one of these.
///
/// Two gates, and both are needed:
/// - `#if compiler(>=6.2)` — a *compile-time* SDK check. Liquid Glass ships in
///   the macOS 26 SDK (Xcode 26 / Swift 6.2). On an older Xcode the symbol
///   doesn't exist at all, and `#available` (a *runtime* check) can't save a
///   symbol the compiler can't even find — so the whole glass branch has to be
///   compiled out.
/// - `#available(macOS 26, *)` — inside the newer SDK, still guards actually
///   *running* on macOS 26 vs falling back on 14–15.
extension View {
    /// A glass chrome panel in the given shape; `.regularMaterial` below 26.
    @ViewBuilder
    func glassPanel(in shape: some Shape) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26, *) {
            glassEffect(.regular, in: shape)
        } else {
            background(.regularMaterial, in: shape)
        }
        #else
        background(.regularMaterial, in: shape)
        #endif
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
        #if compiler(>=6.2)
        if #available(macOS 26, *) {
            glassEffect(.regular.tint(tint), in: .capsule)
        } else {
            background(tint, in: Capsule())
        }
        #else
        background(tint, in: Capsule())
        #endif
    }

    /// `.glass` button on 26, `.bordered` below.
    @ViewBuilder
    func glassButton() -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26, *) {
            buttonStyle(.glass)
        } else {
            buttonStyle(.bordered)
        }
        #else
        buttonStyle(.bordered)
        #endif
    }

    /// `.glassProminent` button on 26, `.borderedProminent` below.
    @ViewBuilder
    func glassProminentButton() -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26, *) {
            buttonStyle(.glassProminent)
        } else {
            buttonStyle(.borderedProminent)
        }
        #else
        buttonStyle(.borderedProminent)
        #endif
    }
}
