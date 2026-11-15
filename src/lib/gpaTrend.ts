// The Grades trend (#265): one point per term, on a fixed scale that holds the 1.00, 1.50 and
// 2.00 guides, lower (better) drawn higher. Pure, so the plot and its spoken summary are testable.

export interface TermPoint {
  /** Short, for the plot: "2nd 25". */
  label: string;
  /** Long, for the spoken summary: "2nd Semester 2025-2026". */
  term: string;
  v: number;
}

export const GUIDES = [1, 1.5, 2];

/** Positions in a 100 x 40 box. */
export function plot(pts: TermPoint[]) {
  const vs = pts.map((p) => p.v);
  const lo = Math.min(1, ...vs);
  const hi = Math.max(2.25, ...vs);
  const y = (v: number) => 4 + ((v - lo) / (hi - lo)) * 32;
  const last = Math.max(1, pts.length - 1);
  return {
    points: pts.map((p, i) => ({ ...p, x: 4 + (i / last) * 92, y: y(p.v) })),
    guides: GUIDES.map((v) => ({ v, y: y(v) })),
  };
}

/** "GPA 1.75, up from 2.00 in 2nd Semester 2025-2026". Up means better, since lower is better. */
export function spoken(pts: TermPoint[]): string {
  const now = pts.at(-1);
  if (!now) return "";
  const head = `GPA ${now.v.toFixed(2)}`;
  const before = pts.at(-2);
  if (!before) return head;
  const how = now.v < before.v ? "up from" : now.v > before.v ? "down from" : "same as";
  return `${head}, ${how} ${before.v.toFixed(2)} in ${before.term}`;
}
