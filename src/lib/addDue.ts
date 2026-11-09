// The due adder's logic (spec 041 C10–C14), kept out of the window so it can
// be tested: the core's drafts become tickets with the student's fixes on
// top, the When row's days come from the timetable, and a greyed Add says
// what is missing. Days are ISO dates ("2026-11-13") in local time.
import { isoDate, WEEKDAYS, type ClassSession, type DeadlineDraft, type ItemKind } from "./api";

export type Ticket = DeadlineDraft & { keep: boolean };
export type Fix = Partial<DeadlineDraft>;

/** Only these three: an own deadline is never a lecture. */
export const KINDS: [ItemKind, string][] = [["quiz", "Quiz"], ["exam", "Exam"], ["project", "Project"]];
export const kindName = (k: ItemKind) => KINDS.find(([x]) => x === k)?.[1] ?? "Project";

/** The core's drafts with the student's fixes laid over them by position, and
 *  the ones the student unticked. A fix outlives a re-read of the text. A lone
 *  ticket has no keep toggle, so it is always kept. */
export function tickets(parsed: DeadlineDraft[], fixes: Fix[], dropped: boolean[]): Ticket[] {
  return parsed.map((p, i) => ({ ...p, ...fixes[i], keep: parsed.length < 2 || !dropped[i] }));
}

const day = (iso: string, plus = 0) => {
  const [y, m, d] = iso.split("-").map(Number);
  return new Date(y, m - 1, d + plus);
};

/** The subject has a class on that day. */
export function meets(sessions: ClassSession[], code: string | null, iso: string): boolean {
  const wd = WEEKDAYS[(day(iso).getDay() + 6) % 7];
  return !!code && sessions.some((s) => s.subject_code === code && s.day === wd);
}

/** The subject's next class days after tomorrow, at most `count`, within three weeks. */
export function nextClassDays(sessions: ClassSession[], code: string | null, today: string, count = 2): string[] {
  const out: string[] = [];
  for (let i = 2; i < 21 && out.length < count; i++) {
    const iso = isoDate(day(today, i));
    if (meets(sessions, code, iso)) out.push(iso);
  }
  return out;
}

/** The When row: Today, Tomorrow, the subject's next class days, and the ticket's own day. */
export function whenDays(sessions: ClassSession[], code: string | null, date: string | null, today: string): string[] {
  const days = [today, isoDate(day(today, 1)), ...nextClassDays(sessions, code, today)];
  if (date && !days.includes(date)) days.push(date);
  return days.sort();
}

/** A chip's word: Today, Tomorrow, "Fri 13" this month, "Fri, Dec 4" after. */
export function dayLabel(iso: string, today: string): string {
  const d = day(iso);
  const t = day(today);
  const n = Math.round((d.getTime() - t.getTime()) / 864e5);
  if (n === 0) return "Today";
  if (n === 1) return "Tomorrow";
  if (d.getMonth() === t.getMonth() && d.getFullYear() === t.getFullYear()) return `${d.toLocaleDateString("en-US", { weekday: "short" })} ${d.getDate()}`;
  return d.toLocaleDateString("en-US", { weekday: "short", month: "short", day: "numeric" });
}

/** For screen readers: "Friday, November 13". */
export const dayName = (iso: string) => day(iso).toLocaleDateString("en-US", { weekday: "long", month: "long", day: "numeric" });

/** The ticket's stub: FRI over 13 over NOV. */
export function stub(iso: string) {
  const d = day(iso);
  const up = (o: Intl.DateTimeFormatOptions) => d.toLocaleDateString("en-US", o).toUpperCase();
  return { dow: up({ weekday: "short" }), day: d.getDate(), mon: up({ month: "short" }) };
}

export type Missing = "text" | "keep" | "day" | "name";
export interface Verdict {
  ok: boolean;
  label: string;
  why?: Missing;
  /** The ticket that is missing it. */
  i?: number;
}

/** The button's word. Greyed, it names what is missing, and tapping it goes there. */
export function verdict(ts: Ticket[], edit: boolean): Verdict {
  const kept = ts.filter((t) => t.keep).length;
  if (!ts.length) return { ok: false, label: edit ? "Save" : "Add", why: "text" };
  if (!kept) return { ok: false, label: "Keep one", why: "keep" };
  const i = ts.findIndex((t) => t.keep && !t.date);
  if (i >= 0) return { ok: false, label: "Add a day", why: "day", i };
  const j = ts.findIndex((t) => t.keep && !t.title.trim());
  if (j >= 0) return { ok: false, label: "Name it", why: "name", i: j };
  return { ok: true, label: edit ? "Save" : kept > 1 ? `Add ${kept}` : "Add" };
}

/** "quiz COMP fri" names a subject only by its letters, and two subjects can
 *  share them. The core leaves such a draft with no subject; here the letters
 *  pick the one that meets on the draft's day (or the only one), and leave the
 *  title. With no clear match the draft is left as the core read it. */
export function guessSubject(d: DeadlineDraft, sessions: ClassSession[]): DeadlineDraft {
  if (d.subject) return d;
  const codes = [...new Set(sessions.map((s) => s.subject_code))];
  for (const word of d.title.split(/\s+/)) {
    if (!/^[A-Za-z]{3,5}$/.test(word)) continue;
    const prefix = word.toUpperCase();
    const hits = codes.filter((c) => c.toUpperCase().split(/\s+/)[0] === prefix);
    const onDay = d.date ? hits.filter((c) => meets(sessions, c, d.date!)) : [];
    const code = hits.length === 1 ? hits[0] : onDay.length === 1 ? onDay[0] : null;
    if (!code) continue;
    const title = d.title.split(/\s+/).filter((w) => w !== word).join(" ").trim();
    return { ...d, subject: code, title: title || d.title };
  }
  return d;
}
