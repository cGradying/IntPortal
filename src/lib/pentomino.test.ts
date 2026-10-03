import { describe, expect, it } from "vitest";
import { FRAME, PIECES, ring, shapeOf } from "./pentomino";

const key = ([c, r]: readonly [number, number]) => `${c},${r}`;

describe("the pentomino portal frame", () => {
  it("is a two-cell ring with a multiple of five cells", () => {
    const cells = ring(FRAME.cols, FRAME.rows, FRAME.thick);
    expect(cells.length % 5).toBe(0);
    expect(cells.length).toBe(PIECES.length * 5);
  });

  it("is tiled exactly: no gaps, no overlaps, nothing outside the ring", () => {
    const want = new Set(ring(FRAME.cols, FRAME.rows, FRAME.thick).map(key));
    const got = PIECES.flatMap((p) => p.cells.map(key));
    expect(new Set(got).size).toBe(got.length);
    expect(new Set(got)).toEqual(want);
  });

  it("is made of real pentominoes, each the shape it claims", () => {
    for (const p of PIECES) expect(shapeOf(p.cells)).toBe(p.shape);
  });

  it("uses ten different shapes, none more than twice (the most a 60-cell ring allows)", () => {
    const uses = new Map<string, number>();
    for (const p of PIECES) uses.set(p.shape, (uses.get(p.shape) ?? 0) + 1);
    expect(uses.size).toBe(10);
    expect(Math.max(...uses.values())).toBeLessThanOrEqual(2);
  });

  it("knows a pentomino from five cells that aren't one", () => {
    expect(shapeOf([[0, 0], [1, 0], [2, 0], [3, 0], [4, 0]])).toBe("I");
    expect(shapeOf([[0, 0], [1, 0], [0, 1], [1, 1], [3, 3]])).toBeNull();
  });

  it("lands bottom-up, like Tetris", () => {
    const lowest = PIECES.map((p) => Math.max(...p.cells.map(([, r]) => r)));
    expect(lowest).toEqual([...lowest].sort((a, b) => b - a));
  });
});
