// The dither open (spec 048 C1–C3, C6): LAR's window grows out of the chip as an ordered-dither (Bayer)
// pixel dissolve. Pure grid, timing and mask math, in page points and ms; `dither-draw.ts` paints it.
// Replaces the 3D pour at the owner's request, 2026-11-14.

export interface Rect {
  x: number;
  y: number;
  w: number;
  h: number;
}

export const OPEN_MS = 420;
export const CLOSE_MS = 320;
/** A square cell, in points; a whole number of device pixels at 2x and 3x. */
export const CELL = 6;
/** The wave: how far (0–1 of the farthest cell) a cell's reveal lags the chip's. */
const SPREAD = 0.6;
/** The reveal moves in this many steps, so the dissolve ticks rather than glides. */
const STEPS = 14;

const BAYER = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5];
/** The 4 x 4 Bayer threshold at a cell, 0 to 15/16. */
export const bayer4 = (cx: number, cy: number) => BAYER[(cy & 3) * 4 + (cx & 3)] / 16;

export const clamp = (v: number) => Math.min(1, Math.max(0, v));

export interface Cell {
  x: number;
  y: number;
  /** Bayer threshold, 0 to 15/16. */
  thr: number;
  /** Distance from the chip's centre, 0 (nearest) to 1 (farthest). */
  d: number;
}

/** The grid of cells covering `area`, each with its threshold and its distance from the chip's centre. */
export function gridOf(area: Rect, chip: Rect, cell = CELL): Cell[] {
  const cols = Math.ceil(area.w / cell);
  const rows = Math.ceil(area.h / cell);
  const [px, py] = [chip.x + chip.w / 2, chip.y + chip.h / 2];
  const out: Cell[] = [];
  let far = 0;
  for (let r = 0; r < rows; r++)
    for (let c = 0; c < cols; c++) {
      const x = area.x + c * cell;
      const y = area.y + r * cell;
      const d = Math.hypot(x + cell / 2 - px, y + cell / 2 - py);
      far = Math.max(far, d);
      out.push({ x, y, thr: bayer4(c, r), d });
    }
  for (const o of out) o.d = far ? o.d / far : 0;
  return out;
}

/** A cell is shown at `p` (0 empty, 1 whole): nearest the chip first, the Bayer order within each ring. */
export const shown = (c: Cell, p: number) => c.thr < p * (1 + SPREAD) - SPREAD * c.d;

/** The reveal at `t` ms: eased, in steps. Closing is the same run backwards, so the outer cells go first. */
export function progressAt(t: number, opening: boolean) {
  const k = clamp(t / (opening ? OPEN_MS : CLOSE_MS));
  const eased = 1 - (1 - k) ** 3;
  const p = Math.round(eased * STEPS) / STEPS;
  return opening ? p : 1 - p;
}
