// Shared HyperFrames clip helpers: the film's beat grid (window.GRID, written
// by scripts/clips.mjs), closed-form springs, seeded hash, and clip()
// which registers a paused GSAP timeline that the renderer seeks frame by
// frame. draw(t) receives FILM time in seconds, so beat math matches Remotion.
const G = window.GRID;
export const NOMINAL = G.nominal;
export function B(b) {
  const g = G.beats;
  if (b <= 0) return b * NOMINAL;
  const i = Math.floor(b);
  if (i >= g.length - 1) return g[g.length - 1] + (b - g.length + 1) * NOMINAL;
  return g[i] + (g[i + 1] - g[i]) * (b - i);
}
export function bt(t) {
  const g = G.beats;
  let lo = 0, hi = g.length - 1;
  if (t <= 0) return t / NOMINAL;
  if (t >= g[hi]) return hi + (t - g[hi]) / NOMINAL;
  while (hi - lo > 1) { const m = (lo + hi) >> 1; if (g[m] <= t) lo = m; else hi = m; }
  return lo + (t - g[lo]) / (g[hi] - g[lo]);
}
export const clamp = (x, a = 0, b = 1) => Math.min(b, Math.max(a, x));
export const lerp = (a, b, k) => a + (b - a) * k;
export function spring(t, k = 170, d = 26) {
  if (t <= 0) return 0;
  const w0 = Math.sqrt(k), z = d / (2 * w0);
  if (z < 0.999) { const wd = w0 * Math.sqrt(1 - z * z); return 1 - Math.exp(-z * w0 * t) * (Math.cos(wd * t) + ((z * w0) / wd) * Math.sin(wd * t)); }
  return 1 - Math.exp(-w0 * t) * (1 + w0 * t);
}
export const hash = (n) => { const x = Math.sin(n * 127.1 + 311.7) * 43758.5453; return x - Math.floor(x); };
export function clip(id, from, to, draw) {
  const t0 = B(from), dur = B(to) - t0;
  const p = { t: 0 };
  const tl = window.gsap.timeline({ paused: true });
  tl.to(p, { t: dur, duration: dur, ease: "none", onUpdate: () => draw(t0 + p.t) }, 0);
  draw(t0);
  window.__timelines = window.__timelines || {};
  window.__timelines[id] = tl;
}
export function loadImg(src) {
  return new Promise((res) => { const i = new Image(); i.onload = () => res(i); i.src = src; });
}
