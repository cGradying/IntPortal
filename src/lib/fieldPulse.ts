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
