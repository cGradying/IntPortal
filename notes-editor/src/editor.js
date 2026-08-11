// PUPSISPortal notes editor: CodeMirror 6 with Obsidian-style live preview —
// $$…$$ / $…$ render inline via KaTeX (auto, no click); move the caret into a
// math span to edit its source. Bridged to the native app over WKWebView.
import { EditorView, Decoration, WidgetType, ViewPlugin, keymap, drawSelection, lineNumbers } from "@codemirror/view";
import { EditorState, RangeSetBuilder } from "@codemirror/state";
import { history, historyKeymap, defaultKeymap, indentWithTab } from "@codemirror/commands";
import { markdown } from "@codemirror/lang-markdown";
import { syntaxHighlighting, HighlightStyle, LanguageDescription, syntaxTree } from "@codemirror/language";
import { tags as t } from "@lezer/highlight";
import katex from "katex";

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
const BLOCK = /\$\$([\s\S]+?)\$\$/g;
const INLINE = /(?<![$\w])\$(?! )([^$\n]+?)(?<! )\$(?!\$)/g;

function findMath(text) {
  const found = [];
  let m;
  BLOCK.lastIndex = 0;
  while ((m = BLOCK.exec(text))) {
    found.push({ from: m.index, to: m.index + m[0].length, latex: m[1], display: true });
  }
  INLINE.lastIndex = 0;
  while ((m = INLINE.exec(text))) {
    const from = m.index, to = m.index + m[0].length;
    if (found.some((f) => from < f.to && to > f.from)) continue; // inside a block
    found.push({ from, to, latex: m[1], display: false });
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
  const sel = view.state.selection.main;
  const text = view.state.doc.toString();
  for (const m of findMath(text)) {
    // Show raw source while the caret is inside/adjacent, so it stays editable.
    const editing = sel.from <= m.to && sel.to >= m.from;
    if (editing) continue;
    builder.add(m.from, m.to, Decoration.replace({ widget: new MathWidget(m.latex, m.display) }));
  }
  return builder.finish();
}

const mathPlugin = ViewPlugin.fromClass(
  class {
    constructor(view) { this.decorations = mathDecorations(view); }
    update(u) {
      if (u.docChanged || u.selectionSet || u.viewportChanged) {
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
  const sel = view.state.selection.main;
  const items = [];
  for (const { from, to } of view.visibleRanges) {
    syntaxTree(view.state).iterate({
      from, to,
      enter: (node) => {
        if (node.name !== "FencedCode") return;
        // Editing this block? Show the raw fences so they're changeable.
        if (sel.from <= node.to && sel.to >= node.from) return;
        const open = view.state.doc.lineAt(node.from);
        const close = view.state.doc.lineAt(node.to);
        if (close.number <= open.number) return;
        const lang = open.text.replace(/^`+/, "").trim().toLowerCase();
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

// --- Syntax highlighting: markdown structure + code tokens (Discord-ish) ---
const highlight = HighlightStyle.define([
  { tag: t.heading1, fontSize: "1.6em", fontWeight: "700" },
  { tag: t.heading2, fontSize: "1.4em", fontWeight: "700" },
  { tag: t.heading3, fontSize: "1.25em", fontWeight: "600" },
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

export function initEditor(initialText, key) {
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
        markdown({ codeLanguages }),
        syntaxHighlighting(highlight),
        codeBlockPlugin,
        fencePlugin,
        mathPlugin,
        EditorView.updateListener.of((u) => {
          if (u.docChanged) post("notes", { key: docKey, text: view.state.doc.toString() });
        }),
      ],
    }),
  });
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
    case "heading": return toggleHeading();
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
  }
}
