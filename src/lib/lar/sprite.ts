// LAR, the Lakbay-Aral Robot: a pocket-size robot from the portal's other
// side. Ported from the film rig (intportal-films/assets/isko/isko.js, where
// he was drafted as "Isko 3.0"). An obsidian pebble with stepped block ears,
// a dark visor with gold eyes, a belly window showing the live swirl, a
// gold spark antenna, two floating mitts and a tiny orbiting portal cube.
// Outlined, four-tone, ordered dither between tones. Pure grids here, plus
// tint() (a portal's colours), pose() (every part's offset for a state),
// extents() (where the parts land) and drawLar(), the one renderer that
// Lar.svelte, the landing's flight and the sheet all draw him with.
export const LAR_PAL = {
  o: "#1a0f20",
  d: "#2c1c3a",
  k: "#43295a",
  b: "#5f3f7e",
  B: "#8663a8",
  L: "#b996d8",
  v: "#140b1b",
  V: "#2d1d3c",
  g: "#f5b227",
  G: "#b87a10",
  w: "#fff6dc",
  p: "#ff7a9c",
  r: "#7a1128",
  s: "#24162e",
  e: "#5d3f78",
  m: "#e27bd0",
  c: "#c2403a",
  // The portal's own pixels: belly and ear studs (lit, shade) and the alert red.
  t: "#f5b227",
  T: "#b87a10",
  x: "#ff5a4a",
  // The spawn fire, coolest to hottest under the white core (the portal's ramp).
  "1": "#7a1c2c",
  "2": "#b5412a",
  "3": "#e08a35",
  "4": "#f3cf6a",
} as const;
export type Key = keyof typeof LAR_PAL;
export type Palette = Record<Key, string>;
export type Grid = (Key | null)[][];

export const MOODS = ["open", "blink", "happy", "wow", "wink", "focus", "sleep"] as const;
export type Mood = (typeof MOODS)[number];

export const W = 26;
export const H = 23;
/** The visor, where every face is drawn. */
export const VISOR = { x0: 5, x1: W - 6, y0: 6, y1: 13 } as const;

const BAYER = [
  [0, 8, 2, 10],
  [12, 4, 14, 6],
  [3, 11, 1, 9],
  [15, 7, 13, 5],
];
const clamp = (v: number, a = 0, b = 1) => Math.min(b, Math.max(a, v));
const grid = (w: number, h: number): Grid => Array.from({ length: h }, () => Array<Key | null>(w).fill(null));

function outline(g: Grid): Grid {
  const out = g.map((r) => r.slice());
  for (let j = 0; j < g.length; j++)
    for (let i = 0; i < g[0].length; i++) {
      if (g[j][i]) continue;
      const near = [[1, 0], [-1, 0], [0, 1], [0, -1]].some(([a, b]) => {
        const k = g[j + b]?.[i + a];
        return k && k !== "o";
      });
      if (near) out[j][i] = "o";
    }
  return out;
}

/** The pebble body, lit from the top left, with ears, visor and belly window. */
export function bodyGrid(): Grid {
  const g = grid(W, H);
  const cx = W / 2 - 0.5;
  const cy = 12.2;
  const rx = 10.6;
  const ry = 9.8;
  const tones: Key[] = ["d", "k", "b", "B", "L"];
  for (let j = 0; j < H; j++)
    for (let i = 0; i < W; i++) {
      const nx = (i - cx) / rx;
      const ny = (j - cy) / (j > cy ? ry * 0.92 : ry);
      if (Math.abs(nx) ** 2.4 + Math.abs(ny) ** 2.2 > 1) continue;
      const nz = Math.sqrt(Math.max(0, 1 - Math.min(1, nx * nx + ny * ny)));
      let l = clamp(0.5 + (-nx * 0.55 - ny * 0.65 + nz * 0.55) * 0.62);
      l = l * 4 + (BAYER[j % 4][i % 4] / 16 - 0.5) * 0.55;
      g[j][i] = tones[clamp(Math.round(l), 0, 4)];
    }
  // Stepped block ears: the portal frame's own corner blocks.
  const ear = (x0: number, dir: number) => {
    for (let s = 0; s < 3; s++) for (let w = 0; w < 3 - s; w++) g[3 - s][x0 + dir * w] = s === 2 ? "B" : "b";
  };
  ear(5, 1);
  ear(W - 6, -1);
  g[1][5] = "t";
  g[1][W - 6] = "t";
  for (let j = VISOR.y0; j <= VISOR.y1; j++)
    for (let i = VISOR.x0; i <= VISOR.x1; i++) {
      const corner = (j === VISOR.y0 || j === VISOR.y1) && (i === VISOR.x0 || i === VISOR.x1);
      if (corner) continue;
      const rim = j === VISOR.y0 || j === VISOR.y1 || i === VISOR.x0 || i === VISOR.x1;
      g[j][i] = rim ? "V" : "v";
    }
  g[7][7] = "V";
  g[7][8] = "V";
  // Belly window: a tiny pixel portal; the swirl inside is drawn live.
  const bx0 = W / 2 - 4;
  const by0 = 14;
  for (let j = 0; j < 7; j++)
    for (let i = 0; i < 8; i++) {
      const corner = (j === 0 || j === 6) && (i === 0 || i === 7);
      if (corner) continue;
      g[by0 + j][bx0 + i] = j === 0 || j === 6 || i === 0 || i === 7 ? "s" : "v";
    }
  g[by0][bx0 + 1] = "t";
  g[by0][bx0 + 6] = "t";
  g[by0 + 6][bx0 + 1] = "T";
  g[by0 + 6][bx0 + 6] = "T";
  // Magenta rim light on the right edge, so he reads on dark scenes.
  for (let j = 0; j < H; j++)
    for (let i = W - 1; i > 0; i--) {
      const k = g[j][i];
      if (k && k !== "o") {
        if (j > 4 && j < 19 && !"vVsgGtT".includes(k)) g[j][i] = "m";
        break;
      }
    }
  return outline(g);
}

