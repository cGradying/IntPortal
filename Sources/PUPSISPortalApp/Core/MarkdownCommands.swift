import Foundation

/// Pure selection transforms behind the notes toolbar — no view, no AppKit UI.
/// Each takes the full text plus the current `NSRange` selection and returns the
/// new text and where the selection should land. Ranges are UTF-16 (`NSString`),
/// matching what `NSTextView` hands us. Kept pure so the fiddly cursor math is
/// unit-testable without a running editor.
enum MarkdownCommands {
    typealias Result = (text: String, range: NSRange)

    // MARK: Inline wrap (bold / italic / strike / highlight / code)

    /// Wrap the selection in `marker` on both sides. With no selection, insert the
    /// pair and drop the cursor between them so the user can type inside.
    static func wrap(_ text: String, range: NSRange, with marker: String) -> Result {
        let ns = text as NSString
        let markerLen = (marker as NSString).length
        let selected = ns.substring(with: range)
        if selected.isEmpty {
            let newText = ns.replacingCharacters(in: range, with: marker + marker)
            return (newText, NSRange(location: range.location + markerLen, length: 0))
        }
        let newText = ns.replacingCharacters(in: range, with: marker + selected + marker)
        return (newText, NSRange(location: range.location + markerLen, length: (selected as NSString).length))
    }

    // MARK: Line prefixes (bullet / numbered / quote / checklist)

    static func toggleBullet(_ text: String, range: NSRange) -> Result {
        transformLines(text, range: range) { lines in
            let all = lines.allSatisfy { $0.range(of: "^\\s*[-*] ", options: .regularExpression) != nil }
            return lines.map { line in
                if all {
                    return line.replacingOccurrences(of: "^(\\s*)[-*] ", with: "$1", options: .regularExpression)
                }
                return line.range(of: "^\\s*[-*] ", options: .regularExpression) != nil ? line : "- " + line
            }
        }
    }

    static func toggleQuote(_ text: String, range: NSRange) -> Result {
        transformLines(text, range: range) { lines in
            let all = lines.allSatisfy { $0.hasPrefix("> ") }
            return lines.map { line in
                if all { return String(line.dropFirst(2)) }
                return line.hasPrefix("> ") ? line : "> " + line
            }
        }
    }

    static func toggleNumbered(_ text: String, range: NSRange) -> Result {
        transformLines(text, range: range) { lines in
            let all = lines.allSatisfy { $0.range(of: "^\\s*\\d+\\. ", options: .regularExpression) != nil }
            if all {
                return lines.map { $0.replacingOccurrences(of: "^(\\s*)\\d+\\. ", with: "$1", options: .regularExpression) }
            }
            return lines.enumerated().map { index, line in
                line.range(of: "^\\s*\\d+\\. ", options: .regularExpression) != nil ? line : "\(index + 1). " + line
            }
        }
    }

    static func toggleChecklist(_ text: String, range: NSRange) -> Result {
        transformLines(text, range: range) { lines in
            let mark = "^\\s*- \\[[ xX]\\] "
            let all = lines.allSatisfy { $0.range(of: mark, options: .regularExpression) != nil }
            return lines.map { line in
                if all {
                    return line.replacingOccurrences(of: "^(\\s*)- \\[[ xX]\\] ", with: "$1", options: .regularExpression)
                }
                return line.range(of: mark, options: .regularExpression) != nil ? line : "- [ ] " + line
            }
        }
    }

    /// Flip a single checkbox line's mark. Used by the click-to-toggle handler.
    static func toggleCheckbox(_ line: String) -> String {
        if line.contains("- [ ] ") {
            return line.replacingOccurrences(of: "- [ ] ", with: "- [x] ")
        }
        for mark in ["- [x] ", "- [X] "] where line.contains(mark) {
            return line.replacingOccurrences(of: mark, with: "- [ ] ")
        }
        return line
    }

    // MARK: Heading / link

