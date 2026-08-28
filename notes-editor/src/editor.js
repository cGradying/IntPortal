// PUPSISPortal notes editor: CodeMirror 6 with Obsidian-style live preview —
// $$…$$ / $…$ render inline via KaTeX (auto, no click); move the caret into a
// math span to edit its source. Bridged to the native app over WKWebView.
import { EditorView, Decoration, WidgetType, ViewPlugin, keymap, drawSelection, lineNumbers } from "@codemirror/view";
import { EditorState, StateField, StateEffect, RangeSetBuilder } from "@codemirror/state";
import { history, historyKeymap, defaultKeymap, indentWithTab } from "@codemirror/commands";
import { markdown } from "@codemirror/lang-markdown";
import { Strikethrough } from "@lezer/markdown";
import { syntaxHighlighting, HighlightStyle, LanguageDescription, syntaxTree } from "@codemirror/language";
import { tags as t } from "@lezer/highlight";
import katex from "katex";
import { parse as latexParse, HtmlGenerator as LatexHtmlGenerator } from "latex.js";
// Relative into node_modules — latex.js's package `exports` map blocks the
// bare "latex.js/dist/css/*" subpath, but esbuild resolves a relative file fine.
import latexBaseCss from "../node_modules/latex.js/dist/css/base.css";
import latexArticleCss from "../node_modules/latex.js/dist/css/article.css";
import latexKatexCss from "../node_modules/latex.js/dist/css/katex.css";
// The editor's own chrome (wayfinder ticket #11) — was inline in the Swift
// HTML shell, moved here for the same reason latex.js's CSS above is a text
// import rather than hand-copied: real CSS tooling instead of a Swift
// string literal. Injected as a <style> tag in initEditor(), below.
import editorCss from "./editor.css";

import { javascript } from "@codemirror/lang-javascript";
import { python } from "@codemirror/lang-python";
import { cpp } from "@codemirror/lang-cpp";
import { java } from "@codemirror/lang-java";
import { rust } from "@codemirror/lang-rust";
import { go } from "@codemirror/lang-go";
import { html } from "@codemirror/lang-html";
import { css } from "@codemirror/lang-css";
import { json } from "@codemirror/lang-json";
import { sql } from "@codemirror/lang-sql";
import { php } from "@codemirror/lang-php";
import { xml } from "@codemirror/lang-xml";

// Languages available inside ```lang fenced blocks. `load` returns an
// already-imported LanguageSupport (statically bundled — no dynamic import).
const codeLanguages = [
  LanguageDescription.of({ name: "javascript", alias: ["js", "jsx", "ts", "tsx", "typescript", "node"], load: () => Promise.resolve(javascript({ jsx: true, typescript: true })) }),
  LanguageDescription.of({ name: "python", alias: ["py"], load: () => Promise.resolve(python()) }),
  LanguageDescription.of({ name: "cpp", alias: ["c", "c++", "h", "hpp", "cc"], load: () => Promise.resolve(cpp()) }),
  LanguageDescription.of({ name: "java", load: () => Promise.resolve(java()) }),
  LanguageDescription.of({ name: "rust", alias: ["rs"], load: () => Promise.resolve(rust()) }),
  LanguageDescription.of({ name: "go", alias: ["golang"], load: () => Promise.resolve(go()) }),
  LanguageDescription.of({ name: "html", load: () => Promise.resolve(html()) }),
  LanguageDescription.of({ name: "css", load: () => Promise.resolve(css()) }),
  LanguageDescription.of({ name: "json", load: () => Promise.resolve(json()) }),
  LanguageDescription.of({ name: "sql", load: () => Promise.resolve(sql()) }),
  LanguageDescription.of({ name: "php", load: () => Promise.resolve(php()) }),
  LanguageDescription.of({ name: "xml", load: () => Promise.resolve(xml()) }),
];

// --- Math detection (mirrors the native MarkdownCommands.mathMatches rules) ---
// KaTeX's standard delimiter set (mirrors renderMathInElement) plus the common
// math environments. Ordered block-level first; `whole` passes the entire match
// (incl. \begin…\end) to KaTeX, which parses environments itself.
const MATH_PATTERNS = [
  { re: /\$\$([\s\S]+?)\$\$/g, display: true, whole: false },
  { re: /\\\[([\s\S]+?)\\\]/g, display: true, whole: false },
  { re: /\\begin\{(equation\*?|align\*?|alignat\*?|flalign\*?|gather\*?|multline\*?|aligned|gathered|split|cases|array|[pbBvV]?matrix|smallmatrix)\}[\s\S]*?\\end\{\1\}/g, display: true, whole: true },
  { re: /(?<![$\w])\$(?! )([^$\n]+?)(?<! )\$(?!\$)/g, display: false, whole: false },
  { re: /\\\(([\s\S]+?)\\\)/g, display: false, whole: false },
];

// A full LaTeX document `\documentclass … \end{document}` is rendered whole by
// latexDocField. The inline scanners below must NOT also decorate inside it, or
// two replace decorations overlap (a hard error). These helpers let each skip
// any match that falls within a document region.
const LATEX_DOC_RE = /\\documentclass\b[\s\S]*?\\end\{document\}/g;

function latexRegions(text) {
  const regions = [];
  LATEX_DOC_RE.lastIndex = 0;
  let m;
  while ((m = LATEX_DOC_RE.exec(text))) regions.push({ from: m.index, to: m.index + m[0].length });
  return regions;
}

function inRegions(from, to, regions) {
  return regions.some((r) => from < r.to && to > r.from);
}

// Fenced code content is verbatim — CONFIRMED LIVE BUG this fixes: every
// other "render this markdown construct" decorator below (headings, hr,
// checkboxes, wikilinks, colors, highlight, images, the LaTeX-document
// renderer) scans either the raw document text with a regex or the document
// line-by-line, with NO awareness of block structure — only the syntax-tree
// -based ones (inlineMarkDecorations, fenceDecorations itself) respect it
// natively. So typing `# not a heading` or `- [ ] not a checkbox` or `---`
// as literal example text *inside* a ```fenced block``` got rendered as a
// real heading/checkbox/rule anyway — markdown from outside the block
// leaking into content that should stay exactly what was typed. One shared
// `codeRegions` (mirrors `latexRegions`, syntax-tree based since a regex
// can't reliably find fence boundaries around arbitrary content) plus
// `excludedRegions` combining both is used everywhere `latexRegions` was
// checked instead of sprinkling a second one-off check at each site.
function codeRegions(state) {
  const regions = [];
  syntaxTree(state).iterate({
    enter(node) {
      if (node.name === "FencedCode") regions.push({ from: node.from, to: node.to });
    },
  });
  return regions;
}

function excludedRegions(state) {
  return latexRegions(state.doc.toString()).concat(codeRegions(state));
}

// Every "reveal raw syntax while editing" decorator (math, fences, hr,
// headings, inline marks, wikilinks, colors, highlight, images) asks the
// same question: is the caret inside this construct right now? Confirmed
// live bug this fixes: CodeMirror's default selection sits at document
// offset 0 even before the webview has ever been focused, so a note whose
// very first line was a heading (or any other of these constructs) showed
// its raw marks on first load — nothing had "clicked into" it, but the
// selection-only check couldn't tell the difference. Requiring focus too is
// the fix; every call site below routes through this instead of repeating
// `sel.from <= to && sel.to >= from` (and forgetting the focus half) on its
// own.
function caretOverlaps(view, from, to) {
  if (!view.hasFocus) return false;
  const sel = view.state.selection.main;
  return sel.from <= to && sel.to >= from;
}

function findMath(text) {
  const found = [];
  for (const p of MATH_PATTERNS) {
    p.re.lastIndex = 0;
    let m;
    while ((m = p.re.exec(text))) {
      const from = m.index, to = m.index + m[0].length;
      if (found.some((f) => from < f.to && to > f.from)) continue; // overlaps an earlier (block) match
      found.push({ from, to, latex: p.whole ? m[0] : m[1], display: p.display });
    }
  }
  return found.sort((a, b) => a.from - b.from);
}

class MathWidget extends WidgetType {
  constructor(latex, display) { super(); this.latex = latex; this.display = display; }
  eq(other) { return other.latex === this.latex && other.display === this.display; }
  toDOM() {
    const el = document.createElement(this.display ? "div" : "span");
    el.className = this.display ? "pup-math pup-math-block" : "pup-math";
    try {
      katex.render(this.latex, el, { output: "mathml", displayMode: this.display, throwOnError: false });
    } catch (e) {
      el.textContent = this.latex;
    }
    return el;
  }
  ignoreEvent() { return false; }
}

