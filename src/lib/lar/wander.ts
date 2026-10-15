// LAR flying round the portal on the landing: a small steering agent
// (Reynolds' seek, arrive and wander) that switches between a handful of
// moods of movement at random, weighted by what the student is doing. The
// portal's frame is solid: he is pushed off it softly and never allowed to
// overlap a block. Pure and seeded, so it can be tested; LarFlight steps it
// each frame and draws him.

export interface Rect {
  x: number;
  y: number;
  w: number;
  h: number;
}

export interface World {
  /** The stage, in CSS px. */
  w: number;
  h: number;
  /** The portal's frame on the stage: solid. */
  portal: Rect;
  /** Other places he never goes. */
  keepOut: Rect[];
  /** His body's radius, so the whole of him stays clear, not just his centre. */
  r: number;
}

export type Mode = "orbit" | "drift" | "peek" | "approach" | "rest";
/** What the student is doing, which biases what he does. */
export type Context = "idle" | "typing" | "busy" | "error" | "signed";

export interface Lar {
  x: number;
  y: number;
  vx: number;
  vy: number;
  mode: Mode;
  /** Seconds on his clock when this mode ends. */
  until: number;
  /** Where the current mode is taking him. */
  tx: number;
  ty: number;
  /** Orbit angle and direction. */
  theta: number;
  spin: number;
  /** 0 far away, 1 right in front of the student. */
  depth: number;
  /** Seconds since he appeared. */
  t: number;
  wanderAngle: number;
}

export type Rand = () => number;

