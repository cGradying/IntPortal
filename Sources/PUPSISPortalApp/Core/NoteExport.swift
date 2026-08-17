import AppKit

enum NoteExportFormat: String, CaseIterable, Identifiable {
    case markdown, plainText, pdf

    var id: String { rawValue }
    var label: String {
        switch self {
        case .markdown: "Markdown…"
        case .plainText: "Plain text…"
        case .pdf: "PDF…"
        }
    }
    var fileExtension: String {
        switch self {
        case .markdown: "md"
        case .plainText: "txt"
        case .pdf: "pdf"
        }
    }
}

/// Renders a note's stored Markdown into the three export shapes the vault
/// offers — reusing `Markdown.parse` (`Core/Markdown.swift`), which until now
/// only backed the block-splitter tests.
enum NoteExport {
    /// Headings bare, bullets as `• `, checkboxes as `☐`/`☑` — the syntax
    /// noise stripped, nothing else changed. Inline emphasis markers
    /// (`**`/`*`/`` ` ``) are left as-is: `Markdown.parse` only splits block
    /// structure, and stripping inline syntax character-by-character isn't
    /// worth it for a plain-text export nobody expects to be typeset.
    static func plainText(from markdown: String) -> String {
        Markdown.parse(markdown).map { block -> String in
            switch block {
            case .heading(_, let text): text
            case .bullet(let text): "• \(text)"
            case .checkbox(let done, let text): "\(done ? "☑" : "☐") \(text)"
            case .paragraph(let text): text
            case .blank: ""
            }
        }.joined(separator: "\n")
    }

    /// One paragraph style + font per block, inline emphasis re-applied from
    /// whatever `NSAttributedString(markdown:)` already infers for `**bold**`
    /// / `*italic*` / `` `code` `` within a line.
    static func attributedString(from markdown: String, title: String) -> NSAttributedString {
        let result = NSMutableAttributedString()
        result.append(styledLine(title, font: .boldSystemFont(ofSize: 22), spacingAfter: 16))

        for block in Markdown.parse(markdown) {
            switch block {
            case .heading(let level, let text):
                let size: CGFloat = level <= 2 ? 18 : 15
                result.append(styledLine(text, font: .boldSystemFont(ofSize: size), spacingBefore: 10, spacingAfter: 4))
            case .bullet(let text):
                result.append(inlineLine("•  " + text, indent: 18))
            case .checkbox(let done, let text):
                result.append(inlineLine((done ? "☑  " : "☐  ") + text, indent: 18))
            case .paragraph(let text):
                result.append(inlineLine(text, spacingAfter: 4))
            case .blank:
                result.append(styledLine("", font: .systemFont(ofSize: 6)))
            }
        }
        return result
    }

    /// Prints the attributed note straight to a PDF file — an `NSTextView`
    /// paginates its own content across pages, so no manual page-splitting is
    /// needed. Same `NSPrintOperation` family `CalendarView.printWeek()` uses,
    /// just with `jobDisposition = .save` so it writes a file instead of
    /// opening the system print sheet.
    static func writePDF(_ markdown: String, title: String, to url: URL) {
        let pageSize = NSSize(width: 612, height: 792) // US Letter
        let margin: CGFloat = 54

        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: pageSize.width - margin * 2, height: 100))
        textView.textContainerInset = NSSize(width: 0, height: 0)
        textView.textStorage?.setAttributedString(attributedString(from: markdown, title: title))

        let printInfo = NSPrintInfo()
        printInfo.paperSize = pageSize
        printInfo.topMargin = margin
        printInfo.bottomMargin = margin
        printInfo.leftMargin = margin
        printInfo.rightMargin = margin
        printInfo.horizontalPagination = .fit
        printInfo.verticalPagination = .automatic
        printInfo.jobDisposition = .save
        printInfo.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url

        let operation = NSPrintOperation(view: textView, printInfo: printInfo)
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        operation.run()
    }

    private static func styledLine(_ text: String, font: NSFont, spacingBefore: CGFloat = 0, spacingAfter: CGFloat = 0) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.paragraphSpacingBefore = spacingBefore
        paragraph.paragraphSpacing = spacingAfter
        return NSAttributedString(string: text + "\n", attributes: [.font: font, .paragraphStyle: paragraph])
    }

    /// Runs the line through `NSAttributedString(markdown:)` so `**bold**` /
    /// `*italic*` / `` `code` `` render, then appends the trailing newline and
    /// paragraph spacing as plain attributes (markdown parsing doesn't carry
    /// paragraph style).
    private static func inlineLine(_ text: String, indent: CGFloat = 0, spacingAfter: CGFloat = 2) -> NSAttributedString {
        let base = (try? NSAttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? NSAttributedString(string: text)
        let line = NSMutableAttributedString(attributedString: base)
        line.addAttribute(.font, value: NSFont.systemFont(ofSize: 12), range: NSRange(location: 0, length: line.length))
        line.append(NSAttributedString(string: "\n"))

        let paragraph = NSMutableParagraphStyle()
        paragraph.paragraphSpacing = spacingAfter
        paragraph.firstLineHeadIndent = indent
        paragraph.headIndent = indent
        line.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: line.length))
        return line
    }
}
