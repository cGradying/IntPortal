// The landing's clock, as a pure function of time: landingAt(t) says whether
// the portal is still forming, resting under the form, or being stepped
// through. The tiles themselves are timed by the Rust scene (tiles.ts).

export type Phase = "forming" | "rest" | "stepping" | "entered";

export interface Moment {
  phase: Phase;
  /** Progress through the phase, 0 to 1. */
  k: number;
}

export interface Opening {
  /** Signed in already: the frame is standing, so the build is skipped. */
  returning: boolean;
  reduce: boolean;
  /** When Step through was pressed, in the same clock as t; null until then. */
  steppedAt: number | null;
}

/** Seconds for the frame to build; covers the scene's own FORM (a Rust test pins it under 0.8). */
export const FORM = 0.8;
/** Seconds from Step through to landing on Today. */
export const DIVE = 1.1;

/** When the sign-in card (or Step through) is reachable. */
export const restAt = (o: Opening) => (o.returning || o.reduce ? 0 : FORM);

export function landingAt(t: number, o: Opening): Moment {
  const rest = restAt(o);
  if (o.steppedAt !== null) {
    const from = Math.max(o.steppedAt, rest);
    if (t >= from) {
      const k = o.reduce ? 1 : (t - from) / DIVE;
      return k >= 1 - 1e-9 ? { phase: "entered", k: 1 } : { phase: "stepping", k };
    }
  }
  if (t >= rest) return { phase: "rest", k: 1 };
  return { phase: "forming", k: t / rest };
}