function mathDecorations(view) {
  const builder = new RangeSetBuilder();
  const text = view.state.doc.toString();
  const regions = excludedRegions(view.state);
  for (const m of findMath(text)) {
    // Show raw source while the caret is inside/adjacent, so it stays editable.
    if (caretOverlaps(view, m.from, m.to)) continue;
    if (inRegions(m.from, m.to, regions)) continue; // rendered by the LaTeX document
    builder.add(m.from, m.to, Decoration.replace({ widget: new MathWidget(m.latex, m.display) }));
  }
  return builder.finish();
}

const mathPlugin = ViewPlugin.fromClass(
  class {
    constructor(view) { this.decorations = mathDecorations(view); }
    update(u) {
      // NOT viewportChanged: mathDecorations scans the whole doc (not
      // visibleRanges), and re-rendering KaTeX on a viewport change shifts
      // layout → fires viewportChanged again → measure/re-render freeze loop.
      if (u.docChanged || u.selectionSet) {
        this.decorations = mathDecorations(u.view);
      }
    }
  },
  { decorations: (v) => v.decorations }
);

// --- Discord-style fenced code blocks: a dark rounded box behind ```lang … ``` ---
function codeBlockDecorations(view) {
  const marks = [];
  for (const { from, to } of view.visibleRanges) {
    syntaxTree(view.state).iterate({
      from, to,
      enter: (node) => {
        if (node.name !== "FencedCode") return;
        const first = view.state.doc.lineAt(node.from).number;
        // A ```pupdb block renders as an interactive table (tablePlugin), not
        // the dark code box.
        const lang = view.state.doc.line(first).text.replace(/^`+/, "").trim().toLowerCase();
        if (lang === "pupdb") return;
        const last = view.state.doc.lineAt(node.to).number;
        for (let n = first; n <= last; n++) {
          const line = view.state.doc.line(n);
          let cls = "pup-code";
          if (n === first) cls += " pup-code-first";
          if (n === last) cls += " pup-code-last";
          marks.push({ from: line.from, deco: Decoration.line({ class: cls }) });
        }
      },
    });
  }
  marks.sort((a, b) => a.from - b.from);
  const builder = new RangeSetBuilder();
  for (const m of marks) builder.add(m.from, m.from, m.deco);
  return builder.finish();
}

const codeBlockPlugin = ViewPlugin.fromClass(
  class {
    constructor(view) { this.decorations = codeBlockDecorations(view); }
    update(u) {
      if (u.docChanged || u.viewportChanged) this.decorations = codeBlockDecorations(u.view);
    }
  },
  { decorations: (v) => v.decorations }
);

// --- Fence hiding + language badge + copy (Discord-style header) ---
const LANG_COLORS = {
  python: "#3572A5", javascript: "#f1e05a", typescript: "#3178c6", cpp: "#f34b7d",
  c: "#a8b9cc", java: "#b07219", rust: "#dea584", go: "#00ADD8", html: "#e34c26",
  css: "#563d7c", json: "#cbcb41", sql: "#e38c00", php: "#4F5D95", xml: "#0060ac",
};
const LANG_LABEL = { js: "javascript", ts: "typescript", py: "python", "c++": "cpp", rs: "rust", golang: "go" };

function copyToClipboard(text) {
  const ta = document.createElement("textarea");
  ta.value = text;
  ta.style.position = "fixed";
  ta.style.opacity = "0";
  document.body.appendChild(ta);
  ta.select();
  try { document.execCommand("copy"); } catch (e) {}
  document.body.removeChild(ta);
}

class CodeHeaderWidget extends WidgetType {
  constructor(lang, code) { super(); this.lang = lang; this.code = code; }
  eq(o) { return o.lang === this.lang && o.code === this.code; }
  toDOM() {
    const canon = LANG_LABEL[this.lang] || this.lang || "code";
    const row = document.createElement("div");
    row.className = "pup-code-header";
    const badge = document.createElement("span");
    badge.className = "pup-lang";
    badge.textContent = canon;
    const color = LANG_COLORS[canon] || "#8a8f98";
    badge.style.setProperty("--lang", color);
    const copy = document.createElement("button");
    copy.className = "pup-copy";
    copy.textContent = "Copy";
    copy.onmousedown = (e) => { e.preventDefault(); e.stopPropagation(); };
    copy.onclick = (e) => {
      e.preventDefault(); e.stopPropagation();
      copyToClipboard(this.code);
      copy.textContent = "Copied";
      setTimeout(() => { copy.textContent = "Copy"; }, 1200);
    };
    row.appendChild(badge);
    row.appendChild(copy);
    return row;
  }
  ignoreEvent() { return false; }
}

class HiddenWidget extends WidgetType {
  toDOM() { const s = document.createElement("span"); s.className = "pup-hidden-fence"; return s; }
  ignoreEvent() { return true; }
}

function fenceDecorations(view) {
  const items = [];
  for (const { from, to } of view.visibleRanges) {
    syntaxTree(view.state).iterate({
      from, to,
      enter: (node) => {
        if (node.name !== "FencedCode") return;
        // Editing this block? Show the raw fences so they're changeable.
        if (caretOverlaps(view, node.from, node.to)) return;
        const open = view.state.doc.lineAt(node.from);
        const close = view.state.doc.lineAt(node.to);
        if (close.number <= open.number) return;
        const lang = open.text.replace(/^`+/, "").trim().toLowerCase();
        if (lang === "pupdb") return;
        const codeStart = open.to + 1, codeEnd = close.from - 1;
        const code = codeEnd > codeStart ? view.state.doc.sliceString(codeStart, codeEnd) : "";
        items.push({ from: open.from, to: open.to, deco: Decoration.replace({ widget: new CodeHeaderWidget(lang, code) }) });
        items.push({ from: close.from, to: close.to, deco: Decoration.replace({ widget: new HiddenWidget() }) });
      },
    });
  }
  items.sort((a, b) => a.from - b.from || a.to - b.to);
  const builder = new RangeSetBuilder();
  for (const it of items) builder.add(it.from, it.to, it.deco);
  return builder.finish();
}

const fencePlugin = ViewPlugin.fromClass(
  class {
    constructor(view) { this.decorations = fenceDecorations(view); }
    update(u) {
      if (u.docChanged || u.selectionSet || u.viewportChanged) this.decorations = fenceDecorations(u.view);
    }
  },
  { decorations: (v) => v.decorations, provide: (p) => EditorView.atomicRanges.of((v) => v.plugin(p)?.decorations || Decoration.none) }
);

// --- Horizontal rule: a line that's exactly ---, ***, or ___ renders as <hr> ---
const HR_RE = /^(?:-{3,}|\*{3,}|_{3,})$/;

class HrWidget extends WidgetType {
  toDOM() {
    // A block-display <div> (not <hr>) so a non-block replace widget still
    // spans the full editor width as a clearly visible rule.
    const el = document.createElement("div");
    el.className = "pup-hr";
    return el;
  }
  ignoreEvent() { return false; }
}

function hrDecorations(view) {
  const builder = new RangeSetBuilder();
  const doc = view.state.doc;
  const regions = excludedRegions(view.state);
  for (let n = 1; n <= doc.lines; n++) {
    const line = doc.line(n);
    if (!HR_RE.test(line.text.trim())) continue;
    if (caretOverlaps(view, line.from, line.to)) continue;
    if (inRegions(line.from, line.to, regions)) continue;
    builder.add(line.from, line.to, Decoration.replace({ widget: new HrWidget() }));
  }
  return builder.finish();
}

const hrPlugin = ViewPlugin.fromClass(
  class {
    constructor(view) { this.decorations = hrDecorations(view); }
    update(u) {
      if (u.docChanged || u.selectionSet) this.decorations = hrDecorations(u.view);
    }
  },
  { decorations: (v) => v.decorations }
);

// --- Interactive checkboxes: "- [ ] " / "- [x] " get a clickable box ---
const CHECKBOX_RE = /^(\s*[-*] )\[( |x|X)\] /;

class CheckboxWidget extends WidgetType {
  constructor(checked, pos) { super(); this.checked = checked; this.pos = pos; }
  eq(other) { return other.checked === this.checked && other.pos === this.pos; }
  toDOM() {
    const box = document.createElement("input");
    box.type = "checkbox";
    box.className = "pup-checkbox";
    box.checked = this.checked;
    box.onmousedown = (e) => e.stopPropagation();
    box.onclick = (e) => {
      e.stopPropagation();
      view.dispatch({ changes: { from: this.pos, to: this.pos + 1, insert: this.checked ? " " : "x" } });
    };
    return box;
  }
  ignoreEvent() { return false; }
}

function checkboxDecorations(view) {
  const builder = new RangeSetBuilder();
  const doc = view.state.doc;
  const regions = excludedRegions(view.state);
  for (let n = 1; n <= doc.lines; n++) {
    const line = doc.line(n);
    const m = line.text.match(CHECKBOX_RE);
    if (!m) continue;
    if (inRegions(line.from, line.to, regions)) continue;
    const bracketOpen = line.from + m[1].length;
    const charPos = bracketOpen + 1;
    builder.add(bracketOpen, bracketOpen + 3, Decoration.replace({ widget: new CheckboxWidget(m[2].toLowerCase() === "x", charPos) }));
  }
  return builder.finish();
}