/** Eyes, blush and mouth for one mood, drawn over the visor. */
export function faceGrid(mood: Mood): Grid {
  const g = grid(W, H);
  const L = 9;
  const R = W - 11;
  const y = 8;
  const put = (i: number, j: number, k: Key) => (g[j][i] = k);
  const open = (x: number) => {
    for (let j = 0; j < 4; j++) for (let i = 0; i < 2; i++) put(x + i, y + j, "g");
    put(x, y, "w");
    put(x + 1, y + 3, "G");
  };
  const closed = (x: number) => [-1, 0, 1, 2].forEach((d) => put(x + d, y + 2, "g"));
  const happy = (x: number) => {
    put(x - 1, y + 2, "g");
    put(x, y + 1, "g");
    put(x + 1, y + 1, "g");
    put(x + 2, y + 2, "g");
  };
  const wow = (x: number) => {
    for (let j = 0; j < 4; j++)
      for (let i = -1; i < 3; i++) {
        const edge = j === 0 || j === 3 || i === -1 || i === 2;
        const corner = (j === 0 || j === 3) && (i === -1 || i === 2);
        if (edge && !corner) put(x + i, y + j, "g");
      }
    put(x, y + 1, "w");
  };
  const focus = (x: number, side: number) => {
    put(x - 1, y + 1, "g");
    for (let i = 0; i < 3; i++) put(x + i - (side < 0 ? 1 : 0), y + 2, "g");
    put(x, y + 3, "G");
    put(x + 1, y + 3, "G");
  };
  // Eyes shut and drooping, like two little bowls.
  const shut = (x: number) => {
    put(x - 1, y + 2, "G");
    put(x, y + 3, "g");
    put(x + 1, y + 3, "g");
    put(x + 2, y + 2, "G");
  };
  const eyes: Record<Mood, [(x: number) => void, (x: number) => void]> = {
    open: [open, open],
    blink: [closed, closed],
    happy: [happy, happy],
    wow: [wow, wow],
    wink: [open, happy],
    focus: [(x) => focus(x, 1), (x) => focus(x, -1)],
    sleep: [shut, shut],
  };
  eyes[mood][0](L);
  eyes[mood][1](R);
  if (mood !== "focus") {
    put(L - 2, y + 4, "p");
    put(L - 1, y + 4, "p");
    put(R + 2, y + 4, "p");
    put(R + 3, y + 4, "p");
  }
  if (mood === "sleep") {
    put(W / 2 - 1, y + 4, "r");
    put(W / 2, y + 4, "r");
  } else if (mood === "wow") {
    put(W / 2 - 1, y + 4, "g");
    put(W / 2, y + 4, "g");
  } else if (mood === "happy" || mood === "wink") {
    put(W / 2 - 2, y + 4, "g");
    put(W / 2 + 1, y + 4, "g");
    put(W / 2 - 1, y + 5, "g");
    put(W / 2, y + 5, "g");
  }
  return g;
}

export const MITT = ["..ooo..", ".oBLBo.", "oBLBbbo", "obBbbko", "obbbkko", ".okkko.", "..ooo.."];
export const THUMB = ["..oo...", ".oLBo..", ".oBbo..", "oBLBbbo", "obBbbko", "obbbkko", ".ooooo."];
export const ANTENNA = ["...g...", "..gwg..", ".ggwgg.", "..gwg..", "...g...", "..oBo..", "..obo..", "..oko..", ".okkko."];
export const CUBE = ["...o...", "..oto..", ".otwto.", "otwctTo", ".otcTo.", "..oTo..", "...o..."];
/** Speed dashes behind a flying mitt; the right edge touches the mitt. */
export const STREAK = ["...kbB", ".dkkbB", "...kbB"];
/** The sleeper's z, three sizes. */
export const ZZZ = [
  ["LLL", ".L.", "LLL"],
  ["LLLL", "..L.", ".L..", "LLLL"],
  ["LLLLL", "...L.", "..L..", ".L...", "LLLLL"],
];
/** Sparkle frames: a pip, a plus, a star. */
export const SPARKLE = [["...", ".w.", "..."], [".w.", "www", ".w."], ["..w..", "..g..", "wgwgw", "..g..", "..w.."]];
export const rows = (r: readonly string[]): Grid => r.map((line) => [...line].map((c) => (c === "." ? null : (c as Key))));

/** Three dashes across the top of the visor, above the focused eyes; `on` (0 to 2) is the bright one. */
export function dotsGrid(on: number): Grid {
  const g = grid(W, H);
  for (let d = 0; d < 3; d++) for (let i = 0; i < 2; i++) g[7][9 + d * 3 + i] = d === on ? "w" : "G";
  return g;
}

/** A dithered red wash and bright rim over the visor, for the error flicker. */
export function redGrid(): Grid {
  const g = grid(W, H);
  for (let j = VISOR.y0; j <= VISOR.y1; j++)
    for (let i = VISOR.x0; i <= VISOR.x1; i++) {
      if ((j === VISOR.y0 || j === VISOR.y1) && (i === VISOR.x0 || i === VISOR.x1)) continue;
      const rim = j === VISOR.y0 || j === VISOR.y1 || i === VISOR.x0 || i === VISOR.x1;
      if (rim) g[j][i] = "x";
      else if ((i + j) % 2 === 0) g[j][i] = "r";
    }
  return g;
}

/**
 * Spawn: the grid redrawn as blocks b by b, centred on the sprite, each the
 * palette colour nearest the average of the pixels in it (empty blocks stay empty).
 */
export function mosaic(g: Grid, b: number, pal: Palette = LAR_PAL): Grid {
  if (b <= 1) return g;
  const h = g.length;
  const w = g[0].length;
  const out = grid(w, h);
  const all = (Object.keys(pal) as Key[]).map((k) => [k, rgb(pal[k])] as const);
  const x0 = -Math.floor((Math.ceil(w / b) * b - w) / 2);
  const y0 = -Math.floor((Math.ceil(h / b) * b - h) / 2);
  for (let j = y0; j < h; j += b)
    for (let i = x0; i < w; i += b) {
      const sum = [0, 0, 0];
      let n = 0;
      for (let y = Math.max(0, j); y < Math.min(h, j + b); y++)
        for (let x = Math.max(0, i); x < Math.min(w, i + b); x++) {
          const k = g[y][x];
          if (k) (n++, rgb(pal[k]).forEach((v, c) => (sum[c] += v)));
        }
      const area = (Math.min(w, i + b) - Math.max(0, i)) * (Math.min(h, j + b) - Math.max(0, j));
      if (n * 2 < area) continue;
      const k = all.map(([key, c]) => [key, c.reduce((d, v, q) => d + (v - sum[q] / n) ** 2, 0)] as const).sort((p, q) => p[1] - q[1])[0][0];
      for (let y = Math.max(0, j); y < Math.min(h, j + b); y++) for (let x = Math.max(0, i); x < Math.min(w, i + b); x++) out[y][x] = k;
    }
  return out;
}

// ---------------------------------------------------------------- portals

