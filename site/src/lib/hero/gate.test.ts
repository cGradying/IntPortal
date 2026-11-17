import { describe, expect, it } from "vitest";
import { canRun } from "./gate";
import { COLS, ROWS, frameTiles, swirlAt } from "./portal";

const ok = { webgl2: true, reduced: false, saveData: false, cores: 8 };

describe("057 hero", () => {
  it("c2_runs_only_with_webgl2_motion_data_and_cores", () => {
    expect(canRun(ok)).toBe(true);
    expect(canRun({ ...ok, webgl2: false })).toBe(false);
    expect(canRun({ ...ok, reduced: true })).toBe(false);
    expect(canRun({ ...ok, saveData: true })).toBe(false);
    expect(canRun({ ...ok, cores: 2 })).toBe(false);
  });
  it("c3_frame_is_two_tiles_thick_and_builds_from_the_bottom_centre", () => {
    const tiles = frameTiles();
    expect(tiles.length).toBe(COLS * ROWS - (COLS - 4) * (ROWS - 4));
    const first = tiles.reduce((a, b) => (a.order <= b.order ? a : b));
    expect(first.y).toBe(0);
    expect(Math.abs(first.x + 0.5 - COLS / 2)).toBeLessThanOrEqual(0.5);
    expect(Math.max(...tiles.map((t) => t.order))).toBeLessThanOrEqual(1);
  });
  it("c4_swirl_stays_in_the_ramp", () => {
    for (let y = 0; y < 12; y++) for (let x = 0; x < 8; x++) {
      const i = swirlAt(x / 7, y / 11, x, y);
      expect(i).toBeGreaterThanOrEqual(0);
      expect(i).toBeLessThanOrEqual(4);
    }
  });
});
