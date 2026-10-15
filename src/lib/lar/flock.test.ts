import { describe, expect, it } from "vitest";
import { BIRD, spawn, step, wingsUp, type Bird } from "./flock";
import { create, rng, tick, type World } from "./wander";

const WORLD: World = {
  w: 370,
  h: 600,
  portal: { x: 115, y: 40, w: 140, h: 190 },
  keepOut: [{ x: 0, y: 380, w: 370, h: 220 }],
  r: 26,
};

function fly(seconds: number, seed: number, each: (birds: Bird[], lead: { x: number; y: number }) => void) {
  const rand = rng(seed);
  const lar = create(WORLD, rand);
  const birds = spawn(12, WORLD.portal.x + WORLD.portal.w / 2, WORLD.portal.y + WORLD.portal.h + 10, rand);
  for (let i = 0; i < seconds * 60; i++) {
    const t = i / 60;
    tick(lar, WORLD, "idle", 1 / 60, rand);
    step(birds, lar, WORLD, 1 / 60, t, rand);
    each(birds, lar);
  }
  return birds;
}

const overRect = (b: Bird, r: { x: number; y: number; w: number; h: number }) => b.x > r.x - BIRD && b.x < r.x + r.w + BIRD && b.y > r.y - BIRD && b.y < r.y + r.h + BIRD;

describe("the flock", () => {
  it("never flies through the portal's blocks or the card", () => {
    let hits = 0;
    fly(60, 3, (birds) => birds.forEach((b) => (overRect(b, WORLD.portal) || overRect(b, WORLD.keepOut[0])) && hits++));
    expect(hits).toBe(0);
  });

  it("stays with LAR", () => {
    let total = 0;
    let n = 0;
    fly(40, 5, (birds, lead) => {
      for (const b of birds) {
        total += Math.hypot(b.x - lead.x, b.y - lead.y);
        n++;
      }
    });
    expect(total / n).toBeLessThan(110);
  });

  it("keeps its spacing: birds rarely bunch on top of each other", () => {
    let close = 0;
    let pairs = 0;
    fly(30, 7, (birds) => {
      for (let i = 0; i < birds.length; i++)
        for (let j = i + 1; j < birds.length; j++) {
          pairs++;
          if (Math.hypot(birds[i].x - birds[j].x, birds[i].y - birds[j].y) < 3) close++;
        }
    });
    expect(close / pairs).toBeLessThan(0.02);
  });

  it("always keeps flying, on the stage", () => {
    let bad = 0;
    fly(30, 9, (birds) =>
      birds.forEach((b) => {
        const v = Math.hypot(b.vx, b.vy);
        if (b.x < 0 || b.x > WORLD.w || b.y < 0 || b.y > WORLD.h || !Number.isFinite(v)) bad++;
      }),
    );
    expect(bad).toBe(0);
  });

  it("is deterministic for a seed", () => {
    expect(fly(10, 4, () => {})).toEqual(fly(10, 4, () => {}));
  });

  it("flaps out of step", () => {
    const birds = spawn(8, 0, 0, rng(1));
    const up = birds.filter((b) => wingsUp(b, 0.3)).length;
    expect(up).toBeGreaterThan(0);
    expect(up).toBeLessThan(8);
  });
});
