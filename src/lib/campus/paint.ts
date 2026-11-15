// A scene is a palette and a few drawing calls. `build` rasterises it once,
// when the scene loads, into an indexed-colour cell grid (192x80, plus the
// jeepney sprite in the rows below) that the shader and the 2D fallback both
// read. Nothing here runs per frame.
import { JEEP, JEEP_COLORS } from "../sprites";
import { H, W } from "./sky";

/** A flat colour; `k` is how far night darkens it (0 = a light), `far` how much the horizon tints it. */
export type Paint = string | { c: string; k?: number; far?: number };

export interface Painter {
  rect(c: string, x: number, y: number, w: number, h: number): void;
  /** A filled polygon, as x, y pairs. */
  poly(c: string, pts: number[]): void;
  /** Water: shimmers and reflects the sky. */
  water(c: string, x: number, y: number, w: number, h: number): void;
  /** A grid of windows; each can be the class's lit window, and some light up at night. */
  windows(c: string, x: number, y: number, cols: number, rows: number, dx: number, dy: number, w: number, h: number): void;
  /** Lit at night (a street lamp, a far window). */
  lamp(c: string, x: number, y: number, w: number, h: number): void;
  /** The 3x5 pixel font, upper case. Returns the width drawn. */
  text(c: string, x: number, y: number, s: string): number;
}

export interface SceneDef {
  id: string;
  /** What the hero's label says: "PUP Sta. Mesa at this hour". */
  label: string;
  palette: Record<string, Paint>;
  /** Top row of the jeepney's lane. */
  road: number;
  draw(p: Painter): void;
}

export const ROLE = { solid: 0, water: 1, window: 2, lamp: 3 } as const;
/** Cell rows: the scene, then the jeepney sprite. */
export const ROWS = H + 8;
export const JEEP_ROW = H;

export interface Colour {
  rgb: [number, number, number];
  k: number;
  far: number;
}

export interface Built {
  id: string;
  label: string;
  road: number;
  /** RGBA per cell: palette index (0 = sky), role, window number + 1, 255. */
  cells: Uint8Array;
  /** Index 0 is the sky. */
  colours: Colour[];
  windows: number;
  /** Anything drawn outside the frame or in a colour the palette lacks. Empty for a good scene. */
  errors: string[];
}

const GLYPHS: Record<string, string> = {
  A: "010101111101101", B: "110101110101110", C: "011100100100011", D: "110101101101110", E: "111100110100111",
  F: "111100110100100", G: "011100101101011", H: "101101111101101", I: "111010010010111", J: "001001001101010",
  K: "101101110101101", L: "100100100100111", M: "101111111101101", N: "110101101101101",
  O: "010101101101010", P: "110101110100100", Q: "010101101110011", R: "110101110101101", S: "011100010001110",
  T: "111010010010010", U: "101101101101111", V: "101101101101010", W: "101101111111101", X: "101101010101101",
  Y: "101101010010010", Z: "111001010100111", ".": "000000000000010", "-": "000000111000000", " ": "000000000000000",
  "0": "111101101101111", "1": "010110010010111", "2": "110001010100111", "3": "110001010001110", "4": "101101111001001",
  "5": "111100110001110", "6": "011100111101111", "7": "111001010010010", "8": "111101111101111", "9": "111101111001110",
};

/** Width of `s` in the pixel font, gaps included. */
export const textWidth = (s: string) => Math.max(0, s.length * 4 - 1);

const toRgb = (h: string): [number, number, number] => [1, 3, 5].map((i) => parseInt(h.slice(i, i + 2), 16)) as [number, number, number];
const JEEP_PAINT: Record<string, Paint> = Object.fromEntries(Object.entries(JEEP_COLORS).map(([k, c]) => [`jeep.${k}`, { c, k: k === "k" ? 0 : 0.35 }]));

