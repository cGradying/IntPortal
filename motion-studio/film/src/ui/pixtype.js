// Glitch type: the film's headline system. Each line is rasterised in two
// faces: its own (Montserrat sans, or Pixelify for pixel labels) and the other.
// On the way in it glitches between them on sixteenth notes: chunky pixel
// cells, then the pixel face, then sans with horizontal slices still in pixel,
// then a size-jumped pixel flicker, then it lands in its own face. A spectral
// split (magenta / cyan fringes, offset sideways) rides the glitch and decays
// to zero as it settles. Exits reverse it and de-rez into cells. One ink
// colour per line: the colour lives in the chromatic fringes, not a fill.
import { clamp, css, el, hash, inv } from "../lib/core.js";

const FONTS = {
  display: (s) => [`800 ${s}px Montserrat`, -0.035],
  pixel: (s) => [`700 ${s}px "Pixelify Sans"`, 0.02],
  ui: (s) => [`700 ${s}px "Source Sans 3"`, 0],
};
const FRINGE = ["#ff2bd6", "#00e5ff"];

/**
 * pixText(parent, { text, size, font: "display"|"pixel"|"ui", alt, ink, shadow,
 *   x, y, anchor: "l"|"c"|"r", lh })
 * → { node, w (text advance), h, render(b, { at, dur, out, outDur, glitchAt, chroma }) }
 */