const checkboxPlugin = ViewPlugin.fromClass(
  class {
    constructor(view) { this.decorations = checkboxDecorations(view); }
    update(u) {
      if (u.docChanged || u.viewportChanged) this.decorations = checkboxDecorations(u.view);
    }
  },
  { decorations: (v) => v.decorations }
);

// --- Headings: hide the leading `#{1,6} ` marks (the line stays styled big via
// the syntax highlighter); reveal them when the caret is on that line. ---
const HEADING_RE = /^(#{1,6})\s/;

function headingDecorations(view) {
  const builder = new RangeSetBuilder();
  const doc = view.state.doc;
  const regions = excludedRegions(view.state);
  for (let n = 1; n <= doc.lines; n++) {
    const line = doc.line(n);
    const m = line.text.match(HEADING_RE);
    if (!m) continue;
    if (caretOverlaps(view, line.from, line.to)) continue; // caret on line, focused → show marks
    if (inRegions(line.from, line.to, regions)) continue;
    builder.add(line.from, line.from + m[0].length, Decoration.replace({}));
  }
  return builder.finish();
}

const headingPlugin = ViewPlugin.fromClass(
  class {
    constructor(view) { this.decorations = headingDecorations(view); }
    update(u) {
      if (u.docChanged || u.selectionSet) this.decorations = headingDecorations(u.view);
    }
  },
  { decorations: (v) => v.decorations }
);

// --- Inline emphasis marks: hide **/__ (strong), */_ (emphasis), ~~ (strike),
// ` (inline code) — the line stays styled via `highlight` below; reveal the
// marks when the caret is anywhere inside the marked span (both delimiters
// together, like headingDecorations reveals a whole line). ---
const INLINE_MARK_NODES = new Set(["EmphasisMark", "CodeMark", "StrikethroughMark"]);

function inlineMarkDecorations(view) {
  const builder = new RangeSetBuilder();
  syntaxTree(view.state).iterate({
    enter(node) {
      if (!INLINE_MARK_NODES.has(node.name)) return;
      const parent = node.node.parent;
      const from = parent ? parent.from : node.from;
      const to = parent ? parent.to : node.to;
      if (caretOverlaps(view, from, to)) return; // caret inside, focused → show marks
      builder.add(node.from, node.to, Decoration.replace({}));
    },
  });
  return builder.finish();
}

const inlineMarkPlugin = ViewPlugin.fromClass(
  class {
    constructor(view) { this.decorations = inlineMarkDecorations(view); }
    update(u) {
      if (u.docChanged || u.selectionSet) this.decorations = inlineMarkDecorations(u.view);
    }
  },
  { decorations: (v) => v.decorations }
);

// --- Note connections: [[Title]] renders as a clickable link to another note ---
const WIKILINK_RE = /\[\[([^\[\]]+)\]\]/g;

class WikilinkWidget extends WidgetType {
  constructor(title) { super(); this.title = title; }
  eq(other) { return other.title === this.title; }
  toDOM() {
    const span = document.createElement("span");
    span.className = "pup-wikilink";
    span.textContent = this.title;
    span.onmousedown = (e) => { e.preventDefault(); e.stopPropagation(); };
    span.onclick = (e) => {
      e.preventDefault(); e.stopPropagation();
      post("open", { title: this.title });
    };
    return span;
  }
  ignoreEvent() { return false; }
}

function wikilinkDecorations(view) {
  const builder = new RangeSetBuilder();
  const text = view.state.doc.toString();
  const regions = excludedRegions(view.state);
  WIKILINK_RE.lastIndex = 0;
  let m;
  while ((m = WIKILINK_RE.exec(text))) {
    const from = m.index, to = m.index + m[0].length;
    if (caretOverlaps(view, from, to)) continue;
    if (inRegions(from, to, regions)) continue;
    builder.add(from, to, Decoration.replace({ widget: new WikilinkWidget(m[1]) }));
  }
  return builder.finish();
}

const wikilinkPlugin = ViewPlugin.fromClass(
  class {
    constructor(view) { this.decorations = wikilinkDecorations(view); }
    update(u) {
      if (u.docChanged || u.selectionSet) this.decorations = wikilinkDecorations(u.view);
    }
  },
  { decorations: (v) => v.decorations }
);

// --- Colored text: {#rrggbb:text} renders `text` in that color, hiding the
// syntax (caret inside reveals the source to edit). Matches cmd("color"). ---
const COLOR_RE = /\{#([0-9a-fA-F]{3,8}):([^{}]*)\}/g;

// Color via a MARK on the real text (not a replace widget), so the text keeps
// whatever its context gives it — a colored word inside a heading stays
// heading-sized/weighted. The `{#hex:` and `}` delimiters are hidden with
// empty replace decorations.
function colorDecorations(view) {
  const builder = new RangeSetBuilder();
  const text = view.state.doc.toString();
  const regions = excludedRegions(view.state);
  COLOR_RE.lastIndex = 0;
  let m;
  while ((m = COLOR_RE.exec(text))) {
    const from = m.index, to = m.index + m[0].length;
    if (caretOverlaps(view, from, to)) continue; // editing, focused → show source
    if (inRegions(from, to, regions)) continue;
    const innerFrom = from + 2 + m[1].length + 1; // past "{#" + hex + ":"
    const innerTo = to - 1;                        // before "}"
    if (innerTo <= innerFrom) continue;            // empty → nothing to color
    builder.add(from, innerFrom, Decoration.replace({}));
    builder.add(innerFrom, innerTo, Decoration.mark({ attributes: { style: `color:#${m[1]}` } }));
    builder.add(innerTo, to, Decoration.replace({}));
  }
  return builder.finish();
}

const colorPlugin = ViewPlugin.fromClass(
  class {
    constructor(view) { this.decorations = colorDecorations(view); }
    update(u) {
      if (u.docChanged || u.selectionSet) this.decorations = colorDecorations(u.view);
    }
  },
  { decorations: (v) => v.decorations }
);

// --- Highlighted text: ==text== renders `text` with a highlight background,
// hiding the `==` marks (matches cmd("highlight")). Neither CommonMark nor
// GFM has a node for this, so it's regex-based like colorPlugin above — it
// was previously a dead command: cmd("highlight") inserted `==` markers that
// rendered as literal text with no styling and nothing hiding them. ---
const HIGHLIGHT_RE = /==([^=]+)==/g;

function highlightMarkDecorations(view) {
  const builder = new RangeSetBuilder();
  const text = view.state.doc.toString();
  const regions = excludedRegions(view.state);
  HIGHLIGHT_RE.lastIndex = 0;
  let m;
  while ((m = HIGHLIGHT_RE.exec(text))) {
    const from = m.index, to = m.index + m[0].length;
    if (caretOverlaps(view, from, to)) continue; // editing, focused → show source
    if (inRegions(from, to, regions)) continue;
    const innerFrom = from + 2, innerTo = to - 2;
    builder.add(from, innerFrom, Decoration.replace({}));
    builder.add(innerFrom, innerTo, Decoration.mark({ class: "pup-highlight" }));
    builder.add(innerTo, to, Decoration.replace({}));
  }
  return builder.finish();
}

const highlightMarkPlugin = ViewPlugin.fromClass(
  class {
    constructor(view) { this.decorations = highlightMarkDecorations(view); }
    update(u) {
      if (u.docChanged || u.selectionSet) this.decorations = highlightMarkDecorations(u.view);
    }
  },
  { decorations: (v) => v.decorations }
);

// --- Inline image preview: ![alt](url) renders as a block <img>, both for
// pupimg:// (pasted/dropped, served by the native side) and http(s):// URLs ---
const IMAGE_RE = /!\[([^\]]*)\]\(([^)]+)\)/g;

class ImageWidget extends WidgetType {
  constructor(url, alt) { super(); this.url = url; this.alt = alt; }
  eq(other) { return other.url === this.url && other.alt === this.alt; }
  toDOM() {
    const img = document.createElement("img");
    img.className = "pup-image";
    img.src = this.url;
    img.alt = this.alt;
    return img;
  }
  ignoreEvent() { return false; }
}

function imageDecorations(view) {
  const builder = new RangeSetBuilder();
  const text = view.state.doc.toString();
  const regions = excludedRegions(view.state);
  IMAGE_RE.lastIndex = 0;
  let m;
  while ((m = IMAGE_RE.exec(text))) {
    const from = m.index, to = m.index + m[0].length;
    if (caretOverlaps(view, from, to)) continue;
    if (inRegions(from, to, regions)) continue;
    const url = m[2].trim();
    if (!/^(https?:|pupimg:)/.test(url)) continue;
    builder.add(from, to, Decoration.replace({ widget: new ImageWidget(url, m[1]) }));
  }
  return builder.finish();
}

