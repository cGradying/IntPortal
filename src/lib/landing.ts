// The landing as a pure function of time, like the film rig: landingAt(t)
// says which phase the scene is in, how far through it (k, 0 to 1), and how
// many frame pieces have landed. The scene draws from this and nothing else.
import { PIECES } from "./pentomino";

export type Phase = "dark" | "assembling" | "igniting" | "arrival" | "glimpse" | "rest" | "stepping" | "entered";

export interface Moment {
  phase: Phase;
  /** Progress through the phase, 0 to 1. */
  k: number;
  /** Frame pieces locked in place. */
  placed: number;
}

export interface Opening {
  /** Signed in already: the frame is standing, so the build is skipped. */
  returning: boolean;
  reduce: boolean;
  /** When Step through was pressed, in the same clock as t; null until then. */
  steppedAt: number | null;
}

/** Seconds between one piece starting to fall and the next. */
export const PIECE_GAP = 0.19;
/** Seconds a piece takes to fall and lock. */
export const FALL = 0.42;
/** A beat after the last piece locks, before the swirl ignites. */
const SETTLE = 0.15;
/** Seconds from Step through to landing on Today. */
export const DIVE = 1.1;

function segments(o: Opening): [Phase, number][] {
  if (o.reduce) return [];
  const build = (PIECES.length - 1) * PIECE_GAP + FALL + SETTLE;
  return o.returning
    ? [["dark", 0.2], ["igniting", 0.5], ["arrival", 0.8], ["glimpse", 0.5]]
    : [["dark", 0.4], ["assembling", build], ["igniting", 0.7], ["arrival", 1.0], ["glimpse", 0.7]];
}

/** When the sign-in card (or Step through) is reachable. */
export const restAt = (o: Opening) => segments(o).reduce((a, [, d]) => a + d, 0);

/** How many pieces have locked by `s` seconds into assembling. */
const placedAt = (s: number) => Math.max(0, Math.min(PIECES.length, Math.floor((s - FALL) / PIECE_GAP + 1e-9) + 1));

export function landingAt(t: number, o: Opening): Moment {
  const rest = restAt(o);
  const all = PIECES.length;
  if (o.steppedAt !== null) {
    const from = Math.max(o.steppedAt, rest);
    if (t >= from) {
      const k = (t - from) / DIVE;
      return k >= 1 - 1e-9 ? { phase: "entered", k: 1, placed: all } : { phase: "stepping", k, placed: all };
    }
  }
  if (t >= rest) return { phase: "rest", k: 1, placed: all };
  let start = 0;
  for (const [phase, d] of segments(o)) {
    if (t < start + d) {
      const s = t - start;
      const placed = phase === "dark" ? (o.returning ? all : 0) : phase === "assembling" ? placedAt(s) : all;
      return { phase, k: s / d, placed };
    }
    start += d;
  }
  return { phase: "rest", k: 1, placed: all };
}
