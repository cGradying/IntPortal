import { describe, expect, it, vi } from "vitest";
vi.mock("./dive", () => ({ DOT_PITCH: 14, rgbOf: () => 0 }));
import { growRoots } from "./fieldPulse";

describe("rootPull's roots (046 C1b4)", () => {
  it("c1b4_every_joint_is_on_the_dot_grid_and_on_screen", () => {
    for (let i = 0; i < 40; i++) {
      const { segs } = growRoots(350, 760, 402, 874);
      expect(segs.length).toBeGreaterThan(0);
      for (const q of segs) {
        for (const v of [q.x1, q.y1, q.x2, q.y2]) expect((v - 7) % 14).toBe(0);
        expect(q.x2 >= 0 && q.x2 <= 402 && q.y2 >= 0 && q.y2 <= 874).toBe(true);
        // Straight along the grid, never diagonal.
        expect(q.x1 === q.x2 || q.y1 === q.y2).toBe(true);
      }
    }
  });

  it("c1b4_one_trunk_climbs_the_open_gutter", () => {
    const { segs } = growRoots(350, 760, 402, 874);
    const up = segs.filter((q) => q.x1 === 399 && q.x2 === 399);
    expect(up.length).toBeGreaterThan(1);
    expect(Math.min(...up.map((q) => q.y2))).toBeLessThan(700);
  });

  it("c1b4_data_runs_home_along_a_connected_path", () => {
    const { packets } = growRoots(350, 760, 402, 874);
    for (const p of packets) expect(p.path[p.path.length - 1].d0).toBe(0);
  });
});
