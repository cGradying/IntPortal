// Draws a built campus scene into a 192x80 canvas, upscaled by CSS with
// nearest-neighbour. WebGL2, then WebGL1, then Canvas 2D. One rAF loop at a
// stepped 12 fps that stops while the strip is off-screen or the app is quiet
// (quiet.ts); Reduce Motion draws one still frame a minute. Per frame the
// shader gets only the time and the hour.
import { animate } from "../quiet";
import type { Built } from "./paint";
import { JEEP_ROW, ROLE, ROWS } from "./paint";
import { SHADERS } from "./shader";
import { H, SKY, W, bayer, hazeFor, hex, mix, skyAt, type RGB } from "./sky";

export interface StripOptions {
  /** The class's window, or -1. */
  lit: number;
  /** A fixed hour for previews; null follows the clock. */
  hour: () => number | null;
  /** Keep the drawing buffer, so a still can be read back (the contact sheet). */
  keep?: boolean;
  /** Force a renderer (the contact sheet and tests); otherwise the best one available. */
  force?: "webgl2" | "webgl" | "2d";
}

export interface Strip {
  mode: "webgl2" | "webgl" | "2d";
  /** Swap the scene or the lit window; draws at once. */
  set(scene: Built, lit: number): void;
  /** Draw now (for stills). */
  draw(ms?: number): void;
  stop(): void;
}

// The clock's hour without a Date per frame. The Philippines has no daylight saving.
const offsetH = -new Date().getTimezoneOffset() / 60;
const clockHour = () => (((Date.now() / 3_600_000 + offsetH) % 24) + 24) % 24;

export function startStrip(cv: HTMLCanvasElement, scene: Built, o: StripOptions): Strip {
  cv.width = W;
  cv.height = H;
  const reduce = matchMedia("(prefers-reduced-motion: reduce)").matches;
  const haze = hazeFor(new Date().getMonth());
  const hourNow = () => o.hour() ?? clockHour();
  let lit = o.lit;
  let paint: (ms: number) => void;
  let swap: () => void;
  let mode: Strip["mode"];

  const gl = o.force === "2d" ? null : tryGl(cv, o);
  if (gl) {
    mode = gl.version === 2 ? "webgl2" : "webgl";
    let r: GlRenderer | null = initGl(gl.ctx, gl.version, scene, lit, haze);
    paint = (ms) => r?.draw(reduce ? 10 : ms / 1000, hourNow());
    swap = () => r?.upload(scene, lit);
    cv.addEventListener("webglcontextlost", (e) => {
      e.preventDefault();
      r = null;
      halt();
    });
    cv.addEventListener("webglcontextrestored", () => {
      r = initGl(gl.ctx, gl.version, scene, lit, haze);
      paint(performance.now());
      run();
    });
  } else {
    mode = "2d";
    const g = cv.getContext("2d")!;
    g.imageSmoothingEnabled = false;
    const d = draw2d(g, () => scene, () => lit);
    paint = (ms) => d(reduce ? 0 : ms, hourNow());
    swap = () => {};
  }

  // Twelve frames a second is the art's own rate.
  let last = 0;
  let loop: (() => void) | null = null;
  let seen = true;
  const tick = (ms: number) => {
    if (ms - last < 83) return;
    last = ms;
    paint(ms);
  };
  function run() {
    if (!reduce && seen && !loop) loop = animate(tick, () => cv);
  }
  function halt() {
    loop?.();
    loop = null;
  }
  const io = typeof IntersectionObserver === "function" ? new IntersectionObserver(([e]) => ((seen = e.isIntersecting) ? run() : halt())) : null;
  io?.observe(cv);
  const minute = setInterval(() => reduce && paint(performance.now()), 60_000);
  paint(performance.now());
  run();

  return {
    mode,
    set(next, n) {
      scene = next;
      lit = n;
      swap();
      paint(performance.now());
    },
    draw: (ms = performance.now()) => paint(ms),
    stop() {
      halt();
      io?.disconnect();
      clearInterval(minute);
    },
  };
}

type Gl = WebGL2RenderingContext | WebGLRenderingContext;

function tryGl(cv: HTMLCanvasElement, o: StripOptions): { ctx: Gl; version: 1 | 2 } | null {
  const attrs: WebGLContextAttributes = { alpha: false, antialias: false, depth: false, stencil: false, preserveDrawingBuffer: !!o.keep, powerPreference: "low-power" };
  try {
    if (o.force !== "webgl") {
      const g2 = cv.getContext("webgl2", attrs);
      if (g2) return { ctx: g2, version: 2 };
    }
    const g1 = cv.getContext("webgl", attrs);
    return g1 ? { ctx: g1, version: 1 } : null;
  } catch {
    return null;
  }
}

