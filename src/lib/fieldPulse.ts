// A ring of brighter, bigger dots runs out through the dot grid, once, behind
// the cards (spec 010 C29, 045 C28). It lives in `.shell`, which is its own
// stacking context, so z-index -1 sits above the dots and under everything else.
import { DOT_PITCH, rgbOf, styleOf } from "./dive";

export function fieldPulse(x: number, y: number, strength = 1) {
  const host = document.querySelector(".shell");
  if (!host || matchMedia("(prefers-reduced-motion: reduce)").matches) return;
  const cv = document.createElement("canvas");
  const dpr = Math.min(devicePixelRatio, 3);
  const [w, h] = [innerWidth, innerHeight];
  cv.width = Math.round(w * dpr);
  cv.height = Math.round(h * dpr);
  cv.setAttribute("aria-hidden", "true");
  cv.style.cssText = "position:fixed;inset:0;width:100%;height:100%;z-index:-1;pointer-events:none";
  host.prepend(cv);
  const g = cv.getContext("2d");
  if (!g) return cv.remove();
  const rgb = rgbOf(getComputedStyle(document.documentElement).getPropertyValue("--dot"), 0xf5b227);
  const start = performance.now();
  const span = 620 + 260 * strength;
  const reach = 180 + 260 * strength;
  const tick = (now: number) => {
    const k = (now - start) / span;
    if (k >= 1 || !cv.isConnected) return cv.remove();
    const r = (1 - (1 - k) ** 3) * reach;
    g.setTransform(dpr, 0, 0, dpr, 0, 0);
    g.clearRect(0, 0, w, h);
    for (let j = 0; j * DOT_PITCH < h; j++)
      for (let i = 0; i * DOT_PITCH < w; i++) {
        const [cx, cy] = [i * DOT_PITCH + DOT_PITCH / 2, j * DOT_PITCH + DOT_PITCH / 2];
        const b = Math.exp(-(((Math.hypot(cx - x, cy - y) - r) / 15) ** 2)) * (1 - k);
        if (b < 0.03) continue;
        const s = 1.8 + 3.4 * b * Math.min(1.3, strength);
        g.fillStyle = styleOf(((rgb << 8) | Math.round(Math.min(1, 0.2 + 0.75 * b) * 255)) >>> 0);
        g.fillRect(cx - s / 2, cy - s / 2, s, s);
      }
    requestAnimationFrame(tick);
  };
  requestAnimationFrame(tick);
}

/**
 * What finished sinks into the field (#220): a few tiles leave a rect and settle on their own
 * places in the dot grid, shrinking to dot size as they arrive. Above the cards, since they start
 * on one. Freed at the end; nothing under Reduce Motion.
 */
export function sinkTiles(rect: DOMRect, count = 16) {
  if (matchMedia("(prefers-reduced-motion: reduce)").matches) return;
  const cv = document.createElement("canvas");
  const dpr = Math.min(devicePixelRatio, 3);
  const [w, h] = [innerWidth, innerHeight];
  cv.width = Math.round(w * dpr);
  cv.height = Math.round(h * dpr);
  cv.setAttribute("aria-hidden", "true");
  cv.style.cssText = "position:fixed;inset:0;width:100%;height:100%;z-index:74;pointer-events:none";
  document.body.append(cv);
  const g = cv.getContext("2d");
  if (!g) return cv.remove();
  const vars = getComputedStyle(document.documentElement);
  const [ink, gold] = [vars.getPropertyValue("--ink-2").trim(), vars.getPropertyValue("--gold").trim()];
  const snap = (v: number) => Math.round((v - DOT_PITCH / 2) / DOT_PITCH) * DOT_PITCH + DOT_PITCH / 2;
  const tiles = Array.from({ length: count }, (_, i) => {
    const [x, y] = [rect.left + Math.random() * rect.width, rect.top + Math.random() * rect.height];
    return { x, y, tx: snap(x + (Math.random() - 0.5) * 28), ty: snap(y + 22 + Math.random() * 44), delay: Math.random() * 0.22, c: i % 6 ? ink : gold };
  });
  const start = performance.now();
  const ease = (k: number) => 1 - (1 - k) ** 3;
  const tick = (now: number) => {
    const k = (now - start) / 620;
    if (k >= 1 || !cv.isConnected) return cv.remove();
    g.setTransform(dpr, 0, 0, dpr, 0, 0);
    g.clearRect(0, 0, w, h);
    for (const t of tiles) {
      const u = ease(Math.min(1, Math.max(0, (k - t.delay) / 0.72)));
      const s = 4.5 - 2.7 * u;
      g.globalAlpha = 1 - Math.max(0, k - 0.7) / 0.3;
      g.fillStyle = t.c;
      g.fillRect(t.x + (t.tx - t.x) * u - s / 2, t.y + (t.ty - t.y) * u - s / 2, s, s);
    }
    requestAnimationFrame(tick);
  };
  requestAnimationFrame(tick);
}

