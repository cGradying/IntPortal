// Morph type: the film's headline system. Each line is rasterised in two faces,
// its own (Montserrat sans, or Pixelify for pixel labels) and the other, and
// both are turned into signed distance fields at init. The text really morphs
// between the faces by blending the fields, so strokes flow from pixel steps to
// sans curves. On the way in, glyphs slide in side by side from alternating
// directions in the other face and morph home while the block settles from a
// slight zoom. Geometry rides along: a baseline rule drawn from the centre,
// corner brackets that snap in and retract, an end square and a crosshair.
// Exits morph back to the other face and scatter the glyphs sideways.
import { clamp, css, ease, el, inv } from "../lib/core.js";

const FONTS = {
  display: (s) => [`800 ${s}px Montserrat`, -0.035],
  pixel: (s) => [`700 ${s}px "Pixelify Sans"`, 0.02],
  ui: (s) => [`700 ${s}px "Source Sans 3"`, 0],
};
const INF = 1e20;
const R = 2; // SDF resolution divisor

// ------------------------------------------------------------ distance fields
function edt1d(f, n, d, v, z) {
  let k = 0;
  v[0] = 0; z[0] = -INF; z[1] = INF;
  for (let q = 1; q < n; q++) {
    let s = (f[q] + q * q - (f[v[k]] + v[k] * v[k])) / (2 * q - 2 * v[k]);
    while (s <= z[k]) { k--; s = (f[q] + q * q - (f[v[k]] + v[k] * v[k])) / (2 * q - 2 * v[k]); }
    k++; v[k] = q; z[k] = s; z[k + 1] = INF;
  }
  k = 0;
  for (let q = 0; q < n; q++) { while (z[k + 1] < q) k++; d[q] = (q - v[k]) * (q - v[k]) + f[v[k]]; }
}
function edt(grid, w, h) {
  const n = Math.max(w, h), f = new Float64Array(n), d = new Float64Array(n), v = new Int32Array(n), z = new Float64Array(n + 1);
  for (let x = 0; x < w; x++) {
    for (let y = 0; y < h; y++) f[y] = grid[y * w + x];
    edt1d(f, h, d, v, z);
    for (let y = 0; y < h; y++) grid[y * w + x] = d[y];
  }
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) f[x] = grid[y * w + x];
    edt1d(f, w, d, v, z);
    for (let x = 0; x < w; x++) grid[y * w + x] = d[x];
  }
  return grid;
}
function sdfOf(canvas, w, h) {
  const s = document.createElement("canvas");
  s.width = w; s.height = h;
  const g = s.getContext("2d");
  g.drawImage(canvas, 0, 0, w, h);
  const a = g.getImageData(0, 0, w, h).data;
  const inside = new Float64Array(w * h), outside = new Float64Array(w * h);
  for (let i = 0; i < w * h; i++) {
    const on = a[i * 4 + 3] > 127;
    inside[i] = on ? 0 : INF;
    outside[i] = on ? INF : 0;
  }
  edt(inside, w, h); edt(outside, w, h);
  const out = new Float32Array(w * h);
  for (let i = 0; i < w * h; i++) out[i] = Math.sqrt(inside[i]) - Math.sqrt(outside[i]);
  return out;
}

/**
 * pixText(parent, { text, size, font: "display"|"pixel"|"ui", alt, ink, shadow,
 *   x, y, anchor: "l"|"c"|"r", lh, deco })
 * → { node, w (text advance), h, render(b, { at, dur, out, outDur, glitchAt, m, ink }) }
 */