    /// Cycle the current line: none → `# ` → `## ` → … → `###### ` → none.
    static func cycleHeading(_ text: String, range: NSRange) -> Result {
        let ns = text as NSString
        let lineRange = ns.lineRange(for: NSRange(location: range.location, length: 0))
        var line = ns.substring(with: lineRange)
        let trailingNewline = line.hasSuffix("\n") ? "\n" : ""
        if !trailingNewline.isEmpty { line.removeLast() }

        let hashes = line.prefix { $0 == "#" }.count
        let isHeading = hashes >= 1 && hashes <= 6 && Array(line).count > hashes && line[line.index(line.startIndex, offsetBy: hashes)] == " "
        let content = isHeading ? String(line.dropFirst(hashes + 1)) : line
        let level = isHeading ? hashes : 0
        let next = level >= 6 ? 0 : level + 1
        let newLine = (next == 0 ? content : String(repeating: "#", count: next) + " " + content) + trailingNewline

        let newText = ns.replacingCharacters(in: lineRange, with: newLine)
        let caret = lineRange.location + (newLine as NSString).length - (trailingNewline as NSString).length
        return (newText, NSRange(location: caret, length: 0))
    }

    /// Wrap the selection in a color mark `{#RRGGBB:text}`. Empty selection drops
    /// the cursor where the text goes. `hex` is 6 hex digits, no `#`.
    static func color(_ text: String, range: NSRange, hex: String) -> Result {
        let ns = text as NSString
        let selected = ns.substring(with: range)
        let prefix = "{#\(hex):"
        let newText = ns.replacingCharacters(in: range, with: prefix + selected + "}")
        let innerLocation = range.location + (prefix as NSString).length
        return (newText, NSRange(location: innerLocation, length: (selected as NSString).length))
    }

    /// `[selection](url)` with the cursor landing on the `url` placeholder.
    static func link(_ text: String, range: NSRange) -> Result {
        let ns = text as NSString
        let selected = ns.substring(with: range)
        let placeholder = "url"
        let newText = ns.replacingCharacters(in: range, with: "[\(selected)](\(placeholder))")
        let urlLocation = range.location + ("[\(selected)](" as NSString).length
        return (newText, NSRange(location: urlLocation, length: (placeholder as NSString).length))
    }

    // MARK: Math detection (shared by styler, inline collapse, and tests)

    struct MathMatch: Equatable {
        var range: NSRange
        var latex: String
        var display: Bool // true for $$block$$, false for $inline$
    }

    private static let blockMath = try! NSRegularExpression(pattern: "\\$\\$([\\s\\S]+?)\\$\\$")
    // Non-space boundaries + not preceded by word/`$` keep currency ("$5 and $10")
    // from reading as math.
    private static let inlineMath = try! NSRegularExpression(pattern: "(?<![$\\w])\\$(?! )([^$\\n]+?)(?<! )\\$(?!\\$)")

    /// All `$$…$$` / `$…$` spans in `text`, in document order, non-overlapping
    /// (block wins). Used to render/collapse math and to reconstruct source.
    static func mathMatches(in text: String) -> [MathMatch] {
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        var matches: [MathMatch] = []
        for m in blockMath.matches(in: text, range: full) {
            matches.append(MathMatch(range: m.range, latex: ns.substring(with: m.range(at: 1)), display: true))
        }
        for m in inlineMath.matches(in: text, range: full) {
            if matches.contains(where: { NSIntersectionRange($0.range, m.range).length > 0 }) { continue }
            matches.append(MathMatch(range: m.range, latex: ns.substring(with: m.range(at: 1)), display: false))
        }
        return matches.sorted { $0.range.location < $1.range.location }
    }

    // MARK: Line helper

    /// Apply `transform` to every line the selection touches, keeping the block
    /// selected afterward. Preserves a trailing newline so the last line isn't
    /// merged into the next.
    private static func transformLines(_ text: String, range: NSRange, _ transform: ([String]) -> [String]) -> Result {
        let ns = text as NSString
        let lineRange = ns.lineRange(for: range)
        let block = ns.substring(with: lineRange)
        let hadTrailingNewline = block.hasSuffix("\n")
        var lines = block.components(separatedBy: "\n")
        if hadTrailingNewline { lines.removeLast() }

        var newBlock = transform(lines).joined(separator: "\n")
        if hadTrailingNewline { newBlock += "\n" }

        let newText = ns.replacingCharacters(in: lineRange, with: newBlock)
        return (newText, NSRange(location: lineRange.location, length: (newBlock as NSString).length))
    }
}
