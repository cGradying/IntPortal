/** Layout changes open and close over this, so nothing jumps. Same as `--t-flow` in app.css. */
export const FLOW_MS = 360;

/** The pentatonic scale the done pluck draws its first note from, in semitones above the first note. */
export const SCALE = [0, 2, 4, 7, 9, 12, 14, 16, 19, 21];

/** A note's frequency, from the C above middle C. */
export const noteHz = (step: number) => 523.25 * 2 ** (SCALE[Math.min(step, SCALE.length - 1)] / 12);

/** Segments in the progress bar: every deadline in this card, kept to a row's width. */
export const barSegments = (open: number, finished: number) => Math.min(8, open + finished);
