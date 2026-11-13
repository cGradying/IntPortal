// What the week and day views show (spec 044), apart from drawing it. Pure.
import { clock, isoDate, span, type ClassSession, type DeadlineEntry, type Mark, type Meeting } from "./api";
import { WEEKDAYS } from "./api";
import { contrast } from "./rooms";

export interface DayColumn {
  day: (typeof WEEKDAYS)[number];
  index: number;
  /** A full column, or a thin ghost that keeps the day's place (C3). */
  full: boolean;
}

/** Days with something on them, plus today, are full; the rest are ghosts. An empty Sunday isn't shown. */
export function columns(meetings: Pick<Meeting, "session">[], spanDays: number[], todayIdx: number, moved: Pick<ClassSession, "day">[] = []): DayColumn[] {
  return WEEKDAYS.map((day, index) => ({
    day,
    index,
    full: index === todayIdx || meetings.some((m) => m.session.day === day) || spanDays.includes(index) || moved.some((s) => s.day === day),
  })).filter((c) => c.full || c.index < 6);
}

/** Ink or white, whichever reads better on a course colour (044 Accessibility). */
export const onColor = (hex: string) => (contrast("#ffffff", hex) >= contrast("#120a06", hex) ? "#ffffff" : "#120a06");

export interface Stamp {
  text: "ONLINE" | "VACANT" | "MOVED";
  kind: "online" | "vacant" | "moved";
}

/** A class's mark as a stamp (C4). Vacant wins over moved: it isn't happening at all. */
export function stampOf(mark: Mark, moved: boolean): Stamp | null {
  if (mark === "vacant") return { text: "VACANT", kind: "vacant" };
  if (mark === "online") return { text: "ONLINE", kind: "online" };
  return moved ? { text: "MOVED", kind: "moved" } : null;
}

export interface Gap {
  start: number;
  end: number;
}

/** Free stretches of at least `min` minutes between classes. */
export function gaps(sessions: { start: number; end: number }[], min: number): Gap[] {
  const sorted = [...sessions].sort((a, b) => a.start - b.start);
  const out: Gap[] = [];
  let reach = sorted[0]?.end ?? 0;
  for (const s of sorted.slice(1)) {
    if (s.start - reach >= min) out.push({ start: reach, end: s.start });
    reach = Math.max(reach, s.end);
  }
  return out;
}

/** A moved class's slot in the term, for the dashed ghost it leaves behind (C6). */
export function movedFrom(m: Meeting, term: ClassSession[]): ClassSession | null {
  if (!m.moved) return null;
  const own = term.find((s) => s.subject_code === m.session.subject_code && s.occurrence === m.session.occurrence);
  return own && (own.day !== m.session.day || own.start !== m.session.start) ? own : null;
}

export type Phase = "past" | "now" | "later";

/** Where a class on today's column sits against the clock. Other days have no phase. */
export const phaseOf = (s: { start: number; end: number }, isToday: boolean, minute: number): Phase => (!isToday ? "later" : s.end <= minute ? "past" : s.start <= minute ? "now" : "later");

/** A free gap's label in the day view (C9). */
export const gapText = (g: Gap, isToday: boolean, minute: number) => (isToday && g.start <= minute && minute < g.end ? `Now · free for ${span(g.end - minute)}` : `${span(g.end - g.start)} free`);

/** A deadline's calendar day. */
const dueDay = (d: DeadlineEntry) => ("day" in d.due ? d.due.day : isoDate(new Date(d.due.at * 1000)));

export interface MonthCell {
  date: string;
  due: boolean;
  over: boolean;
  today: boolean;
  thisWeek: boolean;
}

/** The four-week pixel month from `monday` (C11). */
export function month(deadlines: DeadlineEntry[], monday: Date, today: string): MonthCell[] {
  return Array.from({ length: 28 }, (_, i) => {
    const d = new Date(monday);
    d.setDate(monday.getDate() + i);
    const date = isoDate(d);
    const here = deadlines.filter((x) => dueDay(x) === date);
    return { date, due: here.some((x) => !x.overdue), over: here.some((x) => x.overdue), today: date === today, thisWeek: i < 7 };
  });
}

/** Whether a day has a deadline, and whether it's overdue, for the pin under its header. */
export function pin(deadlines: DeadlineEntry[], date: string): "over" | "due" | null {
  const here = deadlines.filter((x) => dueDay(x) === date);
  return here.some((x) => x.overdue) ? "over" : here.length ? "due" : null;
}

/** The stamps not yet seen on this phone land with a thunk once (C5). */
export function freshStamps(ids: string[], seen: Set<string>): string[] {
  return ids.filter((id) => !seen.has(id));
}

/** What a block says (C2): the title always (up to four lines); the code and time/faculty line only in the open day. */
export function blockLines(s: Pick<ClassSession, "subject_code" | "description" | "start" | "end" | "faculty">, open: boolean) {
  return {
    title: s.description || s.subject_code,
    code: open ? s.subject_code : null,
    meta: open ? `${clock(s.start)}–${clock(s.end)}${s.faculty ? ` · ${s.faculty}` : ""}` : null,
    maxLines: 4,
  };
}

/** C13: tapping a day opens it; tapping the open day again closes it. */
export const toggleOpen = (open: number, tapped: number) => (open === tapped ? -1 : tapped);

/** C13: a drag of more than 10 px lets the open day go back to even. */
export const dragLetsGo = (dx: number, dy: number) => Math.hypot(dx, dy) > 10;

/** C10: "Oct 27 – Nov 2", or "Nov 3 – 9" inside one month. */
export function weekRange(monday: Date): string {
  const end = new Date(monday);
  end.setDate(monday.getDate() + 6);
  const md = (d: Date) => d.toLocaleDateString("en-US", { month: "short", day: "numeric" });
  return monday.getMonth() === end.getMonth() ? `${md(monday)} – ${end.getDate()}` : `${md(monday)} – ${md(end)}`;
}
