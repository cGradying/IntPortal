import { describe, expect, it } from "vitest";
import { atomAt, cellOf, CLOSE_MS, closeT, FLY_MS, HAND_MS, OPEN_MS, pourPlan, SEAM_PT } from "./pour";

// The chip in the corner over the tab bar, the window anchored on its bottom edge (spec 048 C1–C6).
const chip = { x: 268, y: 548, w: 48, h: 48 };
const win = { x: 14, y: 272, w: 304, h: 324 };
const plan = pourPlan(chip, win);
const near = (a: number, b: number) => Math.abs(a - b) < 1e-6;

describe("the pour", () => {
  it("c1: starts as the cube's face, a 3 x 3 grid centred on the chip, the other 18 stacked behind", () => {
    const at0 = plan.atoms.map((_, i) => atomAt(plan, i, 0));
    const centres = new Set(at0.map((p) => `${(p.x + p.w / 2).toFixed(3)},${(p.y + p.h / 2).toFixed(3)}`));
    expect(centres.size).toBe(9);
    const cx = at0.reduce((s, p) => s + p.x + p.w / 2, 0) / 27;
    const cy = at0.reduce((s, p) => s + p.y + p.h / 2, 0) / 27;
    expect(near(cx, chip.x + chip.w / 2) && near(cy, chip.y + chip.h / 2)).toBe(true);
    expect(at0.every((p) => near(p.w, 6.2) && p.depth === 0 && p.u === 0)).toBe(true);
    const big = pourPlan({ ...chip, w: 96, h: 96 }, win);
    expect(near(big.pitch, 13.6) && near(big.edge, 12.4)).toBe(true);
  });

  it("c2: lands on a 3 x 9 tiling of the window, with 2 pt seams that close by the swap", () => {
    const cells = plan.atoms.map((a) => cellOf(plan, a));
    expect(new Set(cells.map((c) => `${c.x},${c.y}`)).size).toBe(27);
    const area = cells.reduce((s, c) => s + c.w * c.h, 0);
    expect(area + 2 * SEAM_PT * win.h + 8 * SEAM_PT * win.w - 16 * SEAM_PT * SEAM_PT).toBeCloseTo(win.w * win.h, 6);
    expect(Math.min(...cells.map((c) => c.x))).toBeCloseTo(win.x);
    expect(Math.max(...cells.map((c) => c.x + c.w))).toBeCloseTo(win.x + win.w);
    expect(Math.min(...cells.map((c) => c.y))).toBeCloseTo(win.y);
    expect(Math.max(...cells.map((c) => c.y + c.h))).toBeCloseTo(win.y + win.h);
    const whole = plan.atoms.map((_, i) => atomAt(plan, i, OPEN_MS));
    expect(whole.reduce((s, p) => s + p.w * p.h, 0)).toBeCloseTo(win.w * win.h, 3);
  });

  it("c2: pours upward, the bottom row leaving first and the top (the sky) last", () => {
    const leaves = (r: number) => Math.min(...plan.atoms.filter((a) => a.r === r).map((a) => a.delay));
    for (let r = 1; r < 9; r++) expect(leaves(r)).toBeGreaterThan(leaves(r - 1));
    expect(Math.min(...plan.atoms.map((a) => a.delay))).toBe(HAND_MS);
  });

  it("c3: every atom has landed by the swap", () => {
    expect(Math.max(...plan.atoms.map((a) => a.delay)) + FLY_MS).toBeLessThanOrEqual(OPEN_MS);
    expect(plan.atoms.every((_, i) => atomAt(plan, i, OPEN_MS).u === 1)).toBe(true);
  });

  it("c3: the sky's 104 pt is carried by the top rows", () => {
    const top = plan.atoms.filter((a) => cellOf(plan, a).y < win.y + 104);
    expect(Math.min(...top.map((a) => a.r))).toBeGreaterThanOrEqual(6);
  });

  it("c6: closing is the opening backwards, so the top rows leave first", () => {
    expect(closeT(0)).toBe(OPEN_MS);
    expect(closeT(CLOSE_MS)).toBe(0);
    // When each atom first stops being landed, closing.
    const leaves = plan.atoms.map((_, i) => {
      for (let t = 0; t <= CLOSE_MS; t += 2) if (atomAt(plan, i, closeT(t)).u < 1) return t;
      return Infinity;
    });
    const byRow = (r: number) => Math.min(...leaves.filter((_, i) => plan.atoms[i].r === r));
    for (let r = 1; r < 9; r++) expect(byRow(r)).toBeLessThanOrEqual(byRow(r - 1));
    expect(byRow(8)).toBeLessThan(byRow(0));
  });

  it("c2: no atom strays outside the chip and window, give or take its arc and depth", () => {
    const [x0, y0] = [Math.min(chip.x, win.x) - 9, Math.min(chip.y, win.y) - 9];
    const [x1, y1] = [Math.max(chip.x + chip.w, win.x + win.w) + 9, Math.max(chip.y + chip.h, win.y + win.h) + 9];
    for (let t = 0; t <= OPEN_MS; t += 8)
      for (let i = 0; i < 27; i++) {
        const p = atomAt(plan, i, t);
        expect(p.x >= x0 && p.y - p.depth >= y0 && p.x + p.w + p.depth <= x1 && p.y + p.h <= y1, `atom ${i} at ${t} ms`).toBe(true);
      }
  });
});
