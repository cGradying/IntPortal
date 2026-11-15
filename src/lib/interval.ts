// How long until a card comes back (#268): "10m" under a rating button, "in 3 days" in the recap.

const MIN = 60;
const HOUR = 60 * MIN;
const DAY = 24 * HOUR;

/** "10m", "6h", "3d", "2mo", "1.5y". */
export function interval(secs: number): string {
  if (secs < HOUR) return `${Math.max(1, Math.round(secs / MIN))}m`;
  if (secs < DAY) return `${Math.round(secs / HOUR)}h`;
  const d = Math.round(secs / DAY);
  if (d < 30) return `${d}d`;
  if (d < 365) return `${Math.round(d / 30)}mo`;
  return `${+(d / 365).toFixed(1)}y`;
}

/** "in 10 minutes", "tomorrow", "in 3 days", "in 2 months". */
export function dueIn(secs: number): string {
  if (secs < HOUR) {
    const m = Math.max(1, Math.round(secs / MIN));
    return `in ${m} minute${m === 1 ? "" : "s"}`;
  }
  if (secs < DAY) {
    const h = Math.round(secs / HOUR);
    return `in ${h} hour${h === 1 ? "" : "s"}`;
  }
  const d = Math.round(secs / DAY);
  if (d === 1) return "tomorrow";
  if (d < 30) return `in ${d} days`;
  const mo = Math.round(d / 30);
  if (d < 365) return `in ${mo} month${mo === 1 ? "" : "s"}`;
  return `in ${+(d / 365).toFixed(1)} years`;
}
