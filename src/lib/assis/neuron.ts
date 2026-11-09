// The neuron in LAR's window (spec 046 C1d3, picked 2026-11-09, round three C2), on one canvas
// over the page. Thinking: dendrites grow from LAR's spark through the glass's cells, lighting each
// cell they cross, and signals run in to him. Answering with a source: the axon grows out of the
// glass to the From chip (and to the card behind the window when it is on screen), signals run out
// along it and ring the source, then it settles. No source: a short fire inside the glass only.
// The geometry is pure (seeded, tested); mountNeuron draws it. Ported from
// reference/prototypes/lar-window/window.html. (fieldPulse's roots walk the dot grid; these curve, so
// they share only its colour helpers.)
import { rgbOf, styleOf } from "../dive";
import { rng, type Rand } from "../lar/wander";

export interface Pt {
  x: number;
  y: number;
}
export interface Rect {
  x: number;
  y: number;
  w: number;
  h: number;
}
/** A polyline with its running length, so a point can be found by distance along it. */
export interface Path {
  pts: Pt[];
  cum: number[];
  L: number;
}
export interface Branch extends Path {
  /** Width at the root and at the tip. */
  w0: number;
  w1: number;
  /** When it starts growing and how long it takes, in seconds. */
  t0: number;
  dur: number;
  parent: Branch | null;
}

const clamp = (v: number, lo = 0, hi = 1) => Math.min(hi, Math.max(lo, v));

export function path(pts: Pt[]): Path {
  const cum = [0];
  for (let i = 1; i < pts.length; i++) cum.push(cum[i - 1] + Math.hypot(pts[i].x - pts[i - 1].x, pts[i].y - pts[i - 1].y));
  return { pts, cum, L: cum[cum.length - 1] };
}

/** The point `s` along `p`, clamped to its ends. */
export function pointAt(p: Path, s: number): Pt {
  s = clamp(s, 0, p.L);
  let i = 1;
  while (i < p.cum.length - 1 && p.cum[i] < s) i++;
  const f = (s - p.cum[i - 1]) / (p.cum[i] - p.cum[i - 1] || 1);
  const [a, b] = [p.pts[i - 1], p.pts[i]];
  return { x: a.x + (b.x - a.x) * f, y: a.y + (b.y - a.y) * f };
}

/** Where a signal sent at `t0` at `v` px/s is at `t`: null before it leaves and after it arrives. */
export function pulseAt(p: Path, t0: number, v: number, t: number): Pt | null {
  const s = (t - t0) * v;
  return s < 0 || s >= p.L ? null : pointAt(p, s);
}

/** The glass's 3x3 cells. */
export function cellsOf(r: Rect, n = 3): Rect[] {
  const out: Rect[] = [];
  for (let j = 0; j < n; j++) for (let i = 0; i < n; i++) out.push({ x: r.x + (i * r.w) / n, y: r.y + (j * r.h) / n, w: r.w / n, h: r.h / n });
  return out;
}

const inside = (q: Pt, r: Rect) => q.x > r.x && q.x < r.x + r.w && q.y > r.y && q.y < r.y + r.h;

/**
 * Five dendrites fanned between the angles `fan`, each a gently curving tapered stroke that forks in
 * two, three generations deep, kept inside `box`. Grows at 150 px/s; a child starts as its parent ends.
 */
export function dendrites(soma: Pt, fan: [number, number], box: Rect, R: Rand = Math.random) {
  const all: Branch[] = [];
  const tips: Branch[] = [];
  const grow = (p: Pt, ang: number, len: number, w: number, depth: number, t0: number, parent: Branch | null): Branch | null => {
    const pts = [p];
    const n = Math.max(3, Math.round(len / 5));
    const bend = (R() - 0.5) * 0.9;
    let [a, q] = [ang, p];
    for (let i = 0; i < n; i++) {
      a += bend / n + (R() - 0.5) * 0.1;
      q = { x: q.x + (Math.cos(a) * len) / n, y: q.y + (Math.sin(a) * len) / n };
      if (!inside(q, box)) break;
      pts.push(q);
    }
    if (pts.length < 3) return null;
    const b: Branch = { ...path(pts), w0: w, w1: w * 0.66, t0, dur: 0, parent };
    b.dur = b.L / 150;
    all.push(b);
    const kids = depth > 0 ? [-1, 1].map((s) => grow(pts[pts.length - 1], a + s * (0.32 + R() * 0.28) * (0.8 + R() * 0.5), len * (0.66 + R() * 0.16), w * 0.66, depth - 1, t0 + b.dur * 0.9, b)) : [];
    if (!kids.some(Boolean)) tips.push(b);
    return b;
  };
  for (let i = 0; i < 5; i++) grow(soma, fan[0] + ((fan[1] - fan[0]) * (i + 0.5 + (R() - 0.5) * 0.5)) / 5, 50 + R() * 26, 2.4, 3, R() * 0.12, null);
  return { all, tips };
}

