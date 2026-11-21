// Own classes on the UI side (spec 060): grouping the week's own sessions back
// into classes for the editor, and the day chips. Mirrors `own_class.rs`.
import type { ClassSession, ClassTime, OwnClass, Weekday } from "./api";

export const DAYS: { day: Weekday; short: string }[] = [
  { day: "Monday", short: "M" },
  { day: "Tuesday", short: "T" },
  { day: "Wednesday", short: "W" },
  { day: "Thursday", short: "Th" },
  { day: "Friday", short: "F" },
  { day: "Saturday", short: "S" },
  { day: "Sunday", short: "Su" },
];
const ORDER = DAYS.map((d) => d.day);

/** The own sessions as classes, in the order they were added; days at one time are one meeting. */
export function classesOf(sessions: ClassSession[]): OwnClass[] {
  const out: OwnClass[] = [];
  for (const s of sessions) {
    if (!s.own) continue;
    let c = out.find((c) => c.code === s.subject_code);
    if (!c) out.push((c = { code: s.subject_code, name: s.description, room: s.room ?? "", teacher: s.faculty, meetings: [] }));
    const m = c.meetings.find((m) => m.start === s.start && m.end === s.end);
    if (!m) c.meetings.push({ days: [s.day], start: s.start, end: s.end });
    else if (!m.days.includes(s.day)) m.days.push(s.day);
  }
  for (const m of out.flatMap((c) => c.meetings)) m.days.sort((a, b) => ORDER.indexOf(a) - ORDER.indexOf(b));
  return out;
}

/** "MW 7:30–9:00 AM" for one meeting. */
export function timeLine(m: ClassTime): string {
  const days = DAYS.filter((d) => m.days.includes(d.day)).map((d) => d.short).join("");
  return `${days} ${clock(m.start, m.end >= 720 && m.start < 720)}–${clock(m.end, true)}`;
}

/** 450 is "7:30", with AM or PM when `period`. */
export function clock(min: number, period: boolean): string {
  const h = Math.floor(min / 60) % 24;
  const t = `${((h + 11) % 12) + 1}:${String(min % 60).padStart(2, "0")}`;
  return period ? `${t} ${h < 12 ? "AM" : "PM"}` : t;
}

/** The first thing wrong with a class before it goes to the core, or "" (C3). */
export function problem(c: OwnClass): string {
  if (!c.name.trim()) return "Give the class a name.";
  if (!c.meetings.length || c.meetings.some((m) => !m.days.length)) return "Pick at least one day.";
  if (c.meetings.some((m) => m.end <= m.start)) return "It has to end after it starts.";
  return "";
}
