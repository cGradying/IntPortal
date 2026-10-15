// Cards from a note: the pure parts. What goes to the model, and what comes
// back, is cleaned here so it is tested without a phone.
import type { NoteItem } from "../api";

export const MAX_CARDS = 20;
/** The model's window is small; a longer note is cut at a line break rather than refused. */
export const MAX_SOURCE = 3500;

export type Draft = { front: string; back: string };

const key = (s: string) => s.toLowerCase().replace(/[^\p{L}\p{N}]/gu, "");

/** The note's words, tidied and cut to what fits. */
export function sourceText(text: string): string {
  const t = text.replace(/\r/g, "").replace(/[ \t]+/g, " ").replace(/\n{3,}/g, "\n\n").trim();
  if (t.length <= MAX_SOURCE) return t;
  const cut = t.slice(0, MAX_SOURCE);
  const nl = cut.lastIndexOf("\n");
  return (nl > MAX_SOURCE / 2 ? cut.slice(0, nl) : cut).trim();
}

/** Trim, drop blanks, drop a front the deck already has or the list repeats, cap the count. */
export function tidy(proposed: Draft[], existingFronts: string[], cap = MAX_CARDS): Draft[] {
  const seen = new Set(existingFronts.map(key));
  const out: Draft[] = [];
  for (const c of proposed) {
    const front = c.front.trim();
    const back = c.back.trim();
    const k = key(front);
    if (!k || !back || seen.has(k)) continue;
    seen.add(k);
    out.push({ front, back });
    if (out.length >= cap) break;
  }
  return out;
}

export function noteLabel(n: Pick<NoteItem, "key" | "title">): string {
  if (n.key.startsWith("note:")) return n.title?.trim() || "Untitled note";
  if (n.key.startsWith("class:")) return n.key.slice(6);
  const [y, m, d] = n.key.slice(4).split("-").map(Number);
  return new Date(y, m - 1, d).toLocaleDateString(undefined, { weekday: "short", month: "short", day: "numeric" });
}

/** Notes with words in them, the deck's own subject first. */
export function usable(notes: NoteItem[], subject: string | null): NoteItem[] {
  const own = (n: NoteItem) => (subject && n.key === `class:${subject}` ? 0 : 1);
  return notes.filter((n) => n.text.trim()).sort((a, b) => own(a) - own(b) || b.updated - a.updated);
}

/** Sentences pass through; the rest become one the student can act on. */
export function friendlyError(e: unknown): string {
  const s = typeof e === "string" ? e : (e as { message?: string })?.message ?? "";
  if (s.endsWith(".") || s.endsWith("?")) return s;
  if (s.includes("busy")) return "LAR is still working on something. Give it a second.";
  if (s.includes("memory")) return "This phone doesn't have enough free memory right now. Close other apps and try again.";
  if (s.includes("does not fit")) return "That note is too long for me. Try a shorter one.";
  if (s.includes("first") || s.includes("Download the model")) return "Turn IntAssis on first, in the You tab.";
  return "I couldn't make cards from that. Try again, or try another note.";
}

/** Same cap as the reader in the Rust core (`pdf::MAX_BYTES`); checked first so a huge file is never read into memory. */
export const MAX_PDF = 20 * 1024 * 1024;
const TOO_BIG = "That PDF is over 20 MB. Pick a smaller one, o hatiin muna.";

/** Why this picked file can't be used, or null when it can. */
export function pdfProblem(f: { size: number; type: string; name: string }): string | null {
  if (!f.size) return "That file is empty. Pick another PDF.";
  if (f.type !== "application/pdf" && !(f.type === "" && /\.pdf$/i.test(f.name))) return "That isn't a PDF. Pick a .pdf file.";
  return f.size > MAX_PDF ? TOO_BIG : null;
}

/** A scanned PDF is pictures of pages: the reader may return stray marks but no words. */
export function hasText(text: string): boolean {
  return (text.match(/\p{L}/gu)?.length ?? 0) >= 20;
}

const SCANNED = "This PDF looks scanned, so there is no text to read. Walang mabasa si LAR dito. Try a PDF you can select words in.";

/** The PDF reader's errors (crates/intportal-ai/src/pdf.rs), as sentences. */
export function pdfError(e: unknown): string {
  const s = typeof e === "string" ? e : (e as { message?: string })?.message ?? "";
  if (s.includes("no text")) return SCANNED;
  if (s.includes("over 20 MB")) return TOO_BIG;
  const pages = s.match(/the limit is (\d+)/);
  if (pages) return `That PDF has too many pages (limit ${pages[1]}). Pick a shorter one.`;
  if (s.includes("could not be read")) return "I couldn't open that file as a PDF. Try another one.";
  if (s.includes("raw bytes")) return "I couldn't read that PDF. Try again, or try a note instead.";
  return friendlyError(e);
}