export interface Theme {
  ramp: readonly string[];
  accent: string;
}
/** The six portal themes, as in crates/intportal-core/src/portal.rs (a test keeps them equal). */
export const THEMES = {
  sis: { ramp: ["#3b1220", "#7a1c2c", "#b5412a", "#e08a35", "#f3cf6a"], accent: "#e8b04a" },
  mabini: { ramp: ["#0b2238", "#13466f", "#1f78a8", "#3fb4c9", "#a8efe4"], accent: "#5fd0d6" },
  up: { ramp: ["#0d2418", "#17452c", "#2a7a46", "#6cbf6a", "#d4f2b0"], accent: "#9fe07a" },
  tup: { ramp: ["#16181f", "#2c3140", "#56607a", "#9aa6bd", "#e6ebf5"], accent: "#ff6b5f" },
  pnu: { ramp: ["#160f33", "#2d1f66", "#5440b0", "#9a86f0", "#e2dbff"], accent: "#c8b6ff" },
  bulsu: { ramp: ["#2a1405", "#5c2c08", "#b0560f", "#f0a030", "#ffe3a3"], accent: "#ffc04d" },
} as const satisfies Record<string, Theme>;
export const SIS: Theme = THEMES.sis;
/** The scene LAR flies on; his rim light has to read against it. */
export const VOID = "#0b0710";

const rgb = (h: string) => [1, 3, 5].map((i) => parseInt(h.slice(i, i + 2), 16));
const hex = (c: number[]) => "#" + c.map((v) => Math.round(clamp(v, 0, 255)).toString(16).padStart(2, "0")).join("");
const mixHex = (a: string, b: string, f: number) => {
  const y = rgb(b);
  return hex(rgb(a).map((v, i) => v + (y[i] - v) * f));
};
function lum(h: string) {
  const [r, g, b] = rgb(h).map((v) => ((v /= 255) <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4));
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}
/** WCAG contrast ratio of two hex colours. */
export function contrast(a: string, b: string) {
  const [hi, lo] = [lum(a), lum(b)].sort((p, q) => q - p);
  return (hi + 0.05) / (lo + 0.05);
}
function hsl(h: string): [number, number, number] {
  const [r, g, b] = rgb(h).map((v) => v / 255);
  const mx = Math.max(r, g, b);
  const mn = Math.min(r, g, b);
  const l = (mx + mn) / 2;
  if (mx === mn) return [0, 0, l];
  const d = mx - mn;
  const s = d / (1 - Math.abs(2 * l - 1));
  const hu = mx === r ? ((g - b) / d + 6) % 6 : mx === g ? (b - r) / d + 2 : (r - g) / d + 4;
  return [hu * 60, s, l];
}
function fromHsl(h: number, s: number, l: number) {
  const a = s * Math.min(l, 1 - l);
  const f = (n: number) => l - a * Math.max(-1, Math.min((n + h / 30) % 12 - 3, 9 - ((n + h / 30) % 12), 1));
  return hex([f(0), f(8), f(4)].map((v) => v * 255));
}
/** Hue a part of the way from a to b, the short way round. */
const hueMix = (a: number, b: number, f: number) => a + (((((b - a) % 360) + 540) % 360) - 180) * f;
const BODY_KEYS = ["d", "k", "b", "B", "L"] as const;

/**
 * LAR's palette for a portal: he wears the university's colours. His body
 * keeps its lightness ladder and dither, but its five tones run as a gradient
 * from the ramp's deep hue in the shadows to the accent's hue in the light
 * (maroon to gold for PUP, forest to lime for UP, slate to coral for TUP).
 * The outline and mitts follow, the rim light is the accent lifted until it
 * reads on the void, the studs, cube, swirl and spawn fire take the ramp.
 * His gold eyes and spark never change: that is how you know him.
 */
export function tint(theme: Theme = SIS): Palette {
  const [r0, r1, r2, r3, r4] = theme.ramp;
  const [deep, deepS] = hsl(r1);
  const [glow, glowS] = hsl(theme.accent);
  const body = Object.fromEntries(
    BODY_KEYS.map((k, i) => {
      // Most of him stays in the deep hue; the accent comes in at the light.
      const f = (i / (BODY_KEYS.length - 1)) ** 1.6;
      const s = clamp(deepS + (glowS - deepS) * f, 0.16, 0.46);
      return [k, fromHsl((hueMix(deep, glow, f) + 360) % 360, s, hsl(LAR_PAL[k])[2])];
    }),
  ) as Record<(typeof BODY_KEYS)[number], string>;
  let rim = mixHex(theme.accent, "#ffffff", 0.18);
  for (let i = 0; contrast(rim, VOID) < 3 && i < 20; i++) rim = mixHex(rim, "#ffffff", 0.12);
  return {
    ...LAR_PAL,
    ...body,
    o: fromHsl(deep, 0.32, hsl(LAR_PAL.o)[2]),
    e: body.b,
    m: rim,
    t: mixHex(r3, r4, 0.45),
    T: mixHex(r2, r3, 0.3),
    c: mixHex(r1, r2, 0.5),
    s: mixHex(LAR_PAL.s, r0, 0.3),
    V: mixHex(LAR_PAL.V, r1, 0.25),
    "1": r1,
    "2": r2,
    "3": r3,
    "4": r4,
  };
}

const SWIRL_KEYS = 5;
/** The live swirl in his belly window, n × m pixels at time t, in a portal's ramp. */
export function drawSwirl(ctx: CanvasRenderingContext2D, t: number, n = 6, m = 5, ramp: readonly string[] = SIS.ramp) {
  const tones = [mixHex(ramp[0], "#000000", 0.35), ramp[1], ramp[2], ramp[3], ramp[4]];
  ctx.clearRect(0, 0, n, m);
  const c = (n - 1) / 2;
  const cy = (m - 1) / 2;
  for (let j = 0; j < m; j++)
    for (let i = 0; i < n; i++) {
      const dx = i - c;
      const dy = (j - cy) * 1.1;
      const r = Math.hypot(dx, dy);
      let v = 0.5 + 0.5 * Math.sin(Math.atan2(dy, dx) * 2 - r * 1.6 + t * 5.5);
      v = v * (1 - r / (c + 1)) * 1.25 + (1 - r / (c + 0.5)) * 0.35;
      v += (BAYER[j % 4][i % 4] / 16 - 0.5) * 0.28;
      ctx.fillStyle = tones[clamp(Math.floor(v * SWIRL_KEYS), 0, SWIRL_KEYS - 1)];
      ctx.fillRect(i, j, 1, 1);
    }
}

/** Closed for about a tenth of a second at seeded moments, open otherwise. */
export function blinkAt(t: number, seed = 3, base: Mood = "open"): Mood {
  const period = 2.9 + (seed % 3) * 0.4;
  const k = ((t + seed * 0.37) % period) / period;
  return k > 0.958 ? "blink" : base;
}

// ------------------------------------------------------------------ poses

export const STATES = ["idle", "fly", "spawn", "think", "sleep", "error", "happy"] as const;
export type State = (typeof STATES)[number];

