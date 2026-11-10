// The note editor's edits, as pure functions on plain Markdown (spec 046 C9–C14).
// Each takes the text and a selection and gives back the new text and selection,
// so the editor only dispatches what these return, and tests need no editor.

export interface Edit {
  text: string;
  from: number;
  to: number;
}

export type Inline = "bold" | "italic" | "mark" | "strike" | "code";
const MARKS: Record<Inline, string> = { bold: "**", italic: "_", mark: "==", strike: "~~", code: "`" };

/** Wrap the selection in a mark, or unwrap it when it already has it. An empty selection gets an empty pair. */
export function wrap(text: string, from: number, to: number, kind: Inline): Edit {
  const m = MARKS[kind];
  const n = m.length;
  if (text.slice(from - n, from) === m && text.slice(to, to + n) === m) {
    return { text: text.slice(0, from - n) + text.slice(from, to) + text.slice(to + n), from: from - n, to: to - n };
  }
  const inner = text.slice(from, to);
  if (inner.length >= 2 * n && inner.startsWith(m) && inner.endsWith(m)) {
    return { text: text.slice(0, from) + inner.slice(n, -n) + text.slice(to), from, to: to - 2 * n };
  }
  return { text: text.slice(0, from) + m + inner + m + text.slice(to), from: from + n, to: to + n };
}

export type LineKind = "h" | "bullet" | "number" | "check" | "quote";
const PREFIX: Record<LineKind, string> = { h: "### ", bullet: "- ", number: "1. ", check: "- [ ] ", quote: "> " };
/** Any block prefix a line can have; switching kinds replaces it. */
const ANY = /^(#{1,6} |- \[[ xX]\] |[-*+] |\d+[.)] |> )/;

/** The start and end of the lines the selection touches. */
function lines(text: string, from: number, to: number) {
  const a = text.lastIndexOf("\n", from - 1) + 1;
  const e = text.indexOf("\n", to);
  return [a, e < 0 ? text.length : e] as const;
}

/** Turn the touched lines into headings, bullets, numbers, checklist items or quotes; again turns them back. */
export function setLines(text: string, from: number, to: number, kind: LineKind): Edit {
  const [a, b] = lines(text, from, to);
  const rows = text.slice(a, b).split("\n");
  const p = PREFIX[kind];
  const has = (r: string) => (kind === "number" ? /^\d+[.)] /.test(r) : kind === "check" ? /^- \[[ xX]\] /.test(r) : r.startsWith(p) && !(kind === "bullet" && /^- \[[ xX]\] /.test(r)));
  const off = rows.every(has);
  const out = rows.map((r, i) => {
    const bare = r.replace(ANY, "");
    if (off) return bare;
    return (kind === "number" ? `${i + 1}. ` : p) + bare;
  });
  const body = out.join("\n");
  const delta = body.length - (b - a);
  return { text: text.slice(0, a) + body + text.slice(b), from: rows.length === 1 ? Math.max(a, from + delta) : a, to: b + delta };
}

/** A code block or a divider on its own lines at the cursor; the cursor goes inside the block or after the divider. */
export function block(text: string, at: number, kind: "code" | "divider"): Edit {
  const before = text.slice(0, at);
  const lead = before === "" || before.endsWith("\n\n") ? "" : before.endsWith("\n") ? "\n" : "\n\n";
  const body = kind === "code" ? "```\n\n```" : "---";
  const tail = text.slice(at).startsWith("\n") ? "" : "\n";
  const cursor = at + lead.length + (kind === "code" ? 4 : body.length + tail.length);
  return { text: before + lead + body + tail + text.slice(at), from: cursor, to: cursor };
}

export type Template = "blank" | "lecture" | "cornell" | "exam" | "log";
export const TEMPLATES: { id: Template; name: string; hint: string; body: string }[] = [
  { id: "blank", name: "Blank", hint: "An empty page", body: "" },
  { id: "lecture", name: "Lecture", hint: "Key points, examples, to review", body: "### Key points\n- \n\n### Examples\n- \n\n### To review\n- [ ] " },
  { id: "cornell", name: "Cornell", hint: "Cues, notes, summary", body: "### Cues\n- \n\n### Notes\n\n\n### Summary\n> " },
  { id: "exam", name: "Exam reviewer", hint: "Topics, terms, practice", body: "### Topics\n- [ ] \n\n### Terms\nterm - meaning\n\n### Practice\n1. " },
  { id: "log", name: "Dated log", hint: "One dated entry at a time", body: "" },
];

