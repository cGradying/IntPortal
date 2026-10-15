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
export const VOID = "#060607";

export const stageFor = (s: { busy: boolean; open: boolean }): Stage => (s.open ? "open" : s.busy ? "connecting" : "rest");

/** 60 fps while anything moves (the build, a swipe, the pulse, the opening wave); 30 at rest. */
export function fpsFor(t: number, stage: Stage, openedAt: number | null, moving = false): number {
  if (moving || t < FORM + 0.1 || stage === "connecting") return 60;
  if (stage === "open" && openedAt !== null && t - openedAt < 1.2) return 60;
  return 30;
}

export const hex = (rgb: number) => "#" + rgb.toString(16).padStart(6, "0");

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
  frame(t: number, prev: number, stage: number, openedAt: number, flags: number, pos: number): number;
  tiles(): number;
  events(): number;
  gap(): number;
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
}

export async function loadTiles(url = "/tiles.wasm") {
  const bytes = await (await fetch(url)).arrayBuffer();
  const x = (await WebAssembly.instantiate(bytes, {})).instance.exports as unknown as Exports;
  return {
    resize: (w: number, h: number) => x.resize(w, h),
    /** Device px between neighbouring portals in the last frame. */
    gap: () => x.gap(),
    portals(list: Portal[]) {
      // Allocate first: it can grow WASM memory, which detaches older views of it.
      const ptr = x.portals_buf(list.length);
      const buf = new Uint32Array(x.memory.buffer, ptr, list.length * STRIDE);
      list.forEach((p, i) => buf.set(packPortal(p), i * STRIDE));
      x.load();
    },
    /** Draw one frame; returns its haptic bits. */
    draw(ctx: CanvasRenderingContext2D, f: Frame): number {
      const n = x.frame(f.t, f.prev, STAGES[f.stage], f.openedAt, (f.returning ? 1 : 0) | (f.reduce ? 2 : 0), f.pos);
      const a = new Int32Array(x.memory.buffer, x.tiles(), n * 4);
      ctx.fillStyle = VOID;
      ctx.fillRect(0, 0, ctx.canvas.width, ctx.canvas.height);
      for (let i = 0; i < a.length; i += 4) {
        ctx.fillStyle = hex(a[i + 3]);
        ctx.fillRect(a[i], a[i + 1], a[i + 2], a[i + 2]);
      }
      return x.events();
    },
  };
}