export function pixText(parent, o) {
  const size = o.size ?? 120;
  const face = o.font ?? "display";
  const alt = o.alt ?? (face === "pixel" ? "display" : "pixel");
  const lines = String(o.text).split("\n");
  const lh = o.lh ?? 1.0;
  const m0 = document.createElement("canvas").getContext("2d");
  const setFont = (g, f, s) => { const [font, tr] = FONTS[f](s); g.font = font; g.letterSpacing = `${tr * s}px`; };
  const lineW = (f, s) => lines.map((l) => { setFont(m0, f, s); return m0.measureText(l).width; });
  const mainW = lineW(face, size);
  const tw = Math.max(...mainW);
  const altRaw = Math.max(...lineW(alt, size));
  const altSize = Math.round(size * clamp(tw / altRaw, 0.7, 1.15));
  const padX = Math.round(size * 0.35), padY = Math.round(size * 0.3);
  const W = Math.ceil(Math.max(tw, Math.max(...lineW(alt, altSize))) + padX * 2);
  const H = Math.ceil(lines.length * size * lh + padY * 2);
  const align = o.anchor === "c" ? "center" : o.anchor === "r" ? "right" : "left";
  const lineX = (w) => (align === "center" ? W / 2 - w / 2 : align === "right" ? W - padX - w : padX);
  const base = (i) => padY + size * 0.8 + i * size * lh;

  const mask = (f, s) => {
    const c = document.createElement("canvas");
    c.width = W; c.height = H;
    const g = c.getContext("2d");
    setFont(g, f, s);
    g.fillStyle = "#fff";
    const ws = lineW(f, s);
    lines.forEach((l, i) => g.fillText(l, lineX(ws[i]), base(i)));
    return c;
  };
  const M = { main: mask(face, size), alt: mask(alt, altSize) };
  const sw = Math.ceil(W / R), shh = Math.ceil(H / R);
  const SDF = { main: sdfOf(M.main, sw, shh), alt: sdfOf(M.alt, sw, shh) };
  const low = document.createElement("canvas");
  low.width = sw; low.height = shh;
  const lowG = low.getContext("2d");
  const lowImg = lowG.createImageData(sw, shh);

  // glyph bands (main-face layout), for side-by-side scatter
  const bands = [];
  lines.forEach((l, li) => {
    setFont(m0, face, size);
    const x0 = lineX(mainW[li]);
    const top = li === 0 ? 0 : base(li) - size * 0.95, bot = li === lines.length - 1 ? H : base(li) + size * 0.05;
    let prev = 0;
    for (let c = 0; c < l.length; c++) {
      const x1 = m0.measureText(l.slice(0, c + 1)).width;
      if (l[c] !== " ") bands.push({ x: c === 0 ? 0 : x0 + prev, w: (c === l.length - 1 ? W : x0 + x1) - (c === 0 ? 0 : x0 + prev), y: top, h: bot - top, n: bands.length });
      prev = x1;
    }
  });

  const node = el("div", "abs", parent);
  const ox = o.anchor === "c" ? -W / 2 : o.anchor === "r" ? -W + padX : -padX;
  css(node, { left: `${(o.x ?? 0) + ox}px`, top: `${(o.y ?? 0) - padY}px`, width: `${W}px`, height: `${H}px`, pointerEvents: "none", transformOrigin: "50% 50%" });
  const B = el("canvas", "", node);
  B.width = W; B.height = H;
  css(B, { position: "absolute", left: "0", top: "0", width: `${W}px`, height: `${H}px` });
  const g = B.getContext("2d");
  const mk = () => Object.assign(document.createElement("canvas"), { width: W, height: H });
  const S = mk(), T = mk(), TC = mk();
  const shadow = o.shadow;
  const sh = shadow ? Math.max(3, Math.round(size * 0.04)) : 0;

  // geometry overlay
  const deco = o.deco ?? size >= 60;
  const NS = "http://www.w3.org/2000/svg";
  const svg = document.createElementNS(NS, "svg");
  svg.setAttribute("width", W); svg.setAttribute("height", H);
  css(svg, { position: "absolute", left: "0", top: "0", overflow: "visible" });
  node.appendChild(svg);
  const sv = (t, a) => { const e = document.createElementNS(NS, t); for (const k in a) e.setAttribute(k, a[k]); svg.appendChild(e); return e; };
  const lw = Math.max(2, Math.round(size * 0.022));
  const txL = Math.min(...lines.map((_, i) => lineX(mainW[i]))), txR = Math.max(...lines.map((_, i) => lineX(mainW[i]) + mainW[i]));
  const ry = base(lines.length - 1) + size * 0.16;
  const topY = base(0) - size * 0.82;
  const rule = sv("line", { "stroke-width": lw, "stroke-linecap": "square" });
  const sq = sv("rect", { width: size * 0.09, height: size * 0.09, fill: "#f5b227" });
  const ring = sv("rect", { width: size * 0.09, height: size * 0.09, fill: "none", "stroke-width": lw });
  const cross = sv("path", { d: `M${-size * 0.07},0H${size * 0.07}M0,${-size * 0.07}V${size * 0.07}`, stroke: "#f5b227", "stroke-width": lw });
  const bl = size * 0.16, bx = size * 0.14;
  const corners = [[txL - bx, topY - bx, 1, 1], [txR + bx, topY - bx, -1, 1], [txL - bx, ry + bx * 0.6, 1, -1], [txR + bx, ry + bx * 0.6, -1, -1]]
    .map(([x, y, sx, sy]) => ({ x, y, sx, sy, p: sv("path", { fill: "none", stroke: "#f5b227", "stroke-width": lw }) }));
  svg.style.display = deco ? "" : "none";

  function morphTo(m) {
    const x = S.getContext("2d");
    x.clearRect(0, 0, W, H);
    if (m <= 0.001) return void x.drawImage(M.main, 0, 0);
    if (m >= 0.999) return void x.drawImage(M.alt, 0, 0);
    const a = SDF.main, c = SDF.alt, d = lowImg.data;
    const k = ease.inOutCubic(m);
    for (let i = 0; i < a.length; i++) {
      const s = a[i] + (c[i] - a[i]) * k;
      d[i * 4] = d[i * 4 + 1] = d[i * 4 + 2] = 255;
      d[i * 4 + 3] = clamp(0.5 - s * 1.6) * 255;
    }
    lowG.putImageData(lowImg, 0, 0);
    x.imageSmoothingEnabled = true;
    x.drawImage(low, 0, 0, W, H);
  }
  function scatter(offs) {
    const x = T.getContext("2d");
    x.clearRect(0, 0, W, H);
    if (!offs) return void x.drawImage(S, 0, 0);
    bands.forEach((bd, i) => { if (offs[i] !== null) x.drawImage(S, bd.x, bd.y, bd.w, bd.h, bd.x + offs[i], bd.y, bd.w, bd.h); });
  }
  function tint(col) {
    const x = TC.getContext("2d");
    x.globalCompositeOperation = "source-over";
    x.clearRect(0, 0, W, H);
    x.drawImage(T, 0, 0);
    x.globalCompositeOperation = "source-in";
    x.fillStyle = col;
    x.fillRect(0, 0, W, H);
    x.globalCompositeOperation = "source-over";
    return TC;
  }

  let lastKey = "";
  function render(b, { at = 0, dur = 1.5, out = Infinity, outDur = 0.75, glitchAt = [], m: mForce, ink: inkForce } = {}) {
    const vis = b >= at && b < out + outDur;
    node.style.display = vis ? "" : "none";
    if (!vis) return;
    const ink = inkForce ?? o.ink ?? "#f7ecec";
    const n = bands.length;
    let m = 0, offs = null, zoom = 1, ruleK = 1, brK = 0, brOut = 0, cr = 0;
    if (b < at + dur) {
      const k = inv(at, at + dur, b);
      // glyphs slide in side by side, alternating directions, staggered
      offs = bands.map((bd, i) => {
        const ki = clamp((k - (i / Math.max(1, n)) * 0.3) / 0.5);
        if (ki <= 0) return null;
        return (i % 2 ? 1 : -1) * size * 0.9 * (1 - ease.outExpo(ki));
      });
      m = 1 - ease.inOutCubic(clamp((k - 0.3) / 0.7));
      zoom = 1 + 0.1 * (1 - ease.outCubic(k));
      ruleK = ease.outExpo(clamp((k - 0.1) / 0.6));
      brK = ease.outBack(clamp((k - 0.2) / 0.35));
      brOut = ease.inCubic(clamp((k - 0.75) / 0.25));
      cr = k;
    } else if (b >= out) {
      const k = inv(out, out + outDur, b);
      m = ease.outCubic(clamp(k / 0.6));
      offs = bands.map((bd, i) => {
        const ki = clamp((k - 0.15 - (i / Math.max(1, n)) * 0.25) / 0.6);
        return ki >= 1 ? null : (i % 2 ? -1 : 1) * size * 1.4 * ease.inCubic(ki);
      });
      zoom = 1 - 0.06 * ease.inCubic(k);
      ruleK = 1 - ease.inCubic(clamp(k / 0.7));
      cr = 1 + k;
    } else {
      const g0 = glitchAt.find((a) => b >= a && b < a + 0.6);
      if (g0 != null) {
        const k = inv(g0, g0 + 0.6, b);
        m = Math.sin(Math.PI * clamp(k * 1.1)) * 0.9;
        brK = Math.sin(Math.PI * k);
        cr = 1 + k;
      }
    }
    if (mForce != null) m = mForce;
    // geometry (cheap: every frame)
    if (deco) {
      const cx = (txL + txR) / 2, half = ((txR - txL) / 2) * ruleK;
      rule.setAttribute("x1", cx - half); rule.setAttribute("x2", cx + half);
      rule.setAttribute("y1", ry); rule.setAttribute("y2", ry);
      rule.setAttribute("stroke", ink);
      rule.setAttribute("opacity", b >= at + dur && b < out ? 0.35 : 0.9);
      sq.setAttribute("x", cx - half - size * 0.045); sq.setAttribute("y", ry - size * 0.045);
      ring.setAttribute("x", cx + half - size * 0.045); ring.setAttribute("y", ry - size * 0.045);
      ring.setAttribute("stroke", ink);
      sq.style.display = ring.style.display = ruleK > 0.05 ? "" : "none";
      cross.setAttribute("transform", `translate(${txR + size * 0.28},${topY - size * 0.05}) rotate(${cr * 90})`);
      cross.style.display = cr > 0 && cr < 2 ? "" : "none";
      const bk = clamp(brK) * (1 - brOut);
      corners.forEach((c) => {
        const L = bl * bk;
        c.p.setAttribute("d", `M${c.x},${c.y + c.sy * L}V${c.y}H${c.x + c.sx * L}`);
        c.p.style.display = bk > 0.02 ? "" : "none";
      });
    }
    node.style.transform = zoom !== 1 ? `scale(${zoom})` : "";
    const key = `${m.toFixed(3)}|${offs ? offs.map((v) => (v == null ? "n" : v.toFixed(1))).join(",") : "-"}|${ink}`;
    if (key === lastKey) return;
    lastKey = key;
    morphTo(m);
    scatter(offs);
    g.clearRect(0, 0, W, H);
    if (sh) g.drawImage(tint(shadow), sh, sh);
    g.drawImage(tint(ink), 0, 0);
  }
  return { node, render, w: tw, h: H };
}