const imagePlugin = ViewPlugin.fromClass(
  class {
    constructor(view) { this.decorations = imageDecorations(view); }
    update(u) {
      if (u.docChanged || u.selectionSet) this.decorations = imageDecorations(u.view);
    }
  },
  { decorations: (v) => v.decorations }
);

// --- pupdb: an interactive table with typed columns (text/number/checkbox/
// date/select) embedded as a ```pupdb fenced JSON block. One widget covers
// both "checklist connected to a table" and a lightweight Notion-style
// database — a checkbox column, a custom colored select/status column with
// its own option list, freely added/removed. ---
const DB_COLORS = ["#e5484d", "#e57a00", "#d4a300", "#2f9e44", "#0d9488", "#3b7dd8", "#8f5cd8", "#d6409f"];
let dbUidCounter = 0;
function dbUid() { return `id${Date.now().toString(36)}${(dbUidCounter++).toString(36)}`; }

function newColumn(type) {
  const col = { id: dbUid(), name: type === "select" ? "Status" : type === "checkbox" ? "Done" : "Column", type };
  if (type === "select") {
    col.options = [
      { label: "Not started", color: DB_COLORS[0] },
      { label: "In progress", color: DB_COLORS[2] },
      { label: "Done", color: DB_COLORS[3] },
    ];
  }
  return col;
}

function newRow(columns) {
  const row = { id: dbUid() };
  for (const c of columns) row[c.id] = c.type === "checkbox" ? false : "";
  return row;
}

function starterDb() {
  const columns = [newColumn("text"), newColumn("select"), newColumn("checkbox")];
  return { columns, rows: [newRow(columns)] };
}

const COLUMN_TYPES = ["text", "number", "checkbox", "date", "select"];

function closeDbMenus() { document.querySelectorAll(".pup-db-menu").forEach((m) => m.remove()); }

// A popover anchored under `anchor`, appended to <body> so its own inputs live
// outside CodeMirror's contentEditable (where typing would otherwise be eaten).
function makeDbMenu(anchor) {
  closeDbMenus();
  const menu = document.createElement("div");
  menu.className = "pup-db-menu";
  menu.addEventListener("mousedown", (e) => e.stopPropagation());
  document.body.appendChild(menu);
  const r = anchor.getBoundingClientRect();
  menu.style.left = `${r.left}px`;
  menu.style.top = `${r.bottom + 4}px`;
  setTimeout(() => document.addEventListener("mousedown", function close(e) {
    if (!menu.contains(e.target)) { menu.remove(); document.removeEventListener("mousedown", close); }
  }), 0);
  return menu;
}

class TableWidget extends WidgetType {
  constructor(db, from, to) { super(); this.db = db; this.from = from; this.to = to; this.pending = false; }
  eq(other) { return other.from === this.from && other.to === this.to && JSON.stringify(other.db) === JSON.stringify(this.db); }
  // Interactive widget: CodeMirror must not treat DOM events here as its own,
  // or it steals focus/selection from the inputs.
  ignoreEvent() { return true; }

  // Re-serialize the (live-mutated) db back into the ```pupdb block. Deferred
  // and coalesced: a click that follows a cell edit (blur→change) would
  // otherwise tear down this widget's DOM mid-event, swallowing the click.
  // this.db holds the truth until the single pending write lands.
  commit() {
    if (this.pending) return;
    this.pending = true;
    setTimeout(() => {
      view.dispatch({ changes: { from: this.from, to: this.to, insert: "```pupdb\n" + JSON.stringify(this.db) + "\n```" } });
    }, 0);
  }

  toDOM() {
    const db = this.db;
    const commit = () => this.commit();
    const root = document.createElement("div");
    root.className = "pup-db";
    // The widget is a non-editable island; its form controls are still
    // focusable. Keep CM's editor mousedown handler from hijacking focus.
    root.contentEditable = "false";
    root.addEventListener("mousedown", (e) => e.stopPropagation());

    const openTypeMenu = (anchor) => {
      const menu = makeDbMenu(anchor);
      for (const type of COLUMN_TYPES) {
        const item = document.createElement("div");
        item.className = "pup-db-menuitem pup-db-menuitem-plain";
        item.textContent = type;
        item.onclick = () => {
          const col = newColumn(type);
          db.columns.push(col);
          for (const r of db.rows) r[col.id] = col.type === "checkbox" ? false : "";
          commit(); menu.remove();
        };
        menu.appendChild(item);
      }
    };

    const openOptionMenu = (anchor, col, row, applyPill) => {
      const menu = makeDbMenu(anchor);
      for (const opt of col.options || []) {
        const item = document.createElement("div");
        item.className = "pup-db-menuitem";
        item.style.setProperty("--pill", opt.color);
        const label = document.createElement("span");
        label.textContent = opt.label;
        label.style.flex = "1";
        item.appendChild(label);
        item.onclick = () => { row[col.id] = opt.label; applyPill(); commit(); menu.remove(); };
        const del = document.createElement("span");
        del.className = "pup-db-opt-del";
        del.textContent = "×";
        del.title = "Remove option";
        del.onclick = (e) => {
          e.stopPropagation();
          col.options = (col.options || []).filter((o) => o !== opt);
          for (const r of db.rows) if (r[col.id] === opt.label) r[col.id] = "";
          commit(); menu.remove();
        };
        item.appendChild(del);
        menu.appendChild(item);
      }
      // Inline "new tag" form — replaces the old prompt() (a no-op in WKWebView).
      const form = document.createElement("div");
      form.className = "pup-db-addopt";
      const input = document.createElement("input");
      input.className = "pup-db-optinput";
      input.placeholder = "New tag…";
      let chosen = DB_COLORS[(col.options || []).length % DB_COLORS.length];
      const swatches = document.createElement("div");
      swatches.className = "pup-db-swatches";
      for (const c of DB_COLORS) {
        const s = document.createElement("button");
        s.className = "pup-db-swatch" + (c === chosen ? " sel" : "");
        s.style.background = c;
        s.onclick = () => {
          chosen = c;
          swatches.querySelectorAll(".pup-db-swatch").forEach((e) => e.classList.remove("sel"));
          s.classList.add("sel");
        };
        swatches.appendChild(s);
      }
      const addBtn = document.createElement("button");
      addBtn.className = "pup-db-optadd";
      addBtn.textContent = "Add tag";
      const doAdd = () => {
        const label = input.value.trim();
        if (!label) return;
        col.options = [...(col.options || []), { label, color: chosen }];
        row[col.id] = label;
        applyPill(); commit(); menu.remove();
      };
      addBtn.onclick = doAdd;
      input.onkeydown = (e) => { if (e.key === "Enter") { e.preventDefault(); doAdd(); } };
      form.appendChild(input);
      form.appendChild(swatches);
      form.appendChild(addBtn);
      menu.appendChild(form);
      setTimeout(() => input.focus(), 0);
    };

    // Per-cell text color for text/number/date cells. Stored on the row as
    // `_colors[colId]` so it round-trips in the pupdb JSON; "Default" clears it.
    const openCellColorMenu = (anchor, row, col, applyColor) => {
      const menu = makeDbMenu(anchor);
      const setColor = (hex) => {
        if (hex) { (row._colors || (row._colors = {}))[col.id] = hex; }
        else if (row._colors) { delete row._colors[col.id]; }
        applyColor(); commit(); menu.remove();
      };
      const def = document.createElement("div");
      def.className = "pup-db-menuitem pup-db-menuitem-plain";
      def.textContent = "Default";
      def.onclick = () => setColor(null);
      menu.appendChild(def);
      const swatches = document.createElement("div");
      swatches.className = "pup-db-swatches";
      for (const c of DB_COLORS) {
        const s = document.createElement("button");
        s.className = "pup-db-swatch";
        s.style.background = c;
        s.onclick = () => setColor(c);
        swatches.appendChild(s);
      }
      menu.appendChild(swatches);
    };

    const renderCell = (row, col) => {
      const td = document.createElement("td");
      if (col.type === "checkbox") {
        const box = document.createElement("input");
        box.type = "checkbox";
        box.checked = !!row[col.id];
        box.onchange = () => { row[col.id] = box.checked; commit(); };
        td.appendChild(box);
      } else if (col.type === "select") {
        const pill = document.createElement("button");
        pill.className = "pup-db-pill";
        const applyPill = () => {
          const opt = (col.options || []).find((o) => o.label === row[col.id]);
          pill.textContent = row[col.id] || "＋";
          pill.style.setProperty("--pill", opt ? opt.color : "");
          pill.classList.toggle("pup-db-pill-empty", !opt);
        };
        applyPill();
        pill.onclick = () => openOptionMenu(pill, col, row, applyPill);
        td.appendChild(pill);
      } else {
        const input = document.createElement("input");
        input.className = "pup-db-cell";
        input.type = col.type === "date" ? "date" : col.type === "number" ? "number" : "text";
        input.value = row[col.id] ?? "";
        const applyColor = () => { input.style.color = (row._colors && row._colors[col.id]) || ""; };
        applyColor();
        // Keep memory current on every keystroke (so a cross-click never loses
        // typing); persist on blur/enter.
        input.oninput = () => { row[col.id] = input.value; };
        input.onchange = () => { row[col.id] = input.value; commit(); };
        td.appendChild(input);
        // Hover-reveal color dot → swatch menu; colors this cell's text.
        const dot = document.createElement("button");
        dot.className = "pup-db-cellcolor";
        dot.textContent = "●";
        dot.title = "Text color";
        dot.onclick = () => openCellColorMenu(dot, row, col, applyColor);
        td.appendChild(dot);
      }
      return td;
    };

    const renderHeaderCell = (col, colEl) => {
      const th = document.createElement("th");
      const name = document.createElement("input");
      name.className = "pup-db-name";
      name.value = col.name;
      name.oninput = () => { col.name = name.value || col.name; };
      name.onchange = () => { col.name = name.value || col.name; commit(); };
      th.appendChild(name);
      if (col.type === "select") {
        const cfg = document.createElement("button");
        cfg.className = "pup-db-colmenu";
        cfg.textContent = "▾";
        cfg.title = "Tags";
        cfg.onclick = () => {
          // Configure this column's tags against the first row as a scratch pick.
          openOptionMenu(cfg, col, db.rows[0] || {}, () => {});
        };
        th.appendChild(cfg);
      }
      const del = document.createElement("button");
      del.className = "pup-db-colmenu";
      del.textContent = "×";
      del.title = "Delete column";
      del.onclick = () => {
        db.columns = db.columns.filter((c) => c !== col);
        for (const r of db.rows) delete r[col.id];
        commit();
      };
      th.appendChild(del);
      // Drag the right edge to resize the column. Live-updates the <col> during
      // the drag; persists the width once, on mouseup (no rebuild thrash).
      const grip = document.createElement("div");
      grip.className = "pup-db-resize";
      grip.onmousedown = (e) => {
        e.preventDefault(); e.stopPropagation();
        const startX = e.clientX;
        const startW = colEl.getBoundingClientRect().width;
        const onMove = (ev) => {
          const w = Math.max(60, Math.round(startW + (ev.clientX - startX)));
          colEl.style.width = w + "px";
          col.width = w;
        };
        const onUp = () => {
          document.removeEventListener("mousemove", onMove);
          document.removeEventListener("mouseup", onUp);
          commit();
        };
        document.addEventListener("mousemove", onMove);
        document.addEventListener("mouseup", onUp);
      };
      th.appendChild(grip);
      return th;
    };

    const table = document.createElement("table");
    // Fixed layout so per-column <col> widths are authoritative and resizing sticks.
    const colgroup = document.createElement("colgroup");
    const colEls = db.columns.map((col) => {
      const c = document.createElement("col");
      c.style.width = (col.width || 180) + "px";
      colgroup.appendChild(c);
      return c;
    });
    const actionsCol = document.createElement("col");
    actionsCol.className = "pup-db-actioncol";
    colgroup.appendChild(actionsCol);
    table.appendChild(colgroup);
    const thead = document.createElement("thead");
    const headRow = document.createElement("tr");
    db.columns.forEach((col, i) => headRow.appendChild(renderHeaderCell(col, colEls[i])));
    const addColTh = document.createElement("th");
    const addColBtn = document.createElement("button");
    addColBtn.className = "pup-db-add";
    addColBtn.textContent = "+";
    addColBtn.title = "Add column";
    addColBtn.onclick = () => openTypeMenu(addColBtn);
    addColTh.appendChild(addColBtn);
    headRow.appendChild(addColTh);
    thead.appendChild(headRow);
    table.appendChild(thead);

    const tbody = document.createElement("tbody");
    for (const row of db.rows) {
      const tr = document.createElement("tr");
      for (const col of db.columns) tr.appendChild(renderCell(row, col));
      const delTd = document.createElement("td");
      const delBtn = document.createElement("button");
      delBtn.className = "pup-db-del";
      delBtn.textContent = "×";
      delBtn.title = "Delete row";
      delBtn.onclick = () => { db.rows = db.rows.filter((r) => r !== row); commit(); };
      delTd.appendChild(delBtn);
      tr.appendChild(delTd);
      tbody.appendChild(tr);
    }
    table.appendChild(tbody);
    root.appendChild(table);

    const addRow = document.createElement("button");
    addRow.className = "pup-db-addrow";
    addRow.textContent = "+ Row";
    addRow.onclick = () => { db.rows.push(newRow(db.columns)); commit(); };
    root.appendChild(addRow);

    return root;
  }
}

