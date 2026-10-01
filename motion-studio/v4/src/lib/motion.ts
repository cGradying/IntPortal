// Motion core for v4. Everything is a pure function of time: no clocks, no
// Math.random, no CSS transitions. Springs are closed-form, so any frame can
// be computed on its own (seek-safe, loop-safe).
import beatsJson from "../../beats.json";

export const FPS = 60;
export const BEATS_TOTAL = 196; // 7 phrases x 7 bars x 4 beats
export const FRAMES = 5428; // 196 beats at ~130 BPM, whole frames so the loop closes
export const DURATION = FRAMES / FPS;
const NOMINAL = DURATION / BEATS_TOTAL; // 0.46156 s

// Measured grid (after the music is generated) or the nominal one.
const GRID: number[] = (beatsJson as { beats?: number[] }).beats?.length
  ? (beatsJson as { beats: number[] }).beats
  : Array.from({ length: BEATS_TOTAL + 1 }, (_, i) => i * NOMINAL);

/** Seconds at fractional beat b. */
export function B(b: number): number {
  if (b <= 0) return b * NOMINAL;
  const i = Math.floor(b);
  if (i >= GRID.length - 1) return GRID[GRID.length - 1] + (b - GRID.length + 1) * NOMINAL;
  return GRID[i] + (GRID[i + 1] - GRID[i]) * (b - i);
}

/** Fractional beat at time t (inverse of B). */
export function bt(t: number): number {
  if (t <= 0) return t / NOMINAL;
  let lo = 0, hi = GRID.length - 1;
  if (t >= GRID[hi]) return hi + (t - GRID[hi]) / NOMINAL;
  while (hi - lo > 1) {
    const m = (lo + hi) >> 1;
    if (GRID[m] <= t) lo = m; else hi = m;
  }
  return lo + (t - GRID[lo]) / (GRID[hi] - GRID[lo]);
}

export const clamp = (x: number, a = 0, b = 1) => Math.min(b, Math.max(a, x));
export const lerp = (a: number, b: number, k: number) => a + (b - a) * k;
export const inv = (a: number, b: number, x: number) => clamp((x - a) / (b - a));
export const smooth = (x: number) => { const k = clamp(x); return k * k * (3 - 2 * k); };

// ------------------------------------------------------------------ springs
export type Spr = { k: number; d: number };
export const SOFT: Spr = { k: 120, d: 22 }; // trail edges, camera
export const STD: Spr = { k: 170, d: 26 }; // the default: zeta ~ 1
export const SNAP: Spr = { k: 320, d: 35 }; // small UI, lead edges
export const CAM: Spr = { k: 90, d: 19 }; // camera: slower, still critical

/** Closed-form step response 0 -> 1 of a unit-mass spring, zero start velocity. */
export function spring(t: number, s: Spr = STD): number {
  if (t <= 0) return 0;
  const w0 = Math.sqrt(s.k);
  const z = s.d / (2 * w0);
  if (z < 0.999) {
    const wd = w0 * Math.sqrt(1 - z * z);
    return 1 - Math.exp(-z * w0 * t) * (Math.cos(wd * t) + ((z * w0) / wd) * Math.sin(wd * t));
  }
  if (z <= 1.001) return 1 - Math.exp(-w0 * t) * (1 + w0 * t);
  const r = Math.sqrt(z * z - 1);
  const r1 = -w0 * (z - r), r2 = -w0 * (z + r);
  return 1 - (r2 * Math.exp(r1 * t) - r1 * Math.exp(r2 * t)) / (r2 - r1);
}

/** Keys: [beat, value]. One spring is added per change of target, never restarted. */
export type Key = [number, number];
export function track(t: number, keys: Key[], s: Spr = STD): number {
  let v = keys[0][1];
  for (let i = 1; i < keys.length; i++) {
    const dt = t - B(keys[i][0]);
    if (dt <= 0) break;
    v += (keys[i][1] - keys[i - 1][1]) * spring(dt, s);
  }
  return v;
}

/** Same as track, but each key may carry its own spring. */
export function trackS(t: number, keys: [number, number, Spr?][], s: Spr = STD): number {
  let v = keys[0][1];
  for (let i = 1; i < keys.length; i++) {
    const dt = t - B(keys[i][0]);
    if (dt <= 0) break;
    v += (keys[i][1] - keys[i - 1][1]) * spring(dt, keys[i][2] ?? s);
  }
  return v;
}