export interface PoseOpts {
  /** The state before this one, so offsets ease across the switch. */
  from?: State;
  /** Seconds since the switch to `state` (default: long ago). Also times the error shake. */
  since?: number;
  /** Spawn progress, 0 to 1 (default 1). */
  k?: number;
  /** Fly velocity in sprite px per second. */
  vx?: number;
  vy?: number;
  /** Cube orbit angle owed to earlier switches (Lar.svelte keeps this; see cubeAngle). */
  phase?: number;
}

export type Kind = "mitt" | "thumb";
export interface MittPose {
  x: number;
  y: number;
  rot: number;
  side: 1 | -1;
  kind: Kind;
  /** Speed streak behind the mitt: length 0 to 1, and its direction in degrees. */
  streak: number;
  streakRot: number;
}
export interface Glyph {
  x: number;
  y: number;
  /** Index into ZZZ or SPARKLE. */
  s: number;
  a: number;
}
/** Every part's offset, in sprite px with the body's top left at 0,0. */
export interface Pose {
  /** Squash is about the body's centre; the antenna, face and belly ride on it. */
  body: { x: number; y: number; sx: number; sy: number; rot: number };
  /** Top left of the antenna, in body space, and its sway about its foot. */
  antenna: { x: number; y: number; rot: number };
  mitts: [MittPose, MittPose];
  /** Centre of the cube, its scale, and whether it passes in front of the body. */
  cube: { x: number; y: number; scale: number; front: boolean; angle: number };
  mood: Mood;
  /** The bright visor dot (0 to 2), or -1 for none. */
  dots: number;
  /** The visor is flickering red. */
  red: boolean;
  zzz: Glyph[];
  sparkle: Glyph[];
  /** Horizontal shake already added to body.x, for whoever wants to know. */
  shake: number;
  /** Spawn: draw the sprite in blocks this many sprite px wide (1 = sharp). */
  resolve: number;
  /** Spawn: how far the fire he comes out of has burned, 0 to 1, or -1 for no fire. */
  fire: number;
  alpha: number;
}

/** The fixed frame every part of every state stays in, with the body at 0,0 to W,H. */
export const BOX = { x0: -13, y0: -17, x1: W + 14, y1: H + 10 } as const;
/** Seconds offsets take to ease across a state switch. */
export const EASE = 0.25;
/** The cube eases a little slower, since it has the furthest to go. */
export const CUBE_EASE = 0.6;
export const SPAWN_SECS = 1.1;
export const ERROR_SECS = 0.4;

const TAU = Math.PI * 2;
/** The body squashes and leans about this point. */
export const PIVOT = { x: W / 2, y: 15 };
const MITT_X = [-5, 24];
const SIDE = [-1, 1] as const;
const ANT = { x: W / 2 - 3.5, y: -7 };
const smooth = (u: number) => u * u * (3 - 2 * u);

/** The numbers that blend across a switch; everything else is picked from one side. */
interface Raw {
  b: { x: number; y: number; sx: number; sy: number; rot: number };
  a: { x: number; y: number; rot: number };
  m: { x: number; y: number; rot: number; streak: number; streakRot: number }[];
  c: { x: number; y: number; rx: number; ry: number; s0: number; sa: number; vis: number };
  alpha: number;
}
interface Pick {
  mood: Mood;
  kinds: [Kind, Kind];
  dots: number;
  red: boolean;
  zzz: Glyph[];
  sparkle: Glyph[];
  shake: number;
  resolve: number;
  fire: number;
}
interface Spec {
  raw: Raw;
  pick: Pick;
}
/** Cube orbit: angular speed, and for a parked cube where it rests. */
const ORBIT: Record<State, { w: number; park?: number }> = {
  idle: { w: 2.2 },
  fly: { w: 2.8 },
  spawn: { w: 2.2 },
  think: { w: 3.5 },
  sleep: { w: 0, park: Math.PI * 1.04 },
  error: { w: 0.9 },
  happy: { w: 3 },
};
const PARK_ACCEL = 0.8;

const mix = <T>(a: T, b: T, e: number): T =>
  typeof a === "number"
    ? ((a + ((b as number) - a) * e) as T)
    : Array.isArray(a)
      ? (a.map((v, i) => mix(v, (b as T[])[i], e)) as T)
      : (Object.fromEntries(Object.entries(a as object).map(([k, v]) => [k, mix(v, (b as Record<string, unknown>)[k], e)])) as T);

const mittRaw = (_i: number, dx = 0, dy = 0, rot = 0, streak = 0, streakRot = 0) => ({ x: dx, y: dy, rot, streak, streakRot });
const cubeRaw = (o: Partial<Raw["c"]> = {}) => ({ x: W / 2, y: 9.5, rx: 16, ry: 3, s0: 0.75, sa: 0.25, vis: 1, ...o });
const calm = (): Pick => ({ mood: "open", kinds: ["mitt", "mitt"], dots: -1, red: false, zzz: [], sparkle: [], shake: 0, resolve: 1, fire: -1 });
const body = (o: Partial<Raw["b"]> = {}) => ({ x: 0, y: 0, sx: 1, sy: 1, rot: 0, ...o });

