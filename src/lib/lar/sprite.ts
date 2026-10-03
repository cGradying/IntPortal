// LAR, the Lakbay-Aral Robot: a pocket-size robot from the portal's other
// side. Ported from the film rig (intportal-films/assets/isko/isko.js, where
// he was drafted as "Isko 3.0"). An obsidian pebble with stepped block ears,
// a dark visor with gold eyes, a belly window showing the live swirl, a
// gold spark antenna, two floating mitts and a tiny orbiting portal cube.
// Outlined, four-tone, ordered dither between tones. Pure grids here;
// Lar.svelte puts them on screen.
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
} as const;
export type Key = keyof typeof LAR_PAL;
export type Grid = (Key | null)[][];

export const MOODS = ["open", "blink", "happy", "wow", "wink", "focus"] as const;
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
  g[1][5] = "g";
  g[1][W - 6] = "g";
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
  g[by0][bx0 + 1] = "g";
  g[by0][bx0 + 6] = "g";
  g[by0 + 6][bx0 + 1] = "G";
  g[by0 + 6][bx0 + 6] = "G";
  // Magenta rim light on the right edge, so he reads on dark scenes.
  for (let j = 0; j < H; j++)
    for (let i = W - 1; i > 0; i--) {
      const k = g[j][i];
      if (k && k !== "o") {
        if (j > 4 && j < 19 && !"vVsgG".includes(k)) g[j][i] = "m";
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
  const eyes: Record<Mood, [(x: number) => void, (x: number) => void]> = {
    open: [open, open],
    blink: [closed, closed],
    happy: [happy, happy],
    wow: [wow, wow],
    wink: [open, happy],
    focus: [(x) => focus(x, 1), (x) => focus(x, -1)],
  };
  eyes[mood][0](L);
  eyes[mood][1](R);
  if (mood !== "focus") {
    put(L - 2, y + 4, "p");
    put(L - 1, y + 4, "p");
    put(R + 2, y + 4, "p");
    put(R + 3, y + 4, "p");
  }
  if (mood === "wow") {
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
export const CUBE = ["...o...", "..ogo..", ".ogwgo.", "ogwcgGo", ".ogcGo.", "..oGo..", "...o..."];
export const rows = (r: readonly string[]): Grid => r.map((line) => [...line].map((c) => (c === "." ? null : (c as Key))));

const SWIRL = ["#2a0a14", "#7a1128", "#c2403a", "#f5b227", "#fff1c4"];
/** The live swirl in his belly window, n × m pixels at time t. */
export function drawSwirl(ctx: CanvasRenderingContext2D, t: number, n = 6, m = 5) {
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
      ctx.fillStyle = SWIRL[clamp(Math.floor(v * 5), 0, 4)];
      ctx.fillRect(i, j, 1, 1);
    }
}

/** Closed for about a tenth of a second at seeded moments, open otherwise. */
export function blinkAt(t: number, seed = 3, base: Mood = "open"): Mood {
  const period = 2.9 + (seed % 3) * 0.4;
  const k = ((t + seed * 0.37) % period) / period;
  return k > 0.958 ? "blink" : base;
}