export function build(def: SceneDef): Built {
  const errors: string[] = [];
  const names = new Map<string, number>();
  const colours: Colour[] = [{ rgb: [0, 0, 0], k: 0, far: 0 }];
  for (const [name, p] of Object.entries({ ...def.palette, ...JEEP_PAINT })) {
    const v = typeof p === "string" ? { c: p } : p;
    if (!/^#[0-9a-f]{6}$/i.test(v.c)) errors.push(`${name}: ${v.c} is not #rrggbb`);
    names.set(name, colours.length);
    colours.push({ rgb: toRgb(v.c), k: v.k ?? 0.6, far: v.far ?? 0 });
  }
  if (colours.length > 256) errors.push(`${colours.length} colours; at most 255`);
  const cells = new Uint8Array(W * ROWS * 4);
  for (let i = 3; i < cells.length; i += 4) cells[i] = 255;
  let windows = 0;

  const index = (c: string) => {
    const i = names.get(c);
    if (i === undefined) errors.push(`${c} is not in the palette`);
    return i ?? 0;
  };
  const inside = (what: string, x: number, y: number, w: number, h: number) => {
    const ok = x >= 0 && y >= 0 && x + w <= W && y + h <= H && w > 0 && h > 0;
    if (!ok) errors.push(`${what} ${x},${y} ${w}x${h} leaves the frame`);
    return ok;
  };
  const put = (x: number, y: number, i: number, role: number, win = 0) => {
    const o = (y * W + x) * 4;
    cells[o] = i;
    cells[o + 1] = role;
    cells[o + 2] = win;
  };
  const fill = (c: string, x: number, y: number, w: number, h: number, role: number, what: string, win = 0) => {
    const i = index(c);
    if (!inside(what, x, y, w, h)) return;
    for (let yy = y; yy < y + h; yy++) for (let xx = x; xx < x + w; xx++) put(xx, yy, i, role, win);
  };

  const p: Painter = {
    rect: (c, x, y, w, h) => fill(c, x, y, w, h, ROLE.solid, "rect"),
    water: (c, x, y, w, h) => fill(c, x, y, w, h, ROLE.water, "water"),
    lamp: (c, x, y, w, h) => fill(c, x, y, w, h, ROLE.lamp, "lamp"),
    windows(c, x, y, cols, rows, dx, dy, w, h) {
      for (let r = 0; r < rows; r++)
        for (let k = 0; k < cols; k++) {
          windows++;
          if (windows > 255) errors.push("more than 255 windows");
          fill(c, x + k * dx, y + r * dy, w, h, ROLE.window, "window", Math.min(255, windows));
        }
    },
    poly(c, pts) {
      const i = index(c);
      const xs = pts.filter((_, n) => n % 2 === 0);
      const ys = pts.filter((_, n) => n % 2 === 1);
      const x0 = Math.floor(Math.min(...xs)), x1 = Math.ceil(Math.max(...xs));
      const y0 = Math.floor(Math.min(...ys)), y1 = Math.ceil(Math.max(...ys));
      if (!inside("poly", x0, y0, x1 - x0, y1 - y0)) return;
      for (let y = y0; y < y1; y++)
        for (let x = x0; x < x1; x++) {
          // Even-odd test at the pixel's centre.
          let hit = false;
          for (let a = 0, b = xs.length - 1; a < xs.length; b = a++) {
            const cy = y + 0.5;
            if (ys[a] > cy !== ys[b] > cy && x + 0.5 < ((xs[b] - xs[a]) * (cy - ys[a])) / (ys[b] - ys[a]) + xs[a]) hit = !hit;
          }
          if (hit) put(x, y, i, ROLE.solid);
        }
    },
    text(c, x, y, s) {
      const i = index(c);
      const str = s.toUpperCase();
      if (!inside("text", x, str.includes("Ñ") ? y - 2 : y, textWidth(str), str.includes("Ñ") ? 7 : 5)) return 0;
      [...str].forEach((ch, n) => {
        // Ñ is an N with its tilde riding above the line.
        if (ch === "Ñ") for (const [dx, dy] of [[0, -1], [1, -2], [2, -1]]) put(x + n * 4 + dx, y + dy, i, ROLE.solid);
        const g = GLYPHS[ch === "Ñ" ? "N" : ch];
        if (!g) return void errors.push(`no glyph for ${ch}`);
        for (let b = 0; b < 15; b++) if (g[b] === "1") put(x + n * 4 + (b % 3), y + Math.floor(b / 3), i, ROLE.solid);
      });
      return textWidth(str);
    },
  };

  def.draw(p);
  JEEP.forEach((row, y) => [...row].forEach((ch, x) => ch !== "." && put(x, JEEP_ROW + y, names.get(`jeep.${ch}`)!, ROLE.solid)));
  if (def.road < 0 || def.road + 7 > H) errors.push(`road ${def.road} leaves no room for the jeepney`);
  return { id: def.id, label: def.label, road: def.road, cells, colours, windows, errors };
}
