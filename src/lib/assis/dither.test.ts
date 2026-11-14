import { describe, expect, it } from "vitest";
import { bayer4, type Cell, CELL, CLOSE_MS, gridOf, OPEN_MS, progressAt, shown } from "./dither";

// The chip in the corner over the tab bar, the window anchored on its bottom edge (spec 048 C1–C3, C6).
const chip = { x: 268, y: 548, w: 48, h: 48 };
const win = { x: 14, y: 272, w: 304, h: 324 };
const cells = gridOf(win, chip);
const mean = (xs: Cell[]) => xs.reduce((s, c) => s + c.d, 0) / xs.length;
const count = (p: number) => cells.filter((c) => shown(c, p)).length;

describe("the dither open", () => {
  it("c1: the grid covers the window in square cells, and the Bayer matrix uses each level once", () => {
    expect(cells.length).toBe(Math.ceil(win.w / CELL) * Math.ceil(win.h / CELL));
    expect(new Set([...Array(16)].map((_, i) => bayer4(i % 4, i >> 2))).size).toBe(16);
  });

  it("c1: empty at progress 0, whole at 1, and it only grows between", () => {
    expect(count(0)).toBe(0);
    expect(count(1)).toBe(cells.length);
    let last = 0;
    for (let p = 0; p <= 1; p += 0.05) {
      expect(count(p)).toBeGreaterThanOrEqual(last);
      last = count(p);
    }
  });

  it("c2: the cells nearest the chip show first", () => {
    const early = cells.filter((c) => shown(c, 0.3));
    expect(early.length).toBeGreaterThan(0);
    expect(mean(early)).toBeLessThan(mean(cells));
  });

  it("c1: opens in 420 ms; the reveal is stepped and ends whole", () => {
    expect(OPEN_MS).toBe(420);
    expect(progressAt(0, true)).toBe(0);
    expect(progressAt(OPEN_MS, true)).toBe(1);
    expect(progressAt(OPEN_MS * 3, true)).toBe(1);
  });

  it("c6: closing is the opening backwards in 320 ms, outer cells first", () => {
    expect(CLOSE_MS).toBe(320);
    expect(progressAt(0, false)).toBe(1);
    expect(progressAt(CLOSE_MS, false)).toBe(0);
    const mid = cells.filter((c) => shown(c, progressAt(CLOSE_MS * 0.5, false)));
    const gone = cells.filter((c) => !mid.includes(c));
    expect(mean(gone)).toBeGreaterThan(mean(mid));
  });
});