/** From a tip back along its parents to the soma, for a signal running home. */
export function inward(b: Branch): Path {
  const pts: Pt[] = [];
  for (let x: Branch | null = b; x; x = x.parent) for (let i = x.pts.length - 1; i >= 0; i--) pts.push(x.pts[i]);
  return path(pts);
}

/** A smooth bow from a to b with a faint living wobble, still at both ends. */
export function curve(a: Pt, b: Pt, bow: number, R: Rand = Math.random): Path {
  const [dx, dy] = [b.x - a.x, b.y - a.y];
  const L = Math.hypot(dx, dy) || 1;
  const [nx, ny] = [-dy / L, dx / L];
  const ph = R() * 6;
  const n = Math.max(8, Math.round(L / 6));
  const pts: Pt[] = [];
  for (let i = 0; i <= n; i++) {
    const u = i / n;
    const m = 3 * u * (1 - u) * bow + Math.sin(u * Math.PI * 3 + ph) * 2.2 * Math.sin(u * Math.PI);
    pts.push({ x: a.x + dx * u + nx * m, y: a.y + dy * u + ny * m });
  }
  return path(pts);
}

/** The point on `r`'s edge nearest `from`, 2 px out. */
export function edgePoint(r: Rect, from: Pt): Pt {
  const [x, y] = [clamp(from.x, r.x, r.x + r.w), clamp(from.y, r.y, r.y + r.h)];
  const d = Math.hypot(from.x - x, from.y - y) || 1;
  return { x: x + ((from.x - x) / d) * 2, y: y + ((from.y - y) / d) * 2 };
}

export interface AxonPart extends Path {
  w0: number;
  w1: number;
  t0: number;
  dur: number;
  /** A collateral's source, which rings when its signal lands. */
  target?: number;
  /** A bouton at the end of this collateral (its index in `parts`). */
  of?: number;
}

/**
 * The axon: a trunk a third of the way toward the targets' middle, then one collateral to each
 * target's edge, ending in four short boutons. Times are seconds after the fire.
 */
export function axon(soma: Pt, targets: Rect[], R: Rand = Math.random) {
  const c = targets.reduce((m, r) => ({ x: m.x + (r.x + r.w / 2) / targets.length, y: m.y + (r.y + r.h / 2) / targets.length }), { x: 0, y: 0 });
  const B = { x: soma.x + (c.x - soma.x) * 0.36 + (R() - 0.5) * 14, y: soma.y + (c.y - soma.y) * 0.36 + (R() - 0.5) * 14 };
  const parts: AxonPart[] = [{ ...curve(soma, B, 10, R), w0: 2.8, w1: 2.2, t0: 0, dur: 0.3 }];
  targets.forEach((r, i) => {
    const E = edgePoint(r, B);
    const k = parts.push({ ...curve(B, E, (i % 2 ? -1 : 1) * 22, R), w0: 2.2, w1: 1.3, t0: 0.28, dur: 0.42, target: i }) - 1;
    const dir = Math.atan2(E.y - B.y, E.x - B.x);
    for (let j = 0; j < 4; j++) {
      const a = dir + (j - 1.5) * 0.55;
      const len = 7 + R() * 6;
      const bend = (R() - 0.5) * 0.6;
      const tip = [{ x: E.x + Math.cos(a) * len * 0.5, y: E.y + Math.sin(a) * len * 0.5 }, { x: E.x + Math.cos(a + bend) * len, y: E.y + Math.sin(a + bend) * len }];
      parts.push({ ...path([E, ...tip]), w0: 1.3, w1: 0.6, t0: 0.68, dur: 0.18, of: k });
    }
  });
  return parts;
}

