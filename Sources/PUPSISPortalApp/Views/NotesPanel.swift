import SwiftUI

/// The Notes column beside the Today timeline. A freeform scratchpad for the
/// whole day at the top, and — when a Today row is tapped — a note attached to
/// that class or event below it.
///
/// Content, not chrome: opaque panels, no glass. Edits write straight to
/// `NotesStore` (which persists on each change), so there's nothing to save.
struct NotesPanel: View {
    @ObservedObject var notes: NotesStore
    let dayKey: String
    /// The tapped Today row's note key and title, or nil when nothing's selected.
    let selectedKey: String?
    let selectedTitle: String?

    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Notes")
                .font(Theme.Typo.detailTitle)

            section(label: "Today", key: dayKey, minHeight: 140)

            if let selectedKey, let selectedTitle {
                Divider()
                section(label: selectedTitle, key: selectedKey, minHeight: 160)
            } else {
                Divider()
                Text("Tap a class or event to add a note to it.")
                    .font(Theme.Typo.footer)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(palette.canvasWash)
    }

    private func section(label: String, key: String, minHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(Theme.Typo.detailMeta)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            TextEditor(text: Binding(
                get: { notes.text(for: key) },
                set: { notes.setText($0, for: key) }
            ))
            .font(Theme.Typo.footer)
            .scrollContentBackground(.hidden)
            .padding(8)
            .frame(minHeight: minHeight)
            .background(RoundedRectangle(cornerRadius: 10).fill(.quaternary.opacity(0.4)))
        }
    }
}