function spec(state: State, t: number, o: PoseOpts): Spec {
  const vx = o.vx ?? 40;
  const vy = o.vy ?? 0;
  const since = o.since ?? Infinity;
  const nx = clamp(vx / 60, -1, 1);
  const ny = clamp(vy / 60, -1, 1);
  const bob = Math.sin(t * 3.1) * 1.4;
  const sway = Math.sin(t * 3.1 - 0.9) * 6;
  const lag = (i: number) => Math.sin(t * 3.1 - 0.7 - i * 0.3) * 1.2;
  const pick = calm();
  switch (state) {
    case "idle":
      pick.mood = blinkAt(t);
      return {
        raw: { b: body({ y: bob }), a: { x: 0, y: 0, rot: sway }, m: [0, 1].map((i) => mittRaw(i, 0, lag(i))), c: cubeRaw({ y: 9.5 + bob * 0.5 }), alpha: 1 },
        pick,
      };
    case "fly": {
      pick.mood = blinkAt(t);
      const sp = clamp(Math.hypot(vx, vy) / 60);
      const flutter = (i: number) => Math.sin(t * 11 + i * 1.7);
      return {
        raw: {
          b: body({ x: 0, y: Math.sin(t * 7) * 0.8 + ny * 1.5, rot: nx * 13 + ny * (nx < 0 ? -4 : 4) }),
          a: { x: -nx * 0.5, y: 0, rot: -nx * 34 + ny * 10 + Math.sin(t * 13) * 3 * sp },
          m: [0, 1].map((i) => mittRaw(i, -nx * 4.5 - SIDE[i] * 1.5, 2 - ny * 3.5 + flutter(i) * 0.7 * sp, -nx * 14 * SIDE[i] + flutter(i + 1) * 5 * sp, sp, (Math.atan2(vy, vx) * 180) / Math.PI)),
          c: cubeRaw({ x: W / 2 - nx * 3.5, y: 9.5 - ny * 2.5, rx: 15 }),
          alpha: 1,
        },
        pick,
      };
    }
    case "spawn": {
      // He comes out of a fire: it flares up first, he resolves inside it from
      // coarse blocks to the sharp sprite, rising, and it burns out round him.
      const k = clamp(o.k ?? 1);
      const u = clamp((k - 0.2) / 0.8);
      const e = 1 - (1 - u) ** 3;
      pick.mood = k < 1 ? "open" : blinkAt(t);
      pick.resolve = k >= 1 ? 1 : u <= 0 ? 8 : [8, 6, 4, 3, 2][Math.min(4, Math.floor(u * 5))];
      pick.fire = k < 1 ? k : -1;
      if (k > 0.78 && k < 1) pick.sparkle = [{ x: W - 2, y: 0, s: k < 0.88 ? 1 : 2, a: 1 }];
      return {
        raw: {
          b: body({ y: bob * e + (1 - e) * 4 }),
          a: { x: 0, y: 0, rot: sway * e },
          m: [0, 1].map((i) => mittRaw(i, 0, lag(i))),
          c: cubeRaw({ y: 9.5 + bob * 0.5 }),
          alpha: clamp(u * 3),
        },
        pick,
      };
    }
    case "think": {
      pick.mood = "focus";
      pick.dots = ((Math.floor(t * 3.4) % 3) + 3) % 3;
      const tap = Math.sin(t * 7);
      return {
        raw: {
          b: body({ y: 0.5 + Math.sin(t * 2.2) * 0.7 }),
          a: { x: 0, y: 0, rot: Math.sin(t * 5) * 4 },
          m: [mittRaw(0, 0.5, 1 + tap * 0.6), mittRaw(1, -2.5, -4.5 + Math.sin(t * 2.2) * 0.4, -10)],
          c: cubeRaw({ y: 3, rx: 12, ry: 2.5 }),
          alpha: 1,
        },
        pick,
      };
    }
    case "sleep": {
      pick.mood = "sleep";
      const P = 3.6;
      const br = Math.sin(t * 1.25);
      for (let i = 0; i < 3; i++) {
        const p = (((t / P + i / 3) % 1) + 1) % 1;
        const s = p < 0.3 ? 0 : p < 0.65 ? 1 : 2;
        const sz = [3, 4, 5][s];
        pick.zzz.push({ x: 21 + p * 5 + Math.sin(p * 6) - sz / 2, y: -1 - p * 12 - sz / 2, s, a: p < 0.15 ? p / 0.15 : p > 0.7 ? (1 - p) / 0.3 : 1 });
      }
      return {
        raw: {
          b: body({ y: 2.5 + br * 0.9, sy: 1 + br * 0.012, rot: 3 }),
          a: { x: 0, y: 1, rot: 22 + Math.sin(t * 1.25 - 1) * 2.5 },
          m: [mittRaw(0, 2.5, 4 + br * 0.5, -12), mittRaw(1, -2.5, 4 + br * 0.5, 12)],
          c: cubeRaw({ y: 15.5, rx: 18, ry: 1 }),
          alpha: 1,
        },
        pick,
      };
    }
    case "error": {
      pick.mood = "wow";
      const dec = clamp(1 - since / ERROR_SECS);
      const u = (since / 0.2) % 1;
      const tri = u < 0.25 ? 4 * u : u < 0.75 ? 2 - 4 * u : 4 * u - 4;
      pick.shake = since < ERROR_SECS ? tri * 2 * dec : 0;
      pick.red = since < ERROR_SECS && Math.floor(since * 20) % 2 === 0;
      const tremble = Math.sin(t * 19) * 0.4;
      return {
        raw: {
          b: body({ x: pick.shake, y: -2 * dec, sy: 1 + 0.05 * dec, sx: 1 - 0.03 * dec }),
          a: { x: 0, y: 0, rot: 16 * dec + Math.sin(t * 17) * 2 },
          m: [0, 1].map((i) => mittRaw(i, SIDE[i] * 1.5, -5 + tremble * (i ? 1 : -1), SIDE[i] * 16)),
          c: cubeRaw({ y: 9.5 - 2 * dec }),
          alpha: 1,
        },
        pick,
      };
    }
    case "happy": {
      pick.mood = "happy";
      const T = 0.8;
      const u = (((t / T) % 1) + 1) % 1;
      const hop = -5 * 4 * u * (1 - u);
      const air = Math.sin(Math.PI * u);
      const pulse = Math.max(0, 1 - Math.min(u, 1 - u) / 0.14);
      const sy = 1 - 0.09 * pulse;
      const by = hop + (1 - sy) * (23 - PIVOT.y);
      const f = (((Math.floor(t * 6) % 3) + 3) % 3);
      // The waving hand comes up over the first moments of the cheer.
      const r = smooth(clamp(since / 0.7));
      pick.sparkle = [{ x: W - 3, y: -4, s: [1, 2, 0][f], a: 1 }];
      return {
        raw: {
          b: body({ y: by, sx: 1 + 0.06 * pulse, sy }),
          a: { x: 0, y: 0, rot: sway * 0.5 + Math.sin(TAU * u + 0.6) * 5 },
          m: [mittRaw(0, 1, hop * 0.7 - 4 * air + 1, -8 * air), mittRaw(1, 2 * r, hop - (4.5 - Math.sin(t * 8)) * r, (-10 + Math.sin(t * 8) * 14) * r)],
          c: cubeRaw({ y: 9.5 + hop * 0.5 }),
          alpha: 1,
        },
        pick,
      };
    }
  }
}

/**
 * The cube's angle. States spin at their own speed, so a switch blends the
 * speeds (not the angles): the cube speeds up or slows down without a jump.
 * Sleeping parks it: it coasts to a stop at its resting spot, and a wake-up
 * eases it back to speed. `phase` is what earlier switches left on the angle.
 */