/** The seed the window grows a neuron from; a fresh one each time he thinks. */
export const seed = () => (Math.random() * 2 ** 32) >>> 0;

// ------------------------------------------------------------------- drawing

export interface Neuron {
  /** He starts thinking: dendrites grow from `soma` through `cells`, inside `box`. */
  think(o: { soma: Pt; box: Rect; cells: Rect[]; fan: [number, number] }): void;
  /** An answer with sources: the axon reaches each target, then it all settles. */
  fire(targets: Rect[]): void;
  /** An answer with no source: a short fire inside the glass. */
  spark(): void;
  clear(): void;
  dispose(): void;
}

interface Pulse {
  p: Path;
  t0: number;
  v: number;
  home?: boolean;
  /** The axon part it runs on. */
  on?: number;
}

const ease = (k: number) => 1 - (1 - k) ** 3;

/** One canvas over the page. 30 fps at most, nothing drawn at rest, paused while the app is hidden. */
/** The neuron moves only where it costs nothing to spare: never under Reduce Motion, and never on the
 *  low-RAM tier (046 C1d2), where a full-page canvas at 30 fps stalls the model as it loads and runs
 *  (#188, #189). There it draws one still, lit frame. `smallRam` is true until the phone answers. */
export const neuronStill = (reduce: boolean, smallRam: boolean) => reduce || smallRam;

