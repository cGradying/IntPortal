// Spec 057: the tile portal of DESIGN.md (12 by 16 tiles, a frame two tiles
// thick round an 8 by 12 mouth), shared by the still and the 3D scene.
export const COLS = 12;
export const ROWS = 16;
export const TONES = ["#1a1622", "#241f2e", "#2f2939", "#3c3548"];
/** The SIS ramp, dark to light (spec 010). */
export const RAMP = ["#3b1220", "#7a1c2c", "#b5412a", "#e08a35", "#f3cf6a"];
export const ACCENT = "#e8b04a";

export type Tile = { x: number; y: number; tone: number; /** 0 at the bottom centre, 1 where the sides meet. */ order: number };

/** The frame's tiles, x left to right and y bottom to top. */
export function frameTiles(): Tile[] {
  const tiles: Tile[] = [];
  for (let y = 0; y < ROWS; y++)
    for (let x = 0; x < COLS; x++) {
      const edge = x < 2 || x >= COLS - 2 || y < 2 || y >= ROWS - 2;
      if (!edge) continue;
      // Walk from the bottom centre round each side: along the bottom, up the
      // side, then along the top to the middle.
      const half = Math.abs(x + 0.5 - COLS / 2);
      let d: number;
      if (y < 2) d = half;
      else if (y >= ROWS - 2) d = COLS / 2 + ROWS + (COLS / 2 - half);
      else d = COLS / 2 + y;
      tiles.push({ x, y, tone: (x * 7 + y * 13 + ((x ^ y) & 3)) % 4, order: d / (COLS + ROWS) });
    }
  // The inner edge is one tone darker (DESIGN.md).
  for (const t of tiles) {
    const inner = (t.x === 1 || t.x === COLS - 2 || t.y === 1 || t.y === ROWS - 2) && t.x > 0 && t.x < COLS - 1 && t.y > 0 && t.y < ROWS - 1;
    if (inner) t.tone = Math.max(0, t.tone - 1);
  }
  return tiles;
}

const BAYER = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5];

/** The swirl's ramp index at a cell of the mouth, for the still frame.
 *  u and v run 0 to 1 across the mouth; the shader draws the same field. */
export function swirlAt(u: number, v: number, cx: number, cy: number, t = 0): number {
  const px = (u - 0.5) * (8 / 12);
  const py = v - 0.5;
  const r = Math.hypot(px, py);
  const a = Math.atan2(py, px);
  const arms = Math.sin(a * 3 - r * 14 + t * 1.6) * 0.5 + 0.5;
  const val = arms * (1 - r * 1.25) + 0.42 * (1 - r * 2.1);
  const d = BAYER[(cy % 4) * 4 + (cx % 4)] / 16 - 0.5;
  return Math.max(0, Math.min(4, Math.floor(val * 4.6 + d)));
}