/**
 * When LAR finishes (046 C1b4): thin roots grow from the crystal along the dot grid, behind the
 * cards, and the data they reach runs home along them. About 1.5 s, then nothing is left.
 */
export function rootPull(from: DOMRect, ondone?: () => void) {
  const host = document.querySelector(".shell");
  if (!host || matchMedia("(prefers-reduced-motion: reduce)").matches) return ondone?.();
  const cv = document.createElement("canvas");
  const dpr = Math.min(devicePixelRatio, 2);
  const [w, h] = [innerWidth, innerHeight];
  cv.width = Math.round(w * dpr);
  cv.height = Math.round(h * dpr);
  cv.setAttribute("aria-hidden", "true");
  cv.style.cssText = "position:fixed;inset:0;width:100%;height:100%;z-index:-1;pointer-events:none";
  host.prepend(cv);
  const g = cv.getContext("2d");
  if (!g) {
    cv.remove();
    return ondone?.();
  }
  const { segs, packets, maxD } = growRoots(from.left + from.width / 2, from.top + from.height / 2, w, h);
  const vars = getComputedStyle(document.documentElement);
  const [gold, ink] = [vars.getPropertyValue("--gold").trim(), vars.getPropertyValue("--ink").trim()];
  const clamp = (v: number) => Math.min(1, Math.max(0, v));
  const start = performance.now();
  let flashed = false;
  const tick = (now: number) => {
    const k = (now - start) / 1500;
    if (k >= 1 || !cv.isConnected) return cv.remove();
    g.setTransform(dpr, 0, 0, dpr, 0, 0);
    g.clearRect(0, 0, w, h);
    const reach = (1 - (1 - clamp(k / 0.4)) ** 3) * maxD;
    const fade = 1 - clamp((k - 0.62) / 0.38);
    g.fillStyle = gold;
    for (const q of segs) {
      if (q.d0 > reach) continue;
      const u = clamp((reach - q.d0) / (q.d1 - q.d0));
      const thick = q.d0 < maxD * 0.3 ? 2 : 1;
      g.globalAlpha = 0.42 * fade * (1 - (q.d0 / maxD) * 0.6);
      const [ex, ey] = [q.x1 + (q.x2 - q.x1) * u, q.y1 + (q.y2 - q.y1) * u];
      g.fillRect(Math.min(q.x1, ex) - thick / 2, Math.min(q.y1, ey) - thick / 2, Math.abs(ex - q.x1) + thick, Math.abs(ey - q.y1) + thick);
      if (u >= 1) {
        g.globalAlpha = 0.6 * fade;
        g.fillRect(q.x2 - 1.5, q.y2 - 1.5, 3, 3);
      }
    }
    // Each leaf's data runs home along its own root.
    g.globalAlpha = 1;
    g.fillStyle = ink;
    for (const p of packets) {
      const u = clamp((k - 0.34 - p.delay) / 0.5);
      if (u <= 0 || u >= 1) continue;
      const dist = p.len * (1 - u) ** 2;
      const seg = p.path.find((q) => dist >= q.d0 && dist <= q.d1) ?? p.path[p.path.length - 1];
      const f = clamp((dist - seg.d0) / (seg.d1 - seg.d0));
      g.fillRect(Math.round(seg.x1 + (seg.x2 - seg.x1) * f) - 1.5, Math.round(seg.y1 + (seg.y2 - seg.y1) * f) - 1.5, 3, 3);
    }
    if (!flashed && k > 0.8) {
      flashed = true;
      ondone?.();
    }
    requestAnimationFrame(tick);
  };
  requestAnimationFrame(tick);
}