/**
 * A template on a blank note becomes the note; on a note with text it goes below and never replaces (C13).
 * The cursor lands on the template's first place to write.
 */
export function applyTemplate(text: string, id: Template, heading?: string): Edit {
  const t = TEMPLATES.find((x) => x.id === id)!;
  const body = id === "log" && heading ? `${heading}\n` : t.body;
  if (!body) return { text, from: text.length, to: text.length };
  const lead = text.trim() ? (text.endsWith("\n\n") ? "" : text.endsWith("\n") ? "\n" : "\n\n") : "";
  const base = text.trim() ? text + lead : "";
  // The end of the template's second line: the first place to write, under its first heading.
  const nl = body.indexOf("\n");
  const end = nl < 0 ? body.length : (body.indexOf("\n", nl + 1) + 1 || body.length + 1) - 1;
  const at = base.length + end;
  return { text: base + body, from: at, to: at };
}

/** A dated entry's heading, in the phone's language: `### Mon, Oct 20` (C14). `iso` is `YYYY-MM-DD`. */
export function entryHeading(iso: string, locale?: string): string {
  const [y, m, d] = iso.split("-").map(Number);
  return `### ${new Date(y, m - 1, d).toLocaleDateString(locale, { weekday: "short", month: "short", day: "numeric" })}`;
}

/** Add a dated heading at the end with the cursor on the line after it; a note already ending in it only moves the cursor (C14). */
export function addEntry(text: string, heading: string): Edit {
  // Only blank lines go: an empty checklist item keeps its "- [ ] ".
  const trimmed = text.replace(/\n+$/, "");
  const last = trimmed.slice(trimmed.lastIndexOf("\n") + 1);
  if (last === heading) {
    const t = trimmed + "\n";
    return { text: t, from: t.length, to: t.length };
  }
  const t = (trimmed ? trimmed + "\n\n" : "") + heading + "\n";
  return { text: t, from: t.length, to: t.length };
}

/** Tick or untick the checklist item on the line that starts at `at` (C12). */
export function toggleCheck(text: string, at: number): string {
  const m = /^- \[([ xX])\]( |\n|$)/.exec(text.slice(at, at + 6));
  if (!m) return text;
  return text.slice(0, at + 3) + (m[1] === " " ? "x" : " ") + text.slice(at + 4);
}

export const words = (text: string) => (text.match(/[\p{L}\p{N}][\p{L}\p{N}'’-]*/gu) ?? []).length;

/** A line Make cards can turn into a card (C18): `term - meaning` lines start chosen, with front and back split. */
export interface CardLine {
  text: string;
  front: string;
  back: string;
  chosen: boolean;
}
export function cardLines(text: string): CardLine[] {
  // Headings name sections; they aren't cards. Inline marks go, so a card reads as written.
  const plain = (l: string) => l.replace(/(\*\*|__|==|~~|`)/g, "").replace(/(^|\s)_(\S[^_]*)_(?=\s|$)/g, "$1$2");
  return text
    .split("\n")
    .filter((l) => !/^\s*#{1,6}\s/.test(l))
    .map((l) => plain(l.replace(/^\s*(- \[[ xX]\]|[-*+]|\d+[.)]|>)(\s|$)/, "")).trim())
    .filter((l) => l && !/^(```|---|\[[ xX]\])$/.test(l))
    .map((l) => {
      const m = /^(.+?)\s+[-–—]\s+(.+)$/.exec(l);
      return m ? { text: l, front: m[1].trim(), back: m[2].trim(), chosen: true } : { text: l, front: l, back: "", chosen: false };
    });
}

/**
 * LAR added to this note while it is open (C12a): the store now holds `ext`, the editor last saved `base`
 * and shows `local`. His addition goes after what is on screen, so neither side's words are lost.
 */
export function mergeExternal(local: string, base: string, ext: string, dirty: boolean): string {
  if (ext.startsWith(base)) return local + ext.slice(base.length);
  return dirty ? local : ext;
}

/** What closing the editor does (C17a): blank text deletes a stored note, and is never saved. */
export function onClose(text: string, stored: boolean, saved: boolean): "delete" | "save" | "none" {
  if (!text.trim()) return stored ? "delete" : "none";
  return saved ? "none" : "save";
}

/** Autosave never writes blank text (C17a). */
export const autosaves = (text: string) => !!text.trim();