/**
 * Tab indicator: keys [beat, left, right]. On each move the leading edge
 * runs on a stiff spring and the trailing edge on a soft one, so the bar
 * stretches toward its target and then catches up.
 */
export function indicator(t: number, keys: [number, number, number][]): [number, number] {
  let l = keys[0][1], r = keys[0][2];
  for (let i = 1; i < keys.length; i++) {
    const dt = t - B(keys[i][0]);
    if (dt <= 0) break;
    const [, l0, r0] = keys[i - 1];
    const [, l1, r1] = keys[i];
    const right = l1 + r1 > l0 + r0;
    l += (l1 - l0) * spring(dt, right ? SOFT : SNAP);
    r += (r1 - r0) * spring(dt, right ? SNAP : SOFT);
  }
  return [l, r];
}

/**
 * Content inside a morphing box: its own enter and exit timing. Enters a
 * beat-fraction after the box starts moving, exits fast before the next
 * content arrives. Returns opacity and blur (px).
 */
export function swapAlpha(t: number, inB: number, outB = Infinity, o: { delay?: number; lead?: number } = {}) {
  const ti = B(inB) + (o.delay ?? 0.06);
  const a = spring(t - ti, { k: 260, d: 32 });
  const to = outB === Infinity ? Infinity : B(outB) - (o.lead ?? 0.02);
  const x = to === Infinity ? 0 : clamp((t - to) / 0.11);
  const out = x * x * (3 - 2 * x);
  const op = clamp(a * (1 - out));
  return { o: op, blur: (1 - clamp(a)) * 6 + out * 6, y: (1 - clamp(a)) * 6 - out * 4, on: op > 0.002 };
}

/** Wraps a frame index into the loop. */
export const loopT = (frame: number) => ((frame % FRAMES) + FRAMES) % FRAMES;

// ------------------------------------------------------------------ colors
const hex = (c: string) => [1, 3, 5].map((i) => parseInt(c.slice(i, i + 2), 16));
export function trackColor(t: number, keys: [number, string][], s: Spr = STD): string {
  const ch = [0, 1, 2].map((j) => track(t, keys.map(([b, c]) => [b, hex(c)[j]] as Key), s));
  return `rgb(${ch.map((v) => Math.round(clamp(v, 0, 255))).join(",")})`;
}
export function mix(a: string, b: string, k: number) {
  const A = hex(a), Bc = hex(b);
  return `rgb(${A.map((v, i) => Math.round(lerp(v, Bc[i], clamp(k)))).join(",")})`;
}

// ------------------------------------------------------------------ state keys
/**
 * Build per-property key lists from a list of sparse states:
 * [[beat, {x: 1}], [beat, {w: 2}]] -> {x: [[0, x0], [beat, 1]], ...}
 * Properties not mentioned keep their previous value.
 */
export function keysFrom<T extends Record<string, number>>(init: T, states: [number, Partial<T>][]) {
  const out = {} as Record<keyof T, Key[]>;
  for (const k in init) out[k] = [[0, init[k]]];
  for (const [b, s] of states) for (const k in s) {
    const list = out[k as keyof T];
    const v = s[k] as number;
    if (list[list.length - 1][0] === b) list[list.length - 1][1] = v;
    else list.push([b, v]);
  }
  return out;
}

/**
 * Press amount 0..1. Clicks land on their beat (down over 0.06 s, released
 * on a spring); holds [down, up] stay pressed for a drag.
 */
export function press(t: number, beats: number[], holds: [number, number][] = []): number {
  let p = 0;
  for (const b of beats) {
    const dt = t - (B(b) - 0.06);
    if (dt < 0 || dt > 0.8) continue;
    p = Math.max(p, clamp(dt / 0.06) * (1 - spring(dt - 0.1, SNAP)));
  }
  for (const [d, u] of holds) {
    const dt = t - (B(d) - 0.06);
    if (dt < 0 || t > B(u) + 0.8) continue;
    p = Math.max(p, clamp(dt / 0.06) * (1 - spring(t - B(u), SNAP)));
  }
  return p;
}

/** Per-beat step (0..1 springs) — used for counters and stepped rotations. */
export const stepAt = (t: number, b: number, s: Spr = SNAP) => spring(t - B(b), s);

/** Seeded hash noise. */
export const hash = (n: number) => {
  const x = Math.sin(n * 127.1 + 311.7) * 43758.5453;
  return x - Math.floor(x);
};
