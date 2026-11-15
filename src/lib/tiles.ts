// The tile portal (spec 010): the scene is Rust (crates/intportal-tiles),
// built to static/tiles.wasm by scripts/tiles.sh. This file only loads it,
// hands it the canvas size and every portal's look, and fills the tiles it
// returns. Sign-in never depends on it: if it fails to load, the form works.
import type { Portal } from "./api";
import { FORM } from "./landing";

export type Stage = "rest" | "connecting" | "open";

const STAGES: Record<Stage, number> = { rest: 0, connecting: 1, open: 2 };
// Order matches Corner::from_u32 and Motif::from_u32 in scene.rs.
const CORNERS: Portal["shape"]["corner"][] = ["square", "cut", "arch"];
const MOTIFS: Portal["motif"][] = ["swirl", "ripple", "bloom", "rain", "lattice", "aurora"];
/** u32s per portal: cols, rows, corner, motif, five ramp tones, accent (lib.rs STRIDE). */
const STRIDE = 10;
/** Haptic bits from the scene: the two sides of the frame meeting. */
export const TICK = 1;
/** The void behind the portal. */
export const VOID = "#0b0710";

export const stageFor = (s: { busy: boolean; open: boolean }): Stage => (s.open ? "open" : s.busy ? "connecting" : "rest");

/** 60 fps while anything moves (the build, a swipe, the pulse, the opening wave); 30 at rest. */
export function fpsFor(t: number, stage: Stage, openedAt: number | null, moving = false): number {
  if (moving || t < FORM + 0.1 || stage === "connecting") return 60;
  if (stage === "open" && openedAt !== null && t - openedAt < 1.2) return 60;
  return 30;
}

/** A packed tile colour, `0xAARRGGBB` with 0 in the top byte for opaque, as a CSS colour. */
export const hex = (v: number) => {
  const a = v >>> 24;
  const rgb = "#" + (v & 0xffffff).toString(16).padStart(6, "0");
  return a ? rgb + a.toString(16).padStart(2, "0") : rgb;
};

/** One portal as the scene reads it. */
export function packPortal(p: Portal): number[] {
  const rgb = (c: string) => parseInt(c.slice(1), 16);
  return [p.shape.cols, p.shape.rows, Math.max(0, CORNERS.indexOf(p.shape.corner)), Math.max(0, MOTIFS.indexOf(p.motif)), ...p.theme.ramp.slice(0, 5).map(rgb), rgb(p.theme.accent)];
}

interface Exports {
  memory: WebAssembly.Memory;
  portals_buf(n: number): number;
  load(): void;
  resize(w: number, h: number): void;
  frame(t: number, prev: number, stage: number, openedAt: number, flags: number, pos: number, vel: number): number;
  tiles(): number;
  events(): number;
  gap(): number;
  portal_rect(pos: number, p: number): number;
  metrics(): number;
  ground_grid(p: number): number;
  poke(c: number, r: number, t: number): void;
}

export interface Frame {
  t: number;
  prev: number;
  stage: Stage;
  openedAt: number;
  returning: boolean;
  reduce: boolean;
  /** The carousel's fractional portal index. */
  pos: number;
  /** The carousel's speed in portals per second, signed. */
  vel: number;
}

export async function loadTiles(url = "/tiles.wasm") {
  // Compiles while the bytes arrive; a server without the wasm MIME type gets the buffered path.
  const made = await WebAssembly.instantiateStreaming(fetch(url), {}).catch(async () => WebAssembly.instantiate(await (await fetch(url)).arrayBuffer(), {}));
  const x = made.instance.exports as unknown as Exports;
  return {
    resize: (w: number, h: number) => x.resize(w, h),
    /** A touch on the selected portal at tile `c`, `r` of its grid, at `t` on the landing's clock (C36). */
    poke: (c: number, r: number, t: number) => x.poke(c, r, t),
    /** The front portal's tile pitch and tile side, in device px. */
    metrics() {
      const m = x.metrics();
      return { pitch: m >>> 16, tile: m & 0xffff };
    },
    /** The ground's grid for portal `p`, in device px: where a dot's cell starts, the pitch and an unlit dot's side. */
    grid(p: number) {
      const g = new Int32Array(x.memory.buffer, x.ground_grid(p), 4);
      return { x: g[0], y: g[1], pitch: g[2], dot: g[3] };
    },
    /** Device px between neighbouring portals in the last frame. */
    gap: () => x.gap(),
    /** Portal `p`'s frame box in device px, [x, y, w, h], at carousel position `pos` (default: the selected one). */
    rect(pos: number, p = Math.round(pos)): [number, number, number, number] {
      const ptr = x.portal_rect(pos, p);
      const r = new Int32Array(x.memory.buffer, ptr, 4);
      return [r[0], r[1], r[2], r[3]];
    },
    portals(list: Portal[]) {
      // Allocate first: it can grow WASM memory, which detaches older views of it.
      const ptr = x.portals_buf(list.length);
      const buf = new Uint32Array(x.memory.buffer, ptr, list.length * STRIDE);
      list.forEach((p, i) => buf.set(packPortal(p), i * STRIDE));
      x.load();
    },
    /** Draw one frame; returns its haptic bits. */
    draw(ctx: CanvasRenderingContext2D, f: Frame): number {
      const n = x.frame(f.t, f.prev, STAGES[f.stage], f.openedAt, (f.returning ? 1 : 0) | (f.reduce ? 2 : 0), f.pos, f.vel);
      const a = new Int32Array(x.memory.buffer, x.tiles(), n * 4);
      // No fill: the page's ground and its grid of dots show through, so the portal stands on them.
      ctx.clearRect(0, 0, ctx.canvas.width, ctx.canvas.height);
      for (let i = 0; i < a.length; i += 4) {
        ctx.fillStyle = hex(a[i + 3]);
        ctx.fillRect(a[i], a[i + 1], a[i + 2], a[i + 2]);
      }
      return x.events();
    },
  };
}
