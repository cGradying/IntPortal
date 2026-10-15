// A small swarm of pixel birds that flies with LAR: Reynolds' boids
// (separation, alignment, cohesion) plus a pull toward a loose ring round
// LAR, so the flock trails and circles him. Like him, they treat the
// portal's frame as solid. Pure and seeded, so it can be tested.
import { inside, type Rand, type Rect, type World } from "./wander";

export interface Bird {
  x: number;
  y: number;
  vx: number;
  vy: number;
  /** Where on the ring round LAR this bird likes to be, in radians. */
  slot: number;
  /** Wing-beat offset, so they don't flap in step. */
  phase: number;
}

export interface Leader {
  x: number;
  y: number;
  vx: number;
  vy: number;
}

const SEP = 14;
const NEAR = 42;
const MAX = 170;
const MIN = 45;
const FORCE = 520;
/** A bird's own radius: they keep this clear of anything solid. */
export const BIRD = 3;

/** A burst of birds from a point (the portal's opening). */
export function spawn(n: number, x: number, y: number, rand: Rand): Bird[] {
  return Array.from({ length: n }, (_, i) => {
    const a = (i / n) * Math.PI * 2 + rand() * 0.4;
    const v = 90 + rand() * 80;
    return { x, y, vx: Math.cos(a) * v, vy: Math.sin(a) * v - 40, slot: a, phase: rand() };
  });
}

const grow = (r: Rect, by: number): Rect => ({ x: r.x - by, y: r.y - by, w: r.w + 2 * by, h: r.h + 2 * by });

/** Advance every bird by `dt` seconds. Mutates and returns `birds`. */
export function step(birds: Bird[], lead: Leader, world: World, dt: number, t: number, rand: Rand): Bird[] {
  dt = Math.min(dt, 0.05);
  const solid = [world.portal, ...world.keepOut].map((r) => grow(r, BIRD + 2));
  // LAR himself is solid to them too: they circle, they don't pass through him.
  const body = world.r + 6;
  for (const b of birds) {
    let sx = 0, sy = 0, ax = 0, ay = 0, cx = 0, cy = 0, n = 0;
    for (const o of birds) {
      if (o === b) continue;
      const dx = b.x - o.x;
      const dy = b.y - o.y;
      const d = Math.hypot(dx, dy);
      if (d > 0 && d < SEP) {
        sx += dx / d / d;
        sy += dy / d / d;
      }
      if (d < NEAR) {
        ax += o.vx;
        ay += o.vy;
        cx += o.x;
        cy += o.y;
        n++;
      }
    }
    let fx = sx * 2600;
    let fy = sy * 2600;
    if (n) {
      fx += (ax / n - b.vx) * 1.1 + (cx / n - b.x) * 1.4;
      fy += (ay / n - b.vy) * 1.1 + (cy / n - b.y) * 1.4;
    }
    // Their place on a ring round LAR, drifting slowly so the swarm turns.
    const ring = body + 16 + 10 * Math.sin(t * 0.7 + b.slot * 3);
    const tx = lead.x + Math.cos(b.slot + t * 0.6) * ring - lead.vx * 0.15;
    const ty = lead.y + Math.sin(b.slot + t * 0.6) * ring * 0.7 - lead.vy * 0.15;
    fx += (tx - b.x) * 3.2;
    fy += (ty - b.y) * 3.2;
    // A little restlessness.
    fx += (rand() - 0.5) * 140;
    fy += (rand() - 0.5) * 140;
    // Keep off LAR's body.
    const ld = Math.hypot(b.x - lead.x, b.y - lead.y);
    if (ld < body && ld > 0) {
      fx += ((b.x - lead.x) / ld) * (body - ld) * 40;
      fy += ((b.y - lead.y) / ld) * (body - ld) * 40;
    }
    const f = Math.hypot(fx, fy);
    if (f > FORCE) {
      fx = (fx / f) * FORCE;
      fy = (fy / f) * FORCE;
    }
    b.vx += fx * dt;
    b.vy += fy * dt;
    const v = Math.hypot(b.vx, b.vy) || 1;
    const clamp = Math.max(MIN, Math.min(MAX, v));
    b.vx = (b.vx / v) * clamp;
    b.vy = (b.vy / v) * clamp;
    b.x = Math.max(BIRD, Math.min(world.w - BIRD, b.x + b.vx * dt));
    b.y = Math.max(BIRD, Math.min(world.h - BIRD, b.y + b.vy * dt));
    // Solid: out of any block or card the short way, bouncing off it.
    for (const r of solid) {
      if (!inside(r, b.x, b.y)) continue;
      const ways = [
        { d: b.x - r.x, x: r.x, y: b.y, bounce: [-1, 1] },
        { d: r.x + r.w - b.x, x: r.x + r.w, y: b.y, bounce: [-1, 1] },
        { d: b.y - r.y, x: b.x, y: r.y, bounce: [1, -1] },
        { d: r.y + r.h - b.y, x: b.x, y: r.y + r.h, bounce: [1, -1] },
      ]
        .filter((w) => w.x >= BIRD && w.x <= world.w - BIRD && w.y >= BIRD && w.y <= world.h - BIRD)
        .sort((p, q) => p.d - q.d);
      const out = ways[0];
      if (!out) continue;
      b.x = out.x;
      b.y = out.y;
      b.vx *= out.bounce[0] * 0.6;
      b.vy *= out.bounce[1] * 0.6;
    }
  }
  return birds;
}

/** Wings up or down this instant. */
export const wingsUp = (b: Bird, t: number) => (t * 9 + b.phase * 2) % 2 < 1;
