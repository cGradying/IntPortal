// The notebook shelf (spec 046 C1 to C7): one notebook per subject, plus General and Past subjects.
// Pure, so the sorting rules are testable.
import type { NoteItem, StudyOverview } from "./api";

export type ShelfDeck = StudyOverview["decks"][number];

export interface Notebook {
  /** A subject code, or "" for General. */
  code: string;
  name: string;
  past: boolean;
  notes: NoteItem[];
  decks: ShelfDeck[];
  due: number;
}

export const GENERAL = "";
/** Pixels in a notebook's window (C1a). */
export const MAX_PX = 15;

/** Which notebook a note sits in: class notes by key, freeform by subject, day notes in General (C2, C3). */
export function subjectOf(n: NoteItem): string {
  if (n.key.startsWith("class:")) return n.key.slice(6);
  if (n.key.startsWith("note:")) return n.subject?.trim() || GENERAL;
  return GENERAL;
}

/** Pinned first, then newest edit (C4). Day notes are never pinned, so they fall in newest first (C3). */
export const byPinThenNewest = (a: NoteItem, b: NoteItem) => Number(b.pinned) - Number(a.pinned) || b.updated - a.updated;

export function shelves(subjects: [code: string, name: string][], notes: NoteItem[], decks: ShelfDeck[]): Notebook[] {
  const books = new Map<string, Notebook>();
  const book = (code: string, name: string, past: boolean) => {
    let b = books.get(code);
    if (!b) books.set(code, (b = { code, name, past, notes: [], decks: [], due: 0 }));
    return b;
  };
  book(GENERAL, "General", false);
  for (const [code, name] of subjects) book(code, name, false);
  // A code that left the schedule keeps its notes and decks, under the code alone (C7).
  for (const n of notes) book(subjectOf(n), subjectOf(n), true).notes.push(n);
  for (const d of decks) {
    const b = book(d.subject?.trim() || GENERAL, d.subject?.trim() || GENERAL, true);
    b.decks.push(d);
    b.due += d.due;
  }
  for (const b of books.values()) b.notes.sort(byPinThenNewest);
  const all = [...books.values()];
  return [...all.filter((b) => !b.past), ...all.filter((b) => b.past).sort((a, b) => a.code.localeCompare(b.code))];
}

/** The window's pixels: one per note, then one per card due, up to 15 (C1a). */
export function pixels(b: Notebook): ("note" | "due")[] {
  const px: ("note" | "due")[] = [];
  for (let i = 0; i < b.notes.length && px.length < MAX_PX; i++) px.push("note");
  for (let i = 0; i < b.due && px.length < MAX_PX; i++) px.push("due");
  return px;
}

/** A fuller notebook stands taller. */
export const heightOf = (b: Notebook) => 112 + pixels(b).length * 3;

/** Search covers every note's name and text, across subjects (C6). Decks all sit on Cards, so it skips them. */
export function search(books: Notebook[], query: string): NoteItem[] {
  const q = query.trim().toLowerCase();
  if (!q) return [];
  const has = (s: string | null | undefined) => (s ?? "").toLowerCase().includes(q);
  return books
    .flatMap((b) => b.notes)
    .filter((n) => has(n.title) || has(n.text) || has(subjectOf(n)))
    .sort(byPinThenNewest);
}

/** The Cards page (C1): decks by subject, in shelf order, only subjects that have decks. */
export const deckGroups = (subjects: [string, string][], decks: ShelfDeck[]) => shelves(subjects, [], decks).filter((b) => b.decks.length);

/** A deck's bar on the Cards tile: a pixel per 3 cards, gold for the due ones, at most `max`. */
export function deckBar(d: ShelfDeck, max = 20) {
  const gold = Math.min(max, Math.ceil(d.due / 3));
  return { gold, rest: Math.max(0, Math.min(max, Math.ceil(d.cards / 3)) - gold) };
}
