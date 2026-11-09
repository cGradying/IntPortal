// The launch hello (spec 010 C35): what it says and how long it takes.

export function greeting(now: Date): string {
  const h = now.getHours();
  return h < 5 ? "Up late" : h < 12 ? "Good morning" : h < 18 ? "Good afternoon" : "Good evening";
}

export function dateLine(now: Date): string {
  return now.toLocaleDateString(undefined, { weekday: "long", month: "long", day: "numeric" });
}

/** When each part of the hello starts, in ms from the dive's landing. */
export function helloTimes(slow: boolean, reduce: boolean) {
  if (reduce) return { in: [0, 0, 0], hold: 1400, out: 300 };
  const s = slow ? 1.6 : 1;
  return { in: [0, 450 * s, 900 * s], hold: 1500 * s, out: 500 };
}
