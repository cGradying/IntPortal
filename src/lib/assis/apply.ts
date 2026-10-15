// What "Apply" does with a proposal from LAR. Pure, so it is tested without a
// phone. LAR never writes: the sheet shows a card and the student confirms.
import type { Card, Deck, NoteItem } from "../api";

export type Proposal =
  | { kind: "add_note"; subject: string | null; text: string }
  | { kind: "set_reminder"; date: string; text: string }
  | { kind: "make_cards"; topic: string };

/** A note about a class goes on that class's note; any other goes on one running "From LAR" note for the day. */
export function noteTarget(p: { subject: string | null }, today: string): { key: string; title: string | null } {
  return p.subject ? { key: `class:${p.subject}`, title: null } : { key: `note:lar-${today}`, title: "From LAR" };
}

export function appended(existing: string | undefined, add: string): string {
  const old = existing?.trimEnd() ?? "";
  return old ? `${old}\n\n${add}` : add;
}

/** The student's own note on a deck's subject, to ground "Why?" in what they wrote. */
export function noteFor(notes: NoteItem[], subject: string | null): string | undefined {
  return subject ? existingText(notes, `class:${subject}`) : undefined;
}

export function existingText(notes: NoteItem[], key: string): string | undefined {
  return notes.find((n) => n.key === key)?.text;
}

/** 8 AM local on `date`: the morning of the day it is about. */
export function reminderAt(date: string, hour = 8): Date {
  const [y, m, d] = date.split("-").map(Number);
  return new Date(y, m - 1, d, hour, 0);
}

/** A stable positive id, so applying the same reminder twice replaces it. */
export function reminderId(text: string, date: string): number {
  let h = 0x811c9dc5;
  for (const c of `lar:${date}:${text}`) h = Math.imul(h ^ c.codePointAt(0)!, 16777619) >>> 0;
  return (h & 0x7fffffff) || 1;
}

const blank = (front: string, back: string): Card => ({
  id: "",
  front,
  back,
  accepted: [],
  memory: { due: 0, stability: 0, difficulty: 0, reps: 0, lapses: 0, last_review: null },
});

export function newDeck(id: string, name: string, subject: string | null, cards: { front: string; back: string }[]): Deck {
  return { id, name, subject, cards: cards.map((c) => blank(c.front, c.back)) };
}

/** The card shown to the student before anything is saved. */
export function describe(p: Proposal): { label: string; text: string; yes: string } {
  switch (p.kind) {
    case "add_note":
      return { label: p.subject ? `Note for ${p.subject}` : "New note", text: p.text, yes: "Save note" };
    case "set_reminder": {
      const d = reminderAt(p.date);
      const day = d.toLocaleDateString(undefined, { weekday: "short", month: "short", day: "numeric" });
      return { label: `Reminder · ${day}, 8 AM`, text: p.text, yes: "Set reminder" };
    }
    case "make_cards":
      return { label: "Flashcards", text: p.topic, yes: "Make cards" };
  }
}
