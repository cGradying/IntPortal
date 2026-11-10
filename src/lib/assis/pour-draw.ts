// Draws the pour (spec 048 C1–C6) on one 2D canvas over the page. Each atom is a 2.5D pixel tile carrying
// its own slice of the window's face, drawn once offscreen in window coordinates, so the landed tiles
// are the window exactly and the real one can take over in one frame. Only the canvas changes per frame,
// and the chip's opacity and scale; nothing is laid out.
import { readTones } from "./crystal";
import { atomAt, chipAt, CLOSE_MS, closedAt, closeT, HAND_MS, OPEN_MS, pourPlan, type Plan, type Rect } from "./pour";

export interface PourOpts {
  /** A fixed, full-viewport canvas, above the window, `pointer-events: none`. */
  canvas: HTMLCanvasElement;
  /** In viewport points. */
  chip: Rect;
  win: Rect;
  /** The window's element: its `--r0`, `--r1`, `--g-a`, `--g-b`, `--g-rim` and `--g-ext` colour the tiles. */
  tokens: HTMLElement;
  mode: "open" | "close";
  /** The chip's element: it dips and fades out at the hand-off, and fades back in under the atoms closing. */
  chipEl?: HTMLElement;
  headerH?: number;
  /** 1 is real time; 4 for checking by eye. */
  slow?: number;
  /** Reduce Motion: no pour; resolves at once and the caller cross-fades. */
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

/** The window's face once, offscreen: the glass, the sky band over it, its lit top and its dithered edge. */
function drawFace(plan: Plan, t: ReturnType<typeof tokensOf>, dpr: number) {
  const { win, headerH } = plan;
  const face = document.createElement("canvas");
  face.width = Math.ceil(win.w * dpr);
  face.height = Math.ceil(win.h * dpr);
  const f = face.getContext("2d")!;
  f.setTransform(dpr, 0, 0, dpr, 0, 0);
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

/**
 * Runs the pour. Opening: call after `crystal.face(true)`; the promise resolves on the frame the tiles
 * form the whole window, and the canvas is cleared on the next frame, so show the real window as soon
 * as it resolves. The chip is left at inline `opacity: 0`: hide it (`crystal.hide(true)`) and clear that
 * before closing. Closing: hide the real window and call it; it resolves once the chip is back, its
 * inline styles cleared; then call `crystal.face(false)`.
 */
export function runPour(o: PourOpts): Promise<void> {
  const { canvas, chipEl } = o;
  const g = canvas.getContext("2d");
  if (o.reduce || !g) return Promise.resolve();
  const dpr = Math.min(devicePixelRatio || 1, 3);
  const [vw, vh] = [innerWidth, innerHeight];
  canvas.width = Math.round(vw * dpr);
  canvas.height = Math.round(vh * dpr);
  const plan = pourPlan(o.chip, o.win, o.headerH);
  const tok = tokensOf(o.tokens);
  const { faces, hair } = readTones();
  const tone = faces[2]; // the face it turned to show, as the WebGL cube draws it
  const face = drawFace(plan, tok, dpr);
  const { win } = plan;
  const opening = o.mode === "open";
  const total = opening ? OPEN_MS : CLOSE_MS;
  const slow = o.slow ?? 1;

  // 2.5D: a lit top and a shaded side, d points deep, up and to the right of the tile.
  function bevel(X: number, Y: number, w: number, h: number, d: number) {
    if (d <= 0.2) return;
    g!.fillStyle = tone;
    g!.beginPath();
    g!.moveTo(X, Y); g!.lineTo(X + d, Y - d); g!.lineTo(X + w + d, Y - d); g!.lineTo(X + w + d, Y + h - d); g!.lineTo(X + w, Y + h); g!.lineTo(X + w, Y);
    g!.fill();
    g!.fillStyle = "rgb(255 240 220 / 0.24)";
    g!.beginPath();
    g!.moveTo(X, Y); g!.lineTo(X + d, Y - d); g!.lineTo(X + w + d, Y - d); g!.lineTo(X + w, Y);
    g!.fill();
    g!.fillStyle = "rgb(0 0 0 / 0.36)";
    g!.beginPath();
    g!.moveTo(X + w, Y); g!.lineTo(X + w + d, Y - d); g!.lineTo(X + w + d, Y + h - d); g!.lineTo(X + w, Y + h);
    g!.fill();
  }
  // The gold rim and the 2 pt extrusion, k of the way in: a ring, so the page shows through inside.
  function ring(k: number) {
    if (k <= 0) return;
    g!.globalAlpha = k;
    g!.fillStyle = tok.ext;
    g!.fillRect(win.x + 1, win.y + 1, win.w + 2, win.h + 2);
    g!.fillStyle = tok.rim;
    g!.fillRect(win.x - 1, win.y - 1, win.w + 2, win.h + 2);
    g!.globalAlpha = 1;
    g!.clearRect(win.x, win.y, win.w, win.h);
  }

  /** The pour at `t` ms of the opening's own time. */
  function pose(t: number) {
    g!.setTransform(dpr, 0, 0, dpr, 0, 0);
    g!.clearRect(0, 0, vw, vh);
    if (chipEl) {
      const c = chipAt(t, opening);
      chipEl.style.opacity = String(c.opacity);
      chipEl.style.scale = String(c.scale);
    }
    if (t < HAND_MS) return;
    const k = closedAt(t);
    ring(k);
    if (k >= 1) return void g!.drawImage(face, win.x, win.y, win.w, win.h);
    for (let i = 0; i < 27; i++) {
      const p = atomAt(plan, i, t);
      bevel(p.x, p.y, p.w, p.h, p.depth);
      g!.fillStyle = tone;
      g!.fillRect(p.x, p.y, p.w, p.h);
      // Its slice of the window's face comes up as it flies; the cube's hairline goes.
      const f = Math.min(1, Math.max(0, (p.u - 0.1) / 0.7));
      const show = f * f * (3 - 2 * f);
      if (show > 0) {
        const c = p.cell;
        g!.globalAlpha = show;
        g!.drawImage(face, (c.x - win.x) * dpr, (c.y - win.y) * dpr, c.w * dpr, c.h * dpr, p.x, p.y, p.w, p.h);
        g!.globalAlpha = 1;
      }
      if (p.u < 1) {
        g!.globalAlpha = 1 - p.u;
        g!.strokeStyle = hair;
        g!.lineWidth = 1;
        g!.strokeRect(p.x + 0.5, p.y + 0.5, p.w - 1, p.h - 1);
        g!.globalAlpha = 1;
      }
    }
  }

  const clear = () => {
    g.setTransform(1, 0, 0, 1, 0, 0);
    g.clearRect(0, 0, canvas.width, canvas.height);
  };
  const done = () => {
    if (chipEl) chipEl.style.opacity = chipEl.style.scale = "";
  };

  return new Promise((resolve) => {
    const t0 = performance.now();
    const step = (now: number) => {
      const t = (now - t0) / slow;
      if (t >= total) {
        if (opening) {
          // The tiles are the whole window this frame; the real one takes over, then the canvas goes.
          pose(OPEN_MS);
          if (chipEl) chipEl.style.scale = "";
          resolve();
          requestAnimationFrame(clear);
        } else {
          clear();
          done();
          resolve();
        }
        return;
      }
      pose(opening ? t : closeT(t));
      requestAnimationFrame(step);
    };
    pose(opening ? 0 : OPEN_MS);
    requestAnimationFrame(step);
  });
}
