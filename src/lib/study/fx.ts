// The study session's art (spec 055 C7–C9): one dithered portal swirl shared by every canvas
// that shows it (the score panel, the card backs, the pile), and pixel bursts. One loop for
// all of them, at most 30 frames a second, paused while the app is hidden; still under
// Reduce Motion or with effects off.

// The portal swirl ramp (DESIGN.md: pixel-art palettes keep their hex).
const RAMP = ["#170509", "#540a1c", "#941c30", "#cca128", "#faebb3"];
const RGB = RAMP.map((h) => [1, 3, 5].map((i) => parseInt(h.slice(i, i + 2), 16)));
const BAYER = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5];
export const BURST = ["#b5412a", "#e08a35", "#f3cf6a", "#fff6dc", "#e8b04a"];

// One shared swirl buffer, painted once a frame. Each canvas shows a centred crop of it at the
// same pixel scale (never stretched), so a wide strip shows a slice and a card a bigger piece.
const BW = 128;
const BH = 80;
const targets = new Set<HTMLCanvasElement>();
let src: HTMLCanvasElement | null = null;
let img: ImageData | null = null;
let raf = 0;
let last = 0;
let t = 2.1;

/** 0–3, from the soft clock (spec 055 C6). Each step speeds the swirl and lifts it a tone. */
export const table = { heat: 0, still: false };

/** Canvas pixels per unit of the swirl. */
const UNIT = 40;

// The swirl's geometry never changes, so angle, radius and the Bayer threshold are worked out
// once; a frame is then three sines a pixel over BW × BH.
let geo: { a: Float32Array; r: Float32Array; b: Float32Array } | null = null;
function geometry() {
  if (geo) return geo;
  geo = { a: new Float32Array(BW * BH), r: new Float32Array(BW * BH), b: new Float32Array(BW * BH) };
  for (let y = 0; y < BH; y++) {
    for (let x = 0; x < BW; x++) {
      const dx = (x + 0.5 - BW / 2) / UNIT;
      const dy = (y + 0.5 - BH / 2) / UNIT;
      const i = y * BW + x;
      geo.r[i] = Math.hypot(dx, dy) * 2.4;
      geo.a[i] = Math.atan2(dy, dx);
      geo.b[i] = BAYER[(y & 3) * 4 + (x & 3)] / 16;
    }
  }
  return geo;
}

/** One frame of the swirl into a BW × BH buffer: polar bands twisted with time, quantised to the ramp through a 4×4 Bayer. */
export function paint(px: Uint8ClampedArray, time: number, heat: number) {
  const { a, r, b } = geometry();
  const lift = 0.05 * heat;
  const gain = 0.62 + 0.1 * heat;
  for (let i = 0, n = BW * BH; i < n; i++) {
    const v = 0.5 + 0.5 * (0.7 * Math.sin(a[i] * 3 + r[i] * 7 - time + 1.2 * Math.sin(r[i] * 4 - time * 0.7)) + 0.3 * Math.sin(a[i] * 5 - r[i] * 11 + time * 1.3));
    const c = RGB[Math.max(0, Math.min(4, Math.floor((v * gain + lift) * 4 + b[i])))];
    const p = i * 4;
    px[p] = c[0];
    px[p + 1] = c[1];
    px[p + 2] = c[2];
    px[p + 3] = 255;
  }
}

function draw() {
  if (!src) {
    src = document.createElement("canvas");
    src.width = BW;
    src.height = BH;
    img = src.getContext("2d")!.createImageData(BW, BH);
  }
  paint(img!.data, t, table.heat);
  src.getContext("2d")!.putImageData(img!, 0, 0);
  for (const cv of targets) {
    const g = cv.getContext("2d");
    if (!g || !cv.isConnected) continue;
    // A canvas bigger than the buffer (a wide desktop card) takes a scaled crop with its own aspect.
    const k = Math.max(1, cv.width / BW, cv.height / BH);
    const sw = cv.width / k;
    const sh = cv.height / k;
    g.imageSmoothingEnabled = false;
    g.drawImage(src, (BW - sw) / 2, (BH - sh) / 2, sw, sh, 0, 0, cv.width, cv.height);
  }
}

function frame(now: number) {
  raf = 0;
  if (!targets.size || document.hidden) return;
  const dt = Math.min(0.1, (now - last) / 1000);
  if (dt >= 1 / 30) {
    last = now;
    t += dt * (0.5 + 0.35 * table.heat);
    draw();
  }
  if (!table.still) raf = requestAnimationFrame(frame);
}

/** Redraw now (after a heat change or a switch to still) and keep going unless still. */
export function kick() {
  if (!targets.size) return;
  draw();
  if (!table.still && !raf && !document.hidden) {
    last = performance.now();
    raf = requestAnimationFrame(frame);
  }
}

if (typeof document !== "undefined") document.addEventListener("visibilitychange", kick);

/** Svelte action: this canvas shows the swirl, at one canvas pixel per 3 CSS px. */
export function swirl(cv: HTMLCanvasElement) {
  // Layout size, not the box on screen: a card mounts mid-deal, scaled and turned.
  const fit = () => {
    cv.width = Math.max(8, Math.round(cv.offsetWidth / 3));
    cv.height = Math.max(8, Math.round(cv.offsetHeight / 3));
  };
  fit();
  const watch = new ResizeObserver(() => {
    fit();
    kick();
  });
  watch.observe(cv);
  targets.add(cv);
  kick();
  return {
    destroy() {
      watch.disconnect();
      targets.delete(cv);
      if (!targets.size && raf) {
        cancelAnimationFrame(raf);
        raf = 0;
      }
    },
  };
}

type Bit = { x: number; y: number; vx: number; vy: number; life: number; max: number; s: number; c: string };

/** Pixel bursts on one canvas over the session; draws only while bits are alive. */
export function bursts(cv: HTMLCanvasElement) {
  const bits: Bit[] = [];
  let id = 0;
  let prev = 0;
  const g = cv.getContext("2d")!;
  const step = (now: number) => {
    id = 0;
    const dt = Math.min(0.05, (now - prev) / 1000);
    prev = now;
    g.clearRect(0, 0, cv.width, cv.height);
    for (let i = bits.length - 1; i >= 0; i--) {
      const b = bits[i];
      b.life += dt;
      if (b.life >= b.max) {
        bits.splice(i, 1);
        continue;
      }
      b.vy += 700 * dt;
      b.x += b.vx * dt;
      b.y += b.vy * dt;
      g.globalAlpha = 1 - (b.life / b.max) ** 2;
      g.fillStyle = b.c;
      g.fillRect(Math.round(b.x / 2), Math.round(b.y / 2), b.s, b.s);
    }
    g.globalAlpha = 1;
    if (bits.length) id = requestAnimationFrame(step);
  };
  return {
    /** n bits from (x, y) in CSS px of the canvas. */
    burst(x: number, y: number, n: number) {
      const r = cv.getBoundingClientRect();
      cv.width = Math.round(r.width / 2);
      cv.height = Math.round(r.height / 2);
      for (let i = 0; i < n; i++) {
        const a = Math.random() * Math.PI * 2;
        const v = 60 + Math.random() * 230;
        bits.push({ x, y, vx: Math.cos(a) * v, vy: Math.sin(a) * v - 120, life: 0, max: 0.55 + Math.random() * 0.45, s: 2 + Math.floor(Math.random() * 2), c: BURST[i % BURST.length] });
      }
      if (!id) {
        prev = performance.now();
        id = requestAnimationFrame(step);
      }
    },
    stop() {
      cancelAnimationFrame(id);
      id = 0;
      bits.length = 0;
    },
  };
}