interface GlRenderer {
  draw(t: number, hour: number): void;
  upload(scene: Built, lit: number): void;
}

function initGl(gl: Gl, version: 1 | 2, scene: Built, lit: number, haze: number): GlRenderer | null {
  const src = SHADERS[version];
  const compile = (type: number, text: string) => {
    const s = gl.createShader(type)!;
    gl.shaderSource(s, text);
    gl.compileShader(s);
    return s;
  };
  const prog = gl.createProgram()!;
  const vs = compile(gl.VERTEX_SHADER, src.vert);
  const fs = compile(gl.FRAGMENT_SHADER, src.frag);
  gl.attachShader(prog, vs);
  gl.attachShader(prog, fs);
  gl.bindAttribLocation(prog, 0, "a_pos");
  gl.linkProgram(prog);
  if (!gl.getProgramParameter(prog, gl.LINK_STATUS)) {
    if (!gl.isContextLost()) console.error("campus shader:", gl.getShaderInfoLog(fs) || gl.getProgramInfoLog(prog));
    return null;
  }
  gl.useProgram(prog);
  gl.bindBuffer(gl.ARRAY_BUFFER, gl.createBuffer());
  gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 3, -1, -1, 3]), gl.STATIC_DRAW);
  gl.enableVertexAttribArray(0);
  gl.vertexAttribPointer(0, 2, gl.FLOAT, false, 0, 0);
  gl.viewport(0, 0, W, H);

  const texture = (unit: number) => {
    const t = gl.createTexture();
    gl.activeTexture(gl.TEXTURE0 + unit);
    gl.bindTexture(gl.TEXTURE_2D, t);
    for (const [k, v] of [[gl.TEXTURE_MIN_FILTER, gl.NEAREST], [gl.TEXTURE_MAG_FILTER, gl.NEAREST], [gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE], [gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE]]) gl.texParameteri(gl.TEXTURE_2D, k, v);
  };
  texture(0);
  texture(1);
  const u = (name: string) => gl.getUniformLocation(prog, name);
  gl.uniform1i(u("u_cells"), 0);
  gl.uniform1i(u("u_pal"), 1);
  gl.uniform1f(u("u_haze"), haze);
  gl.uniform1fv(u("u_skyH"), SKY.map((k) => k[0]));
  gl.uniform3fv(u("u_skyT"), SKY.flatMap((k) => hex(k[1]).map((v) => v / 255)));
  gl.uniform3fv(u("u_skyB"), SKY.flatMap((k) => hex(k[2]).map((v) => v / 255)));
  const uTime = u("u_time");
  const uHour = u("u_hour");
  const uLit = u("u_lit");
  const uRoad = u("u_road");

  function upload(s: Built, n: number) {
    gl.activeTexture(gl.TEXTURE0);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, W, ROWS, 0, gl.RGBA, gl.UNSIGNED_BYTE, s.cells);
    // Row 0: colour and how far night darkens it; row 1: how much the horizon tints it.
    const pal = new Uint8Array(256 * 2 * 4);
    s.colours.forEach((c, i) => {
      pal.set([c.rgb[0], c.rgb[1], c.rgb[2], Math.round(c.k * 255)], i * 4);
      pal.set([Math.round(c.far * 255), 0, 0, 255], (256 + i) * 4);
    });
    gl.activeTexture(gl.TEXTURE1);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, 256, 2, 0, gl.RGBA, gl.UNSIGNED_BYTE, pal);
    gl.uniform1f(uLit, n >= 0 ? n + 1 : 0);
    gl.uniform1f(uRoad, s.road);
  }
  upload(scene, lit);

  return {
    upload,
    draw(t, hour) {
      gl.uniform1f(uTime, t);
      gl.uniform1f(uHour, hour);
      gl.drawArrays(gl.TRIANGLES, 0, 3);
    },
  };
}

