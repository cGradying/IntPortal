// The chip (spec 046 C1b to C1d2): LAR's button, a flat 3x3 grid of pixel squares in the room's own
// tokens. The centre cross is the +; the four corners dither out through a 4x4 Bayer matrix to
// make it one. 3D crystal removed at the owner's request, 2026-11-14.
import { rgbOf } from "../dive";

export type CrystalMode = "cube" | "plus";

/** One floating button (046 C1b, C1c, C11): the + on Study and in the note editor; the grid elsewhere once a model is installed. */
export const crystalMode = (tab: string, hasModel: boolean, editing = false): CrystalMode | null => (editing || tab === "study" ? "plus" : hasModel ? "cube" : null);

/** The same 4x4 Bayer matrix as the campus strip and the pour. */
const BAYER = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5];

/** Chip canvas is 24 x 24 pixels, shown at 48 pt: 3 cells of 6 with a 1 px hairline gap. */
export const PX = 24;
const CELL = 6;
const GAP = 1;
const EDGE = 2;
/** Cells that hold data wear a gold dot (the 27-cell seed of the old cube, front layer). */
export const DOTS = [0, 2, 3, 5, 7];

/** Is the corner pixel at (x, y) still there at progress p (0 = gone, 1 = whole)? Ordered dither. */
export const dithered = (x: number, y: number, p: number) => BAYER[(y & 3) * 4 + (x & 3)] < Math.round(p * 16);

/**
 * Draws the chip. `p` is the cube-ness: 1 is the grid with its corners, 0 is the + (corners gone,
 * cross gold). `step` > 0 runs the thinking sweep: a band of the matrix that advances with it.
 */
export function drawChip(ctx: CanvasRenderingContext2D, t: RestTones, p: number, step = 0) {
  ctx.clearRect(0, 0, PX, PX);
  for (let n = 0; n < 9; n++) {
    const [cx, cy] = [n % 3, (n / 3) | 0];
    const corner = cx !== 1 && cy !== 1;
    const [x0, y0] = [EDGE + cx * (CELL + GAP), EDGE + cy * (CELL + GAP)];
    for (let y = y0; y < y0 + CELL; y++)
      for (let x = x0; x < x0 + CELL; x++) {
        const whole = dithered(x, y, p);
        if (corner && !whole) continue;
        const dot = DOTS.includes(n) && whole && x >= x0 + 2 && x < x0 + 4 && y >= y0 + 2 && y < y0 + 4;
        const swept = step > 0 && (BAYER[(y & 3) * 4 + (x & 3)] + step) % 16 < 3;
        ctx.fillStyle = dot || swept || (!corner && !whole) ? t.gold : t.faces[1];
        ctx.fillRect(x, y, 1, 1);
      }
  }
}

export interface RestTones {
  faces: [string, string, string];
  hair: string;
  gold: string;
  goldDark: string;
}

const hexOf = (rgb: number) => `#${(rgb & 0xffffff).toString(16).padStart(6, "0")}`;
const parts = (rgb: number) => [(rgb >> 16) & 255, (rgb >> 8) & 255, rgb & 255];
const mixed = (a: number, b: number, k: number) => {
  const [x, y] = [parts(a), parts(b)];
  return (Math.round(x[0] + (y[0] - x[0]) * k) << 16) | (Math.round(x[1] + (y[1] - x[1]) * k) << 8) | Math.round(x[2] + (y[2] - x[2]) * k);
};
const luma = (rgb: number) => {
  const [r, g, b] = parts(rgb);
  return (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255;
};

/** The rest state's colours, from the room's tokens (C1b2). The glass and the still image share them. */
export function restTones(card: number, ink: number, gold: number): RestTones {
  const day = luma(card) > 0.3;
  const k = day ? [0, 0.07, 0.15] : [0.2, 0.1, 0.035];
  const faces = k.map((v) => hexOf(mixed(card, ink, v))) as [string, string, string];
  return { faces, hair: hexOf(mixed(card, ink, day ? 0.24 : 0.3)), gold: hexOf(gold), goldDark: hexOf(mixed(0, gold, 0.68)) };
}

export const readTones = (el: Element = document.documentElement) => {
  const vars = getComputedStyle(el);
  const v = (name: string, fallback: number) => rgbOf(vars.getPropertyValue(name), fallback);
  return restTones(v("--card", 0x170b1a), v("--ink", 0xf4ecd8), v("--gold", 0xf5b227));
};
