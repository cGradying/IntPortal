// Today's list: classes and the student's own events in time order, with
// the free stretches left between them.
import type { Busy } from "./api";

type ClassLike = { session: { start: number; end: number }; phase: string };

export type DayRow<C> =
  | { kind: "class"; i: C; start: number; end: number }
  | { kind: "busy"; b: Busy; start: number; end: number; past: boolean }
  | { kind: "gap"; minutes: number; past: boolean };

export function dayRows<C extends ClassLike>(items: C[], busy: Busy[], day: string, now: number): DayRow<C>[] {
  const entries: Exclude<DayRow<C>, { kind: "gap" }>[] = [
    ...items.map((i) => ({ kind: "class" as const, i, start: i.session.start, end: i.session.end })),
    ...busy.map((b) => {
      const end = b.to.date > day ? 1440 : b.to.minute;
      return { kind: "busy" as const, b, start: b.from.date < day ? 0 : b.from.minute, end, past: end <= now };
    }),
  ].sort((a, b) => a.start - b.start);
  const out: DayRow<C>[] = [];
  let reach: number | null = null;
  for (const e of entries) {
    if (reach !== null && e.start - reach >= 15) out.push({ kind: "gap", minutes: e.start - reach, past: e.start <= now });
    out.push(e);
    reach = Math.max(reach ?? 0, e.end);
  }
  return out;
}
