// eMabini deadlines as the student reads them: a day word, a clean title, the
// subject, overdue ones apart. Pure, so the card only draws.
import type { Deadline } from "./api";

const startOfDay = (d: Date) => new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime();

/** "Overdue", "Today", "Tomorrow", a weekday within the week, else a short date. */
export function dueLabel(d: Deadline, now: Date): string {
  if (d.overdue || d.due * 1000 < now.getTime()) return "Overdue";
  const due = new Date(d.due * 1000);
  const days = Math.round((startOfDay(due) - startOfDay(now)) / 86_400_000);
  if (days === 0) return "Today";
  if (days === 1) return "Tomorrow";
  return days < 7 ? due.toLocaleDateString(undefined, { weekday: "short" }) : due.toLocaleDateString(undefined, { month: "short", day: "numeric" });
}

/** Overdue and upcoming, each soonest first; `max` caps the upcoming list. */
export function splitDeadlines(list: Deadline[], now: Date, max = Infinity) {
  const late = (d: Deadline) => d.overdue || d.due * 1000 < now.getTime();
  const byDue = [...list].sort((a, b) => a.due - b.due);
  return { overdue: byDue.filter(late), upcoming: byDue.filter((d) => !late(d)).slice(0, max) };
}

/** Moodle titles an event "X is due", "X closes" or "X opens"; the student wants X. */
export const titleOf = (name: string) => name.replace(/\s+(is due|closes|opens)$/i, "");

/** `Subject_Term_Section` as its parts; the whole name as the subject when it doesn't fit. */
export function splitCourseName(fullname: string): { subject: string; term: string; section: string } {
  const parts = fullname.split("_").map((s) => s.trim());
  return parts.length === 3 ? { subject: parts[0], term: parts[1], section: parts[2] } : { subject: fullname.trim(), term: "", section: "" };
}

/** The subject part of a course name. */
export const subjectOf = (fullname: string) => splitCourseName(fullname).subject;
