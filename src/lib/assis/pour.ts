// The pour (spec 048 C1–C6): the crystal's 27 atoms leave its face and pour upward into a 3 x 9 tiling
// of LAR's window, bottom rows first, in one wave; the seams close and the real window takes over.
// Pure geometry and timing, in page points and ms; `pour-draw.ts` draws it. Ported from the round-four
// mockup, option A (reference/prototypes/lar-chat/morph.html).

export interface Rect {
  x: number;
  y: number;
  w: number;
  h: number;
}

/** The canvas takes over from the WebGL cube here, once it has turned to face the student. */
export const HAND_MS = 120;
/** One atom's flight. */
export const FLY_MS = 400;
/** The seams start to close; the window is whole at OPEN_MS, when the real one replaces the canvas. */
export const SEAM_MS = 540;
export const OPEN_MS = 664;
/** Closing plays the opening backwards over this long, top rows first. */
export const CLOSE_MS = 440;
export const SEAM_PT = 2;
/** The sky header's height, which the top rows of tiles carry. */
export const HEADER_PT = 104;
/** At a 48 pt chip the face's atoms sit 6.8 pt apart and are 6.2 pt across, matched to the WebGL face. */
const PITCH_48 = 6.8;
const EDGE_48 = 6.2;
const ARC_PT = 6;
const DEPTH_PT = 3;

export const clamp = (v: number) => Math.min(1, Math.max(0, v));
export const easeInOut = (k: number) => (k < 0.5 ? 4 * k * k * k : 1 - (-2 * k + 2) ** 3 / 2);
const lerp = (a: number, b: number, u: number) => a + (b - a) * u;

/** One atom: its column and row from the bottom in the window, and its place on the cube's face. */
export interface Atom {
  /** Column 0–2 and row 0–8 from the bottom. The cube's bottom layer fills the bottom rows, its top layer the sky. */
  c: number;
  r: number;
  /** -1, 0 or 1 across and up the cube's face. The 18 atoms behind start under the 9 in front. */
  i: number;
  j: number;
  /** When it leaves, after the hand-off: 14 ms a row from the bottom, 6 ms a column. */
  delay: number;
}

export interface Plan {
  chip: Rect;
  win: Rect;
  headerH: number;
  pitch: number;
  edge: number;
  atoms: Atom[];
}

export function pourPlan(chip: Rect, win: Rect, headerH = HEADER_PT): Plan {
  const atoms: Atom[] = [];
  // Back layer first, so the front draws over it while they are stacked.
  for (let k = 1; k >= -1; k--)
    for (let j = -1; j <= 1; j++)
      for (let i = -1; i <= 1; i++) {
        const c = i + 1;
        const r = (j + 1) * 3 + (k + 1);
        atoms.push({ c, r, i, j, delay: HAND_MS + r * 14 + c * 6 });
      }
  const scale = chip.w / 48;
  return { chip, win, headerH, pitch: PITCH_48 * scale, edge: EDGE_48 * scale, atoms };
}

/** How far the seams have closed, and the rim and extrusion come in: 0 until SEAM_MS, 1 just before OPEN_MS. */
export const closedAt = (t: number) => easeInOut(clamp((t - SEAM_MS) / (OPEN_MS - 4 - SEAM_MS)));

/** An atom's cell in the window's tiling, with seams `s` points wide. */
export function cellOf(plan: Plan, a: Atom, s = SEAM_PT): Rect {
  const { win } = plan;
  const w = (win.w - 2 * s) / 3;
  const h = (win.h - 8 * s) / 9;
  return { x: win.x + a.c * (w + s), y: win.y + win.h - (a.r + 1) * h - a.r * s, w, h };
}

export interface AtomPose extends Rect {
  /** 0 on the cube, 1 landed. */
  u: number;
  /** The 2.5D tile's depth: none on the cube or landed, most mid-flight. */
  depth: number;
  /** Where it lands: the slice of the window's face it carries. */
  cell: Rect;
}

/** Atom `i` at `t` ms into the opening. Closing is the same at `closeT(t)`. */
export function atomAt(plan: Plan, i: number, t: number): AtomPose {
  const a = plan.atoms[i];
  const cell = cellOf(plan, a, SEAM_PT * (1 - closedAt(t)));
  const u = easeInOut(clamp((t - a.delay) / FLY_MS));
  const sx = plan.chip.x + plan.chip.w / 2 + a.i * plan.pitch;
  const sy = plan.chip.y + plan.chip.h / 2 - a.j * plan.pitch;
  const ex = cell.x + cell.w / 2;
  const ey = cell.y + cell.h / 2;
  // A slight arc across its path, so the wave flows rather than slides.
  const [dx, dy] = [ex - sx, ey - sy];
  const len = Math.hypot(dx, dy) || 1;
  const arc = Math.sin(Math.PI * u) * ARC_PT;
  const w = lerp(plan.edge, cell.w, u);
  const h = lerp(plan.edge, cell.h, u);
  const x = lerp(sx, ex, u) - (dy / len) * arc;
  const y = lerp(sy, ey, u) + (dx / len) * arc;
  return { x: x - w / 2, y: y - h / 2, w, h, u, depth: DEPTH_PT * Math.sin(Math.PI * u), cell };
}

/** Closing, `t` ms in: the opening's time, run backwards. */
export const closeT = (t: number) => OPEN_MS * (1 - clamp(t / CLOSE_MS));

/** The chip, while the canvas takes over: it dips to 0.94 as it turns, then fades out over 60 ms. */
export const chipAt = (t: number, opening: boolean) => ({
  opacity: 1 - clamp((t - HAND_MS) / 60),
  scale: opening ? 1 - 0.06 * Math.sin(Math.PI * clamp(t / 150)) : 1,
});
