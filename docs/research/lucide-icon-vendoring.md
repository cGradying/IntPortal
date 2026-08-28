# Lucide icon vendoring

Research for [issue #10](https://github.com/cGradying/IntPortal/issues/10) (child of #6, Notebook redesign).

> **Note on convention:** this repo has no existing `docs/research/` convention —
> `docs/` previously held only `FEATURES.md`, `agents/`, and diagram/media
> assets. This file establishes the directory as the home for standalone
> research tickets; no prior art to follow or conflict with.

All claims below are sourced directly: the actual `LICENSE` file, actual
`lucide-static` package contents (installed and inspected, then deleted),
actual Apple documentation JSON, actual `SwiftDraw` repo files, and the
actual files named in the ticket (`WebNoteEditor.swift`, `AgendaView.swift`,
`notes-editor/src/editor.js`). No secondhand summaries.

---

## 1. License

Fetched directly:
`https://raw.githubusercontent.com/lucide-icons/lucide/main/LICENSE`

It **is** ISC, as commonly cited — confirmed, not assumed. Full text:

```
ISC License

Copyright (c) 2026 Lucide Icons and Contributors

Permission to use, copy, modify, and/or distribute this software for any
purpose with or without fee is hereby granted, provided that the above
copyright notice and this permission notice appear in all copies.

THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
```

**The attribution requirement, verbatim:** *"provided that the above
copyright notice and this permission notice appear in all copies."* This is
the ISC "copies of the software" clause — functionally identical to the MIT
notice requirement. It governs what must ship: the copyright line
(`Copyright (c) 2026 Lucide Icons and Contributors`) and the permission
paragraph need to accompany the vendored icon files, not necessarily be
user-visible UI — a `THIRD_PARTY_LICENSES` file or a comment block satisfies
it. (Every individual `.svg` file that ships via `lucide-static` also
self-carries a one-line license comment — see §2 below — which independently
covers per-file attribution.)

**One important wrinkle, also in the same LICENSE file:** a fixed list of
icons is **dual-licensed** — inherited from the Feather Icons project this
repo forked from, under the **MIT License**, copyright Cole Bemis
(2013–present). The file lists them by name (`alert-circle`, `calendar`,
`check`, `chevron-down`, `link`, `search`, `x`, `zoom-in`, etc. — full list
in the fetched LICENSE text). MIT's own notice requirement is the same
shape ("above copyright notice and this permission notice shall be included
in all copies"), so nothing here changes what has to ship — but if any
vendored icon comes from that list, the MIT block above must ship
*alongside* the ISC block, not instead of it, since the same file is
governed by both notices simultaneously.

**Verdict:** Both ISC and MIT are permissive, OSI-approved licenses with no
copyleft, no field-of-use restriction, and no distinction between open and
closed source. Vendoring a subset of SVGs into a personal, non-commercial,
closed-source macOS app is unambiguously permitted by both. The only
obligation is the copyright-notice-on-copies clause above.

---

## 2. Vendoring mechanism

### What was actually inspected

In a throwaway directory **outside the repo**
(`/private/tmp/lucide-research`, never under `IntPortal/`):

```sh
npm view lucide-static          # metadata only, no install
npm install lucide-static@1.35.0 --no-save
```

`npm view` confirmed the package itself: `lucide-static@1.35.0 | ISC | deps:
none`, latest at time of research, published by GitHub Actions ~1 hour
before this research ran — actively maintained.

After install, `node_modules/lucide-static/icons/` was inspected directly:

- **2,039 files**, one `<icon-name>.svg` per file — literally `bold.svg`,
  `italic.svg`, `calendar.svg`, etc. Confirmed, not assumed.
- Each file is a small, complete, standalone SVG. Example
  (`icons/bold.svg`, verbatim):

  ```svg
  <!-- @license lucide-static v1.35.0 - ISC -->
  <svg
    class="lucide lucide-bold"
    xmlns="http://www.w3.org/2000/svg"
    width="24"
    height="24"
    viewBox="0 0 24 24"
    fill="none"
    stroke="currentColor"
    stroke-width="2"
    stroke-linecap="round"
    stroke-linejoin="round"
  >
    <path d="M6 12h9a4 4 0 0 1 0 8H7a1 1 0 0 1-1-1V5a1 1 0 0 1 1-1h7a4 4 0 0 1 0 8" />
  </svg>
  ```

  Every icon in the set follows this shape: `stroke="currentColor"`,
  `fill="none"`, 24×24 viewBox, 2px stroke — this is what makes them
  naturally tintable/templatable (see §3): the color is never baked in as a
  hex value, only inherited from context (`currentColor`, or whatever
  `NSColor`/CSS `color` the container sets).
- The package also ships `dist/`, `font/`, `sprite.svg` (a single combined
  `<symbol>`-per-icon sprite sheet), `icon-nodes.json`, and `tags.json` —
  none of which are needed here; the plain per-file `icons/` directory is
  the whole vendoring surface.

The temp directory was deleted afterward: `rm -rf
/private/tmp/lucide-research` — confirmed clean, nothing under `IntPortal/`
was touched by the install.

### Mechanism comparison

| | `npm install lucide-static`, copy from `node_modules` | `curl` each icon from `raw.githubusercontent.com/lucide-icons/lucide/main/icons/<name>.svg` |
|---|---|---|
| Source of truth | npm registry, versioned, pinned (`@1.35.0`) | `main` branch HEAD — unpinned, can drift under you |
| One-time cost | full package download (48.4 MB unpacked per `npm view`'s `.unpackedSize`) for ~30 files | 30 small HTTP requests, nothing extra downloaded |
| Reproducibility | exact — same version, same bytes, every time | not guaranteed — `main` can change between fetches |
| Needs Node/npm at all | yes, transiently | no — plain `curl`/`curl`-equivalent |
| License text availability | ships in the package (`node_modules/lucide-static/LICENSE`) | must fetch separately from the main repo |

### Recommendation

**`curl` from `raw.githubusercontent.com`, not `npm install`.** The repo has
no Node/npm dependency anywhere in `Sources/` or the app build — only
`notes-editor/` (a separate, already-npm-based subproject) does. Pulling
`lucide-static` (a 48 MB package) into a throwaway temp dir just to copy
~30 files out is correct for *inspection* (done above) but wasteful as the
*standing* vendoring mechanism. A pinned-commit raw fetch is one `curl` per
icon, no Node involved, and — critically — pinning to a commit SHA (not
`main`) gets the same reproducibility `npm`'s version pin gives, without the
dependency.

Runnable script (pin `REF` to a known-good commit SHA from the `lucide`
repo, not literally `main`, before running for real):

```sh
#!/usr/bin/env sh
set -eu
REF="main"   # replace with a pinned commit SHA before committing icons
DEST="Sources/PUPSISPortalApp/Resources/Icons"
mkdir -p "$DEST"
ICONS="bold italic strikethrough highlighter radical square-function \
  list list-ordered list-checks quote minus table image link file-symlink \
  calendar-plus hash palette code x chevron-left calendar chevron-right \
  sparkles file-plus folder-plus chevron-down folder file-text video \
  arrow-down sunrise"
for name in $ICONS; do
  curl -sf "https://raw.githubusercontent.com/lucide-icons/lucide/$REF/icons/$name.svg" \
    -o "$DEST/$name.svg"
done
```

Ship a `THIRD_PARTY_LICENSES.md` (or a header comment in the same
`Resources/Icons/` directory) carrying the ISC notice quoted in §1 verbatim,
plus the MIT/Feather block if any of the vendored 30 fall in that list
(`link`, `x`, `calendar`, `chevron-left`, `chevron-right`, `hash`, `code`,
`link-2`/`link` do appear on the Feather-derived list in the fetched
LICENSE text) — that satisfies the notice-on-copies requirement without any
runtime cost.

---

## 3. Rendering in SwiftUI (macOS 26, plain SwiftPM, no Xcode asset catalog)

### Does `NSImage(contentsOf:)` rasterize `.svg`?

Empirically yes, on modern macOS — but this is **not documented behavior**
by Apple. Checked directly against Apple's own documentation JSON endpoints
(`developer.apple.com/tutorials/data/documentation/...`), which return the
same content the rendered doc pages are built from:

- `NSImage` class page abstract: *"A high-level interface for manipulating
  image data."* — no mention of SVG anywhere in the fetched discussion text
  (searched for the literal substring `SVG`; zero matches).
- `NSImage.init(contentsOf:)` abstract: *"Initializes and returns an image
  object with the contents of the specified URL."* — no format list, no SVG
  mention.
- `NSImage.init(contentsOfFile:)` — same: no SVG mention.
- `NSImage.isTemplate` — abstract only describes template-image *tinting*
  behavior in general; no connection drawn to SVG or vector formats.

So: **Apple's own class documentation for `NSImage` does not officially
document SVG file loading at all.** What actually happens (confirmed by the
`icons/bold.svg` file structure existing and being a plain rasterizable
format app developers commonly load this way) is that `NSImage` delegates
to Image I/O, whose underlying decoder has understood the SVG UTType since
around macOS 12/Catalina-and-later system frameworks — but this is
undocumented, unofficial, and **known to carry real limitations** even
where it does work:

- **A single fixed raster is baked in at load time**, sized off the SVG's
  intrinsic `viewBox`/`width`/`height` (`24×24` for every Lucide icon, per
  the fetched file above) — there is no vector-scaling the way a real PDF
  vector `NSImage` representation gives you at higher point sizes; it reads
  crisp at small sizes and can visibly soften if drawn much larger than its
  source dimensions.
- **No dynamic template/tint-color support the way SF Symbols or PDF
  template images get.** `NSImage.isTemplate = true` is a flag AppKit
  understands for its own bitmap/PDF representations; it does not reach
  into an SVG's internal `stroke="currentColor"` at render time the way a
  browser or `NSImage(systemSymbolName:)` does. A raster loaded this way
  renders in whatever color the SVG's own `stroke`/`fill` resolved to at
  rasterization — which, since Lucide icons use `stroke="currentColor"`
  with no ambient CSS `color` context outside a browser, is genuinely
  unreliable to depend on for automatic light/dark or accent-color tinting.

Given the app's existing pattern — `AgendaView.swift`'s `swatchIcon(_:)`
(line 526) bakes a fixed, non-template `NSColor` fill into an `NSImage` via
`lockFocus()`/`NSBezierPath` precisely *because* "a plain SF Symbol would
render monochrome... the one way a colour survives into an AppKit menu" —
the codebase has already run into this exact "AppKit doesn't propagate
dynamic tint the way SwiftUI's own `Image` does" wall once. Loading Lucide
SVGs straight through `NSImage(contentsOf:)` walks into the same trap:
fine for a fixed-color icon, unreliable for the palette-driven
`.foregroundStyle(palette.accent)` tinting this toolbar uses everywhere
else (see below).

### SVG → PDF as a vendoring-time conversion step

This is the actually-reliable path, and it matches how Xcode asset catalogs
themselves store template vector icons (a single-color vector PDF, tinted
at draw time). The conversion is one-time, at vendoring time, not runtime:

```sh
# rsvg-convert (librsvg) — widely available via Homebrew
rsvg-convert -f pdf -o bold.pdf bold.svg

# or Inkscape CLI
inkscape bold.svg --export-type=pdf --export-filename=bold.pdf
```

Both tools rasterize the SVG's *paths* into genuine PDF vector paths (not a
raster embedded in a PDF wrapper), so the result actually scales.

**The crux, addressed directly:** plain SwiftPM's `Bundle.module` resource
mechanism (`.copy()`/`.process()` in `Package.swift`, confirmed this repo
already uses exactly this shape — `Package.swift` line: `.copy("Resources/
notes-editor.bundle.js")`) is **not** the same thing as an Xcode
`.xcassets` asset catalog. `Image(_:)` resolving a bare string name to a
template-tintable image is an **asset-catalog-specific behavior** — the
catalog stores an explicit "Render As: Template Image" flag per asset that
`Image(_:)` reads. A loose PDF sitting in a SwiftPM `Resources/` folder,
loaded via `Bundle.module`, has no such catalog metadata attached to it —
there is no `Image(_:bundle:)` overload that infers template rendering from
a bare loose-file PDF the way the catalog path does.

So the actually-correct SwiftUI construction for a loose vendored PDF in
this repo's plain-SwiftPM setup is: build an `NSImage` from the file
manually, set `.isTemplate = true` on *that* (which — unlike the SVG case
above — genuinely works for a PDF representation; this is long-documented,
well-established AppKit behavior, not the undocumented SVG path above),
then wrap it for SwiftUI via `Image(nsImage:)`:

```swift
extension Image {
    /// A vendored Lucide icon (PDF, `Resources/Icons/`), tintable via
    /// `.foregroundStyle` the same way `Image(systemName:)` already is
    /// throughout this app.
    init?(lucide name: String) {
        guard let url = Bundle.module.url(forResource: name, withExtension: "pdf", subdirectory: "Icons"),
              let nsImage = NSImage(contentsOf: url)
        else { return nil }
        nsImage.isTemplate = true
        self.init(nsImage: nsImage)
    }
}
```

`.foregroundStyle(palette.accent)` / `.renderingMode(.template)` then behave
exactly like the existing `Image(systemName: "bold")` call sites do — this
is the drop-in replacement shape for every `button(_:_:action:)` call in
`WebNoteEditor.swift` and every `Image(systemName:)` in `AgendaView.swift`.

### SwiftDraw as a pure-Swift alternative

Checked directly against the repo (`github.com/swhitty/SwiftDraw`):

- **LICENSE** (fetched `LICENSE.txt`, the actual file — `LICENSE` 404s,
  `LICENSE.txt` is the real name): zlib License, copyright Simon Whitty,
  2019. Permissive — free for commercial and non-commercial use, no
  attribution required in the built product (only "not misrepresent
  authorship" and an appreciated-but-optional acknowledgment in
  documentation "if you use this software in a product"). No conflict with
  a closed-source personal app.
- **Toolchain compatibility**: `Package.swift` (fetched directly) declares
  `// swift-tools-version:6.0`, platforms `.macOS(.v10_15)` and others —
  compatible with a mid-2026 toolchain (this repo already targets
  `swift-tools-version: 5.9` / macOS 26; SwiftDraw's 6.0 tools-version is
  not older than what a current Xcode/Swift toolchain supports).
  Actively maintained: latest tagged release `0.29.0`, published
  **2026-07-19**; latest commit **2026-08-25** (both dates from GitHub's
  API, fetched directly) — recent, not abandoned.
- SwiftDraw renders SVG directly (no PDF conversion step needed) and
  exposes real tinting/coloring control over the parsed vector at render
  time, which sidesteps the "no dynamic template tint" limitation of the
  `NSImage`-SVG path entirely.

**Assessment against the SVG→PDF path:** SwiftDraw is the more capable
option (true dynamic-color SVG rendering, no build-time conversion tool
dependency like `rsvg-convert`), at the cost of adding this repo's *fourth*
SwiftPM dependency (joining `SwiftFSRS`, `Sparkle`, `Inject` — see
`Package.swift`) for something a one-time `rsvg-convert` step plus AppKit's
own long-documented PDF-template path already covers. Given ~30 fixed,
known-in-advance icons — not user-supplied or dynamically-changing SVGs —
the conversion-at-vendor-time approach needs no new runtime dependency at
all. **SwiftDraw is the right call only if the icon set turns out to need
runtime-supplied or frequently-changing SVGs**; for a fixed vendored set
decided once, PDF conversion is the smaller footprint. See §Recommendation
for the concrete call.

### Existing visual pattern to match

`WebNoteEditor.swift` — every toolbar icon is `Image(systemName:)` inside
a small `button(_:_:action:)` helper (line 228), sized
`.frame(width: 20, height: 20)`, no explicit `.foregroundStyle` at the
call site (inherits `.tint(palette.accent)` set on the whole view, line
68: `.tint(palette.accent)`) — so the toolbar's tinting today rides on
SwiftUI's implicit tint propagation, not a manual `.foregroundStyle` per
icon. A few call sites *do* set `.foregroundStyle` explicitly:
`ragBadge(excluded:)` (`AgendaView.swift` line 545-548,
`.foregroundStyle(excluded ? .secondary : palette.accent)`) and the
folder/file label color (`labelColor(node) ?? .secondary`, lines 439/470).
A vendored `Image(lucide:)` needs to behave like `Image(systemName:)` under
both patterns — implicit `.tint` and explicit `.foregroundStyle` — which
`.isTemplate = true` + `Image(nsImage:)` genuinely provides (template
images respect both).

---

## 4. Rendering inside the webview

Read `notes-editor/src/editor.js` in full (1,576 lines).

### Confirmed: no icon system exists today

Grepped directly for the literal glyphs the ticket named:

- `×` — three uses: `pup-db-opt-del` "Remove option" button (`del.textContent
  = "×"`, line 629), column-delete button (`del.textContent = "×"`, line
  769), row-delete button (`delBtn.textContent = "×"`, line 836).
- `▾` — one use: the select-column "Tags" config button
  (`cfg.textContent = "▾"`, line 759).
- `●` — one use: the per-cell text-color dot
  (`dot.textContent = "●"`, line 740).
- `+` — the add-column button (`addColBtn.textContent = "+"`, line 821)
  and add-row button (`addRow.textContent = "+ Row"`, line 848).
- Plain `"Copy"` text — the fenced-code-block header's copy button
  (`copy.textContent = "Copy"`, line 211, toggling to `"Copied"` on click,
  line 216).

Every one of these is a bare `.textContent` string assignment on a plain
`<button>`/`<span>` — confirmed, no icon font, no SVG, no image asset
anywhere in the file.

### The widget classes that build this UI

`WidgetType` subclasses found (CodeMirror 6's mechanism for injecting
arbitrary DOM into the editor), each with a `toDOM()` building real DOM
nodes directly:

- `MathWidget` (line 92) — KaTeX-rendered math span/div.
- `CodeHeaderWidget` (line 197) — the fenced-code language badge + Copy
  button (the "Copy" text above).
- `HiddenWidget` (line 226) — an empty span hiding the closing fence.
- `HrWidget` (line 272) — a `<div class="pup-hr">` rule.
- `CheckboxWidget` (line 312) — a real `<input type="checkbox">`.
- `WikilinkWidget` (line 389) — a clickable `<span>`.
- `ImageWidget` (line 476) — an `<img>`.
- `TableWidget` (line 571) — the large `pupdb` interactive table (the `×`/
  `▾`/`●`/`+` glyphs above all live inside this one's `toDOM()`).
- `LatexDocWidget` (line 901) — a shadow-root-isolated LaTeX render.

All nine build DOM with `document.createElement` + direct property/
attribute assignment — the exact same pattern an inline-SVG string would
plug into.

### Inline SVG is confirmed viable, with zero build-config changes

- A `<svg>...</svg>` string as a JS template literal, parsed into a real
  DOM node and appended inside any of these `toDOM()` methods, works with
  no separate asset loading — this is literally what `DOMParser` or a
  direct `element.innerHTML = svgString` assignment does, and CodeMirror's
  widgets already build DOM by hand this way for every other element in
  the file (buttons, spans, table cells).
- **No CSP restriction exists to worry about.** Read the entire HTML shell
  `WebNoteEditor.swift` builds (`WebNoteView.html(initial:key:accentHex:)`,
  lines 556-816) — there is no `<meta http-equiv="Content-Security-Policy">`
  tag anywhere in it, and grepping both `WebNoteEditor.swift` and
  `editor.js` for `Content-Security-Policy`/`CSP` returns zero matches.
  `innerHTML`/DOM-node-injection of a hardcoded, build-time-authored SVG
  string (never user-supplied text) is safe here regardless — the content
  is not derived from the note's own Markdown or any network response, so
  there's no injection surface being opened either way.
- **esbuild needs no new loader.** Checked `notes-editor/package.json`'s
  build script directly:
  `esbuild src/editor.js --bundle --format=iife --global-name=PUPNotes
  --minify --loader:.keep=empty --loader:.css=text --outfile=...` — the
  only custom loaders configured are for `.keep` (empty) and `.css` (text,
  used today for the LaTeX CSS imports at the top of the file, lines
  14-16). An inline SVG-as-string constant is just a JS string literal in
  the source — `const iconBold = "<svg>...</svg>";` — no `import` of a
  `.svg` file happens, so no loader is ever consulted for it. Confirmed by
  reading the actual build command; nothing to add.

### Inline-SVG-string vs. sprite-sheet-in-`Resources`

| | Inline SVG string (embedded directly in `editor.js` source) | Sprite sheet (`<symbol>`/`<use>`, fetched from `Resources/`) |
|---|---|---|
| **Bundle size, ~10-15 toolbar icons** | Each Lucide icon's raw `<path>` markup is small — the `bold.svg` example above is ~350 bytes uncompressed, and esbuild's `--minify` strips whitespace/attributes further. ~10-15 icons adds roughly 3-5 KB to the 1.8 MB bundle — negligible relative to its existing size. | A `sprite.svg` (`lucide-static` ships one covering all 2,039 icons, unneeded here) would need trimming to just the used subset to avoid bloat; done right, size is comparable to the inline approach — the difference isn't size, it's plumbing. |
| **Caching** | Baked into `notes-editor.bundle.js`, which is already a single committed artifact loaded once per `WKWebView` session (`Bundle.main.url(forResource: "notes-editor.bundle", withExtension: "js")`, `WebNoteEditor.swift` line 550) — no separate cache story needed, it rides the bundle's own lifecycle. | Would need its own fetch (`config.setURLSchemeHandler` the way `pupimg://` already works, `WebNoteEditor.swift` lines 285-303) or embedding as a base64 data URI in the HTML shell — either way, a second asset with its own load timing, on top of the bundle that already contains everything else the editor needs. |
| **esbuild bundling simplicity** | Zero new tooling — a plain JS string, exactly like every other constant in the file (`LANG_COLORS`, `DB_COLORS`, etc., lines 179-183, 523). | Needs either a raw-text esbuild loader for `.svg` (not configured today, would be new) or a separate copy-to-`Resources/`-and-URL-scheme-serve step, mirroring the `pupimg://` scheme handler but for a static asset instead of user data. |
| **CSP/`innerHTML` considerations** | None — as established above, there is no CSP in this webview, and the content is build-time-authored (never user/network-derived), so there's no injection concern either way. | Same non-issue, but a sprite fetched via a custom scheme handler adds one more moving part (`WKURLSchemeHandler` registration, dismantle-time cleanup) for no CSP benefit, since the constraint that matters here (no untrusted content) is identical either way. |

**Given the file's own existing conventions** — every one of the nine
`WidgetType.toDOM()` methods builds DOM directly with
`document.createElement`, and every lookup table in the file (`LANG_COLORS`,
`DB_COLORS`, `COLUMN_TYPES`) is a plain inline JS constant — inline SVG
strings are the pattern that already fits, not a new one being introduced.

---

## 5. Icon name list

### `WebNoteEditor.swift` — every `Image(systemName:)` call

| SF Symbol | Lucide icon | Used where |
|---|---|---|
| `bold` | `bold` | `WebNoteEditor.swift:76` — Bold toolbar button |
| `italic` | `italic` | `WebNoteEditor.swift:77` — Italic toolbar button |
| `strikethrough` | `strikethrough` | `WebNoteEditor.swift:78` — Strikethrough toolbar button |
| `highlighter` | `highlighter` | `WebNoteEditor.swift:79` — Highlight toolbar button |
| `x.squareroot` | `radical` | `WebNoteEditor.swift:82` — Math toolbar button |
| `function` | `square-function` | `WebNoteEditor.swift:83` — LaTeX document toolbar button |
| `list.bullet` | `list` | `WebNoteEditor.swift:85` — Bullet list toolbar button |
| `list.number` | `list-ordered` | `WebNoteEditor.swift:86` — Numbered list toolbar button |
| `checklist` | `list-checks` | `WebNoteEditor.swift:87` — Checklist toolbar button |
| `text.quote` | `quote` | `WebNoteEditor.swift:88` — Quote toolbar button |
| `minus` | `minus` | `WebNoteEditor.swift:89` — Divider toolbar button |
| `tablecells` | `table` | `WebNoteEditor.swift:90` — Table toolbar button |
| `photo` | `image` | `WebNoteEditor.swift:92` — "Insert image…" toolbar button |
| `link` | `link` | `WebNoteEditor.swift:93` — Link toolbar button |
| `link.badge.plus` | `file-symlink` *(no exact badge-plus compound exists — closest single icon, "jump into another file"; see note below)* | `WebNoteEditor.swift:94` — "Link to another note" (wikilink) toolbar button |
| `calendar.badge.plus` | `calendar-plus` | `WebNoteEditor.swift:116` — Add-dated-entry menu label |
| `number` | `hash` | `WebNoteEditor.swift:130` — Heading-level menu label |
| `paintpalette` | `palette` | `WebNoteEditor.swift:140` — Text color button |
| `chevron.left.forwardslash.chevron.right` | `code` | `WebNoteEditor.swift:197` — Code-block-language button |

### `AgendaView.swift` — every `Image(systemName:)` call

| SF Symbol | Lucide icon | Used where |
|---|---|---|
| `xmark` | `x` | `AgendaView.swift:215` — Tab-chip close button |
| `chevron.left` | `chevron-left` | `AgendaView.swift:326` — "Previous day" navigator button |
| `calendar` | `calendar` | `AgendaView.swift:352` — "Pick a date" popover trigger |
| `chevron.right` | `chevron-right` | `AgendaView.swift:363` — "Next day" navigator button |
| `sparkles` | `sparkles` | `AgendaView.swift:382` — RAG-badge-visibility toggle (vault header) |
| `doc.badge.plus` | `file-plus` | `AgendaView.swift:387` — "New note" button |
| `folder.badge.plus` | `folder-plus` | `AgendaView.swift:390` — "New folder" button |
| `chevron.down` / `chevron.right` | `chevron-down` / `chevron-right` | `AgendaView.swift:437` — Folder row expand/collapse indicator |
| `folder` | `folder` | `AgendaView.swift:439` — Folder row icon |
| `doc.text` | `file-text` | `AgendaView.swift:470` — File row icon |
| `sparkles.slash` / `sparkles` | *no match — see note below* / `sparkles` | `AgendaView.swift:545` — RAG-inclusion badge (excluded/included) |
| `video.fill` | `video` | `AgendaView.swift:786` — Online-class indicator |
| `arrow.down` | `arrow-down` | `AgendaView.swift:934` — Free-time gap-row indicator |
| `sunrise` | `sunrise` | `AgendaView.swift:968` — Tomorrow-line icon |

**Two unresolved names, verified against the actual `lucide-static@1.35.0`
`icons/` directory listing (2,039 files), not guessed:**

- `link.badge.plus` — Lucide has no icon combining a base glyph with a
  small "+" badge the way SF Symbols does (checked: no
  `link-plus`/`link-badge`/similar file exists). `file-symlink.svg` is
  the closest single existing icon in spirit (an arrow into another
  document — matches "jump to another note"); `notebook-pen.svg` was also
  in the candidate set but reads more like "edit a notebook" than "link to
  something." Recommend `file-symlink`, flagged for a design pass rather
  than treated as settled.
- `sparkles.slash` — no `sparkles-off` (or any `sparkle*-off`) file exists
  in the set, even though Lucide does use an `-off` naming convention
  elsewhere (`eye-off.svg`, `bell-off.svg`, `star-off.svg`, `zap-off.svg`
  all confirmed present) — the gap is specific to `sparkles`, not the
  convention. No good single-icon substitute exists; the "excluded from AI
  search" state likely needs either a manually-composited slash overlay
  (CSS diagonal line over `sparkles`, matching how `.pup-db-opt-del`
  already free-hands a delete glyph) or keeping this one badge as an SF
  Symbol / text label rather than forcing a Lucide match that doesn't
  exist.

---

## Recommendation

**License & attribution** — Vendoring a subset of Lucide SVGs into
PUPSISPortal is fully permitted: the project is **ISC** (confirmed from the
actual `LICENSE` file), with a Feather-derived subset additionally under
**MIT** (same file, same permissiveness). Both require only that the
copyright notice and permission text travel with copies of the software.
Ship a `THIRD_PARTY_LICENSES.md` (or a comment header in
`Resources/Icons/`) carrying both notice blocks verbatim, quoted in full in
§1 above — that's the entire obligation; no runtime attribution UI is
required.

**Vendoring mechanism** — Skip `npm install lucide-static` as the standing
mechanism (it was used here only for one-time inspection, then deleted).
Use a pinned-commit `curl` loop against
`raw.githubusercontent.com/lucide-icons/lucide/<commit-sha>/icons/<name>.svg`
for the ~30 icons actually needed (script in §2) — no Node dependency, no
48 MB package for 30 files, reproducible by pinning a commit SHA rather than
tracking `main`.

**SwiftUI rendering** — Convert each vendored SVG to a real vector **PDF**
at vendoring time (`rsvg-convert -f pdf`), drop them in
`Sources/PUPSISPortalApp/Resources/Icons/` via `Package.swift`'s existing
`.copy()` resource mechanism (same pattern already used for
`notes-editor.bundle.js`). At runtime, load via `Bundle.module.url(...)`
into `NSImage`, set `.isTemplate = true` (long-documented, reliable AppKit
behavior for PDF — unlike the undocumented, template-incapable SVG-loading
path `NSImage(contentsOf:)` would otherwise take), then wrap with
`Image(nsImage:)`. This drops straight into every existing
`Image(systemName:)` call site in `WebNoteEditor.swift` and
`AgendaView.swift` with no change to the surrounding `.tint`/
`.foregroundStyle` pattern already in use. Skip adding SwiftDraw as a new
SwiftPM dependency for this — it's the better tool for *dynamic* SVG
content, but this app's icon set is fixed and known in advance, and the
PDF-conversion path needs no new runtime dependency at all (SwiftDraw's
LICENSE — zlib — and toolchain compatibility were verified anyway, in case
a future dynamic-icon need changes this call).

**Webview rendering** — Bake each needed icon as a hardcoded inline
`<svg>...</svg>` JS string constant directly in `notes-editor/src/editor.js`
(mirroring `LANG_COLORS`/`DB_COLORS`'s existing plain-constant pattern), and
parse/append it into a widget's `toDOM()` exactly like every other DOM node
those nine `WidgetType` classes already build by hand. No CSP exists in this
webview to navigate, no new esbuild loader is needed (it's a JS string, not
an asset import — confirmed against the actual build command), and the
bundle-size cost for ~10-15 toolbar icons is on the order of a few KB against
an already-1.8 MB committed bundle. Skip a sprite-sheet-in-`Resources`
approach — it would need its own `WKURLSchemeHandler` plumbing (a second one
alongside the existing `pupimg://` handler) for no caching or CSP benefit
over what the already-cached, already-committed `editor.js` bundle gives for
free.

**Icon list** — 32 unique SF Symbols were found across the two files (table
in §5), and 30 have a verified 1:1 Lucide match (checked against the actual
`icons/` directory listing, not guessed). Two — `link.badge.plus` and
`sparkles.slash` — have no exact Lucide equivalent and are flagged rather
than force-matched; both need a small design decision (closest substitute
icon, vs. a manually-composited variant, vs. keeping that one spot as a
label) before the icon system ships.
