import Foundation

/// Plain-text extraction from Office Open XML containers (.docx/.pptx) — no
/// new dependency, per wayfinder ticket #16's research writeup. Both formats
/// are a zip of XML parts; we don't need a real zip reader, just the one
/// entry that holds the document text, so we shell out to the system
/// `/usr/bin/unzip -p` (present on every macOS install) rather than link a
/// zip library for one call site.
enum OPCContainer {
    enum ExtractError: LocalizedError {
        case unreadable
        case noExtractableText

        var errorDescription: String? {
            switch self {
            case .unreadable: "Couldn't read that file."
            case .noExtractableText: "No text found in that file."
            }
        }
    }

    /// `.docx` text runs live in `word/document.xml` as `<w:t>` elements,
    /// with `<w:p>` marking paragraph breaks.
    static func docxText(from url: URL) throws -> String {
        let xml = try entry("word/document.xml", from: url)
        return try text(from: xml, runElement: "w:t", breakElement: "w:p")
    }

    /// `.pptx` text runs live one XML part per slide, `ppt/slides/slideN.xml`,
    /// as `<a:t>` elements inside `<a:p>` paragraphs. Slides are read in
    /// numeric order and joined with a blank line so a downstream chunker
    /// sees slide boundaries.
    static func pptxText(from url: URL) throws -> String {
        let names = try listSlideEntries(in: url)
        guard !names.isEmpty else { throw ExtractError.noExtractableText }
        let slides = try names.compactMap { name -> String? in
            let xml = try entry(name, from: url)
            let slideText = try text(from: xml, runElement: "a:t", breakElement: "a:p")
            return slideText.isEmpty ? nil : slideText
        }
        guard !slides.isEmpty else { throw ExtractError.noExtractableText }
        return slides.joined(separator: "\n\n")
    }

    // MARK: - Zip access via /usr/bin/unzip

    private static func entry(_ name: String, from url: URL) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-p", url.path, name]
        let out = Pipe()
        process.standardOutput = out
        process.standardError = Pipe() // discard "not matched" noise
        do {
            try process.run()
        } catch {
            throw ExtractError.unreadable
        }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0, !data.isEmpty else { throw ExtractError.unreadable }
        return data
    }

    /// `unzip -l` lists archive entries one per line; slide parts sort
    /// lexicographically wrong past 9 slides (`slide10.xml` before
    /// `slide2.xml`), so we sort by the numeric suffix, not the string.
    private static func listSlideEntries(in url: URL) throws -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-Z1", url.path]
        let out = Pipe()
        process.standardOutput = out
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            throw ExtractError.unreadable
        }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0, let listing = String(data: data, encoding: .utf8) else {
            throw ExtractError.unreadable
        }
        let pattern = #"^ppt/slides/slide(\d+)\.xml$"#
        let regex = try? NSRegularExpression(pattern: pattern)
        let matches: [(name: String, index: Int)] = listing.split(separator: "\n").compactMap { line in
            let line = String(line)
            guard let match = regex?.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                  let range = Range(match.range(at: 1), in: line), let index = Int(line[range])
            else { return nil }
            return (line, index)
        }
        return matches.sorted { $0.index < $1.index }.map(\.name)
    }

    // MARK: - Text-run extraction

    /// Concatenates every `runElement`'s character content, inserting a
    /// newline at each `breakElement` boundary. `XMLParser`'s SAX-style
    /// events are enough here — the document schema is fixed, we only ever
    /// want a subset of tags, and this is byte-cheaper than building a DOM
    /// for a file we throw away right after.
    private static func text(from xml: Data, runElement: String, breakElement: String) throws -> String {
        let delegate = RunTextCollector(runElement: runElement, breakElement: breakElement)
        let parser = XMLParser(data: xml)
        parser.delegate = delegate
        guard parser.parse() else { throw ExtractError.unreadable }
        let joined = delegate.paragraphs
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !joined.isEmpty else { throw ExtractError.noExtractableText }
        return joined
    }
}

/// `XMLParser` delegate: accumulates text runs into paragraphs, keyed by the
/// element names the caller asks for. `w:t`/`a:t` can be self-closing when
/// empty, so `currentRun` only gets flushed on `characters(_:)`.
private final class RunTextCollector: NSObject, XMLParserDelegate {
    private let runElement: String
    private let breakElement: String
    private var inRun = false
    private var currentRun = ""
    private var currentParagraph = ""
    private(set) var paragraphs: [String] = []

    init(runElement: String, breakElement: String) {
        self.runElement = runElement
        self.breakElement = breakElement
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        if elementName == runElement { inRun = true; currentRun = "" }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard inRun else { return }
        currentRun += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == runElement {
            currentParagraph += currentRun
            inRun = false
            currentRun = ""
        } else if elementName == breakElement {
            paragraphs.append(currentParagraph)
            currentParagraph = ""
        }
    }

    func parserDidEndDocument(_ parser: XMLParser) {
        if !currentParagraph.isEmpty { paragraphs.append(currentParagraph) }
    }
}
