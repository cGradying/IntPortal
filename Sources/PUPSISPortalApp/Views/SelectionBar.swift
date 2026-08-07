import SwiftUI

/// What you can do with a selection, said out loud.
///
/// ⌫ and ⌘D worked before this, but nothing on screen said so — a selection
/// you can't act on with the mouse is a selection most people never use.
struct SelectionBar: View {
    let count: Int
    let onDelete: () -> Void
    let onDuplicate: () -> Void
    let onDone: () -> Void

    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 14) {
            Text("\(count) selected")
                .font(Theme.Typo.footer)
                .monospacedDigit()
                .foregroundStyle(.secondary)

            Divider().frame(height: 16)

            Button(action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
            .help("Delete selected (⌫)")

            Button(action: onDuplicate) {
                Label("Duplicate", systemImage: "plus.square.on.square")
            }
            .help("Duplicate selected (⌘D)")

            Divider().frame(height: 16)

            Button("Done", action: onDone)
                .help("Clear selection (Esc)")
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .tint(palette.accent)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        // Transient chrome floating over content — the layer glass is for.
        .glassCapsule()
        .transition(
            .move(edge: .bottom).combined(with: .opacity)
            .animation(Motion.arrival(reduced: reduceMotion))
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(count) blocks selected")
    }
}