export interface RootSeg {
  x1: number;
  y1: number;
  x2: number;
  y2: number;
  d0: number;
  d1: number;
  par: number;
}

/** Four trunks with a few branches, every joint on the dot grid, up and left of the crystal. */
export function growRoots(x: number, y: number, w: number, h: number, R: () => number = Math.random) {
  const P = DOT_PITCH;
  const snap = (v: number) => Math.round((v - P / 2) / P) * P + P / 2;
  const [ox, oy] = [snap(x), snap(y)];
  const segs: RootSeg[] = [];
  const leaves: number[] = [];
  const grow = (sx: number, sy: number, dx: number, dy: number, d: number, parent: number, gen: number) => {
    let [cx, cy, cd, par] = [sx, sy, d, parent];
    const steps = 2 + Math.floor(R() * 3);
    for (let i = 0; i < steps; i++) {
      const len = (1 + Math.floor(R() * 3)) * P;
      const [nx, ny] = [cx + dx * len, cy + dy * len];
      if (nx < 0 || ny < 0 || nx > w || ny > h) break;
      segs.push({ x1: cx, y1: cy, x2: nx, y2: ny, d0: cd, d1: cd + len, par });
      par = segs.length - 1;
      [cx, cy, cd] = [nx, ny, cd + len];
      if (R() < 0.45) {
        const t = R() < 0.5 ? 1 : -1;
        [dx, dy] = dx ? [0, t] : [t, 0];
        if (dy > 0 && cy > oy) dy = -dy;
      }
      if (gen < 2 && R() < 0.3) {
        const t = R() < 0.5 ? 1 : -1;
        grow(cx, cy, dx ? 0 : t, dx ? t : 0, cd, par, gen + 1);
      }
    }
    if (par !== parent) leaves.push(par);
  };
  // One trunk climbs the page's open gutter, so it shows even on a screen full of cards.
  const gutter = snap(w - 8);
  if (gutter > ox && gutter <= w) {
    segs.push({ x1: ox, y1: oy, x2: gutter, y2: oy, d0: 0, d1: gutter - ox, par: -1 });
    let [cy, cd, par] = [oy, gutter - ox, 0];
    for (let i = 0; i < 6 && cy - 3 * P > 0; i++) {
      const len = (2 + Math.floor(R() * 3)) * P;
      if (cy - len < 0) break;
      segs.push({ x1: gutter, y1: cy, x2: gutter, y2: cy - len, d0: cd, d1: cd + len, par });
      par = segs.length - 1;
      [cy, cd] = [cy - len, cd + len];
    }
    if (par) leaves.push(par);
  }
  for (const [dx, dy] of [[-1, 0], [0, -1], [-1, 0], [0, -1]]) grow(ox, oy, dx, dy, 0, -1, 0);
  const maxD = Math.max(1, ...segs.map((q) => q.d1));
  const packets = leaves.map((l, i) => {
    const path: RootSeg[] = [];
    for (let c = l; c >= 0; c = segs[c].par) path.push(segs[c]);
    return { path, delay: (i % 7) * 0.035, len: segs[l].d1 };
  });
  return { segs, packets, maxD };
}
