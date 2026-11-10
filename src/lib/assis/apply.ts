// What "Apply" does with a proposal from LAR. Pure, so it is tested without a
// phone. LAR never writes: the sheet shows a card and the student confirms.
import type { Card, DeadlineEntry, Deck, NoteItem, Today } from "../api";
import { entryLabel } from "../deadlines";

export type Proposal =
  | { kind: "add_note"; subject: string | null; text: string }
  | { kind: "set_reminder"; date: string; text: string }
  | { kind: "make_cards"; topic: string; count: number };

/** A note about a class goes on that class's note; any other goes on one running "From LAR" note for the day. */
export function noteTarget(p: { subject: string | null }, today: string): { key: string; title: string | null } {
  return p.subject ? { key: `class:${p.subject}`, title: null } : { key: `note:lar-${today}`, title: "From LAR" };
}

export function appended(existing: string | undefined, add: string): string {
  const old = existing?.trimEnd() ?? "";
  return old ? `${old}\n\n${add}` : add;
}

/** Swaps the characters from `start` to `end` for `add`. */
export function replaced(text: string, start: number, end: number, add: string): string {
  return text.slice(0, start) + add + text.slice(end);
}

/**
 * A suggestion over the chat's input (spec 048 C16). `fill` puts it in the field for the student to finish;
 * `open` is a source key (a note, `card:<deck>`, `plan:<subject>`) to open instead of asking; `why` is the
 * short gold reason it is offered.
 */
export interface Suggestion {
  label: string;
  fill: boolean;
  why?: string;
  open?: string;
}

/** What the chat knows of the student's day, for the first suggestions. Any part may be missing. */
export interface Day {
  now: Date;
  /** The nearest due, from the one deadline list. */
  due?: DeadlineEntry | null;
  /** The note opened last. */
  note?: Pick<NoteItem, "key" | "title"> | null;
  next?: Today["next"];
}

const cut = (s: string, n: number) => (s.length > n ? `${s.slice(0, n - 1).trimEnd()}…` : s);
const hhmm = (min: number) => `${Math.floor(min / 60) % 12 || 12}:${String(min % 60).padStart(2, "0")}`;
const DAYS = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];

/**
 * What the chat suggests first (spec 048 C17): about the open note when there is one; else from the day,
 * each with its reason and skipped when its data is missing, topped up from the plain ones. At most four.
 */
export function starters(noteOpen: boolean, day?: Day): Suggestion[] {
  const base: Suggestion[] = [
    { label: "Ano ang due ko?", fill: false },
    { label: "Anong klase ko ngayon?", fill: false },
    { label: "Remind me bukas ng umaga", fill: true },
    { label: "Add a note: bring calculator", fill: true },
  ];
  if (noteOpen) return [{ label: "Summarize this note", fill: false }, { label: "What should I review from this note?", fill: false }, ...base.slice(0, 2)];
  if (!day) return base;
  const out: Suggestion[] = [];
  if (day.due) out.push({ label: "What's due this week?", fill: false, why: `${cut(day.due.title, 14)} ${entryLabel(day.due, day.now)}` });
  if (day.note?.title) out.push({ label: `Explain ${cut(day.note.title, 28)} simply`, fill: false, why: "last note" });
  if (day.next && !day.next.is_now && day.next.minutes_away < 24 * 60) out.push({ label: "Anong klase ko ngayon?", fill: false, why: hhmm(day.next.session.start) });
  out.push(base[2]);
  for (const b of base) if (out.length < 4 && !out.some((o) => o.label === b.label || (b === base[0] && day.due))) out.push(b);
  return out.slice(0, 4);
}

/** A source key's kind, as `sources.ts` reads it. */
const kindOf = (key: string) => (key.startsWith("card:") ? "deck" : key.startsWith("plan:") ? "subject" : "note");

/**
 * What a search found, by kind (spec 048 C12): "2 notes", "1 note and 1 deck", "2 notes, 1 deck and 1 subject".
 * The found step reads "Found " + this, the folded trace "Looked at " + this.
 */
export function foundLine(sources: { key: string }[]): string {
  const parts = (["note", "deck", "subject"] as const)
    .map((k) => [k, sources.filter((s) => kindOf(s.key) === k).length] as const)
    .filter(([, n]) => n)
    .map(([k, n]) => `${n} ${k}${n === 1 ? "" : "s"}`);
  return parts.length < 2 ? (parts[0] ?? "") : `${parts.slice(0, -1).join(", ")} and ${parts[parts.length - 1]}`;
}

/**
 * The follow-ups after an answer in this session (spec 048 C18), by its intent and sources, with no model
 * call. Anything else gets the day's suggestions again.
 */
export function followUps(turn: { intent?: string; sources?: { key: string; title: string }[] }, day?: Day): Suggestion[] {
  const src = turn.sources?.[0];
  if (turn.intent === "due" && day?.due) {
    const at = "at" in day.due.due ? new Date(day.due.due.at * 1000) : new Date(`${day.due.due.day}T12:00`);
    const before = DAYS[(at.getDay() + 6) % 7];
    const out: Suggestion[] = [{ label: `Remind me ${before} night`, fill: true }];
    if (day.due.subject) out.push({ label: `Open ${day.due.subject}`, fill: false, open: `plan:${day.due.subject}` });
    return out;
  }
  if (turn.intent === "classes") {
    const out: Suggestion[] = [{ label: "What's due this week?", fill: false }];
    const code = day?.next?.session.subject_code;
    if (code) out.push({ label: `Open ${code}`, fill: false, open: `plan:${code}` });
    return out;
  }
  if (turn.intent === "ask" && src) return [{ label: `Make 5 cards from ${cut(src.title, 24)}`, fill: false }, { label: `Open ${cut(src.title, 24)}`, fill: false, open: src.key }];
  return starters(false, day);
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

/** True when the words read as Filipino or Taglish. A small word list is enough to pick the language of a one-line notice. */
export function looksFilipino(...texts: (string | undefined)[]): boolean {
  const fil = ["ang", "ng", "sa", "na", "ko", "mo", "ako", "ba", "po", "para", "paalala", "handa", "bukas", "mamaya", "ngayon", "lang", "i-remind", "i-confirm", "pa-remind"];
  return (texts.join(" ").toLowerCase().match(/[\p{L}-]+/gu) ?? []).some((w) => fil.includes(w));
}

/** What a reminder says when the phone will not show notifications: saved, but it cannot ring until they are on. */
export const notificationsOff = (fil: boolean) =>
  fil ? "Na-save ko na, pero naka-off ang notifications. I-on mo sa Settings para tumunog ito." : "I saved it, but notifications are off. Turn them on in Settings so it can ring.";

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

const LAR_KEY = "larReminders";

/** Ids of reminders LAR set that are still ahead, so the weekly reschedule leaves them queued. */
export function larReminderIds(now = Date.now()): Set<number> {
  try {
    const all: { id: number; at: number }[] = JSON.parse(localStorage.getItem(LAR_KEY) ?? "[]");
    return new Set(all.filter((r) => r.at > now).map((r) => r.id));
  } catch {
    return new Set(); // Storage off: LAR's reminders last until the next reschedule.
  }
}

export function rememberLarReminder(id: number, at: Date) {
  try {
    const all: { id: number; at: number }[] = JSON.parse(localStorage.getItem(LAR_KEY) ?? "[]");
    localStorage.setItem(LAR_KEY, JSON.stringify(all.filter((r) => r.at > Date.now() && r.id !== id).concat({ id, at: at.getTime() })));
  } catch {
    // Storage off: see larReminderIds.
  }
}
