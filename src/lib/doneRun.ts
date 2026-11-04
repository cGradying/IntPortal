// A run of deadlines marked done (spec 045 C18): each one within RUN_MS of the
// last climbs a step, and the tiers follow. Pure, so it can be tested.
export const RUN_MS = 4000;

/** The pentatonic scale a run climbs, in semitones above the first note. */
export const SCALE = [0, 2, 4, 7, 9, 12, 14, 16, 19, 21];

export interface Run {
  step: number;
  at: number;
}

export const nextRun = (r: Run | null, now: number): Run => ({ step: r && now - r.at < RUN_MS ? r.step + 1 : 0, at: now });

/** How hard a card reacts: the first nudges, the next two shake, then harder. */
export const tierOf = (step: number) => (step >= 3 ? "hard" : step >= 1 ? "shake" : "nudge");

/** The shown count on a run: nothing on the first, then ×2, ×3. */
export const comboText = (step: number) => (step > 0 ? `×${step + 1}` : "");

/** A note's frequency on the run, from the C above middle C. */
export const noteHz = (step: number) => 523.25 * 2 ** (SCALE[Math.min(step, SCALE.length - 1)] / 12);

/** Segments in the progress bar: every deadline in this card, kept to a row's width. */
export const barSegments = (open: number, finished: number) => Math.min(8, open + finished);
