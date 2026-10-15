// The tile portal (spec 010): the scene is Rust (crates/intportal-tiles),
// built to static/tiles.wasm by scripts/tiles.sh. This file only loads it,
// hands it the canvas size and the portal's theme, and fills the tiles it
// returns. Sign-in never depends on it: if it fails to load, the form works.
import { FORM } from "./landing";

export type Stage = "rest" | "connecting" | "open";

const STAGES: Record<Stage, number> = { rest: 0, connecting: 1, open: 2 };
/** Haptic bits from the scene: the two sides of the frame meeting. */
export const TICK = 1;
/** The void behind the portal. */
export const VOID = "#060607";

export const stageFor = (s: { busy: boolean; open: boolean }): Stage => (s.open ? "open" : s.busy ? "connecting" : "rest");

/** 30 fps for the build, the pulse and the opening wave; 15 fps at rest. */
export function fpsFor(t: number, stage: Stage, openedAt: number | null): number {
  if (t < FORM + 0.1 || stage === "connecting") return 30;
  if (stage === "open" && openedAt !== null && t - openedAt < 1.2) return 30;
  return 15;
}

export const hex = (rgb: number) => "#" + rgb.toString(16).padStart(6, "0");

interface Exports {
  memory: WebAssembly.Memory;
  theme_buf(): number;
  resize(w: number, h: number): void;
  frame(t: number, prev: number, stage: number, openedAt: number, flags: number): number;
  tiles(): number;
  events(): number;
}

export interface Frame {
  t: number;
  prev: number;
  stage: Stage;
  openedAt: number;
  returning: boolean;
  reduce: boolean;
}

export async function loadTiles(url = "/tiles.wasm") {
  const bytes = await (await fetch(url)).arrayBuffer();
  const x = (await WebAssembly.instantiate(bytes, {})).instance.exports as unknown as Exports;
  return {
    resize: (w: number, h: number) => x.resize(w, h),
    theme(ramp: string[], accent: string) {
      const buf = new Uint32Array(x.memory.buffer, x.theme_buf(), 6);
      [...ramp.slice(0, 5), accent].forEach((c, i) => (buf[i] = parseInt(c.slice(1), 16)));
    },
    /** Draw one frame; returns its haptic bits. */
    draw(ctx: CanvasRenderingContext2D, f: Frame): number {
      const n = x.frame(f.t, f.prev, STAGES[f.stage], f.openedAt, (f.returning ? 1 : 0) | (f.reduce ? 2 : 0));
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