/** mulberry32: a small seeded generator. */
export function rng(seed: number): Rand {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

const WEIGHTS: Record<Context, Record<Mode, number>> = {
  idle: { orbit: 0.34, drift: 0.24, peek: 0.16, approach: 0.14, rest: 0.12 },
  typing: { orbit: 0.1, drift: 0.3, peek: 0.2, approach: 0, rest: 0.4 },
  busy: { orbit: 0.7, drift: 0, peek: 0, approach: 0, rest: 0.3 },
  error: { orbit: 0, drift: 0, peek: 0, approach: 1, rest: 0 },
  signed: { orbit: 0.3, drift: 0.1, peek: 0, approach: 0.45, rest: 0.15 },
};

const SPEED = 120; // px/s
const FORCE = 260; // px/s²
const MARGIN = 28;

export const inside = (r: Rect, x: number, y: number, pad = 0) => x > r.x - pad && x < r.x + r.w + pad && y > r.y - pad && y < r.y + r.h + pad;

/** Where he lands after coming out of the portal: just below its frame. */
export const landing = (world: World) => ({
  x: world.portal.x + world.portal.w / 2,
  y: Math.min(world.h - world.r - 4, world.portal.y + world.portal.h + world.r + 10),
});

/** Start him where he lands after coming through. */
export function create(world: World, rand: Rand): Lar {
  const at = landing(world);
  const lar: Lar = {
    x: at.x,
    y: at.y,
    vx: 0,
    vy: 0,
    mode: "rest",
    until: 0,
    tx: 0,
    ty: 0,
    theta: Math.PI / 2,
    spin: rand() < 0.5 ? -1 : 1,
    depth: 0.6,
    t: 0,
    wanderAngle: rand() * Math.PI * 2,
  };
  lar.tx = lar.x;
  lar.ty = lar.y;
  return lar;
}

function choose(ctx: Context, rand: Rand): Mode {
  const w = WEIGHTS[ctx];
  let r = rand() * Object.values(w).reduce((a, b) => a + b, 0);
  for (const [m, v] of Object.entries(w) as [Mode, number][]) {
    if ((r -= v) <= 0 && v > 0) return m;
  }
  return "rest";
}

/** Every solid thing, grown by his radius so his whole body stays clear. */
const solids = (world: World) => [world.portal, ...world.keepOut].map((r) => ({ x: r.x - world.r, y: r.y - world.r, w: r.w + 2 * world.r, h: r.h + 2 * world.r }));

/** A free spot on the stage, clear of everything solid. */
function freeSpot(world: World, rand: Rand): [number, number] {
  const solid = solids(world);
  for (let i = 0; i < 32; i++) {
    const x = world.r + rand() * (world.w - 2 * world.r);
    const y = world.r + rand() * (world.h - 2 * world.r);
    if (!solid.some((r) => inside(r, x, y, 8))) return [x, y];
  }
  const at = landing(world);
  return [at.x, at.y];
}

function begin(l: Lar, world: World, ctx: Context, rand: Rand) {
  l.mode = choose(ctx, rand);
  l.until = l.t + (l.mode === "approach" ? 3 + rand() * 2 : 3 + rand() * 5);
  const p = world.portal;
  if (l.mode === "orbit") {
    l.spin = rand() < 0.5 ? -1 : 1;
    l.theta = Math.atan2((l.y - (p.y + p.h / 2)) / (p.h * 0.2 || 1), (l.x - (p.x + p.w / 2)) / (p.w * 0.66 || 1));
  } else if (l.mode === "drift") {
    [l.tx, l.ty] = freeSpot(world, rand);
  } else if (l.mode === "peek") {
    // Hover close beside the frame, as if looking round its edge.
    const left = rand() < 0.5;
    l.tx = left ? p.x - world.r - 6 : p.x + p.w + world.r + 6;
    l.ty = p.y + p.h * (0.3 + rand() * 0.4);
  } else if (l.mode === "approach") {
    // Down toward the student, but above the card.
    const card = world.keepOut.reduce((low, r) => (r.y > (low?.y ?? -1) ? r : low), undefined as Rect | undefined);
    l.tx = world.w / 2 + (rand() - 0.5) * world.w * 0.3;
    l.ty = Math.min((card ? card.y : world.h) - 70, p.y + p.h + 30);
  } else {
    l.tx = l.x + (rand() - 0.5) * 30;
    l.ty = l.y + (rand() - 0.5) * 20;
  }
}

/** Advance him by `dt` seconds. Mutates and returns `l`. */
export function tick(l: Lar, world: World, ctx: Context, dt: number, rand: Rand): Lar {
  dt = Math.min(dt, 0.05);
  l.t += dt;
  // An error grabs his attention at once; otherwise modes run their course.
  if (l.t >= l.until || (ctx === "error" && l.mode !== "approach") || (ctx === "typing" && l.mode === "approach")) begin(l, world, ctx, rand);

  const p = world.portal;
  const cx = p.x + p.w / 2;
  const cy = p.y + p.h / 2;
  let wantDepth = 0.75;
  if (l.mode === "orbit") {
    // A loop round the outside of the frame, never across it.
    l.theta += l.spin * dt * 0.5;
    l.tx = cx + Math.cos(l.theta) * (p.w / 2 + world.r + 22);
    l.ty = cy + Math.sin(l.theta) * (p.h / 2 + world.r + 14);
    wantDepth = 0.55 + 0.4 * Math.sin(l.theta);
  } else if (l.mode === "peek") {
    wantDepth = 0.5;
  } else if (l.mode === "approach") {
    wantDepth = 1;
  } else if (l.mode === "rest") {
    wantDepth = 0.8;
  }

  // Seek with arrival, plus a wandering nudge so the path never looks drawn.
  const dx = l.tx - l.x;
  const dy = l.ty - l.y;
  const dist = Math.hypot(dx, dy) || 1;
  const speed = (l.mode === "rest" ? 0.25 : 1) * SPEED * Math.min(1, dist / 90);
  let ax = (dx / dist) * speed - l.vx;
  let ay = (dy / dist) * speed - l.vy;
  l.wanderAngle += (rand() - 0.5) * 2.4 * dt * 6;
  const jitter = l.mode === "rest" ? 18 : 34;
  ax += Math.cos(l.wanderAngle) * jitter;
  ay += Math.sin(l.wanderAngle) * jitter * 0.6;

  // Soft walls: the stage edge and every keep-out push him away.
  const push = (amount: number, nx: number, ny: number) => {
    ax += nx * amount;
    ay += ny * amount;
  };
  if (l.x < MARGIN) push((MARGIN - l.x) * 12, 1, 0);
  if (l.x > world.w - MARGIN) push((l.x - world.w + MARGIN) * 12, -1, 0);
  if (l.y < MARGIN) push((MARGIN - l.y) * 12, 0, 1);
  if (l.y > world.h - MARGIN) push((l.y - world.h + MARGIN) * 12, 0, -1);
  for (const r of solids(world)) {
    if (!inside(r, l.x, l.y, 30)) continue;
    const ox = l.x < r.x + r.w / 2 ? -1 : 1;
    const oy = l.y < r.y + r.h / 2 ? -1 : 1;
    const depthX = ox < 0 ? l.x - (r.x - 30) : r.x + r.w + 30 - l.x;
    const depthY = oy < 0 ? l.y - (r.y - 30) : r.y + r.h + 30 - l.y;
    if (depthX < depthY) push(depthX * 14, ox, 0);
    else push(depthY * 14, 0, oy);
  }

  const mag = Math.hypot(ax, ay);
  if (mag > FORCE) {
    ax = (ax / mag) * FORCE;
    ay = (ay / mag) * FORCE;
  }
  l.vx += ax * dt;
  l.vy += ay * dt;
  const v = Math.hypot(l.vx, l.vy);
  if (v > SPEED * 1.3) {
    l.vx *= (SPEED * 1.3) / v;
    l.vy *= (SPEED * 1.3) / v;
  }
  l.x += l.vx * dt;
  l.y += l.vy * dt;
  l.x = Math.max(world.r, Math.min(world.w - world.r, l.x));
  l.y = Math.max(world.r, Math.min(world.h - world.r, l.y));
  // Solid: if a step would put any of him inside something, slide him out to
  // its nearest edge and stop the part of his velocity that pushed in.
  for (const r of solids(world)) {
    if (!inside(r, l.x, l.y)) continue;
    // The nearest way out that still leaves him on the stage.
    const ways = [
      { d: l.x - r.x, x: r.x, y: l.y, side: 0 },
      { d: r.x + r.w - l.x, x: r.x + r.w, y: l.y, side: 1 },
      { d: l.y - r.y, x: l.x, y: r.y, side: 2 },
      { d: r.y + r.h - l.y, x: l.x, y: r.y + r.h, side: 3 },
    ]
      .filter((w) => w.x >= world.r && w.x <= world.w - world.r && w.y >= world.r && w.y <= world.h - world.r)
      .sort((a, b) => a.d - b.d);
    const out = ways[0];
    if (!out) continue;
    l.x = out.x;
    l.y = out.y;
    if (out.side === 0) l.vx = Math.min(0, l.vx);
    if (out.side === 1) l.vx = Math.max(0, l.vx);
    if (out.side === 2) l.vy = Math.min(0, l.vy);
    if (out.side === 3) l.vy = Math.max(0, l.vy);
  }
  l.depth += (wantDepth - l.depth) * Math.min(1, dt * 2.5);
  return l;
}

/** Which way he faces, -1 to 1, from how he is moving. */
export const turnOf = (l: Lar) => Math.max(-1, Math.min(1, l.vx / SPEED));
