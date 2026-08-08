import SwiftUI

/// The popup notes editor: raw Markdown in Edit, rendered in Preview. Used by the
/// Today screen's popup notes style. Writes straight to `NotesStore`, which
/// persists on each change — nothing to save.
struct MarkdownNotesEditor: View {
    @ObservedObject var notes: NotesStore
    let noteKey: String
    let title: String

    @Environment(\.palette) private var palette
    @State private var mode: Mode = .edit

    private enum Mode: String, CaseIterable, Identifiable {
        case edit = "Edit"
        case preview = "Preview"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(Theme.Typo.detailTitle)
                    .lineLimit(1)
                Spacer()
                Picker("", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }

            switch mode {
            case .edit:
                TextEditor(text: Binding(
                    get: { notes.text(for: noteKey) },
                    set: { notes.setText($0, for: noteKey) }
                ))
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 10).fill(.quaternary.opacity(0.4)))

            case .preview:
                ScrollView {
                    let text = notes.text(for: noteKey)
                    if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Nothing written yet. Switch to Edit — use # for headings, - for bullets, - [ ] for tasks.")
                            .font(Theme.Typo.footer)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        MarkdownText(text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 10).fill(.quaternary.opacity(0.4)))
            }
        }
        .padding(16)
        .frame(width: 360, height: 420)
        .tint(palette.accent)
    }
}

/// Renders `Markdown` blocks — headings, bullets, checkboxes, paragraphs — with
/// inline emphasis handled by `AttributedString(markdown:)`.
struct MarkdownText: View {
    private let blocks: [MarkdownBlock]

    init(_ text: String) {
        blocks = Markdown.parse(text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                row(block)
            }
        }
    }

    @ViewBuilder
    private func row(_ block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(inline(text))
                .font(headingFont(level))
                .fontWeight(.semibold)
                .padding(.top, level <= 2 ? 4 : 0)

        case .bullet(let text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•").foregroundStyle(.secondary)
                Text(inline(text))
            }

        case .checkbox(let done, let text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: done ? "checkmark.square.fill" : "square")
                    .foregroundStyle(done ? .secondary : .primary)
                Text(inline(text))
                    .strikethrough(done)
                    .foregroundStyle(done ? .secondary : .primary)
            }

        case .paragraph(let text):
            Text(inline(text))

        case .blank:
            Color.clear.frame(height: 4)
        }
    }

    /// Inline emphasis only — block structure is already split out, so the
    /// inline parser never sees a leading `#`/`-` to misread.
    private func inline(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text)) ?? AttributedString(text)
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: .title2
        case 2: .title3
        default: .headline
        }
    }
}
