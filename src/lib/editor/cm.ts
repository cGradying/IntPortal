// The note editor's CodeMirror 6 setup (spec 046 C9–C12): plain Markdown underneath,
// shown formatted as it is typed. A line's marks show only while the cursor is on it;
// checklist boxes are real buttons that tick without opening the keyboard.
import { defaultKeymap, history, historyKeymap, redo, undo, undoDepth, redoDepth } from "@codemirror/commands";
import { Language, defineLanguageFacet, syntaxTree } from "@codemirror/language";
import { GFM, parser } from "@lezer/markdown";
import { EditorSelection, EditorState, RangeSetBuilder, type Range } from "@codemirror/state";
import { Decoration, EditorView, ViewPlugin, WidgetType, keymap, placeholder as hint, type DecorationSet, type ViewUpdate } from "@codemirror/view";
import type { Edit } from "./md";

/** CommonMark plus GitHub's tables, strikethrough and task lists, from Lezer alone: `lang-markdown` would bring HTML, CSS and JS too. */
const MARKDOWN = new Language(defineLanguageFacet(), parser.configure(GFM), [], "markdown");

/** Marks that hide when the cursor is on another line. */
const HIDDEN = new Set(["HeaderMark", "EmphasisMark", "StrikethroughMark", "CodeMark", "QuoteMark"]);
const MARK_CLASS: Record<string, string> = {
  StrongEmphasis: "cm-strong",
  Emphasis: "cm-em",
  Strikethrough: "cm-strike",
  InlineCode: "cm-icode",
};

class Box extends WidgetType {
  constructor(readonly on: boolean, readonly at: number, readonly tick: (at: number) => void) {
    super();
  }
  eq(o: Box) {
    return o.on === this.on && o.at === this.at;
  }
  toDOM() {
    const b = document.createElement("button");
    b.className = "cm-box" + (this.on ? " on" : "");
    b.setAttribute("role", "checkbox");
    b.setAttribute("aria-checked", String(this.on));
    b.setAttribute("aria-label", this.on ? "Done" : "Not done");
    // A tick must not focus the text, or the keyboard opens (C12).
    b.addEventListener("mousedown", (e) => e.preventDefault());
    b.addEventListener("pointerdown", (e) => e.preventDefault());
    b.addEventListener("click", (e) => {
      e.preventDefault();
      this.tick(this.at);
    });
    return b;
  }
  ignoreEvent() {
    return true;
  }
}

class Bullet extends WidgetType {
  toDOM() {
    const s = document.createElement("span");
    s.className = "cm-bullet";
    s.textContent = "•";
    return s;
  }
}
const BULLET = new Bullet();

/** A bad range must never take the page down: the plain Markdown still edits and saves. */
function safeBuild(view: EditorView, tick: (at: number) => void): DecorationSet {
  try {
    return build(view, tick);
  } catch (e) {
    console.error("note formatting", e);
    return Decoration.none;
  }
}

