// The portal frame is built from pentominoes, five-block pieces that drop
// in and lock together like Tetris. FRAME and PIECES are baked by
// scripts/pentomino-solve.mjs: a two-cell ring of 60 cells can't take all
// twelve pentominoes once, so it uses ten different shapes, two of them
// twice. PIECES is ordered bottom-up, the order they land in.
export type Shape = "F" | "I" | "L" | "N" | "P" | "T" | "U" | "V" | "W" | "X" | "Y" | "Z";
export type Cell = readonly [col: number, row: number];
export interface Piece {
  shape: Shape;
  cells: readonly Cell[];
}

const SHAPES: Record<Shape, Cell[]> = {
  F: [[1, 0], [2, 0], [0, 1], [1, 1], [1, 2]],
  I: [[0, 0], [0, 1], [0, 2], [0, 3], [0, 4]],
  L: [[0, 0], [0, 1], [0, 2], [0, 3], [1, 3]],
  N: [[1, 0], [1, 1], [0, 2], [1, 2], [0, 3]],
  P: [[0, 0], [1, 0], [0, 1], [1, 1], [0, 2]],
  T: [[0, 0], [1, 0], [2, 0], [1, 1], [1, 2]],
  U: [[0, 0], [2, 0], [0, 1], [1, 1], [2, 1]],
  V: [[0, 0], [0, 1], [0, 2], [1, 2], [2, 2]],
  W: [[0, 0], [0, 1], [1, 1], [1, 2], [2, 2]],
  X: [[1, 0], [0, 1], [1, 1], [2, 1], [1, 2]],
  Y: [[1, 0], [0, 1], [1, 1], [1, 2], [1, 3]],
  Z: [[0, 0], [1, 0], [1, 1], [1, 2], [2, 2]],
};

/** A shape's cells moved to the origin, in a fixed order, so equal shapes compare equal. */
const signature = (cells: readonly Cell[]) => {
  const mx = Math.min(...cells.map(([c]) => c));
  const my = Math.min(...cells.map(([, r]) => r));
  return cells
    .map(([c, r]) => [c - mx, r - my] as const)
    .sort((a, b) => a[1] - b[1] || a[0] - b[0])
    .join(";");
};

/** Every rotation and mirror of a shape. */
function orientations(cells: readonly Cell[]): string[] {
  const out = new Set<string>();
  let cur = cells;
  for (let flip = 0; flip < 2; flip++) {
    for (let turn = 0; turn < 4; turn++) {
      out.add(signature(cur));
      cur = cur.map(([c, r]) => [r, -c] as const);
    }
    cur = cur.map(([c, r]) => [-c, r] as const);
  }
  return [...out];
}

const LOOKUP = new Map(Object.entries(SHAPES).flatMap(([s, cells]) => orientations(cells).map((o) => [o, s as Shape] as const)));

/** Which pentomino five cells make, or null when they aren't one. */
export const shapeOf = (cells: readonly Cell[]): Shape | null => (cells.length === 5 ? (LOOKUP.get(signature(cells)) ?? null) : null);

/** The cells of a frame `thick` cells deep around a cols × rows block. */
export function ring(cols: number, rows: number, thick: number): Cell[] {
  const cells: Cell[] = [];
  for (let r = 0; r < rows; r++)
    for (let c = 0; c < cols; c++) if (c < thick || r < thick || c >= cols - thick || r >= rows - thick) cells.push([c, r]);
  return cells;
}

export const FRAME = { cols: 8, rows: 11, thick: 2 } as const;

export const PIECES: readonly Piece[] = [
  { shape: "V", cells: [[0, 8], [0, 9], [0, 10], [1, 10], [2, 10]] },
  { shape: "P", cells: [[3, 9], [4, 9], [5, 9], [3, 10], [4, 10]] },
  { shape: "T", cells: [[6, 8], [6, 9], [5, 10], [6, 10], [7, 10]] },
  { shape: "Z", cells: [[0, 7], [1, 7], [1, 8], [1, 9], [2, 9]] },
  { shape: "N", cells: [[6, 6], [6, 7], [7, 7], [7, 8], [7, 9]] },
  { shape: "L", cells: [[1, 3], [1, 4], [1, 5], [0, 6], [1, 6]] },
  { shape: "Y", cells: [[7, 3], [7, 4], [6, 5], [7, 5], [7, 6]] },
  { shape: "I", cells: [[0, 1], [0, 2], [0, 3], [0, 4], [0, 5]] },
  { shape: "Y", cells: [[6, 1], [6, 2], [7, 2], [6, 3], [6, 4]] },
  { shape: "F", cells: [[0, 0], [1, 0], [1, 1], [2, 1], [1, 2]] },
  { shape: "P", cells: [[2, 0], [3, 0], [4, 0], [3, 1], [4, 1]] },
  { shape: "U", cells: [[5, 0], [6, 0], [7, 0], [5, 1], [7, 1]] },
];