export function cubeAngle(state: State, t: number, o: PoseOpts = {}): number {
  const B = ORBIT[state];
  const s = o.since ?? Infinity;
  const steady = (st: State, tt: number) => ORBIT[st].park ?? ORBIT[st].w * tt;
  const phase = o.phase ?? 0;
  if (!o.from || o.from === state || !isFinite(s)) return B.park ?? B.w * t + phase;
  const A = ORBIT[o.from];
  const a0 = A.park ?? steady(o.from, t - s) + phase;
  if (B.park !== undefined) {
    if (A.park !== undefined) return B.park;
    // Coast from speed A.w to a stop exactly at the parking spot.
    let d = (((B.park - a0) % TAU) + TAU) % TAU;
    if (d < 0.6) d += TAU;
    const td = (2 * d) / A.w;
    return a0 + (s < td ? A.w * (s - (s * s) / (2 * td)) : d);
  }
  if (A.park !== undefined) return a0 + B.w * (s < PARK_ACCEL ? (s * s) / (2 * PARK_ACCEL) : s - PARK_ACCEL / 2);
  const u = clamp(s / CUBE_EASE);
  return a0 + A.w * s + (B.w - A.w) * (s < CUBE_EASE ? CUBE_EASE * (u ** 3 - u ** 4 / 2) : s - CUBE_EASE / 2);
}

/**
 * Every part's offset for `state` at time t (seconds). Pure. With `from` and
 * `since`, offsets ease from the old state's pose over EASE seconds so a
 * switch never pops; faces and glyphs swap instantly, they are not offsets.
 */
export function pose(state: State, t: number, o: PoseOpts = {}): Pose {
  const s = o.since ?? Infinity;
  const B = spec(state, t, o);
  let raw = B.raw;
  let pick = B.pick;
  if (o.from && o.from !== state && s < CUBE_EASE) {
    // The old state is settled: nothing of its entrance (shake, spawn) is left.
    const A = spec(o.from, t, { ...o, since: Infinity, k: 1 });
    const e = smooth(clamp(s / easeTime(o.from, state, t - s, o)));
    raw = { ...mix(A.raw, B.raw, e), c: mix(A.raw.c, B.raw.c, smooth(clamp(s / CUBE_EASE))) };
    pick = { ...B.pick };
    if (e < 0.4) (pick.mood = A.pick.mood, (pick.kinds = A.pick.kinds), (pick.dots = A.pick.dots));
    pick.zzz = [...A.pick.zzz.map((g) => ({ ...g, a: g.a * (1 - e) })), ...B.pick.zzz.map((g) => ({ ...g, a: g.a * e }))];
    pick.sparkle = [...A.pick.sparkle.map((g) => ({ ...g, a: g.a * (1 - e) })), ...B.pick.sparkle.map((g) => ({ ...g, a: g.a * e }))];
  }
  return build(raw, pick, cubeAngle(state, t, o));
}

function build(raw: Raw, pick: Pick, angle: number): Pose {
  const c = raw.c;
  const sn = Math.sin(angle);
  const scale = (c.s0 + c.sa * sn) * c.vis;
  return {
    body: raw.b,
    antenna: { x: ANT.x + raw.a.x, y: ANT.y + raw.a.y, rot: raw.a.rot },
    mitts: [0, 1].map((i) => {
      const m = raw.m[i];
      return { x: MITT_X[i] + m.x, y: 13 + m.y, rot: m.rot, side: SIDE[i], kind: pick.kinds[i], streak: m.streak, streakRot: m.streakRot };
    }) as [MittPose, MittPose],
    cube: { x: c.x + c.rx * Math.cos(angle), y: c.y + c.ry * sn, scale, front: sn > 0, angle },
    mood: pick.mood,
    dots: pick.dots,
    red: pick.red,
    zzz: pick.zzz.filter((g) => g.a > 0.02),
    sparkle: pick.sparkle.filter((g) => g.a > 0.02),
    shake: pick.shake,
    resolve: pick.resolve,
    fire: pick.fire,
    alpha: raw.alpha,
  };
}

/**
 * How long a switch takes: EASE, stretched when the two poses are far apart
 * (measured at the instant of the switch) so no corner ever races.
 */
function easeTime(from: State, to: State, ts: number, o: PoseOpts): number {
  let d = 0;
  // The target keeps moving while the offsets ease, so look a little ahead too.
  for (let i = 0; i <= 6; i++) {
    const tt = ts + i * 0.1;
    const ea = extents(build(spec(from, tt, { ...o, since: Infinity, k: 1 }).raw, calm(), 0));
    const eb = extents(build(spec(to, tt, { ...o, since: i * 0.1, k: 0 }).raw, calm(), 0));
    for (const n of ["body", "antenna", "mitt0", "mitt1"]) ea[n].forEach((p, j) => (d = Math.max(d, Math.hypot(p[0] - eb[n][j][0], p[1] - eb[n][j][1]))));
  }
  return clamp(d / 30, EASE, 0.8);
}

// ---------------------------------------------------------------- extents

type Pt = [number, number];
const rot = ([x, y]: Pt, c: Pt, deg: number): Pt => {
  const r = (deg * Math.PI) / 180;
  const [dx, dy] = [x - c[0], y - c[1]];
  return [c[0] + dx * Math.cos(r) - dy * Math.sin(r), c[1] + dx * Math.sin(r) + dy * Math.cos(r)];
};
const quad = (x: number, y: number, w: number, h: number): Pt[] => [[x, y], [x + w, y], [x + w, y + h], [x, y + h]];

/** Where the body's squash and lean put a point of the sprite. */
export function bodyAt(p: Pose, pt: Pt): Pt {
  const { x, y, sx, sy, rot: r } = p.body;
  const q = rot([PIVOT.x + (pt[0] - PIVOT.x) * sx, PIVOT.y + (pt[1] - PIVOT.y) * sy], [PIVOT.x, PIVOT.y], r);
  return [q[0] + x, q[1] + y];
}

/** The corners of each part's box after its transform, for bounds and continuity checks. */
export function extents(p: Pose): Record<string, Pt[]> {
  const out: Record<string, Pt[]> = {};
  out.body = quad(0, 0, W, H).map((q) => bodyAt(p, q));
  const a = p.antenna;
  out.antenna = quad(a.x, a.y, 7, 9).map((q) => bodyAt(p, rot(q, [a.x + 3.5, a.y + 9], a.rot)));
  p.mitts.forEach((m, i) => {
    out[`mitt${i}`] = quad(m.x, m.y, 7, 7).map((q) => rot(q, [m.x + 3.5, m.y + 3.5], m.rot));
    if (m.streak > 0.02) out[`streak${i}`] = quad(m.x + 3.5 - 9.5, m.y + 2, 6, 3).map((q) => rot(q, [m.x + 3.5, m.y + 3.5], m.streakRot));
  });
  const c = p.cube;
  out.cube = quad(c.x - 3.5 * c.scale, c.y - 3.5 * c.scale, 7 * c.scale, 7 * c.scale);
  p.zzz.forEach((g, i) => (out[`zzz${i}`] = quad(g.x, g.y, ZZZ[g.s][0].length, ZZZ[g.s].length)));
  p.sparkle.forEach((g, i) => (out[`spark${i}`] = quad(g.x, g.y, SPARKLE[g.s][0].length, SPARKLE[g.s].length)));
  if (p.fire >= 0) out.fire = quad(FIRE.x, FIRE.y, FIRE.w, FIRE.h);
  return out;
}