// The Canvas 2D fallback: today's strip code (dithered sky bands, stars, sun or
// moon, clouds) under the same scene cells, shaded per colour for the hour.
// No water shimmer, glow ring or haze.
function draw2d(g: CanvasRenderingContext2D, scene: () => Built, lit: () => number) {
  const css = (c: RGB) => `rgb(${c[0]},${c[1]},${c[2]})`;
  const NIGHT: RGB = [10, 12, 30];
  const sky = scratch(W, 66);
  const layer = scratch(W, H);
  let skyKey = "";
  let layerKey = "";
  let seed = 11;
  const rnd = () => (seed = (seed * 16807) % 2147483647) / 2147483647;
  const stars = Array.from({ length: 34 }, () => [Math.floor(rnd() * W), Math.floor(rnd() * 34), rnd()]);
  const clouds = [[20, 10, 16], [96, 16, 22], [150, 7, 14]];

  return (ms: number, h: number) => {
    const s = scene();
    const frame = Math.floor(ms / 83);
    const { top, bottom, light } = skyAt(h);
    const night = 1 - light;
    const R = (c: string | RGB, x: number, y: number, w: number, hh: number) => {
      g.fillStyle = typeof c === "string" ? c : css(c);
      g.fillRect(x, y, w, hh);
    };
    const key = h.toFixed(2);
    if (key !== skyKey) {
      skyKey = key;
      const img = sky.g.createImageData(W, 66);
      for (let y = 0; y < 66; y++)
        for (let x = 0; x < W; x++) {
          const b = Math.min(6, Math.max(0, Math.floor((y / 65) * 7 + bayer(x, y) - 0.5)));
          const c = mix(top, bottom, b / 6);
          img.data.set([c[0], c[1], c[2], 255], (y * W + x) * 4);
        }
      sky.g.putImageData(img, 0, 0);
    }
    g.fillStyle = css(bottom);
    g.fillRect(0, 0, W, H);
    g.drawImage(sky.c, 0, 0);
    if (night > 0.3) for (const [x, y, p] of stars) if ((frame + Math.floor(p * 40)) % 37 > 2) R(p > 0.8 ? "#fff3c4" : "#c9cde8", x, y, 1, 1);
    const arc = (t: number) => [Math.round(12 + t * (W - 24)), Math.round(40 - Math.sin(t * Math.PI) * 32)];
    if (h >= 5.8 && h <= 18.4) {
      const [sx, sy] = arc((h - 5.8) / 12.6);
      R("#fff1b8", sx - 2, sy - 1, 5, 3);
      R("#fff1b8", sx - 1, sy - 2, 3, 5);
      R("#ffd166", sx - 1, sy - 1, 3, 3);
    } else {
      const [mx, my] = arc(Math.min(1, Math.max(0, ((h < 12 ? h + 24 : h) - 18.4) / 11.4)));
      R("#f4efd9", mx - 2, my - 1, 4, 3);
      R("#f4efd9", mx - 1, my - 2, 2, 5);
      R(bottom, mx, my - 1, 2, 2);
    }
    if (light > 0.2)
      for (const [cx, cy, cw] of clouds) {
        const x = Math.round(((cx + ms / 900) % (W + 40)) - 20);
        g.globalAlpha = 0.85 * light;
        R("#ffffff", x + 2, cy, cw - 4, 2);
        R("#ffffff", x, cy + 2, cw, 2);
        R("#dfe8f2", x + 1, cy + 4, cw - 2, 1);
        g.globalAlpha = 1;
      }

    // The scene, re-shaded when the hour or the scene changes.
    const lk = `${s.id}:${key}`;
    if (lk !== layerKey) {
      layerKey = lk;
      const img = layer.g.createImageData(W, H);
      const lights = night > 0.4;
      for (let i = 0; i < W * H; i++) {
        const id = s.cells[i * 4];
        if (!id) continue;
        const role = s.cells[i * 4 + 1];
        const win = s.cells[i * 4 + 2];
        const col = s.colours[id];
        let c = mix(mix(col.rgb, bottom, col.far), NIGHT, night * col.k);
        if (lights && (role === ROLE.lamp || (role === ROLE.window && ((win * 7919) % 100) / 100 < 0.28))) c = [232, 196, 106];
        img.data.set([c[0], c[1], c[2], 255], i * 4);
      }
      layer.g.putImageData(img, 0, 0);
    }
    g.drawImage(layer.c, 0, 0);

    const n = lit();
    if (n >= 0)
      for (let i = 0; i < W * H; i++)
        if (s.cells[i * 4 + 2] === n + 1) R(frame % 16 < 12 ? "#ffd75e" : "#f2b233", i % W, Math.floor(i / W), 1, 1);

    const cycle = ms ? (ms / 16000) % 1 : -1;
    if (cycle >= 0 && cycle < 0.55) {
      const jx = Math.round(-20 + (cycle / 0.55) * (W + 40));
      const bob = frame % 4 < 2 ? 0 : 1;
      for (let y = 0; y < 7; y++)
        for (let x = 0; x < 18; x++) {
          const id = s.cells[((JEEP_ROW + y) * W + x) * 4];
          if (!id) continue;
          const col = s.colours[id];
          R(mix(col.rgb, NIGHT, night * col.k), jx + x, s.road + y - (y < 6 ? bob : 0), 1, 1);
        }
      if (night > 0.4) R("#fff1b8", jx + 18, s.road + 3, 3, 1);
    }
  };
}

/** A scratch canvas with its 2D context. */
function scratch(w: number, h: number) {
  const c = document.createElement("canvas");
  c.width = w;
  c.height = h;
  return { c, g: c.getContext("2d")! };
}
