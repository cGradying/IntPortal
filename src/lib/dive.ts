// The dive (spec 010 C26–C30). The scene is Rust (crates/intportal-tiles/src/dive.rs);
// this loads it, hands it the room's colours and draws what it returns.
import type { Portal } from "./api";
import { packPortal } from "./tiles";
import type { Theme } from "./lar/sprite";

/** Today's dot grid, in CSS px (app.css `.dots`). */
export const DOT_PITCH = 14;
/** A launch enters Today by now, with whatever is cached (C26). */
export const DIVE_WAIT_MS = 3000;
const STRIDE = 10;

/** Where a first sign-in's dive starts, in device px of the screen. */
export interface Standing {
  ox: number;
  oy: number;
  pitch: number;
  tile: number;
  lar: { x: number; y: number } | null;
}

export interface DiveStart {
  first: boolean;
  portal: Portal;
  /** A first sign-in's portal and LAR, where the landing has them. */
  from?: Standing;
}

export const themeOf = (p: Portal): Theme => ({ ramp: p.theme.ramp, accent: p.theme.accent });

/** A CSS colour as 0xRRGGBB, from `#rgb`, `#rrggbb` or `rgb()`/`rgba()`; alpha is dropped. */
export function rgbOf(css: string, fallback = 0): number {
  const s = css.trim();
  const short = /^#([0-9a-f])([0-9a-f])([0-9a-f])$/i.exec(s);
  if (short) return parseInt(short[1] + short[1] + short[2] + short[2] + short[3] + short[3], 16);
  if (/^#[0-9a-f]{6}/i.test(s)) return parseInt(s.slice(1, 7), 16);
  const fn = /^rgba?\(\s*(\d+)[\s,]+(\d+)[\s,]+(\d+)/i.exec(s);
  return fn ? (+fn[1] << 16) | (+fn[2] << 8) | +fn[3] : fallback;
}

/** `rgba()` for a packed 0xRRGGBBAA, cached: a frame only has a handful of colours. */
const styles = new Map<number, string>();
export function styleOf(rgba: number): string {
  let s = styles.get(rgba);
  if (s === undefined) {
    if (styles.size > 2048) styles.clear();
    s = `rgba(${(rgba >>> 24) & 255},${(rgba >>> 16) & 255},${(rgba >>> 8) & 255},${((rgba & 255) / 255).toFixed(3)})`;
    styles.set(rgba, s);
  }
  return s;
}
const hexOf = (rgb: number) => "#" + rgb.toString(16).padStart(6, "0");

interface Exports {
  memory: WebAssembly.Memory;
  portals_buf(n: number): number;
  dive_start(w: number, h: number, q: number, voidRgb: number, ground: number, dot: number, seed: number, ox: number, oy: number, pitch: number, tile: number, larX: number, larY: number, dpr: number): void;
  dive_frame(t: number, readyAt: number): number;
  dive_tiles(): number;
  dive_pools(): number;
  dive_info(): number;
  dive_arrive(readyAt: number): number;
}

export interface DiveInfo {
  lar: { x: number; y: number; scale: number; alpha: number };
  done: boolean;
}

export async function loadDive(url = "/tiles.wasm") {
  const bytes = await (await fetch(url)).arrayBuffer();
  const x = (await WebAssembly.instantiate(bytes, {})).instance.exports as unknown as Exports;
  return {
    start(s: DiveStart, w: number, h: number, dpr: number) {
      const vars = getComputedStyle(document.documentElement);
      const color = (name: string, fallback: number) => rgbOf(vars.getPropertyValue(name), fallback);
      const ptr = x.portals_buf(1);
      new Uint32Array(x.memory.buffer, ptr, STRIDE).set(packPortal(s.portal));
      const f = s.from;
      // Each dive takes its own order of forms (C29a). A phone whose scale isn't whole rounds the
      // dot pitch, so its tiles drift off Today's dots by a few px: they lift too fast to see it.
      x.dive_start(w, h, Math.round(DOT_PITCH * dpr), f ? 0x060607 : color("--void", 0x0b0710), color("--ground", 0x19191c), color("--dot", 0xf5b227), Math.floor(Date.now() / 1000) >>> 0, f?.ox ?? 0, f?.oy ?? 0, f?.pitch ?? 0, f?.tile ?? 0, f?.lar?.x ?? w / 2, f?.lar?.y ?? h, dpr);
    },
    /** When the field starts landing. `readyAt` < 0: data isn't ready yet. */
    arrive: (readyAt: number) => x.dive_arrive(readyAt),
    /** Draw the frame at `t`. `readyAt` < 0: data isn't ready yet. */
    draw(ctx: CanvasRenderingContext2D, t: number, readyAt: number): DiveInfo {
      const n = x.dive_frame(t, readyAt);
      // Read after the call: it can grow WASM memory, which detaches older views.
      const i = new Float32Array(x.memory.buffer, x.dive_info(), 12);
      const { width, height } = ctx.canvas;
      ctx.clearRect(0, 0, width, height);
      if (i[5] >= 0) {
        ctx.fillStyle = hexOf(i[5]);
        ctx.fillRect(0, 0, width, height);
      }
      const pools = new Int32Array(x.memory.buffer, x.dive_pools(), i[11] * 4);
      for (let k = 0; k < pools.length; k += 4) {
        const [px, py, r, c] = [pools[k], pools[k + 1], pools[k + 2], pools[k + 3]];
        const g = ctx.createRadialGradient(px, py, 0, px, py, r);
        g.addColorStop(0, styleOf(c));
        g.addColorStop(1, styleOf(c & ~255));
        ctx.fillStyle = g;
        ctx.fillRect(0, 0, width, height);
      }
      if (i[10] >= 0) {
        ctx.fillStyle = hexOf(i[10]);
        ctx.fillRect(i[6], i[7], i[8], i[9]);
      }
      const a = new Int32Array(x.memory.buffer, x.dive_tiles(), n * 4);
      for (let k = 0; k < a.length; k += 4) {
        ctx.fillStyle = styleOf(a[k + 3]);
        ctx.fillRect(a[k], a[k + 1], a[k + 2], a[k + 2]);
      }
      return { lar: { x: i[0], y: i[1], scale: i[2], alpha: i[3] }, done: i[4] === 1 };
    },
  };
}
