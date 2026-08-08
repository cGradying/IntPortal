import Foundation

/// A minimal, Obsidian-flavored Markdown block model — enough for notes: ATX
/// headings (`#`…`######`), unordered bullets (`-`/`*`), task checkboxes
/// (`- [ ]` / `- [x]`), and plain paragraphs. Inline emphasis (`**bold**`,
/// `*italic*`, `` `code` ``) is left to `AttributedString(markdown:)` at render
/// time — this only splits the block structure SwiftUI's inline parser can't.
///
/// Pure and line-based on purpose, so it's testable without a view.
enum MarkdownBlock: Equatable {
    case heading(level: Int, text: String)
    case bullet(text: String)
    case checkbox(done: Bool, text: String)
    case paragraph(text: String)
    case blank
}

enum Markdown {
    static func parse(_ text: String) -> [MarkdownBlock] {
        text.components(separatedBy: "\n").map(block(from:))
    }

    private static func block(from line: String) -> MarkdownBlock {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return .blank }

        // Heading: 1–6 leading '#', then a space.
        if trimmed.first == "#" {
            let hashes = trimmed.prefix { $0 == "#" }.count
            let rest = trimmed.dropFirst(hashes)
            if hashes <= 6, rest.first == " " {
                return .heading(level: hashes, text: rest.trimmingCharacters(in: .whitespaces))
            }
        }

        // Bullet / checkbox: '- ' or '* '.
        for marker in ["- ", "* "] where trimmed.hasPrefix(marker) {
            let rest = String(trimmed.dropFirst(marker.count))
            if rest.hasPrefix("[ ] ") {
                return .checkbox(done: false, text: String(rest.dropFirst(4)))
            }
            if rest.lowercased().hasPrefix("[x] ") {
                return .checkbox(done: true, text: String(rest.dropFirst(4)))
            }
            return .bullet(text: rest)
        }

        return .paragraph(text: trimmed)
    }
}