/** `calm` is read on every start, so the tier answering after mount still applies. */
export function mountNeuron(cv: HTMLCanvasElement, calm: () => boolean): Neuron {
  const g = cv.getContext("2d");
  const now = () => performance.now() / 1000;
  let R = rng(seed());
  let soma: Pt | null = null;
  let cells: (Rect & { lit: number; aim: number })[] = [];
  let dend: Branch[] = [];
  let tips: Branch[] = [];
  let parts: AxonPart[] = [];
  let targets: Rect[] = [];
  let hit: number[] = [];
  let pulses: Pulse[] = [];
  let [tStart, tFire, fadeAt, fadeDur, charge, nextP, drawn, raf] = [0, 0, Infinity, 0.7, 0, 0, 0, 0];
  let col = { gold: "#f5b227", core: "#fff6dc", rgb: 0xf5b227 };
  let still: ReturnType<typeof setTimeout> | undefined;

  const size = () => {
    const dpr = Math.min(devicePixelRatio || 1, 2);
    const [w, h] = [Math.round(innerWidth * dpr), Math.round(innerHeight * dpr)];
    if (cv.width !== w || cv.height !== h) [cv.width, cv.height] = [w, h];
    return dpr;
  };
  const colors = () => {
    const cs = getComputedStyle(document.documentElement);
    const rgb = rgbOf(cs.getPropertyValue("--gold"), 0xf5b227);
    const day = cs.colorScheme === "light";
    const dark = (((rgb >> 16) & 255) * 0.6) << 16 | (((rgb >> 8) & 255) * 0.6) << 8 | ((rgb & 255) * 0.6);
    col = { gold: styleOf(((rgb << 8) | 255) >>> 0), core: day ? styleOf(((dark << 8) | 255) >>> 0) : cs.getPropertyValue("--cream").trim() || "#fff6dc", rgb };
  };
  const alpha = (a: number) => styleOf(((col.rgb << 8) | Math.round(clamp(a) * 255)) >>> 0);
  const dot = (q: Pt, r: number, a: number, c: string) => {
    g!.globalAlpha = a;
    g!.fillStyle = c;
    g!.beginPath();
    g!.arc(q.x, q.y, r, 0, Math.PI * 2);
    g!.fill();
  };
  const stroke = (p: Path, upto: number, w0: number, w1: number, a: number) => {
    g!.globalAlpha = a;
    g!.strokeStyle = col.gold;
    for (let i = 1; i < p.pts.length && p.cum[i - 1] < upto; i++) {
      const f = Math.min(1, (upto - p.cum[i - 1]) / (p.cum[i] - p.cum[i - 1] || 1));
      const [q0, q1] = [p.pts[i - 1], p.pts[i]];
      g!.lineWidth = w0 + ((w1 - w0) * i) / (p.pts.length - 1);
      g!.beginPath();
      g!.moveTo(q0.x, q0.y);
      g!.lineTo(q0.x + (q1.x - q0.x) * f, q0.y + (q1.y - q0.y) * f);
      g!.stroke();
    }
  };
  // The ring round a source: the app's stepped corner, 4 px steps.
  const ring = (r: Rect, a: number) => {
    const [x0, y0, x1, y1, s] = [r.x - 3, r.y - 3, r.x + r.w + 3, r.y + r.h + 3, 4];
    g!.globalAlpha = a;
    g!.strokeStyle = col.gold;
    g!.lineWidth = 1.5;
    g!.beginPath();
    for (const [x, y] of [[x0 + s, y0], [x1 - s, y0], [x1 - s, y0 + s], [x1, y0 + s], [x1, y1 - s], [x1 - s, y1 - s], [x1 - s, y1], [x0 + s, y1], [x0 + s, y1 - s], [x0, y1 - s], [x0, y0 + s], [x0 + s, y0 + s]]) g!.lineTo(x, y);
    g!.closePath();
    g!.stroke();
  };
  const light = (q: Pt, v: number, flash = 0) => {
    for (const c of cells)
      if (q.x >= c.x && q.x <= c.x + c.w && q.y >= c.y && q.y <= c.y + c.h) {
        c.aim = Math.max(c.aim, v);
        c.lit = Math.max(c.lit, flash);
      }
  };
  const arrive = (pu: Pulse, t: number) => {
    if (pu.home) charge = Math.min(1.6, charge + 0.45);
    if (pu.on === 0) parts.forEach((q, k) => q.target !== undefined && pulses.push({ p: q, t0: t, v: 380, on: k }));
    else if (pu.on !== undefined && parts[pu.on].target !== undefined) hit[parts[pu.on].target!] = t;
  };

  function draw(t: number, dt: number) {
    const dpr = size();
    g!.setTransform(dpr, 0, 0, dpr, 0, 0);
    g!.clearRect(0, 0, innerWidth, innerHeight);
    const fade = 1 - clamp((t - fadeAt) / fadeDur);
    if (fade <= 0 || !soma) return false;
    g!.lineCap = "round";
    if (!tFire && !calm() && t > nextP) {
      const ready = tips.filter((b) => t - tStart > b.t0 + b.dur);
      if (ready.length) pulses.push({ p: inward(ready[Math.floor(R() * ready.length)]), t0: t, v: 190, home: true });
      nextP = t + 0.14 + R() * 0.2;
    }
    charge += (0.25 - charge) * (1 - Math.exp(-dt * 2.2));
    const grown = (b: { t0: number; dur: number }, from: number) => (calm() ? 1 : ease(clamp((t - from - b.t0) / b.dur)));
    for (const b of dend) {
      const u = grown(b, tStart);
      if (u > 0) light(pointAt(b, u * b.L), 0.55);
    }
    for (const c of cells) {
      c.lit = calm() ? c.aim : c.lit + (c.aim - c.lit) * (1 - Math.exp(-dt * 4));
      if (c.lit < 0.01) continue;
      const [cx, cy] = [c.x + c.w / 2, c.y + c.h / 2];
      const gr = g!.createRadialGradient(cx, cy, 0, cx, cy, Math.max(c.w, c.h) * 0.62);
      gr.addColorStop(0, alpha(0.2 * c.lit));
      gr.addColorStop(1, alpha(0));
      g!.globalAlpha = fade;
      g!.fillStyle = gr;
      g!.fillRect(c.x + 2, c.y + 2, c.w - 4, c.h - 4);
    }
    const dim = tFire ? 1 - 0.5 * clamp((t - tFire) / 0.4) : 1;
    for (const b of dend) {
      const u = grown(b, tStart);
      if (u > 0) stroke(b, u * b.L, b.w0, b.w1, 0.55 * dim * fade);
    }
    for (const q of parts) {
      const u = grown(q, tFire);
      if (u <= 0) continue;
      stroke(q, u * q.L, q.w0, q.w1, 0.9 * fade);
      if (q.of !== undefined && u >= 1) {
        const h = hit[parts[q.of].target!];
        const f = h ? clamp(1 - (t - h) / 0.6) : 0;
        dot(q.pts[q.pts.length - 1], 1.7 + f, fade, f > 0.05 ? col.core : col.gold);
      }
    }
    pulses = pulses.filter((pu) => {
      if (t < pu.t0) return true;
      const s = (t - pu.t0) * pu.v;
      if (s >= pu.p.L) return arrive(pu, t), false;
      for (let k = 4; k >= 0; k--) dot(pointAt(pu.p, s - k * 4), k ? 2 - k * 0.3 : 2.4, fade * (1 - k * 0.2), k ? col.gold : col.core);
      light(pointAt(pu.p, s), 0, 0.9);
      return true;
    });
    targets.forEach((r, i) => hit[i] && ring(r, fade * (0.35 + 0.65 * clamp(1 - (t - hit[i]) / 1.2))));
    const gr = g!.createRadialGradient(soma.x, soma.y, 0, soma.x, soma.y, 9 + 7 * charge);
    gr.addColorStop(0, alpha(0.45 * charge));
    gr.addColorStop(1, alpha(0));
    g!.globalAlpha = fade;
    g!.fillStyle = gr;
    g!.fillRect(soma.x - 30, soma.y - 30, 60, 60);
    dot(soma, 2.6 + charge, fade, col.gold);
    dot(soma, 1.3, fade, col.core);
    return true;
  }

  function loop(ts: number) {
    raf = requestAnimationFrame(loop);
    if (ts - drawn < 32) return; // 30 frames a second, like the crystal
    const dt = Math.min(0.05, (ts - (drawn || ts - 16)) / 1000);
    drawn = ts;
    if (!draw(ts / 1000, dt)) stop();
  }
  const stop = () => {
    cancelAnimationFrame(raf);
    raf = 0;
    if (!soma || 1 - clamp((now() - fadeAt) / fadeDur) <= 0) soma = null;
  };
  // Reduce Motion: one still, lit frame, cleared when it would have faded.
  const run = () => {
    if (!g) return;
    if (calm()) {
      draw(now(), 0);
      clearTimeout(still);
      if (fadeAt < Infinity) still = setTimeout(() => ((soma = null), draw(now(), 0)), (fadeAt - now() + fadeDur) * 1000);
      return;
    }
    if (!raf && !document.hidden) raf = requestAnimationFrame(loop);
  };
  const seen = () => (document.hidden ? stop() : soma && run());
  document.addEventListener("visibilitychange", seen);

  return {
    think(o) {
      colors();
      R = rng(seed());
      soma = o.soma;
      cells = o.cells.map((c) => ({ ...c, lit: 0, aim: 0 }));
      ({ all: dend, tips } = dendrites(o.soma, o.fan, o.box, R));
      [parts, targets, hit, pulses] = [[], [], [], []];
      [charge, tStart, tFire, fadeAt, fadeDur] = [0.3, now(), 0, Infinity, 0.7];
      nextP = tStart + 0.6;
      run();
    },
    fire(rects) {
      if (!soma || !rects.length) return this.spark();
      colors();
      [tFire, fadeAt, fadeDur] = [now(), now() + 2.3, 0.7];
      targets = rects;
      hit = rects.map(() => (calm() ? tFire : 0));
      parts = axon(soma, rects, R);
      if (!calm()) [0.55, 0.68, 0.81].forEach((d) => pulses.push({ p: parts[0], t0: tFire + d, v: 380, on: 0 }));
      run();
    },
    spark() {
      if (!soma) return;
      [tFire, fadeAt, fadeDur, charge] = [now(), now() + 1, 0.6, 1.6];
      if (!calm())
        tips
          .map((b) => [R(), b] as const)
          .sort((a, b) => a[0] - b[0])
          .slice(0, 7)
          .forEach(([, b], i) => pulses.push({ p: path(inward(b).pts.slice().reverse()), t0: tFire + i * 0.04, v: 300 }));
      run();
    },
    clear() {
      if (!soma) return;
      [fadeAt, fadeDur] = [Math.min(fadeAt, now()), 0.25];
      run();
    },
    dispose() {
      document.removeEventListener("visibilitychange", seen);
      clearTimeout(still);
      cancelAnimationFrame(raf);
      raf = 0;
      soma = null;
    },
  };
}
