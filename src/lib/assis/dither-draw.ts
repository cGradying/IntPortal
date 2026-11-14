// Paints the dither open (spec 048 C1–C3, C6) on one 2D canvas over the page. The window's face (glass,
// sky band, gold rim and extrusion) is drawn once offscreen; each frame fills the shown Bayer cells as a
// mask and lays the face through it, so the last frame is the window exactly and the real one takes over
// in one frame. Nothing is laid out.
import { CELL, CLOSE_MS, gridOf, OPEN_MS, progressAt, shown, type Rect } from "./dither";

export interface DitherOpts {
  /** A fixed, full-viewport canvas, above the window, `pointer-events: none`. */
  canvas: HTMLCanvasElement;
  /** In viewport points. */
  chip: Rect;
  win: Rect;
  /** The window's element: its `--r0`, `--r1`, `--g-a`, `--g-b`, `--g-rim` and `--g-ext` colour the face. */
  tokens: HTMLElement;
  mode: "open" | "close";
  headerH?: number;
  /** 1 is real time; 4 for checking by eye. */
  slow?: number;
  /** Closing: called on the last painted step, as the final cells go (the chip reappears). */
  onLast?: () => void;
  /** Reduce Motion: no dither; resolves at once and the caller cross-fades. */
  reduce?: boolean;
}

/** A CSS `linear-gradient(<deg>)` drawn on a canvas, on the line CSS uses. */
function linear(g: CanvasRenderingContext2D, r: Rect, deg: number, stops: [number, string][]) {
  const a = (deg * Math.PI) / 180;
  const [dx, dy] = [Math.sin(a), -Math.cos(a)];
  const len = Math.abs(r.w * dx) + Math.abs(r.h * dy);
  const [cx, cy] = [r.x + r.w / 2, r.y + r.h / 2];
  const gr = g.createLinearGradient(cx - (dx * len) / 2, cy - (dy * len) / 2, cx + (dx * len) / 2, cy + (dy * len) / 2);
  for (const [p, c] of stops) gr.addColorStop(p, c);
  g.fillStyle = gr;
  g.fillRect(r.x, r.y, r.w, r.h);
}

/** The window's tokens, resolved (they are `color-mix`es) through a probe. */
function tokensOf(el: HTMLElement) {
  const probe = document.createElement("i");
  probe.style.display = "none";
  el.appendChild(probe);
  const tok = (v: string, fallback: string) => {
    probe.style.color = `var(${v}, ${fallback})`;
    return getComputedStyle(probe).color;
  };
  const t = { r0: tok("--r0", "#3b1220"), r1: tok("--r1", "#7a1c2c"), a: tok("--g-a", "#241626"), b: tok("--g-b", "#150c18"), rim: tok("--g-rim", "rgb(232 176 74 / 0.42)"), ext: tok("--g-ext", "rgb(0 0 0 / 0.45)") };
  probe.remove();
  return t;
}

/** Room around the window for the rim (1 pt) and the extrusion (3 pt), so the cells cover both. */
const PAD = 3;

/** The window's face once, offscreen, PAD points larger on every side: rim and extrusion, then the glass, the sky band, its lit top and its dithered edge. */
function drawFace(win: Rect, headerH: number, t: ReturnType<typeof tokensOf>, dpr: number): HTMLCanvasElement | null {
  const face = document.createElement("canvas");
  face.width = Math.ceil((win.w + 2 * PAD) * dpr);
  face.height = Math.ceil((win.h + 2 * PAD) * dpr);
  const f = face.getContext("2d");
  if (!f) return null;
  f.setTransform(dpr, 0, 0, dpr, PAD * dpr, PAD * dpr);
  f.fillStyle = t.ext;
  f.fillRect(1, 1, win.w + 2, win.h + 2);
  f.fillStyle = t.rim;
  f.fillRect(-1, -1, win.w + 2, win.h + 2);
  f.clearRect(0, 0, win.w, win.h);
  linear(f, { x: 0, y: 0, w: win.w, h: win.h }, 165, [[0, t.a], [1, t.b]]);
  linear(f, { x: 0, y: 0, w: win.w, h: headerH }, 172, [[0, t.r0], [0.72, t.r1], [1, t.r0]]);
  f.fillStyle = "rgb(255 236 214 / 0.2)";
  f.fillRect(0, 0, win.w, 1);
  f.fillStyle = t.a;
  for (let x = 0; x < win.w; x += 6) {
    f.fillRect(x + 3, headerH - 6, 3, 3);
    f.fillRect(x, headerH - 3, 3, 3);
  }
  return face;
}

