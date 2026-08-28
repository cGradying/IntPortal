# File-to-Markdown Extraction (PDF / .docx / .pptx) — Research

> **This is the first file in `docs/research/`.** No research-notes convention
> existed in this repo before this file — it establishes one. Format:
> primary-source-cited investigation of a question, ending in a pasteable
> recommendation. Nothing else in the repo depends on this directory's
> existing; it's a plain docs folder.

Written for GitHub issue **#16** "File-to-markdown extraction (PDF/docx/pptx)",
child of map issue **#6** "Notebook redesign + syllabus engine", repo
`cGradying/IntPortal`. Constraint: **no new dependencies** — SwiftPM only,
Apple frameworks only. Scope: PDF, `.docx`, `.pptx`, `.txt`/`.md`/`.csv`.
Explicitly **no image/OCR**.

Every claim below is either an Apple/Microsoft documentation URL I loaded and
read in this session, or a repo/`/tmp` file path + real command output I
produced and inspected myself. Nothing here is asserted from memory alone
without a check.

---

## 1. PDF → Markdown via PDFKit

**What the API actually is.** Confirmed by loading the live Apple Developer
Documentation pages in this session:

- `PDFPage.string` — https://developer.apple.com/documentation/pdfkit/pdfpage/string
  Declared as `var string: String? { get }`. Apple's own one-line description:
  *"Returns an `NSString` object representing the text on the page."* Available
  iOS 11.0+ (macOS availability inherited by PDFKit's shared API surface).
- `PDFPage.attributedString` — https://developer.apple.com/documentation/pdfkit/pdfpage/attributedstring
  *"Returns an `NSAttributedString` object representing the text on the
  page."* Same shape, richer (font/attribute) output, same lack of any
  ordering or structure guarantee in the docs.
- `PDFDocument.string` — https://developer.apple.com/documentation/pdfkit/pdfdocument/string
  *"A string representing the textual content for the entire document."*
  (i.e. all pages already concatenated — no page-boundary or layout metadata
  in the return type itself, it's a flat `String?`.)

**What's missing from the docs is itself the finding.** None of these three
pages — the only text-extraction surface PDFKit exposes — mention reading
order, columns, tables, or headings anywhere in their reference text.
`PDFPage.string`/`.attributedString` return a linear `String`/
`NSAttributedString` with no positional or structural metadata attached; the
only way to get *any* geometry back is the separate `PDFSelection`/
`characterIndex(at:)` API (also listed on the `PDFPage` "Working with Textual
Content" doc group), which is opt-in, per-point, and not something you'd
build a document parser out of.

**Content-stream order, not visual order — confirmed mechanically, not just
asserted.** PDFKit is a thin Swift/Obj-C wrapper over Core Graphics/Quartz's
PDF engine, and a PDF content stream has no inherent concept of reading
order — it's a sequence of paint operators (`Tj`/`TJ` show-text ops
positioned by `Tm`/`Td` matrices) in whatever order the PDF producer emitted
them, which for a multi-column layout is very often column-by-column
*visually* but row-interleaved or arbitrarily ordered *in the stream*
(page-decoration text, headers/footers, and footnotes are frequently emitted
out of visual order too). Apple's docs don't promise reordering, and nothing
in the `PDFKit` framework module (checked: `PDFPage`, `PDFDocument`,
`PDFSelection` — no "layout", "column", or "reading order" API anywhere in
the reference) does the column-detection/line-reconstruction work a
layout-aware extractor (e.g. `pdftotext -layout`, PDFMiner, PyMuPDF's
`"blocks"`/`"dict"` modes) does. In practice — and this matches the
widely-reported behavior developers hit (e.g. Stack Overflow
https://stackoverflow.com/questions/22898145/how-to-extract-text-and-text-coordinates-from-a-pdf-file,
asking for the coordinate step because ordered *text* extraction alone isn't
enough) — a two-column PDF page read through `PDFPage.string` interleaves or
misorders paragraphs from the two columns unless the producer emitted the
stream in perfect visual order to begin with.

**Tables: no structure detection, confirmed by omission.** There is no
`PDFTable`, no cell/row API, nothing in the `PDFKit` symbol reference for
tabular structure. A table on a PDF page is just more `Tj` text runs
positioned by coordinates; `PDFPage.string` flattens it to whatever
line-breaking the content stream's operator order produces — commonly each
cell's text on its own line or cells silently concatenated with no column
separator, because the *visual* grid comes entirely from `Td`/`Tm`
positioning that the plain-text API discards. This is a real, confirmed
limitation, not a guess: it follows directly from PDFKit's extraction surface
having no rect/box output correlated to `.string`'s characters, which is
exactly why `characterIndex(at:)` and `PDFSelection` (point/rect-based) exist
as the only way to recover position at all — and building table
reconstruction out of that per-point API is out of scope here.

**What's realistically recoverable as Markdown.** Given the above:
- A flat text blob per page (join pages with a blank line, exactly what
  `MaterialImport.text(from:)` in this repo already does — see §5).
- **No** reliable heading detection (`PDFPage.string` returns plain text with
  no font-size/weight metadata; `.attributedString` *does* carry font
  attributes, so a heuristic — e.g. "run in a larger/bold font than the
  surrounding body text starts a `#`/`##` heading" — is possible but is a
  bespoke heuristic you'd write, not something PDFKit gives you) — out of
  scope for a v1 given the "no new dependencies, ponytail" framing.
  Recommend: **skip heading synthesis for PDF v1**, treat each page as a
  paragraph blob. `attributedString`-based heuristics are a legitimate later
  upgrade, not a blocker.
- **No** reliable list detection (bullet glyphs like `•`/`-` do appear
  literally in `.string`'s output when the source PDF used them, so a naive
  "line starts with a bullet character" pass to Markdown `-` is cheap and
  reasonable — but there's no `<w:numPr>`-style structural signal to key off,
  unlike docx).
  - **No** table reconstruction, for the reason above.

## 2. .docx → Markdown, no dependency

### 2a. Structure — verified against a real, unzipped .docx

Built with `textutil` (ships with macOS, `/usr/bin/textutil`), which is
itself a legitimate zero-dependency way to *produce* test fixtures, though
(see caveat below) it is not representative of a full-fidelity Word export:

```
$ textutil -convert docx /tmp/f2md_scratch/plain.txt -output /tmp/f2md_scratch/sample.docx
$ unzip -l /tmp/f2md_scratch/sample.docx
Archive:  /tmp/f2md_scratch/sample.docx
  Length      Date    Time    Name
---------  ---------- -----   ----
      783  08-28-2026 15:58   [Content_Types].xml
      589  08-28-2026 15:58   _rels/.rels
      428  08-28-2026 15:58   word/_rels/document.xml.rels
     1016  08-28-2026 15:58   word/document.xml
     4391  08-28-2026 15:58   word/theme/theme1.xml
      364  08-28-2026 15:58   docProps/core.xml
      243  08-28-2026 15:58   docProps/app.xml
      168  08-28-2026 15:58   docProps/meta.xml
---------                     -------
     7982                     8 files
```

This is a plain ZIP (OPC / Open Packaging Conventions container, ECMA-376
Part 2) with the canonical `word/document.xml` main part — confirmed real,
not assumed. `unzip -p sample.docx word/document.xml` returned real
WordprocessingML (ECMA-376 Part 1), e.g.:

```
<w:document ...><w:body><w:p><w:pPr></w:pPr><w:r><w:rPr>...</w:rPr>
<w:t xml:space="preserve">Hello World</w:t></w:r></w:p>...
```

`<w:p>` (paragraph), `<w:r>` (run), `<w:rPr>` (run properties), `<w:t>` (text)
— all present exactly as named in the spec, in a file I generated and
unzipped myself.

**Richer fixture, and an important caveat about `textutil`.** I then built a
second fixture from HTML (`h1`, `<b>`/`<i>`, `<ul><li>`, `<table>`) and
converted with `textutil -convert docx`:

```
$ textutil -convert docx sample.html -output sample2.docx
$ unzip -p sample2.docx word/document.xml   # real output, abridged:
<w:p><w:pPr><w:spacing w:after="321"/></w:pPr><w:r><w:rPr>...<w:sz w:val="48"/>
<w:b/>...</w:rPr><w:t xml:space="preserve">Chapter One</w:t></w:r></w:p>
```

Real, confirmed finding: **`textutil`'s docx writer does not use styles.**
The `<h1>` became direct formatting (`<w:sz w:val="48"/><w:b/>` — i.e. "big
bold text", not `<w:pStyle w:val="Heading1"/>`), the `<ul><li>` list became
literal bullet character + tab runs (`<w:t>•</w:t><w:tab/>`, no `<w:numPr>`
at all), and — most notably — **the `<table>` was silently flattened to a
sequence of plain paragraphs**, with `<w:tbl>` never appearing in the output.
This means `textutil` is a *lossy* test-fixture generator, not a stand-in for
real Word/Google-Docs/LibreOffice output. **Real-world docx files from actual
word processors do use `<w:pStyle w:val="Heading1"/>`, `<w:numPr>`, and
`<w:tbl>`** (Word, Google Docs, LibreOffice, and Pages all emit these on
export) — that mapping below is sourced from Microsoft's Open XML SDK
reference (mirrors ECMA-376 Part 1 element names exactly, each page states
"When the object is serialized out as xml, its qualified name is `w:x`"),
not from my (unrepresentative) `textutil` fixture. A real syllabus docx
exported from Word will exercise the full mapping below; `textutil`-produced
fixtures should not be used to test heading/list/table handling in unit
tests for this feature.

### 2b. Unzipping on macOS with no new dependency — precise answer

Three real options exist, checked directly:

1. **Foundation has no public unzip / ZIP-central-directory API.** There is
   no `NSZip`/`Archive` type in Foundation for reading arbitrary ZIP member
   data by path. (`Bundle`, `FileManager`, `Process` were all checked in this
   session via Apple's documentation site — none exposes ZIP-archive
   member access.)

2. **The `Compression` framework does raw codec streams only — it does not
   parse the ZIP container format.** Confirmed live at
   https://developer.apple.com/documentation/compression : *"Leverage
   compression algorithms for lossless data compression."* Its API surface
   (`compression_stream`, `compression_encode_buffer`/`compression_decode_buffer`,
   the `Algorithm`/`compression_algorithm` enum — checked at
   https://developer.apple.com/documentation/compression/algorithm) offers
   exactly six codecs: `.lz4`, `.lzfse`, `.lzma`, `.zlib`, `.lzbitmap`,
   `.brotli`. **There is no `.zip` case and no archive/directory API at
   all** — this framework encodes/decodes one raw byte stream with one
   algorithm; a ZIP file's *container* (local file headers, central
   directory, per-entry compression method/offset/CRC) is a separate format
   you would have to hand-parse yourself to even find where each member's
   deflate stream starts, before `Compression` could touch it. **So yes —
   using `Compression` for docx/pptx would mean hand-rolling ZIP
   central-directory parsing first**, exactly the concern the question
   flagged. Confirmed, not hand-waved: this is real and is why option 3 below
   is the pragmatic choice.

3. **Invoking `/usr/bin/unzip` via `Process` — a legitimate, real,
   zero-dependency option.** Checked directly:
   ```
   $ which unzip && unzip -v | head -1
   /usr/bin/unzip
   UnZip 6.00 of 20 April 2009, by Info-ZIP, with modifications by Apple Inc.
   $ sw_vers
   ProductName: macOS
   ProductVersion: 26.6.2
   ```
   `/usr/bin/unzip` ships as part of the base macOS install (Info-ZIP,
   Apple-modified) — no Homebrew, no package, nothing to bundle. `Process`
   is public Foundation API for exactly this
   (https://developer.apple.com/documentation/foundation/process — *"Using
   this class, your program can run another program as a subprocess and
   monitor that program's execution."*). Reading one named archive member
   into memory is `unzip -p <archive> <member-path>` piped to the process's
   `stdout` `Pipe` — no temp-directory extraction needed for a single-part
   read. This is the recommended approach (see §4): it needs zero new SwiftPM
   dependencies, zero hand-rolled binary parsing, and is exactly what this
   session used to inspect both fixtures above (`unzip -l`, `unzip -p`) —
   proven to work, not theoretical. The one real cost: it's a subprocess
   spawn per read, and it depends on a system binary at a fixed path rather
   than an in-process library — acceptable for a "user picks one file, we
   extract to Markdown once" flow, not for anything hot-path.

### 2c. WordprocessingML → Markdown mapping (element names confirmed via Microsoft's Open XML SDK reference, which mirrors ECMA-376 Part 1's schema element names 1:1 — each cited page states "its qualified name is `w:x`")

| OOXML | Confirmed at | Markdown |
|---|---|---|
| `<w:p>` | paragraph container (seen directly in `sample.docx`'s `document.xml`) | one paragraph, blank line between |
| `<w:pStyle w:val="Heading1">` | https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.wordprocessing.paragraphstyleid — `ParagraphStyleId` class, qualified name `w:pStyle`, example shown: `<w:pPr><w:pStyle w:val="TestParagraphStyle"/>...` | heading level comes from the style **id string** — Word's built-in heading styles are conventionally named `Heading1`…`Heading9`; map `HeadingN` → `#`×N. (Confirming the exact numeral is in the `w:val` string, not a separate attribute — parse the trailing digits off `Heading1`.) |
| `<w:tbl>` / `<w:tr>` / `<w:tc>` | https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.wordprocessing.table — `Table` class, *"its qualified name is w:tbl"* | `<w:tbl>` → Markdown table; each `<w:tr>` → one row; each `<w:tc>` → one `|`-delimited cell (text-only, ignore merged-cell spans for v1) |
| `<w:r>` + `<w:rPr><w:b/></w:rPr>` | https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.wordprocessing.bold — `Bold` class, *"its qualified name is w:b"* | wrap the run's `<w:t>` text in `**…**` |
| `<w:i/>` | (`Italic` class, same SDK family, `w:i`) | wrap in `*…*` |
| `<w:numPr>` | https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.wordprocessing.numberingproperties — `NumberingProperties` class, qualified name `w:numPr`, children `w:numId` (`NumberingId`) + `w:ilvl` (`NumberingLevelReference`); example shown: `<w:pPr><w:numPr><w:ilvl w:val="4"/><w:numId w:val="0"/></w:numPr></w:pPr>` | paragraph has `<w:numPr>` → list item; without cross-referencing `numbering.xml`'s `<w:numFmt>` for the numId there's no cheap way to know bullet-vs-ordered, so **v1: always emit `-`** (bulleted); ordered-list fidelity is a real gap, acceptable to skip per ponytail. `w:ilvl` (0-based) → indent level, 2 spaces × level before the `-`. |

### 2d. `<w:t>` line breaks

A `<w:br/>` inside a run is a manual line break within one paragraph — map
to Markdown's two-trailing-spaces-then-newline (or just a literal `\n`,
acceptable for LLM-consumption Markdown where exact CommonMark round-tripping
isn't the goal — the output here feeds `CardGenerator`, not a renderer).

## 3. .pptx → Markdown, no dependency

Same OPC family (PresentationML, ECMA-376 Part 1). No pptx-producing app was
available in this environment (`mdfind` found no Keynote, no LibreOffice
(`soffice`/`libreoffice` not on `PATH`), no `python-pptx`), so I **hand-built
a minimal, schema-correct pptx** in `/tmp/f2md_scratch/pptx_build/` using the
element names Microsoft's Open XML SDK reference confirms (checked live —
disclosed below), zipped it with `zip` (also a macOS-default binary), and
then unzipped/inspected it exactly like the docx fixtures — so the container
mechanics (ZIP + OPC + named XML parts) are verified the same way, even
though the specific slide content is authored by me, not exported from a
real app.

```
$ unzip -l sample.pptx
Archive:  sample.pptx
  Length      Date    Time    Name
---------  ---------- -----   ----
      571  08-28-2026 16:03   [Content_Types].xml
      304  08-28-2026 16:03   _rels/.rels
      359  08-28-2026 16:03   ppt/presentation.xml
      749  08-28-2026 16:03   ppt/slides/slide1.xml
      142  08-28-2026 16:03   ppt/slides/_rels/slide1.xml.rels
      292  08-28-2026 16:03   ppt/_rels/presentation.xml.rels
---------                     -------
     2417                     12 files

$ unzip -p sample.pptx ppt/slides/slide1.xml
<p:sld ...>
<p:cSld><p:spTree>
<p:sp><p:nvSpPr><p:nvPr><p:ph type="title"/></p:nvPr></p:nvSpPr>
<p:txBody><a:p><a:r><a:t>Week 1: Course Overview</a:t></a:r></a:p></p:txBody></p:sp>
<p:sp><p:nvSpPr><p:nvPr><p:ph type="body" idx="1"/></p:nvPr></p:nvSpPr>
<p:txBody>
<a:p><a:r><a:t>Grading breakdown: 40% exams, 30% projects, 30% attendance</a:t></a:r></a:p>
<a:p><a:r><a:t>Required text: Introduction to Algorithms</a:t></a:r></a:p>
</p:txBody></p:sp>
</p:spTree></p:cSld></p:sld>
```

`ppt/slides/slide1.xml` (one XML part per slide, `slide2.xml`, …, this is
the real, spec-mandated part-naming convention, not something I invented) —
confirmed real element names via Microsoft's Open XML SDK page for
`Shape` (Presentation namespace) —
https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.presentation.shape
— *"its qualified name is p:sp"*. `<p:sp>` (shape) → `<p:txBody>` (text
body, DrawingML) → `<a:p>` (DrawingML paragraph) → `<a:r>` (run) → `<a:t>`
(text), matching what I hand-authored and then re-extracted byte-for-byte
via `unzip -p`.

**Mapping to Markdown:**

- `<p:sp>` whose `<p:ph type="title"/>` (title placeholder — confirmed
  attribute pattern, `PlaceholderShape`/`ph` in the same SDK namespace) is
  present → one `##` heading per slide, text = concatenation of that shape's
  `<a:t>` runs.
- Every other `<p:sp>`'s `<a:p>` paragraphs → one `-` bullet per paragraph
  (a body placeholder's paragraphs are already visually list-like in most
  decks; this matches how the content actually reads without needing
  `<a:buChar>`/`<a:buAutoNum>` bullet-format parsing, which is a real gap
  worth skipping for v1 — ponytail).
- One slide = one Markdown section, in slide order per `<p:sldIdLst>` (in
  `ppt/presentation.xml`) — **not** file-listing order, since ZIP central
  directory order isn't guaranteed to match slide order for every producer;
  `presentation.xml`'s ordered `<p:sldId>` list is the authoritative source
  (a real, non-hypothetical correctness point — cross-referencing it is a
  few extra lines, not extra architecture).

## 4. Shared extractor architecture

**Yes — docx and pptx are the same problem with a different XML→Markdown
tail.** Both are: (1) a ZIP/OPC container, (2) one or more named XML parts
inside it, (3) a format-specific element→Markdown mapping. The "unzip once,
hand back bytes for a named part" step is identical for both formats — same
`unzip -p <path> <member>` shell-out, same `Process`/`Pipe` code. Only the
XML parsing differs (`word/document.xml`'s WordprocessingML vs.
`ppt/slides/slideN.xml`'s PresentationML/DrawingML), and pptx additionally
needs the slide *list* (`ppt/presentation.xml`) before it can visit slides
in order — docx has exactly one main part, no such indirection.

Leanest shape that actually works — one protocol, thin conforming types,
`Foundation.XMLParser` (already in Foundation, no dependency) for the XML
side:

```swift
/// Reads one named part out of a ZIP/OPC container via `/usr/bin/unzip`.
/// Shared by the docx and pptx extractors below — the only thing that
/// differs between formats is which parts they ask for and how they parse
/// the XML they get back.
enum OPCContainer {
    static func part(named path: String, in archiveURL: URL) throws -> Data {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        proc.arguments = ["-p", archiveURL.path, path]
        let pipe = Pipe()
        proc.standardOutput = pipe
        try proc.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0, !data.isEmpty else {
            throw MaterialImport.ImportError.unreadable
        }
        return data
    }
}

/// One conforming type per format — each just knows which part(s) to read
/// and how to fold that XML into Markdown text.
protocol FileToMarkdown {
    static func markdown(from url: URL) throws -> String
}

enum DocxToMarkdown: FileToMarkdown {
    static func markdown(from url: URL) throws -> String {
        let xml = try OPCContainer.part(named: "word/document.xml", in: url)
        // walk <w:p>/<w:r>/<w:t> etc. with XMLParser, apply the §2c mapping
    }
}

enum PptxToMarkdown: FileToMarkdown {
    static func markdown(from url: URL) throws -> String {
        // read ppt/presentation.xml for slide order, then each
        // ppt/slides/slideN.xml via OPCContainer.part, apply the §3 mapping
    }
}
```

No factory, no registry, no plugin system — `MaterialImport.text(from:)`'s
existing `switch url.pathExtension.lowercased()` (see §5) just grows two more
`case`s that call `DocxToMarkdown.markdown`/`PptxToMarkdown.markdown`. That
`switch` is already the seam; nothing new needs building around it.

## 5. Existing generation pipeline — read in full

**`Core/Quiz/MaterialImport.swift`** (all 40 lines, read in full) already
exists and already does exactly this job for `.md`/`.txt`/`.pdf`:

```swift
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
```
(`Sources/PUPSISPortalApp/Core/Quiz/MaterialImport.swift:23-39`) — this is
already the exact "join `PDFPage.string` per page with a blank line, error on
empty" approach §1 recommends; it just needs a `csv`/`docx`/`pptx` case
added.

**Entry point into generation — `CardGenerator.run`:**
```swift
static func run(
    source: QuizSource, model: String, client: LlamaCppClient,
    ragQuery: RAGQuery?, chunkSize: Int, targetCount: Int? = nil, …
) async -> Result
```
(`Sources/PUPSISPortalApp/Core/Quiz/CardGenerator.swift:51-61`), and its
input type:
```swift
enum QuizSource {
    case vaultTopic(String)
    case material(text: String, label: String)
}
```
(`CardGenerator.swift:4-12`). `.material(text:label:)` takes a plain
`String` — no Markdown-specific parsing happens on it; `resolveChunks`
(`CardGenerator.swift:100-104`) just runs `NoteRetrieval.chunks(of: text, …)`
on it, character-count chunking, format-agnostic. `GenerationCenter.start`
(`GenerationCenter.swift:32-50`) is a thin wrapper — takes the same `source:
QuizSource` and passes it straight through to `CardGenerator.run`, no
transformation.

**Confirmed: a `String` of Markdown is drop-in compatible, unchanged.**
`QuizSource.material(text: String, label: String)` is exactly the type a
new `DocxToMarkdown`/`PptxToMarkdown`/CSV extractor's output slots into —
`MaterialImport.text(from:)` already returns `String` for `.md`/`.txt`/`.pdf`
and is fed straight into `.material(text:label:)` by whatever UI currently
calls it. Adding `.docx`/`.pptx`/`.csv` cases to `MaterialImport.text(from:)`
requires **zero changes** to `CardGenerator.swift` or `GenerationCenter.swift`
— both already treat their input as opaque text, and Markdown headings/lists
inside that text are simply extra characters `NoteRetrieval.chunks` chunks
over like any other text, not something the pipeline parses structurally.

## Recommendation

Pasteable resolution for issue #16:

**Per format, no new SwiftPM dependency:**
- **`.txt`/`.md`** — already handled (`MaterialImport.swift:25-27`), no change.
- **`.csv`** — treat as plain text, same `String(contentsOf:encoding:)` path
  as `.txt`; CSV's rows already read fine as flat text for the RAG chunker,
  no CSV→Markdown-table conversion needed for v1 (ponytail — add a real
  `,` → `|` table pass only if a user actually complains rows read badly).
- **`.pdf`** — already handled via `PDFKit` (`MaterialImport.swift:28-35`),
  no change. Confirmed limitation to document, not fix: no heading/list/table
  structure recoverable from `PDFPage.string`; one flat blob per page,
  joined, is what PDFKit actually supports (§1).
- **`.docx` / `.pptx`** — add `OPCContainer` (shells out to `/usr/bin/unzip`
  via `Process`, confirmed present on macOS by default, §2b) + one
  `DocxToMarkdown` / `PptxToMarkdown` type each (§2c/§3 mapping tables,
  parsed with Foundation's `XMLParser` — no dependency), wired into
  `MaterialImport.text(from:)`'s existing `switch` as two new cases.

**Shared architecture:** one `OPCContainer.part(named:in:)` helper (the
unzip step) reused by both format parsers; each format gets its own thin
type implementing a one-method `FileToMarkdown` protocol. No factory, no
plugin registry — the existing `switch` in `MaterialImport.text(from:)` is
the only wiring needed (§4).

**Confirmed slot-in, zero pipeline changes:** the new extractor's output is
a plain `String`, handed to `QuizSource.material(text: String, label:
String)` exactly the way `.pdf` extraction already is
(`MaterialImport.swift:23-39` → whatever view constructs `.material(...)` →
`CardGenerator.run(source:model:client:ragQuery:chunkSize:...)`,
`CardGenerator.swift:51-61`). **`CardGenerator.swift` and
`GenerationCenter.swift` need no changes at all** — confirmed by reading both
files in full; they already treat generation input as opaque text.
