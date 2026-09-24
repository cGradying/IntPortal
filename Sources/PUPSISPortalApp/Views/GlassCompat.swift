import SwiftUI

/// The chrome helpers every pre-Registrar screen calls. They used to draw
/// Liquid Glass; since ADR 0001 they draw the Registrar's pixel chrome
/// instead, so every older screen (Settings, Syllabus, Quizzes, IntAssis,
/// the calendar's day header) takes the new look without being rewritten.
/// The names stay so in-flight screen slices don't conflict on every call
/// site; each slice drops them as it rebuilds its screen.
extension View {
    /// A sheet panel: the room's sheet fill, a 1pt line, notched corners.
    /// The shape argument is ignored; Registrar chrome is always notched.
    func glassPanel(in shape: some Shape) -> some View { modifier(PixelPanel()) }

    func glassPanel(cornerRadius: CGFloat) -> some View { modifier(PixelPanel()) }

    func glassCapsule() -> some View { modifier(PixelPanel()) }

    /// Hovered and clicked chrome (the IntAssis orb, the gear). Same panel.
    func glassInteractive(in shape: some Shape) -> some View { modifier(PixelPanel()) }

    /// A solid tinted marker in the notched shape.
    func glassTintedCapsule(_ tint: Color) -> some View { background(tint, in: PixelNotch()) }

    func glassButton() -> some View { buttonStyle(.pixelSecondary) }

    func glassProminentButton() -> some View { buttonStyle(.pixelPrimary) }
}

private struct PixelPanel: ViewModifier {
    @Environment(\.palette) private var palette

    func body(content: Content) -> some View {
        content
            .background(palette.roles.sheet, in: PixelNotch())
            .overlay(PixelNotch().strokeBorder(palette.roles.line, lineWidth: 1))
    }
}