// ------------------------------------------------------------ fire, sheen

/** Where the spawn fire burns, in sprite px: a bonfire round his body. */
export const FIRE = { x: -2, y: -9, w: 30, h: 34 } as const;
const FIRE_STEPS = 44;
const FIRE_MAX = 31;
const FIRE_KEYS: (Key | null)[] = [null, "1", "2", "3", "4", "w"];
let fireMemo = { key: "", g: [] as Grid };

/**
 * The fire he spawns in: a small Doom-style fire. A bonfire-shaped bed of
 * heat feeds it until k is 0.6; every step each cell's heat rises a row,
 * drifts sideways and cools at random, so flames lick up and taper. Then the
 * bed goes out and the last flames rise and die. Coloured cool to hot by the
 * portal's ramp under a white core. Pure for a k and seed (the last is cached).
 */
export function fireGrid(k: number, seed = 7): Grid {
  const steps = Math.round(clamp(k) * FIRE_STEPS);
  const key = `${steps}:${seed}`;
  if (fireMemo.key === key) return fireMemo.g;
  const { w, h } = FIRE;
  const heat = new Uint8Array(w * h);
  let a = seed >>> 0;
  const rand = () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let x = Math.imul(a ^ (a >>> 15), a | 1);
    x ^= x + Math.imul(x ^ (x >>> 7), x | 61);
    return ((x ^ (x >>> 14)) >>> 0) / 4294967296;
  };
  for (let s = 0; s < steps; s++) {
    const fuel = clamp(1 - (s / FIRE_STEPS - 0.6) / 0.08);
    for (let x = 0; x < w; x++) {
      const bed = Math.max(0, 1 - Math.abs(x - (w - 1) / 2) / (w * 0.44));
      heat[(h - 1) * w + x] = Math.round(FIRE_MAX * fuel * Math.sqrt(bed) * (rand() < 0.8 ? 1 : 0.5));
    }
    // Each cell pulls heat from the one below or a neighbour of it, and cools;
    // heat that came in sideways cools more, which splits the fire into
    // tongues. A slow wind sways the whole fire.
    // Two rows a step, so it flares up fast.
    const wind = Math.sin(s * 0.45) * 0.35;
    for (let sub = 0; sub < 2; sub++)
      for (let y = 1; y < h; y++)
        for (let x = 0; x < w; x++) {
          const dx = Math.round(rand() * 2 - 1 + wind);
          const from = Math.min(w - 1, Math.max(0, x + dx));
          heat[(y - 1) * w + x] = Math.max(0, heat[y * w + from] - (dx ? 1 : 0) - (rand() < 0.35 ? 1 : 0));
        }
  }
  const g = grid(w, h);
  for (let j = 0; j < h; j++)
    for (let i = 0; i < w; i++) {
      const v = heat[j * w + i];
      if (v >= 3) g[j][i] = FIRE_KEYS[Math.min(5, Math.ceil((v / FIRE_MAX) * 5))];
    }
  fireMemo = { key, g };
  return g;
}

/** Seconds between sheens, and how long one takes to cross him. */
export const SHEEN = { every: 5.5, cross: 0.9 } as const;
const LIFT: Partial<Record<Key, Key>> = { d: "k", k: "b", b: "B", B: "L", m: "w" };
let BODY_G: Grid | null = null;

/**
 * A whimsical sheen: now and then a diagonal band of light sweeps across his
 * body, lifting each tone a step (the brightest to white at its core). Its
 * edges are dithered, so it reads as a gradient in whole pixels. Null
 * between sweeps.
 */
export function sheenGrid(t: number): Grid | null {
  const u = (((t % SHEEN.every) + SHEEN.every) % SHEEN.every) / SHEEN.cross;
  if (u >= 1) return null;
  BODY_G ??= bodyGrid();
  const at = -6 + u * (W + H + 12);
  const g = grid(W, H);
  BODY_G.forEach((row, j) =>
    row.forEach((k, i) => {
      if (!k) return;
      const d = Math.abs(i * 0.8 + j - at);
      const core = d < 1.2;
      const edge = d < 3.5 && BAYER[j % 4][i % 4] / 16 < (3.5 - d) / 2.3;
      const up = k === "L" ? (core ? "w" : undefined) : LIFT[k];
      if (up && (core || edge)) g[j][i] = up;
    }),
  );
  return g;
}

// ------------------------------------------------------------------- rig

/**
 * One LAR's state over time: which state he is in, which he came from, when
 * he switched and the cube angle owed, so pose() eases every change.
 */
export function rig(initial: State = "idle") {
  let cur = initial;
  let from: State | undefined;
  let switched = -Infinity;
  let phase = 0;
  let last = 0;
  return {
    get state() {
      return cur;
    },
    /** Seconds in the current state at t. */
    since: (t: number) => t - switched,
    /** Switch to `next` at t, easing from wherever he is (a spawn starts afresh). */
    set(next: State, t: number, o: PoseOpts = {}) {
      if (next === cur) return;
      if (next === "spawn") return this.start(next, t);
      phase = last - pose(cur, t, { ...o, phase: 0 }).cube.angle;
      from = cur;
      cur = next;
      switched = t;
    },
    /** Start `state` afresh at t, with nothing to ease from (a spawn). */
    start(state: State, t: number) {
      cur = state;
      from = undefined;
      switched = t;
      phase = 0;
    },
    /** His pose at t. `still` (Reduce Motion) holds him settled. */
    at(t: number, o: PoseOpts = {}, still = false): Pose {
      const since = still ? Infinity : t - switched;
      const p = pose(cur, still ? 0 : t, { k: still ? 1 : Math.min(1, since / SPAWN_SECS), ...o, from: still ? undefined : from, since, phase });
      last = p.cube.angle;
      return p;
    },
  };
}

// --------------------------------------------------------------- drawing

export interface DrawOpts {
  /** The orbiting cube (default on). */
  cube?: boolean;
  /** The soft shadow under him (default on). */
  shadow?: boolean;
  /** The glow behind him in his portal's colours (default on). */
  aura?: boolean;
}

const palettes = new Map<string, Palette>();
const baked = new Map<string, HTMLCanvasElement>();
const paintInto = (x: CanvasRenderingContext2D, g: Grid, pal: Palette, ox = 0, oy = 0) =>
  g.forEach((row, j) =>
    row.forEach((k, i) => {
      if (!k) return;
      x.fillStyle = pal[k];
      x.fillRect(ox + i, oy + j, 1, 1);
    }),
  );
