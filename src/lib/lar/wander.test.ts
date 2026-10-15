import { describe, expect, it } from "vitest";
import { create, rng, tick, turnOf, type Context, type Lar, type Mode, type World } from "./wander";

// A phone's landing stage: the portal up top, the card along the bottom.
const WORLD: World = {
  w: 370,
  h: 600,
  portal: { x: 115, y: 40, w: 140, h: 190 },
  keepOut: [{ x: 0, y: 380, w: 370, h: 220 }],
};

function run(ctx: Context, seconds: number, seed = 7, each?: (l: Lar) => void): Lar {
  const rand = rng(seed);
  const l = create(WORLD, rand);
  for (let i = 0; i < seconds * 60; i++) {
    tick(l, WORLD, ctx, 1 / 60, rand);
    each?.(l);
  }
  return l;
}

describe("wander", () => {
  it("stays on the stage through ten thousand steps, in every context", () => {
    for (const ctx of ["idle", "typing", "busy", "error", "signed"] as Context[]) {
      run(ctx, 10000 / 60, 3, (l) => {
        expect(l.x).toBeGreaterThanOrEqual(0);
        expect(l.x).toBeLessThanOrEqual(WORLD.w);
        expect(l.y).toBeGreaterThanOrEqual(0);
        expect(l.y).toBeLessThanOrEqual(WORLD.h);
        expect(Number.isFinite(l.vx + l.vy)).toBe(true);
      });
    }
  });

  it("almost never sits on the card, and never deep inside it", () => {
    let on = 0;
    let n = 0;
    run("idle", 180, 11, (l) => {
      n++;
      if (l.y > 380) on++;
      expect(l.y).toBeLessThan(380 + 60);
    });
    expect(on / n).toBeLessThan(0.03);
  });

  it("is deterministic for a seed and differs between seeds", () => {
    expect(run("idle", 20, 5)).toEqual(run("idle", 20, 5));
    expect(run("idle", 20, 5).x).not.toBeCloseTo(run("idle", 20, 6).x, 3);
  });

  it("does several things over a minute, and sometimes goes behind the portal", () => {
    const modes = new Set<Mode>();
    let behind = 0;
    run("idle", 90, 2, (l) => {
      modes.add(l.mode);
      if (l.behind) behind++;
    });
    expect(modes.size).toBeGreaterThanOrEqual(3);
    expect(behind).toBeGreaterThan(0);
  });

  it("comes forward at once on an error", () => {
    const rand = rng(1);
    const l = create(WORLD, rand);
    for (let i = 0; i < 120; i++) tick(l, WORLD, "idle", 1 / 60, rand);
    tick(l, WORLD, "error", 1 / 60, rand);
    expect(l.mode).toBe("approach");
    for (let i = 0; i < 90; i++) tick(l, WORLD, "error", 1 / 60, rand);
    expect(l.depth).toBeGreaterThan(0.8);
  });

  it("never approaches the student while they type", () => {
    run("typing", 120, 4, (l) => expect(l.mode).not.toBe("approach"));
  });

  it("faces where he is going", () => {
    const l = run("idle", 5, 9);
    l.vx = 200;
    expect(turnOf(l)).toBe(1);
    l.vx = -60;
    expect(turnOf(l)).toBeLessThan(0);
  });
});