function build(view: EditorView, tick: (at: number) => void): DecorationSet {
  const { state } = view;
  const doc = state.doc;
  const cursorLines = new Set(state.selection.ranges.flatMap((r) => {
    const a = doc.lineAt(r.from).number;
    const b = doc.lineAt(r.to).number;
    return Array.from({ length: b - a + 1 }, (_, i) => a + i);
  }));
  const focused = view.hasFocus;
  const onCursor = (pos: number) => focused && cursorLines.has(doc.lineAt(pos).number);
  const marks: Range<Decoration>[] = [];
  const lines = new Map<number, string>();
  for (const { from, to } of view.visibleRanges) {
    syntaxTree(state).iterate({
      from,
      to,
      enter: (n) => {
        const name = n.name;
        if (/^ATXHeading[1-6]$/.test(name)) lines.set(doc.lineAt(n.from).from, `cm-h cm-h${name.slice(-1)}`);
        else if (name === "Blockquote") for (let p = n.from; p <= n.to; ) {
          const l = doc.lineAt(p);
          lines.set(l.from, "cm-quote");
          p = l.to + 1;
        }
        else if (name === "FencedCode") for (let p = n.from; p <= n.to; ) {
          const l = doc.lineAt(p);
          lines.set(l.from, "cm-codeblock");
          p = l.to + 1;
        }
        else if (name === "HorizontalRule") {
          lines.set(doc.lineAt(n.from).from, "cm-hr");
          if (!onCursor(n.from)) marks.push(Decoration.replace({}).range(n.from, n.to));
        } else if (MARK_CLASS[name]) marks.push(Decoration.mark({ class: MARK_CLASS[name] }).range(n.from, n.to));
        else if (name === "TaskMarker") {
          const on = /x/i.test(doc.sliceString(n.from, n.to));
          const line = doc.lineAt(n.from);
          // The "- " before the box goes too, so the box sits where the bullet was.
          const start = doc.sliceString(line.from, n.from).endsWith("- ") ? n.from - 2 : n.from;
          marks.push(Decoration.replace({ widget: new Box(on, line.from, tick) }).range(start, Math.min(n.to + 1, line.to)));
          // A mark may not be empty: an item with no words yet has nothing to strike.
          if (on && n.to + 1 < line.to) marks.push(Decoration.mark({ class: "cm-done" }).range(n.to + 1, line.to));
        } else if (name === "ListMark") {
          const after = doc.sliceString(n.to, n.to + 4);
          if (/^ \[[ xX]\]/.test(after)) return;
          const t = doc.sliceString(n.from, n.to);
          if ((t === "-" || t === "*" || t === "+") && !onCursor(n.from)) marks.push(Decoration.replace({ widget: BULLET }).range(n.from, n.to));
        } else if (HIDDEN.has(name) && !onCursor(n.from)) {
          // A heading's "### " goes with its space.
          const end = name === "HeaderMark" || name === "QuoteMark" ? Math.min(n.to + 1, doc.lineAt(n.from).to) : n.to;
          marks.push(Decoration.replace({}).range(n.from, end));
        }
      },
    });
    // ==highlight== is not CommonMark: found by hand.
    const text = doc.sliceString(from, to);
    for (const m of text.matchAll(/==([^=\n]+)==/g)) {
      const a = from + m.index!;
      const b = a + m[0].length;
      marks.push(Decoration.mark({ class: "cm-hl" }).range(a, b));
      if (!onCursor(a)) {
        marks.push(Decoration.replace({}).range(a, a + 2));
        marks.push(Decoration.replace({}).range(b - 2, b));
      }
    }
  }
  const out = new RangeSetBuilder<Decoration>();
  const all: Range<Decoration>[] = [...[...lines].map(([at, cls]) => Decoration.line({ class: cls }).range(at)), ...marks];
  all.sort((a, b) => a.from - b.from || a.value.startSide - b.value.startSide || a.to - b.to);
  for (const r of all) out.add(r.from, r.to, r.value);
  return out.finish();
}

export interface NoteView {
  view: EditorView;
  /** Apply an edit from `md.ts` as one change, so undo takes it back in one step. */
  apply(e: Edit): void;
  undo(): void;
  redo(): void;
  can(): { undo: boolean; redo: boolean };
  /** Replace everything (LAR's text arriving), keeping the cursor where it was. */
  set(text: string): void;
  destroy(): void;
}

export function mountNote(
  parent: HTMLElement,
  text: string,
  on: { change: (text: string) => void; select: (from: number, to: number) => void; tick: (at: number) => void },
  placeholder: string,
): NoteView {
  const live = ViewPlugin.fromClass(
    class {
      decorations: DecorationSet;
      constructor(v: EditorView) {
        this.decorations = safeBuild(v, on.tick);
      }
      update(u: ViewUpdate) {
        if (u.docChanged || u.selectionSet || u.viewportChanged || u.focusChanged) this.decorations = safeBuild(u.view, on.tick);
      }
    },
    { decorations: (v) => v.decorations },
  );
  const view = new EditorView({
    parent,
    state: EditorState.create({
      doc: text,
      extensions: [
        history(),
        keymap.of([...defaultKeymap, ...historyKeymap]),
        MARKDOWN,
        EditorView.lineWrapping,
        EditorView.contentAttributes.of({ "aria-label": "Note text", autocapitalize: "sentences", spellcheck: "true", "aria-multiline": "true" }),
        live,
        hint(placeholder),
        EditorView.updateListener.of((u) => {
          if (u.docChanged) on.change(u.state.doc.toString());
          if (u.selectionSet || u.docChanged) {
            const r = u.state.selection.main;
            on.select(r.from, r.to);
          }
        }),
      ],
    }),
  });
  /** The smallest change from `a` to `b`: keeps history and the cursor sane. */
  const change = (a: string, b: string) => {
    let s = 0;
    while (s < a.length && s < b.length && a[s] === b[s]) s++;
    let e = 0;
    while (e < a.length - s && e < b.length - s && a[a.length - 1 - e] === b[b.length - 1 - e]) e++;
    return { from: s, to: a.length - e, insert: b.slice(s, b.length - e) };
  };
  return {
    view,
    apply(ed) {
      view.dispatch({ changes: change(view.state.doc.toString(), ed.text), selection: EditorSelection.range(ed.from, ed.to), scrollIntoView: true });
    },
    undo: () => void undo(view),
    redo: () => void redo(view),
    can: () => ({ undo: undoDepth(view.state) > 0, redo: redoDepth(view.state) > 0 }),
    set(t) {
      const now = view.state.doc.toString();
      if (now === t) return;
      const head = Math.min(view.state.selection.main.head, t.length);
      view.dispatch({ changes: change(now, t), selection: EditorSelection.cursor(head) });
    },
    destroy: () => view.destroy(),
  };
}