let belly: HTMLCanvasElement | null = null;

/**
 * Draws LAR for a pose. `ctx` is in sprite px with the body's top left at
 * 0,0 (scale it first); smoothing is off, so every part lands on whole pixels
 * of whatever scale the caller picked, while positions stay smooth.
 */
export function drawLar(ctx: CanvasRenderingContext2D, p: Pose, theme: Theme, t: number, o: DrawOpts = {}) {
  const id = theme.ramp.join() + theme.accent;
  let pal = palettes.get(id);
  if (!pal) palettes.set(id, (pal = tint(theme)));
  const P = pal;
  const bake = (name: string, g: () => Grid) => {
    let c = baked.get(id + name);
    if (!c) {
      const gr = g();
      c = document.createElement("canvas");
      c.width = gr[0].length;
      c.height = gr.length;
      paintInto(c.getContext("2d")!, gr, P);
      baked.set(id + name, c);
    }
    return c;
  };
  const res = p.resolve;
  const sharp = (name: string, g: () => Grid) => (res > 1 ? bake(`${name}@${res}`, () => mosaic(g(), res, P)) : bake(name, g));
  const deg = Math.PI / 180;

  ctx.save();
  ctx.imageSmoothingEnabled = false;
  const fire = p.fire >= 0 ? fireGrid(p.fire) : null;
  const fireAlpha = clamp((1 - p.fire) / 0.15);

  // The glow: a soft gradient from the accent through the ramp to nothing.
  if (o.aura !== false && p.alpha > 0) {
    const cx = W / 2 + p.body.x;
    const cy = 12 + p.body.y;
    const r = 20 + Math.sin(t * 1.3) * 1.5;
    const g = ctx.createRadialGradient(cx, cy, 1, cx, cy, r);
    g.addColorStop(0, theme.accent + "38");
    g.addColorStop(0.55, theme.ramp[2] + "16");
    g.addColorStop(1, theme.ramp[2] + "00");
    ctx.globalAlpha = p.alpha;
    ctx.fillStyle = g;
    ctx.fillRect(cx - r, cy - r, r * 2, r * 2);
  }
  if (fire) {
    ctx.globalAlpha = fireAlpha;
    paintInto(ctx, fire, P, FIRE.x, FIRE.y);
  }
  ctx.globalAlpha = p.alpha;
  if (o.shadow !== false) {
    ctx.fillStyle = "rgb(0 0 0 / 0.3)";
    ctx.beginPath();
    ctx.ellipse(W / 2 + p.body.x, 25.5, 8 * Math.max(0.5, 1 + p.body.y / 16), 1, 0, 0, Math.PI * 2);
    ctx.fill();
  }

  const cube = () => {
    const c = p.cube;
    if (o.cube === false || c.scale < 0.01) return;
    ctx.save();
    ctx.translate(c.x, c.y);
    ctx.scale(c.scale, c.scale);
    ctx.drawImage(sharp("cube", () => rows(CUBE)), -3.5, -3.5);
    ctx.restore();
  };
  if (!p.cube.front) cube();
  for (const m of p.mitts) {
    if (m.streak < 0.02) continue;
    ctx.save();
    ctx.globalAlpha = p.alpha * m.streak * 0.9;
    ctx.translate(m.x + 3.5, m.y + 3.5);
    ctx.rotate(m.streakRot * deg);
    ctx.drawImage(bake("streak", () => rows(STREAK)), -9.5, -1.5);
    ctx.restore();
  }

  ctx.save();
  const b = p.body;
  ctx.translate(b.x + PIVOT.x, b.y + PIVOT.y);
  ctx.rotate(b.rot * deg);
  ctx.scale(b.sx, b.sy);
  ctx.translate(-PIVOT.x, -PIVOT.y);
  ctx.save();
  ctx.translate(p.antenna.x + 3.5, p.antenna.y + 9);
  ctx.rotate(p.antenna.rot * deg);
  ctx.drawImage(sharp("antenna", () => rows(ANTENNA)), -3.5, -9);
  ctx.restore();
  if (res > 1) {
    // While he resolves, body and face are blocked together so the blocks agree.
    const flat = (...layers: Grid[]): Grid => bodyGrid().map((row, j) => row.map((k, i) => layers.reduce<Key | null>((acc, l) => l[j][i] ?? acc, k)));
    ctx.drawImage(bake(`whole@${res}${p.mood}${p.red}`, () => mosaic(p.red ? flat(redGrid(), faceGrid(p.mood)) : flat(faceGrid(p.mood)), res, P)), 0, 0);
  } else {
    ctx.drawImage(bake("body", bodyGrid), 0, 0);
    const sheen = sheenGrid(t);
    if (sheen) paintInto(ctx, sheen, P);
    if (p.red) ctx.drawImage(bake("red", redGrid), 0, 0);
    ctx.drawImage(bake(`face:${p.mood}`, () => faceGrid(p.mood)), 0, 0);
    if (p.dots >= 0) ctx.drawImage(bake(`dots:${p.dots}`, () => dotsGrid(p.dots)), 0, 0);
    belly ??= Object.assign(document.createElement("canvas"), { width: 6, height: 5 });
    drawSwirl(belly.getContext("2d")!, t, 6, 5, theme.ramp);
    ctx.drawImage(belly, W / 2 - 3, 15);
  }
  ctx.restore();
  if (p.cube.front) cube();
  for (const m of p.mitts) {
    ctx.save();
    ctx.translate(m.x + 3.5, m.y + 3.5);
    ctx.rotate(m.rot * deg);
    ctx.scale(m.side, 1);
    ctx.drawImage(sharp(m.kind, () => rows(m.kind === "thumb" ? THUMB : MITT)), -3.5, -3.5);
    ctx.restore();
  }
  for (const g of p.zzz) {
    ctx.globalAlpha = g.a * p.alpha;
    ctx.drawImage(bake(`z${g.s}`, () => rows(ZZZ[g.s])), g.x, g.y);
  }
  for (const g of p.sparkle) {
    ctx.globalAlpha = g.a * p.alpha;
    ctx.drawImage(bake(`sp${g.s}`, () => rows(SPARKLE[g.s])), g.x, g.y);
  }
  // The flames in front of him: the lower part, fading as he comes clear.
  if (fire) {
    ctx.save();
    ctx.beginPath();
    ctx.rect(FIRE.x, H * 0.6, FIRE.w, FIRE.y + FIRE.h - H * 0.6);
    ctx.clip();
    ctx.globalAlpha = fireAlpha * clamp(1.5 - p.fire * 1.7);
    paintInto(ctx, fire, P, FIRE.x, FIRE.y);
    ctx.restore();
  }
  ctx.restore();
}
