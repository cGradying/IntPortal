import { describe, expect, it } from "vitest";
import { create, inside, placeBubble, rng, tick, turnOf, type Context, type Lar, type Mode, type World } from "./wander";

// A phone's landing stage: the portal up top, the card along the bottom.
const WORLD: World = {
  w: 370,
  h: 600,
  portal: { x: 115, y: 40, w: 140, h: 190 },
  keepOut: [{ x: 0, y: 380, w: 370, h: 220 }],
  r: 26,
};

/** Any part of his body over the portal's blocks. */
const overPortal = (l: Lar) => {
  const p = WORLD.portal;
  const nx = Math.max(p.x, Math.min(l.x, p.x + p.w));
  const ny = Math.max(p.y, Math.min(l.y, p.y + p.h));
  return Math.hypot(l.x - nx, l.y - ny) < WORLD.r - 0.5;
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
      let bad = 0;
      run(ctx, 10000 / 60, 3, (l) => {
        const off = l.x - WORLD.r < 0 || l.x + WORLD.r > WORLD.w || l.y - WORLD.r < 0 || l.y + WORLD.r > WORLD.h;
        if (off || !Number.isFinite(l.vx + l.vy)) bad++;
      });
      expect(bad, ctx).toBe(0);
    }
  });

  it("never touches the card", () => {
    let on = 0;
    let n = 0;
    run("idle", 180, 11, (l) => {
      n++;
      if (l.y + WORLD.r > 380) on++;
    });
    expect(on).toBe(0);
    expect(n).toBeGreaterThan(0);
  });

  it("is deterministic for a seed and differs between seeds", () => {
    expect(run("idle", 20, 5)).toEqual(run("idle", 20, 5));
    expect(run("idle", 20, 5).x).not.toBeCloseTo(run("idle", 20, 6).x, 3);
  });

  it("does several things over a minute", () => {
    const modes = new Set<Mode>();
    run("idle", 90, 2, (l) => modes.add(l.mode));
    expect(modes.size).toBeGreaterThanOrEqual(3);
  });

  it("never overlaps the portal's blocks, in any context or seed", () => {
    for (const ctx of ["idle", "typing", "busy", "error", "signed"] as Context[])
      for (const seed of [1, 2, 3, 4, 5]) {
        let over = 0;
        run(ctx, 60, seed, (l) => overPortal(l) && over++);
        expect(over, `${ctx} ${seed}`).toBe(0);
      }
  });

  it("treats the neighbouring portals peeking in at the sides as solid too", () => {
    const side: World = { ...WORLD, keepOut: [...WORLD.keepOut, { x: 300, y: 60, w: 120, h: 170 }, { x: -60, y: 60, w: 90, h: 170 }] };
    const near = (l: Lar, r: { x: number; y: number; w: number; h: number }) =>
      Math.hypot(l.x - Math.max(r.x, Math.min(l.x, r.x + r.w)), l.y - Math.max(r.y, Math.min(l.y, r.y + r.h))) < side.r - 0.5;
    const bad: string[] = [];
    for (const ctx of ["idle", "busy", "error"] as Context[])
      for (const seed of [1, 2, 3]) {
        const rand = rng(seed);
        const l = create(side, rand);
        for (let i = 0; i < 60 * 40; i++) {
          tick(l, side, ctx, 1 / 60, rand);
          if (side.keepOut.slice(1).some((r) => near(l, r))) bad.push(`${ctx} ${seed} @${i}`);
        }
      }
    expect(bad.slice(0, 5)).toEqual([]);
  });

  it("flies right round the portal when orbiting", () => {
    let left = false;
    let right = false;
    run("busy", 60, 6, (l) => {
      if (l.x < WORLD.portal.x) left = true;
      if (l.x > WORLD.portal.x + WORLD.portal.w) right = true;
    });
    expect(left && right).toBe(true);
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

describe("placeBubble", () => {
  // A 358 x 384 stage with the frame in the middle, the room LAR has on a 390 pt phone.
  const world: World = { w: 358, h: 384, portal: { x: 85, y: 42, w: 189, h: 253 }, keepOut: [], r: 20 };
  const size = { w: 222, h: 50 };
  const overlaps = (s: { x: number; y: number }, r: { x: number; y: number; w: number; h: number }) =>
    s.x < r.x + r.w && s.x + size.w > r.x && s.y < r.y + r.h && s.y + size.h > r.y;

  it("never covers a frame tile, wherever he flies, and covers him only right under the frame", () => {
    const f = world.portal;
    for (let x = 20; x <= 338; x += 6) {
      for (let y = 20; y <= 364; y += 6) {
        // The frame is solid: he is never inside it.
        if (inside(world.portal, x, y, world.r)) continue;
        const s = placeBubble(world, { x, y }, size);
        expect(overlaps(s, world.portal), `LAR at ${x},${y}`).toBe(false);
        // Under the frame's middle there is no room beside him, and the frame is above: only there.
        if (overlaps(s, { x: x - 14, y: y - 14, w: 28, h: 28 })) expect(x > f.x && x < f.x + f.w && y > f.y + f.h, `LAR at ${x},${y}`).toBe(true);
      }
    }
  });

  it("sits just under the frame when LAR hovers beside it", () => {
    expect(placeBubble(world, { x: 42, y: 184 }, size)).toEqual({ k: 9, x: 58, y: 301 });
  });

  it("keeps the spot it had while that spot is still clear", () => {
    const first = placeBubble(world, { x: 60, y: 348 }, size);
    expect(placeBubble(world, { x: 64, y: 348 }, size, first.k).k).toBe(first.k);
  });
});