// Block/line-break-spanning replace decorations must come from a StateField,
// not a ViewPlugin — so the table lives in one. Whole-doc iteration (notes are
// small) since a field has no viewport.
function tableDecorations(state) {
  const items = [];
  syntaxTree(state).iterate({
    enter: (node) => {
      if (node.name !== "FencedCode") return;
      const open = state.doc.lineAt(node.from);
      const close = state.doc.lineAt(node.to);
      if (close.number <= open.number) return;
      const lang = open.text.replace(/^`+/, "").trim().toLowerCase();
      if (lang !== "pupdb") return;
      // Always render the interactive widget (never raw JSON) — every edit goes
      // through its own inputs, and the atomic range keeps the caret out of the
      // block. Malformed JSON falls through the catch below to plain text, which
      // is the only escape hatch needed.
      const bodyStart = open.to + 1, bodyEnd = close.from - 1;
      const body = bodyEnd > bodyStart ? state.doc.sliceString(bodyStart, bodyEnd) : "";
      let db;
      try { db = JSON.parse(body); } catch (e) { return; }
      if (!db || !Array.isArray(db.columns) || !Array.isArray(db.rows)) return;
      items.push({ from: node.from, to: node.to, deco: Decoration.replace({ widget: new TableWidget(db, node.from, node.to), block: true }) });
    },
  });
  items.sort((a, b) => a.from - b.from);
  const builder = new RangeSetBuilder();
  for (const it of items) builder.add(it.from, it.to, it.deco);
  return builder.finish();
}

const tableField = StateField.define({
  create(state) { return tableDecorations(state); },
  update(deco, tr) {
    return tr.docChanged ? tableDecorations(tr.state) : deco;
  },
  provide: (f) => [
    EditorView.decorations.from(f),
    EditorView.atomicRanges.of((view) => view.state.field(f, false) || Decoration.none),
  ],
});

// --- Full LaTeX document: `\documentclass … \end{document}` renders via
// latex.js into an isolated shadow root (so its stylesheet can't touch the
// editor). Caret inside shows raw source; a parse error falls back to <pre>. ---
class LatexDocWidget extends WidgetType {
  constructor(src) { super(); this.src = src; }
  eq(other) { return other.src === this.src; }
  ignoreEvent() { return false; }
  toDOM() {
    const host = document.createElement("div");
    host.className = "pup-latexdoc";
    const shadow = host.attachShadow({ mode: "open" });
    const style = document.createElement("style");
    style.textContent = latexBaseCss + "\n" + latexArticleCss + "\n" + latexKatexCss +
      "\n:host{display:block;margin:8px 0;} .body{padding:0;}";
    shadow.appendChild(style);
    try {
      const generator = new LatexHtmlGenerator({ hyphenate: false });
      const doc = latexParse(this.src, { generator });
      shadow.appendChild(doc.domFragment());
    } catch (e) {
      const pre = document.createElement("pre");
      pre.style.whiteSpace = "pre-wrap";
      pre.textContent = this.src;
      shadow.appendChild(pre);
    }
    return host;
  }
}

function latexDocDecorations(state) {
  const sel = state.selection.main;
  const text = state.doc.toString();
  const items = [];
  const codeBlocks = codeRegions(state);
  for (const r of latexRegions(text)) {
    if (sel.from <= r.to && sel.to >= r.from) continue; // editing → show source
    if (inRegions(r.from, r.to, codeBlocks)) continue; // a \documentclass sample shown as code, not a live document
    const src = text.slice(r.from, r.to);
    items.push({ from: r.from, to: r.to, deco: Decoration.replace({ widget: new LatexDocWidget(src), block: true }) });
  }
  const builder = new RangeSetBuilder();
  for (const it of items) builder.add(it.from, it.to, it.deco);
  return builder.finish();
}

const latexDocField = StateField.define({
  create(state) { return latexDocDecorations(state); },
  update(deco, tr) {
    return tr.docChanged || tr.selection ? latexDocDecorations(tr.state) : deco;
  },
  provide: (f) => [
    EditorView.decorations.from(f),
    EditorView.atomicRanges.of((view) => view.state.field(f, false) || Decoration.none),
  ],
});

// --- Word-by-word fade-in for AI-inserted text (Replace / Insert below in
// runAI, below). The document is correct from the first frame — this is a
// purely visual overlay of Decoration.mark ranges that fades/glows in and
// then clears itself; it never delays or stages what actually gets saved. ---
const startWordFade = StateEffect.define();
const clearWordFade = StateEffect.define();
let wordFadeGen = 0;

const wordFadeField = StateField.define({
  create() { return Decoration.none; },
  update(deco, tr) {
    deco = deco.map(tr.changes);
    for (const effect of tr.effects) {
      if (effect.is(startWordFade)) deco = effect.value.deco;
      // An older batch's own cleanup timer firing after a newer fade has
      // already started must not wipe the new one out from under it.
      if (effect.is(clearWordFade) && effect.value === wordFadeGen) deco = Decoration.none;
    }
    return deco;
  },
  provide: (f) => EditorView.decorations.from(f),
});

// Every inserted word gets the reveal — no word-count cap. What's bounded is
// the *total* cascade time: stagger compresses for a long insert so 1000
// words doesn't take 1000×16ms=16s to finish revealing. (Previously a fixed
// WORD_FADE_MAX=120 word cap just stopped animating past word 120 with no
// visual cue why — reported as "the animation stops halfway".)
const WORD_FADE_STAGGER_MS = 16;
const WORD_FADE_DURATION_MS = 460;
const WORD_FADE_MAX_TOTAL_MS = 1400;

// "sweep" (default, Settings → AI (beta) → Text reveal): one continuous glow
// band per line. "blink": each word gets its own independent glow pulse —
// the original behavior, kept as the alternative rather than replaced.
let aiRevealMode = "sweep";
export function setAIRevealMode(mode) {
  aiRevealMode = mode === "blink" ? "blink" : "sweep";
}

function triggerWordFade(from, to) {
  if (!view) return;
  const text = view.state.doc.sliceString(from, to);
  const words = [...text.matchAll(/\S+/g)];
  if (!words.length) return;

  // Never exceeds WORD_FADE_STAGGER_MS per word for a short insert; only
  // compresses once the word count would otherwise blow past the total-time
  // budget.
  const stagger = Math.min(WORD_FADE_STAGGER_MS, WORD_FADE_MAX_TOTAL_MS / words.length);

  const glowClass = aiRevealMode === "blink" ? "pup-fade-word pup-glow" : "pup-fade-word";
  const builder = new RangeSetBuilder();
  // Grouped by rendered *visual row*, not the document/hard line — a
  // paragraph is normally one long hard line that soft-wraps under
  // EditorView.lineWrapping, so grouping by doc.lineAt gave one giant band
  // spanning the whole paragraph instead of following each wrapped row.
  // Rows are found by measured position (coordsAtPos, rounded) — the same
  // technique the AI pill/menu already use, and the only way to know where a
  // wrap actually broke since CodeMirror doesn't expose that directly.
  const rowGroups = [];
  for (let i = 0; i < words.length; i++) {
    const start = from + words[i].index;
    const end = start + words[i][0].length;
    builder.add(start, end, Decoration.mark({ attributes: { class: glowClass, style: `--i:${i};--stagger:${stagger}ms` } }));

    const coords = view.coordsAtPos(start);
    const row = coords ? Math.round(coords.top) : -1;
    const currentGroup = rowGroups[rowGroups.length - 1];
    if (!currentGroup || currentGroup.row !== row) {
      rowGroups.push({ row, startIndex: i, endIndex: i });
    } else {
      currentGroup.endIndex = i;
    }
  }

  const gen = ++wordFadeGen;
  view.dispatch({ effects: startWordFade.of({ deco: builder.finish(), gen }) });
  const lastDelay = (words.length - 1) * stagger;
  setTimeout(() => {
    if (view) view.dispatch({ effects: clearWordFade.of(gen) });
  }, lastDelay + WORD_FADE_DURATION_MS + 80);

  if (aiRevealMode !== "blink") spawnSweepBands(from, words, rowGroups, stagger);
}

// One glow band per rendered row, positioned from real measured coordinates
// (coordsAtPos — the same technique the AI pill/menu already use) so it
// tracks the actual wrapped layout rather than assuming a fixed-width line.
// Each band's delay/duration matches the word range it's escorting, using
// the same index bookkeeping triggerWordFade already built above — so a
// multi-row insert reads as one glow flowing row to row, not several
// independent effects fighting for attention.
function spawnSweepBands(from, words, rowGroups, stagger) {
  for (const group of rowGroups) {
    const firstWord = words[group.startIndex];
    const lastWord = words[group.endIndex];
    const segStart = from + firstWord.index;
    const segEnd = from + lastWord.index + lastWord[0].length;
    const startCoords = view.coordsAtPos(segStart);
    const endCoords = view.coordsAtPos(segEnd);
    if (!startCoords || !endCoords) continue;

    const rect = {
      left: startCoords.left,
      right: endCoords.right,
      top: Math.min(startCoords.top, endCoords.top),
      bottom: Math.max(startCoords.bottom, endCoords.bottom),
    };
    const wordCount = group.endIndex - group.startIndex + 1;
    const delayMs = group.startIndex * stagger;
    const durationMs = wordCount * stagger + WORD_FADE_DURATION_MS;
    spawnSweepBand(rect, delayMs, durationMs);
  }
}

// Anchored inside the editor's own scroller (`view.scrollDOM`, CodeMirror's
// `.cm-scroller`) as `position:absolute`, not `document.body` as
// `position:fixed`. `coordsAtPos` gives viewport coordinates, which is what
// broke this: a fixed-position band never moved once spawned, so scrolling
// while a band was still running (now up to ~1.4s for a long insert) left it
// glued to its birth position while the actual text scrolled out from under
// it. Converting that viewport rect to scroller-relative once, then
// appending as the scroller's own child, means the band scrolls for free —
// it's just more scrolled content, no scroll listener needed.
function spawnSweepBand(rect, delayMs, durationMs) {
  const scroller = view.scrollDOM;
  const scrollerRect = scroller.getBoundingClientRect();
  const left = rect.left - scrollerRect.left + scroller.scrollLeft;
  const top = rect.top - scrollerRect.top + scroller.scrollTop;

  const band = document.createElement("div");
  band.className = "pup-sweep-band";
  band.style.left = `${left - 4}px`;
  band.style.top = `${top - 3}px`;
  band.style.width = `${Math.max(rect.right - rect.left + 8, 16)}px`;
  band.style.height = `${rect.bottom - rect.top + 6}px`;
  const beam = document.createElement("div");
  beam.className = "pup-sweep-beam";
  beam.style.animationDelay = `${delayMs}ms`;
  beam.style.animationDuration = `${durationMs}ms`;
  band.appendChild(beam);
  scroller.appendChild(band);
  setTimeout(() => band.remove(), delayMs + durationMs + 80);
}

// --- Syntax highlighting: markdown structure + code tokens (Discord-ish) ---
const highlight = HighlightStyle.define([
  // Clearer step between levels (wayfinder ticket #11) — was 1.6/1.4/1.25,
  // a narrowing gap that read muddier the deeper it went.
  { tag: t.heading1, fontSize: "1.75em", fontWeight: "700" },
  { tag: t.heading2, fontSize: "1.4em", fontWeight: "700" },
  { tag: t.heading3, fontSize: "1.15em", fontWeight: "600" },
  { tag: [t.heading4, t.heading5, t.heading6], fontWeight: "600" },
  { tag: t.strong, fontWeight: "700" },
  { tag: t.emphasis, fontStyle: "italic" },
  { tag: t.strikethrough, textDecoration: "line-through" },
  { tag: [t.monospace], fontFamily: "ui-monospace, Menlo, monospace" },
  { tag: [t.link, t.url], color: "#3b7dd8", textDecoration: "underline" },
  { tag: [t.contentSeparator], color: "#999" },
  { tag: t.processingInstruction, color: "#8a8f98" }, // markdown marks (#, *, `)
  // Code tokens (readable on the dark code box and on the page).
  { tag: [t.keyword, t.moduleKeyword, t.controlKeyword, t.operatorKeyword], color: "#c586c0" },
  { tag: [t.string, t.special(t.string), t.regexp], color: "#7ec699" },
  { tag: [t.comment, t.lineComment, t.blockComment], color: "#7a7d84", fontStyle: "italic" },
  { tag: [t.number, t.bool, t.null, t.atom], color: "#d19a66" },
  { tag: [t.function(t.variableName), t.function(t.propertyName)], color: "#61afef" },
  { tag: [t.typeName, t.className, t.namespace], color: "#e5c07b" },
  { tag: [t.variableName, t.propertyName, t.attributeName], color: "#9cdcfe" },
  { tag: [t.operator, t.punctuation, t.bracket, t.derefOperator], color: "#c9ccd3" },
  { tag: [t.definitionKeyword, t.self], color: "#c586c0" },
]);

// --- The editor instance + native bridge ---
let view = null;
// The key of the note currently in the editor. Every change posts tagged with
// this, so an edit that lands after the user switches notes still saves to the
// note it came from — not whatever note is open when the async message arrives.
let docKey = null;

function post(handler, payload) {
  try {
    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers[handler]) {
      window.webkit.messageHandlers[handler].postMessage(payload);
    }
  } catch (e) {}
}

let editorStyleInjected = false;

export function initEditor(initialText, key) {
  // Once per document load, not per note switch — this doesn't change
  // between notes the way setContent's doc/key do.
  if (!editorStyleInjected) {
    const style = document.createElement("style");
    style.textContent = editorCss;
    document.head.appendChild(style);
    editorStyleInjected = true;
  }
  docKey = key || null;
  const parent = document.getElementById("editor");
  parent.innerHTML = "";
  view = new EditorView({
    parent,
    state: EditorState.create({
      doc: initialText || "",
      extensions: [
        history(),
        drawSelection(),
        EditorView.lineWrapping,
        keymap.of([...defaultKeymap, ...historyKeymap, indentWithTab]),
        // Base CommonMark already tags Emphasis/StrongEmphasis/InlineCode; add
        // GFM's Strikethrough only (not the full GFM set) so `~~text~~` gets a
        // node to style/hide — the checkbox and pupdb-table constructs already
        // have their own regex-based plugins and don't need GFM's TaskList/Table.
        markdown({ codeLanguages, extensions: [Strikethrough] }),
        syntaxHighlighting(highlight),
        codeBlockPlugin,
        fencePlugin,
        mathPlugin,
        hrPlugin,
        headingPlugin,
        inlineMarkPlugin,
        checkboxPlugin,
        wikilinkPlugin,
        colorPlugin,
        highlightMarkPlugin,
        imagePlugin,
        tableField,
        latexDocField,
        wordFadeField,
        EditorView.updateListener.of((u) => {
          if (u.docChanged) post("notes", { key: docKey, text: view.state.doc.toString() });
          if (u.docChanged || u.selectionSet) updateAIPill();
        }),
      ],
    }),
  });
  view.dom.addEventListener("paste", handlePaste);
  view.dom.addEventListener("drop", handleDrop);
  view.dom.addEventListener("dragover", (e) => e.preventDefault());
  view.focus();
}

// --- Images: paste or drag-drop a file, native side saves it and calls
// insertImage back with the pupimg:// URL to drop at the caret ---
function sendImage(file) {
  if (!file || !file.type.startsWith("image/")) return;
  const ext = file.type.split("/")[1] || "png";
  const reader = new FileReader();
  reader.onload = () => post("image", { base64: reader.result.split(",")[1], ext });
  reader.readAsDataURL(file);
}

function handlePaste(e) {
  const file = Array.from(e.clipboardData?.items || [])
    .find((item) => item.type.startsWith("image/"))?.getAsFile();
  if (!file) return;
  e.preventDefault();
  sendImage(file);
}

function handleDrop(e) {
  const file = e.dataTransfer?.files?.[0];
  if (!file || !file.type.startsWith("image/")) return;
  e.preventDefault();
  sendImage(file);
}

export function insertImage(url) {
  if (!view) return;
  const { from } = view.state.selection.main;
  const insert = `![](${url})\n`;
  view.dispatch({ changes: { from, insert }, selection: { anchor: from + insert.length } });
  view.focus();
}

export function setContent(text, key) {
  if (!view) return initEditor(text, key);
  docKey = key || null;
  const current = view.state.doc.toString();
  if (current === text) return;
  view.dispatch({ changes: { from: 0, to: current.length, insert: text || "" } });
}

export function getContent() { return view ? view.state.doc.toString() : ""; }

// --- AI drafting: the native side reads the selection, asks a local model, and
// calls insertText back with the result. Kept as two plain accessors rather
// than a postMessage round trip — the request is driven from the toolbar, which
// is native, so there's nothing for the editor to initiate. ---

export function getSelection() {
  if (!view) return "";
  const { from, to } = view.state.selection.main;
  // No selection: fall back to the whole note, so "expand on this" works on a
  // note you've just started typing without making you select it first.
  return from === to ? view.state.doc.toString() : view.state.sliceDoc(from, to);
}

// Insert generated text after the selection (or at the caret), leaving what
// the user wrote untouched — a draft is an addition, never a replacement.
export function insertText(text) {
  if (!view || !text) return;
  const { to } = view.state.selection.main;
  const insert = `\n\n${text}\n`;
  view.dispatch({ changes: { from: to, insert }, selection: { anchor: to + insert.length } });
  view.focus();
}

// --- AI selection assist: select text -> a floating "Ask AI" pill -> pick
// Summarize / Answer this / a custom prompt -> native runs the model ->
// Replace / Insert below / Copy. Follows the same in-page-popover pattern as
// the pupdb column menu (makeDbMenu, above): a <div> on document.body,
// positioned from getBoundingClientRect, dismissed on outside mousedown —
// nothing here is native chrome. ---
let aiEnabled = false;
let aiPill = null;
// The range + text a request was sent for, captured when the menu opened
// (not when the result lands) — the caret may have moved by then, and the
// answer must still apply to what the user actually selected.
let pendingAI = null;
let aiRequestId = 0;

export function setAIEnabled(on) {
  aiEnabled = !!on;
  if (!aiEnabled) removeAIPill();
}

function closeAIMenus() {
  document.querySelectorAll(".pup-ai-menu").forEach((m) => m.remove());
  pendingAI = null;
}

function removeAIPill() {
  if (aiPill) { aiPill.remove(); aiPill = null; }
  closeAIMenus();
}

// Places `el` (already appended, so its real size is measurable) below `r`
// by default — that's the requested placement — but flips above `r` when
// there isn't room below, and always clamps left/right so the element can
// never render partly off the visible viewport regardless of where the
// selection sits.
function positionBelow(el, r) {
  const margin = 8;
  const rect = el.getBoundingClientRect();

  let left = r.left;
  if (left + rect.width + margin > window.innerWidth) {
    left = window.innerWidth - rect.width - margin;
  }
  left = Math.max(margin, left);

  let top = r.bottom + 6;
  if (top + rect.height + margin > window.innerHeight) {
    const above = r.top - rect.height - 6;
    top = above >= margin ? above : Math.max(margin, window.innerHeight - rect.height - margin);
  }

  el.style.left = `${left}px`;
  el.style.top = `${top}px`;
}

function updateAIPill() {
  if (!view) return;
  const { from, to } = view.state.selection.main;
  if (!aiEnabled || from === to) { removeAIPill(); return; }
  // Anchor to the selection's end, so the pill sits under the text the user
  // just finished selecting rather than over the start of it.
  const coords = view.coordsAtPos(to) || view.coordsAtPos(from);
  if (!coords) { removeAIPill(); return; }
  if (!aiPill) {
    aiPill = document.createElement("button");
    aiPill.className = "pup-ai-pill";
    aiPill.textContent = "✨ Ask AI";
    // Keep the editor's selection alive through the click — a plain click
    // would collapse it before openAIMenu ever reads `from`/`to`.
    aiPill.addEventListener("mousedown", (e) => e.preventDefault());
    document.body.appendChild(aiPill);
  }
  aiPill.onclick = () => openAIMenu(aiPill, from, to);
  positionBelow(aiPill, coords);
}

function openAIMenu(anchor, from, to) {
  closeAIMenus();
  const text = view.state.sliceDoc(from, to);
  const menu = document.createElement("div");
  menu.className = "pup-ai-menu";
  menu.addEventListener("mousedown", (e) => e.stopPropagation());
  document.body.appendChild(menu);
  // The anchor's rect, kept for re-positioning as the menu's own content
  // (and so its size) changes underneath it — "Thinking…" then a preview.
  menu._anchorRect = anchor.getBoundingClientRect();

  const item = (label, onClick) => {
    const el = document.createElement("div");
    el.className = "pup-ai-menuitem";
    el.textContent = label;
    el.addEventListener("click", onClick);
    menu.appendChild(el);
  };
  item("Summarize", () => runAI(menu, "summarize", null, text, from, to));
  item("Answer this", () => runAI(menu, "answer", null, text, from, to));
  item("Structure this", () => runAI(menu, "structure", null, text, from, to));

  const custom = document.createElement("div");
  custom.className = "pup-ai-custom";
  const input = document.createElement("input");
  input.className = "pup-ai-custom-input";
  input.placeholder = "Custom prompt…";
  input.addEventListener("keydown", (e) => {
    if (e.key === "Enter" && input.value.trim()) {
      runAI(menu, "custom", input.value.trim(), text, from, to);
    }
  });
  custom.appendChild(input);
  menu.appendChild(custom);
  positionBelow(menu, menu._anchorRect);
  input.focus();

  setTimeout(() => document.addEventListener("mousedown", function close(e) {
    if (!menu.contains(e.target) && e.target !== aiPill) {
      menu.remove();
      document.removeEventListener("mousedown", close);
    }
  }), 0);
}

function runAI(menu, mode, prompt, text, from, to) {
  const id = ++aiRequestId;
  pendingAI = { id, from, to };
  menu.innerHTML = "";
  const status = document.createElement("div");
  status.className = "pup-ai-status";
  status.textContent = "Thinking…";
  menu.appendChild(status);
  positionBelow(menu, menu._anchorRect);
  post("ai", { id, mode, prompt, text });
}

// Native calls back into this once the model answers (or fails).
export function aiResult(id, text, error) {
  const menu = document.querySelector(".pup-ai-menu");
  if (!menu || !pendingAI || pendingAI.id !== id) return;
  menu.innerHTML = "";

  if (error) {
    const line = document.createElement("div");
    line.className = "pup-ai-status pup-ai-error";
    line.textContent = error;
    menu.appendChild(line);
    positionBelow(menu, menu._anchorRect);
    return;
  }

  const preview = document.createElement("div");
  preview.className = "pup-ai-preview";
  preview.textContent = text;
  menu.appendChild(preview);

  const actions = document.createElement("div");
  actions.className = "pup-ai-actions";
  const range = pendingAI;
  const button = (label, onClick) => {
    const b = document.createElement("button");
    b.className = "pup-ai-actionbtn";
    b.textContent = label;
    b.addEventListener("click", onClick);
    actions.appendChild(b);
  };
  button("Replace", () => {
    view.dispatch({ changes: { from: range.from, to: range.to, insert: text },
      selection: { anchor: range.from + text.length } });
    triggerWordFade(range.from, range.from + text.length);
    view.focus();
    removeAIPill();
  });
  button("Insert below", () => {
    const insert = `\n\n${text}\n`;
    const textStart = range.to + 2; // past the leading "\n\n"
    view.dispatch({ changes: { from: range.to, insert },
      selection: { anchor: range.to + insert.length } });
    triggerWordFade(textStart, textStart + text.length);
    view.focus();
    removeAIPill();
  });
  button("Copy", () => {
    navigator.clipboard?.writeText(text);
    closeAIMenus();
  });
  menu.appendChild(actions);
  positionBelow(menu, menu._anchorRect);
}

// --- Toolbar commands (called from the native toolbar via evaluateJavaScript) ---
function wrapSelection(marker) {
  const { from, to } = view.state.selection.main;
  const sel = view.state.sliceDoc(from, to);
  if (sel) {
    view.dispatch({ changes: { from, to, insert: marker + sel + marker },
      selection: { anchor: from + marker.length, head: from + marker.length + sel.length } });
  } else {
    view.dispatch({ changes: { from, insert: marker + marker },
      selection: { anchor: from + marker.length } });
  }
  view.focus();
}

function prefixLines(makePrefix) {
  const { from, to } = view.state.selection.main;
  const startLine = view.state.doc.lineAt(from).number;
  const endLine = view.state.doc.lineAt(to).number;
  const changes = [];
  for (let n = startLine; n <= endLine; n++) {
    const line = view.state.doc.line(n);
    changes.push({ from: line.from, insert: makePrefix(n - startLine) });
  }
  view.dispatch({ changes });
  view.focus();
}

function toggleHeading() {
  const line = view.state.doc.lineAt(view.state.selection.main.from);
  const m = line.text.match(/^(#{1,6}) /);
  let insert, removeLen = 0;
  if (!m) { insert = "# "; }
  else if (m[1].length >= 6) { insert = ""; removeLen = 7; }
  else { insert = "#".repeat(m[1].length + 1) + " "; removeLen = m[1].length + 1; }
  view.dispatch({ changes: { from: line.from, to: line.from + removeLen, insert } });
  view.focus();
}

// Set the current line to a specific heading level (1–6), or 0 for normal text.
function setHeading(level) {
  const line = view.state.doc.lineAt(view.state.selection.main.from);
  const m = line.text.match(/^(#{1,6}) /);
  const removeLen = m ? m[0].length : 0;
  const insert = level > 0 ? "#".repeat(Math.min(level, 6)) + " " : "";
  view.dispatch({ changes: { from: line.from, to: line.from + removeLen, insert } });
  view.focus();
}

// Insert a ```lang fenced block around the selection (or empty, caret inside).
function insertCodeBlock(lang) {
  const { from, to } = view.state.selection.main;
  const sel = view.state.sliceDoc(from, to);
  const line = view.state.doc.lineAt(from);
  const pre = from === line.from ? "" : "\n";
  const fence = pre + "```" + (lang || "") + "\n";
  const insert = fence + sel + "\n```\n";
  const caret = from + fence.length + sel.length;
  view.dispatch({ changes: { from, to, insert }, selection: { anchor: caret } });
  view.focus();
}

export function cmd(name, arg) {
  if (!view) return;
  switch (name) {
    case "bold": return wrapSelection("**");
    case "italic": return wrapSelection("*");
    case "strike": return wrapSelection("~~");
    case "highlight": return wrapSelection("==");
    case "code": return wrapSelection("`");
    case "codeblock": return insertCodeBlock(arg);
    case "math": return wrapSelection("$$");
    case "heading": return arg !== undefined ? setHeading(parseInt(arg, 10)) : toggleHeading();
    case "bullet": return prefixLines(() => "- ");
    case "numbered": return prefixLines((i) => `${i + 1}. `);
    case "checklist": return prefixLines(() => "- [ ] ");
    case "quote": return prefixLines(() => "> ");
    case "color": {
      const { from, to } = view.state.selection.main;
      const sel = view.state.sliceDoc(from, to);
      const p = `{#${arg}:`;
      view.dispatch({ changes: { from, to, insert: p + sel + "}" },
        selection: { anchor: from + p.length, head: from + p.length + sel.length } });
      return view.focus();
    }
    case "link": {
      const { from, to } = view.state.selection.main;
      const sel = view.state.sliceDoc(from, to);
      const insert = `[${sel}](url)`;
      const urlAt = from + sel.length + 3;
      view.dispatch({ changes: { from, to, insert }, selection: { anchor: urlAt, head: urlAt + 3 } });
      return view.focus();
    }
    case "image": {
      // Manual image by URL/alt (paste & drag-drop go through the native bridge).
      const { from, to } = view.state.selection.main;
      const sel = view.state.sliceDoc(from, to);
      const insert = `![${sel}](url)`;
      const urlAt = from + sel.length + 4;
      view.dispatch({ changes: { from, to, insert }, selection: { anchor: urlAt, head: urlAt + 3 } });
      return view.focus();
    }
    case "wikilink": {
      const { from, to } = view.state.selection.main;
      const sel = view.state.sliceDoc(from, to);
      const insert = `[[${sel}]]`;
      const caret = from + 2 + sel.length;
      view.dispatch({ changes: { from, to, insert }, selection: { anchor: caret } });
      return view.focus();
    }
    case "table": {
      const { from } = view.state.selection.main;
      const line = view.state.doc.lineAt(from);
      const body = "```pupdb\n" + JSON.stringify(starterDb()) + "\n```\n";
      const insert = (line.text.length ? "\n" : "") + body;
      view.dispatch({ changes: { from: line.to, insert }, selection: { anchor: line.to + insert.length } });
      return view.focus();
    }
    case "rule": {
      const { from } = view.state.selection.main;
      const line = view.state.doc.lineAt(from);
      const insert = (line.text.length ? "\n" : "") + "---\n";
      view.dispatch({ changes: { from: line.to, insert }, selection: { anchor: line.to + insert.length } });
      return view.focus();
    }
    case "latexdoc": {
      const { from } = view.state.selection.main;
      const line = view.state.doc.lineAt(from);
      const skeleton = "\\documentclass{article}\n\\begin{document}\n\n\\end{document}\n";
      const insert = (line.text.length ? "\n" : "") + skeleton;
      // Caret on the blank body line, between \begin and \end.
      const caret = line.to + insert.indexOf("\n\n\\end") + 1;
      view.dispatch({ changes: { from: line.to, insert }, selection: { anchor: caret } });
      return view.focus();
    }
    // Appends a "## <date>" heading at the end of the doc — a running dated
    // log entry point for shared per-subject class notes (arg is the label,
    // e.g. "Aug 16", computed natively from the schedule or "today").
    case "datestamp": {
      const end = view.state.doc.length;
      const sep = end === 0 ? "" : "\n\n";
      const insert = `${sep}## ${arg}\n\n`;
      view.dispatch({ changes: { from: end, insert }, selection: { anchor: end + insert.length } });
      return view.focus();
    }
  }
}
