import SwiftUI

/// The sidebar's small portal: an obsidian frame around the swirl. It turns
/// faster while a refresh runs and holds still when the window isn't key or
/// Reduce Motion is on. Clicking it will lead back to the portal hub (L1).
struct PortalGlyph: View {
    var busy = false
    @Environment(\.controlActiveState) private var activeState

    var body: some View {
        SwirlView(speed: busy ? 4 : 1, cell: 2, time: activeState == .inactive ? 1.5 : nil, fps: 9)
            .padding(3)
            .background(Color(rgb: 0x170B1A))
            .overlay(Rectangle().strokeBorder(Color(rgb: 0x34203F), lineWidth: 1))
            .frame(width: 26, height: 36)
            .accessibilityHidden(true)
    }
}