export function pixText(parent, o) {
  const size = o.size ?? 120;
  const face = o.font ?? "display";
  const alt = o.alt ?? (face === "pixel" ? "display" : "pixel");
  const lines = String(o.text).split("\n");
  const lh = o.lh ?? 1.0;
  const m = document.createElement("canvas").getContext("2d");
  const widthOf = (f, s) => {
    const [font, tr] = FONTS[f](s);
    m.font = font;
    m.letterSpacing = `${tr * s}px`;
    return Math.max(...lines.map((l) => m.measureText(l).width));
  };
  const tw = widthOf(face, size);
  // the alt face is sized to roughly the same width; "big" is a size jump
  const altSize = Math.round(size * clamp(tw / widthOf(alt, size), 0.7, 1.15));
  const padX = Math.round(size * 0.3), padY = Math.round(size * 0.24);
  const W = Math.ceil(Math.max(tw, widthOf(alt, altSize) * 1.16) + padX * 2);
  const H = Math.ceil(lines.length * size * lh + padY * 2);
  const align = o.anchor === "c" ? "center" : o.anchor === "r" ? "right" : "left";
  const ax = align === "center" ? W / 2 : align === "right" ? W - padX : padX;

  const mask = (f, s, scale = 1) => {
    const c = document.createElement("canvas");
    c.width = W; c.height = H;
    const g = c.getContext("2d");
    const [font, tr] = FONTS[f](Math.round(s * scale));
    g.font = font;
    g.letterSpacing = `${tr * s * scale}px`;
    g.textAlign = align;
    g.fillStyle = "#fff";
    lines.forEach((l, i) => g.fillText(l, ax, padY + size * 0.8 + i * size * lh));
    return c;
  };
  const M = { main: mask(face, size), alt: mask(alt, altSize), big: mask(alt, altSize, 1.16) };

  const node = el("div", "abs", parent);
  const ox = o.anchor === "c" ? -W / 2 : o.anchor === "r" ? -W + padX : -padX;
  css(node, { left: `${(o.x ?? 0) + ox}px`, top: `${(o.y ?? 0) - padY}px`, width: `${W}px`, height: `${H}px`, pointerEvents: "none" });
  const B = el("canvas", "px", node);
  B.width = W; B.height = H;
  css(B, { position: "absolute", left: "0", top: "0", width: `${W}px`, height: `${H}px` });
  const g = B.getContext("2d");
  const mk = () => Object.assign(document.createElement("canvas"), { width: W, height: H });
  const T = mk(), TC = mk();
  const ink = o.ink ?? "#f7ecec";
  const shadow = o.shadow;
  const sh = shadow ? Math.max(3, Math.round(size * 0.04)) : 0;
  const small = document.createElement("canvas");

  /** Compose the glyph mask: base face, some slices swapped, rows sheared. */
  function compose(base, sliceFace, slices, seed, shear) {
    const x = T.getContext("2d");
    x.globalCompositeOperation = "source-over";
    x.imageSmoothingEnabled = true;
    x.clearRect(0, 0, W, H);
    const n = 9;
    const hh = H / n;
    for (let i = 0; i < n; i++) {
      const pick = slices > 0 && hash(i, seed) < slices ? sliceFace : base;
      const off = shear ? Math.round((hash(i, seed, 3) - 0.5) * shear) : 0;
      x.drawImage(M[pick], 0, i * hh, W, hh + 1, off, i * hh, W, hh + 1);
    }
  }
  /** Replace T with a cell-quantised copy (hard alpha). */
  function cells(c) {
    const cw = Math.ceil(W / c), ch = Math.ceil(H / c);
    small.width = cw; small.height = ch;
    const s = small.getContext("2d");
    s.imageSmoothingEnabled = true;
    s.drawImage(T, 0, 0, cw, ch);
    const im = s.getImageData(0, 0, cw, ch);
    const d = im.data;
    for (let i = 3; i < d.length; i += 4) d[i] = d[i] > 70 ? 255 : 0;
    s.putImageData(im, 0, 0);
    const x = T.getContext("2d");
    x.clearRect(0, 0, W, H);
    x.imageSmoothingEnabled = false;
    x.drawImage(small, 0, 0, cw * c, ch * c);
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
  function paint(chroma) {
    g.clearRect(0, 0, W, H);
    if (sh) g.drawImage(tint(shadow), sh, sh);
    if (chroma > 0.4) {
      g.globalCompositeOperation = "lighter";
      g.drawImage(tint(FRINGE[0]), -chroma, 0);
      g.drawImage(tint(FRINGE[1]), chroma, 0);
      g.globalCompositeOperation = "source-over";
    }
    g.drawImage(tint(ink), 0, 0);
  }

  let lastKey = "";
  /**
   * at: beat the line starts glitching in; dur: beats until it lands (six
   * sixteenth-ish steps); out: beat the exit starts; glitchAt: beats where a
   * settled line flickers back through the other face.
   */
  function render(b, { at = 0, dur = 1.5, out = Infinity, outDur = 0.75, glitchAt = [], chroma = 1 } = {}) {
    const vis = b >= at && b < out + outDur;
    node.style.display = vis ? "" : "none";
    if (!vis) return;
    const C = Math.max(4, size * 0.06) * chroma;
    let st;
    if (b < at + dur) {
      const k = inv(at, at + dur, b);
      const step = Math.min(5, Math.floor(k * 6));
      st = [
        { base: "alt", cell: Math.max(8, Math.round(size / 9)), ch: C * 1.6, sl: 0, shear: size * 0.2 },
        { base: "alt", cell: 0, ch: C * 1.3, sl: 0, shear: size * 0.12 },
        { base: "main", cell: 0, ch: C * 1.0, sl: 0.45, sliceFace: "alt", shear: size * 0.1 },
        { base: "big", cell: 0, ch: C * 0.9, sl: 0, shear: size * 0.05 },
        { base: "main", cell: 0, ch: C * 0.55, sl: 0.2, sliceFace: "alt", shear: 0 },
        { base: "main", cell: 0, ch: C * 0.25, sl: 0, shear: 0 },
      ][step];
      st.seed = step * 13 + Math.floor(at * 4);
    } else if (b >= out) {
      const k = inv(out, out + outDur, b);
      const step = Math.min(3, Math.floor(k * 4));
      st = [
        { base: "main", cell: 0, ch: C * 1.2, sl: 0.5, sliceFace: "alt", shear: size * 0.15 },
        { base: "alt", cell: 0, ch: C * 1.4, sl: 0, shear: size * 0.25 },
        { base: "alt", cell: Math.max(6, Math.round(size / 12)), ch: C * 1.6, sl: 0, shear: size * 0.35 },
        { base: "alt", cell: Math.max(10, Math.round(size / 6)), ch: C * 2, sl: 0, shear: size * 0.5 },
      ][step];
      st.seed = 100 + step * 7 + Math.floor(out * 4);
    } else {
      const g0 = glitchAt.find((a) => b >= a && b < a + 0.25);
      st = g0 != null
        ? { base: b < g0 + 0.125 ? "alt" : "main", cell: 0, ch: C * 1.2, sl: 0.4, sliceFace: "alt", shear: size * 0.12, seed: Math.floor(g0 * 8) }
        : { base: "main", cell: 0, ch: 0, sl: 0, shear: 0, seed: 0 };
    }
    const key = `${st.base}|${st.cell}|${st.ch.toFixed(1)}|${st.sl}|${st.sliceFace}|${st.shear.toFixed(1)}|${st.seed}`;
    if (key === lastKey) return;
    lastKey = key;
    compose(st.base, st.sliceFace, st.sl, st.seed, st.shear);
    if (st.cell > 1) cells(st.cell);
    paint(st.ch);
  }
  return { node, render, w: tw, h: H };
}
