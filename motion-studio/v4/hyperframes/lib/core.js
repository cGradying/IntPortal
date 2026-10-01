// Time, beats, easing, seeded noise and small DOM helpers. Everything here
// is a pure function of its inputs: no clocks, no Math.random.

export let BEATS = [];
export let BEAT = 60 / 124;

export async function loadBeats() {
  const b = await (await fetch("../beats.json")).json();
  BEATS = b.beats;
  BEAT = 60 / b.bpm;
}

/** Time (s) of fractional beat n on the measured grid. */
export function tb(n) {
  if (n <= 0) return n * BEAT;
  const i = Math.floor(n);
  if (i >= BEATS.length - 1) return BEATS[BEATS.length - 1] + (n - BEATS.length + 1) * BEAT;
  return BEATS[i] + (BEATS[i + 1] - BEATS[i]) * (n - i);
}

/** Fractional beat at time t (inverse of tb). */
export function bt(t) {
  if (t <= 0) return t / BEAT;
  let lo = 0, hi = BEATS.length - 1;
  if (t >= BEATS[hi]) return hi + (t - BEATS[hi]) / BEAT;
  while (hi - lo > 1) {
    const m = (lo + hi) >> 1;
    if (BEATS[m] <= t) lo = m; else hi = m;
  }
  return lo + (t - BEATS[lo]) / (BEATS[hi] - BEATS[lo]);
}

// ------------------------------------------------------------------ math
export const clamp = (x, a = 0, b = 1) => Math.min(b, Math.max(a, x));
export const lerp = (a, b, k) => a + (b - a) * k;
export const inv = (a, b, x) => clamp((x - a) / (b - a));
export const map = (x, a, b, c, d) => lerp(c, d, inv(a, b, x));
export const fract = (x) => x - Math.floor(x);

export const ease = {
  lin: (k) => k,
  inQuad: (k) => k * k,
  outQuad: (k) => 1 - (1 - k) * (1 - k),
  inCubic: (k) => k * k * k,
  outCubic: (k) => 1 - (1 - k) ** 3,
  inOutCubic: (k) => (k < 0.5 ? 4 * k * k * k : 1 - (-2 * k + 2) ** 3 / 2),
  outQuart: (k) => 1 - (1 - k) ** 4,
  inOutQuart: (k) => (k < 0.5 ? 8 * k ** 4 : 1 - (-2 * k + 2) ** 4 / 2),
  outExpo: (k) => (k >= 1 ? 1 : 1 - 2 ** (-10 * k)),
  inExpo: (k) => (k <= 0 ? 0 : 2 ** (10 * k - 10)),
  inOutExpo: (k) => (k <= 0 ? 0 : k >= 1 ? 1 : k < 0.5 ? 2 ** (20 * k - 10) / 2 : (2 - 2 ** (-20 * k + 10)) / 2),
  outBack: (k, s = 1.70158) => 1 + (s + 1) * (k - 1) ** 3 + s * (k - 1) ** 2,
  inBack: (k, s = 1.70158) => (s + 1) * k ** 3 - s * k * k,
  inPow: (k, p) => k ** p,
};

/** Closed-form damped spring from 0 to 1. `s` seconds since release. */
export function spring(s, freq = 2.2, damp = 0.55) {
  if (s <= 0) return 0;
  const w = 2 * Math.PI * freq;
  if (damp >= 1) return 1 - (1 + w * s) * Math.exp(-w * s);
  const wd = w * Math.sqrt(1 - damp * damp);
  return 1 - Math.exp(-damp * w * s) * (Math.cos(wd * s) + ((damp * w) / wd) * Math.sin(wd * s));
}

/** Spring driven by beats: starts at beat b0, `now` is the current beat. */
export const springB = (now, b0, freq = 2.2, damp = 0.55) => spring((now - b0) * BEAT, freq, damp);

/** Progress through beats [a, b] with an easing. */
export const pb = (now, a, b, e = ease.lin) => e(inv(a, b, now));

/** Envelope that jumps to 1 at beat b0 and decays over `len` beats. */
export const pulse = (now, b0, len = 1) => (now < b0 ? 0 : Math.exp(-((now - b0) / len) * 4));

// ------------------------------------------------------------------ noise
export function mulberry32(seed) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
/** Stateless hash noise in [0,1) for integer inputs. */
export function hash(...n) {
  let h = 2166136261;
  for (const v of n) {
    h ^= Math.floor(v) | 0;
    h = Math.imul(h, 16777619);
    h ^= h >>> 13;
    h = Math.imul(h, 0x5bd1e995);
  }
  return ((h ^ (h >>> 15)) >>> 0) / 4294967296;
}
/** Smooth 1D value noise, deterministic. */
export function noise1(x, seed = 0) {
  const i = Math.floor(x), f = x - i, u = f * f * (3 - 2 * f);
  return lerp(hash(i, seed), hash(i + 1, seed), u) * 2 - 1;
}

// ------------------------------------------------------------------ dom
export function el(tag, cls = "", parent = null, html = "") {
  const e = document.createElement(tag);
  if (cls) e.className = cls;
  if (html) e.innerHTML = html;
  if (parent) parent.appendChild(e);
  return e;
}
/** Collect [data-r] refs inside a node. */
export function refs(node) {
  const r = {};
  node.querySelectorAll("[data-r]").forEach((n) => (r[n.dataset.r] = n));
  return r;
}
/** Set several style props at once; numbers are left as-is. */
export function css(node, props) {
  for (const k in props) {
    const v = props[k];
    if (node.style[k] !== v) node.style[k] = v;
  }
}
export const show = (node, on) => {
  const v = on ? "" : "none";
  if (node.style.display !== v) node.style.display = v;
};
export const setText = (node, s) => {
  if (node.textContent !== s) node.textContent = s;
};
