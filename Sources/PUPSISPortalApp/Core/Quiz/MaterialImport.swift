import Foundation
import PDFKit

/// Extracts plain text from a file the user picks for the "add your own
/// material" generation path. `.md`/`.txt` are read as-is; `.pdf` goes
/// through PDFKit. No OCR — a scanned PDF with no text layer is reported as
/// an error rather than silently returning nothing.
enum MaterialImport {
    enum ImportError: LocalizedError {
        case unsupportedType
        case noExtractableText
        case unreadable

        var errorDescription: String? {
            switch self {
            case .unsupportedType: "Only Markdown, plain text, and PDF files are supported."
            case .noExtractableText: "This PDF has no extractable text — it looks like a scan. Paste the text directly instead."
            case .unreadable: "Couldn't read that file."
            }
        }
    }

    static func text(from url: URL) throws -> String {
        switch url.pathExtension.lowercased() {
        case "md", "txt":
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { throw ImportError.unreadable }
            return text
        case "pdf":
            guard let document = PDFDocument(url: url) else { throw ImportError.unreadable }
            let text = (0..<document.pageCount)
                .compactMap { document.page(at: $0)?.string }
                .joined(separator: "\n\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { throw ImportError.noExtractableText }
            return text
        default:
            throw ImportError.unsupportedType
        }
    }
}
