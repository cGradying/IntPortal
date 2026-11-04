// Hero numbers count from what the student last saw, not from zero (spec 045 C14).
const KEY = "intportal.seen";
const SPAN_MS = 700;

function readSeen(): Record<string, number> {
  try {
    return JSON.parse(localStorage.getItem(KEY) ?? "{}");
  } catch {
    return {};
  }
}

function remember(key: string, value: number) {
  try {
    localStorage.setItem(KEY, JSON.stringify({ ...readSeen(), [key]: value }));
  } catch {
    // It counts from the value itself next time. Harmless.
  }
}

/** Where a count starts: the last seen value, or the value itself the first time. */
export const startOf = (last: number | undefined, to: number) => last ?? to;

/** The value `k` of the way (0 to 1) from `from` to `to`, easing out. */
export const between = (from: number, to: number, k: number) => from + (to - from) * (1 - (1 - Math.min(1, k)) ** 3);

/** A number that counts to `get()` each time it changes. `null` shows as it is. */
export function counted(key: string, get: () => number | null) {
  let shown = $state<number | null>(get());
  $effect(() => {
    const to = get();
    if (to === null) return void (shown = null);
    const from = startOf(readSeen()[key], to);
    remember(key, to);
    if (from === to || matchMedia("(prefers-reduced-motion: reduce)").matches) return void (shown = to);
    let raf = 0;
    const t0 = performance.now() + 250;
    const step = (now: number) => {
      shown = between(from, to, (now - t0) / SPAN_MS);
      if (now - t0 < SPAN_MS) raf = requestAnimationFrame(step);
    };
    shown = from;
    raf = requestAnimationFrame(step);
    return () => cancelAnimationFrame(raf);
  });
  return {
    get value() {
      return shown;
    },
  };
}
