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
            case .unsupportedType: "Only Markdown, plain text, PDF, Word, and PowerPoint files are supported."
            case .noExtractableText: "This file has no extractable text — a scanned PDF, for one. Paste the text directly instead."
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
        case "docx":
            return try convert(OPCContainer.docxText(from: url))
        case "pptx":
            return try convert(OPCContainer.pptxText(from: url))
        default:
            throw ImportError.unsupportedType
        }
    }

    private static func convert(_ work: @autoclosure () throws -> String) rethrows -> String {
        do {
            return try work()
        } catch let error as OPCContainer.ExtractError {
            switch error {
            case .unreadable: throw ImportError.unreadable
            case .noExtractableText: throw ImportError.noExtractableText
            }
        }
    }
}