/** The run in flight: a new run, or `cancelDither()`, stops it, and its promise never resolves. */
let stop: (() => void) | null = null;
export function cancelDither() {
  stop?.();
}

/**
 * Runs the dither. Opening: the promise resolves on the frame the cells form the whole window, and the
 * canvas is cleared on the next frame, so show the real window as soon as it resolves. Closing: hide the
 * real window and call it; `onLast` fires on the last painted step and it resolves with the canvas
 * cleared. A new run or `cancelDither()` supersedes a run in flight. Hidden (before or during), it
 * finishes at once.
 */
export function runDither(o: DitherOpts): Promise<void> {
  cancelDither();
  const { canvas } = o;
  const g = canvas.getContext("2d");
  const opening = o.mode === "open";
  if (o.reduce || !g || document.hidden) {
    if (!opening) o.onLast?.();
    return Promise.resolve();
  }
  const dpr = Math.min(devicePixelRatio || 1, 3);
  canvas.width = Math.round(innerWidth * dpr);
  canvas.height = Math.round(innerHeight * dpr);
  const { win } = o;
  const face = drawFace(win, o.headerH ?? 104, tokensOf(o.tokens), dpr);
  if (!face) return Promise.resolve(); // no offscreen context: the window just shows
  const snap = (v: number) => Math.round(v * dpr) / dpr;
  const area = { x: snap(win.x - PAD), y: snap(win.y - PAD), w: win.w + 2 * PAD, h: win.h + 2 * PAD };
  const cells = gridOf(area, o.chip, CELL);
  const total = opening ? OPEN_MS : CLOSE_MS;
  const slow = o.slow ?? 1;

  const paint = (p: number) => {
    g.setTransform(dpr, 0, 0, dpr, 0, 0);
    g.globalCompositeOperation = "source-over";
    g.clearRect(0, 0, innerWidth, innerHeight);
    if (p <= 0) return;
    g.imageSmoothingEnabled = false;
    g.fillStyle = "#000";
    g.beginPath();
    for (const c of cells) if (shown(c, p)) g.rect(c.x, c.y, CELL, CELL);
    g.fill();
    g.globalCompositeOperation = "source-in";
    g.drawImage(face, win.x - PAD, win.y - PAD, win.w + 2 * PAD, win.h + 2 * PAD);
    g.globalCompositeOperation = "source-over";
  };
  const clear = () => {
    g.setTransform(1, 0, 0, 1, 0, 0);
    g.clearRect(0, 0, canvas.width, canvas.height);
  };

  return new Promise((resolve) => {
    const t0 = performance.now();
    let raf = 0;
    let live = true;
    const end = () => {
      live = false;
      cancelAnimationFrame(raf);
      document.removeEventListener("visibilitychange", onHide);
      if (stop === cancel) stop = null;
    };
    const cancel = () => {
      end();
      clear();
    };
    const finish = () => {
      end();
      if (opening) {
        // The cells are the whole window this frame; the real one takes over, then the canvas goes.
        paint(1);
        resolve();
        requestAnimationFrame(clear);
      } else {
        o.onLast?.();
        clear();
        resolve();
      }
    };
    const onHide = () => document.hidden && finish();
    document.addEventListener("visibilitychange", onHide);
    stop = cancel;
    const step = (now: number) => {
      if (!live) return;
      const t = (now - t0) / slow;
      if (t >= total) return finish();
      const p = progressAt(t, opening);
      if (!opening && p <= 0) return finish();
      paint(p);
      raf = requestAnimationFrame(step);
    };
    paint(progressAt(0, opening));
    raf = requestAnimationFrame(step);
  });
}
