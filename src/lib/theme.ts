// A theme the student makes (spec 047 C12–C15): four colours, two hues, five
// choices and a name. `roles` turns it into every CSS role with the clamps, so
// a bad pick or a hand-made code can't produce unreadable text (C13).
import { contrast, hex, luminance, mix, push } from "./rooms";

export const PATTERNS = ["dots", "squares", "bold", "plus", "hearts", "stars", "checks", "lines", "grid", "none"] as const;
export const AURA = ["full", "soft", "off"] as const;
export const CORNERS = ["step", "deep", "round", "sharp"] as const;
export const CARDS = ["fill", "outline", "tint"] as const;
export const TITLES = ["phone", "classic", "pixel"] as const;

export interface Theme {
  name: string;
  accent: string;
  ground: string;
  card: string;
  ink: string;
  /** The ground's pools; null follows the accent. */
  hue2: number | null;
  /** LAR's colour; null keeps the school's. */
  lar: number | null;
  pattern: (typeof PATTERNS)[number];
  aura: (typeof AURA)[number];
  corners: (typeof CORNERS)[number];
  cards: (typeof CARDS)[number];
  titles: (typeof TITLES)[number];
}

export function hsl(h: number, s: number, l: number): string {
  const f = (n: number) => {
    const k = (n + h / 30) % 12;
    const a = s * Math.min(l, 1 - l);
    return l - a * Math.max(-1, Math.min(k - 3, 9 - k, 1));
  };
  return "#" + [0, 8, 4].map((n) => Math.round(f(n) * 255).toString(16).padStart(2, "0")).join("");
}

/** The hue of a colour, 0 to 360. */
export function hueOf(c: string): number {
  const [r, g, b] = hex(c).map((v) => v / 255);
  const mx = Math.max(r, g, b);
  const d = mx - Math.min(r, g, b);
  if (d === 0) return 0;
  return (mx === r ? (g - b) / d + (g < b ? 6 : 0) : mx === g ? (b - r) / d + 2 : (r - g) / d + 4) * 60;
}

const alpha = (h: string, a: number) => `${h}${Math.round(a * 255).toString(16).padStart(2, "0")}`;
const SUBJ_HUES = [0, 40, 95, 165, 215, 280];
export const isDark = (t: Theme) => luminance(t.ground) < 0.3;

/** Every CSS role for a theme, clamped: text 7:1 on cards and ground, quieter text 4.5:1, accent 3:1. */
export function roles(t: Theme): Record<string, string> {
  const dark = isDark(t);
  const far = dark ? "#ffffff" : "#000000";
  const near = dark ? "#000000" : "#ffffff";
  // Ground and cards stay on the theme's side of light, far enough that 7:1 text exists on them.
  const ground = push(t.ground, far, 7, near);
  const fill = t.cards === "outline" ? t.ground : t.cards === "tint" ? mix(t.card, t.accent, 0.14) : t.card;
  const card = push(fill, far, 7, near);
  const card2 = t.cards === "outline" ? card : mix(card, far, dark ? 0.05 : 0.02);
  const ink = push(push(t.ink, card, 7, far), ground, 7, far);
  const gold = push(t.accent, card, 3, far);
  const onGold = contrast("#ffffff", gold) >= contrast("#111111", gold) ? "#ffffff" : "#111111";
  const pool = hsl(t.hue2 ?? hueOf(t.accent), 0.7, dark ? 0.5 : 0.7);
  const r: Record<string, string> = {
    "color-scheme": dark ? "dark" : "light",
    "--ground": ground,
    "--ground-2": mix(ground, far, 0.03),
    "--card": card,
    "--card-2": card2,
    "--sunk": mix(ground, "#000000", dark ? 0.2 : 0.05),
    "--edge": alpha(ink, 0.09),
    "--edge-2": alpha(ink, 0.18),
    "--ink": ink,
    "--ink-2": push(mix(ink, card, 0.3), card, 4.5, ink),
    "--ink-3": push(mix(ink, card, 0.48), card, 3, ink),
    "--gold": gold,
    "--gold-soft": alpha(gold, 0.16),
    "--on-gold": onGold,
    "--dot": alpha(gold, dark ? 0.16 : 0.14),
    "--maroon": t.accent,
    "--maroon-2": mix(t.accent, far, 0.15),
    "--good": push(dark ? "#58c792" : "#1e7249", card, 4.5, far),
    "--bad": push(dark ? "#f07a6e" : "#b42318", card, 4.5, far),
    "--island": dark ? mix(ground, "#000000", 0.4) : mix(ink, card, 0.1),
    "--shadow": dark ? "0 10px 30px rgba(0,0,0,.4)" : "0 10px 30px rgba(40,30,30,.12)",
    "--aura-a": alpha(pool, dark ? 0.42 : 0.4),
    "--aura-b": alpha(gold, dark ? 0.2 : 0.14),
    "--aura-c": alpha(pool, dark ? 0.16 : 0.12),
    "--aura-o": t.aura === "off" ? "0" : t.aura === "soft" ? "0.55" : "1",
  };
  const h = hueOf(t.accent);
  SUBJ_HUES.forEach((d, i) => (r[`--s${i + 1}`] = push(hsl((h + d) % 360, 0.55, dark ? 0.56 : 0.42), card, 3, far)));
  return r;
}

// Ground patterns: CSS gradients, or pixel sprites as SVG with the colour baked in.
function sprite(rows: string[], pad: number, colour: string): string {
  const w = rows[0].length + pad;
  const h = rows.length + pad;
  const [rgb, a] = [colour.slice(0, 7), colour.length > 7 ? parseInt(colour.slice(7), 16) / 255 : 1];
  const rects = rows.flatMap((row, y) => [...row].flatMap((c, x) => (c === "#" ? [`<rect x='${x}' y='${y}' width='1' height='1'/>`] : [])));
  const svg = `<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 ${w} ${h}' shape-rendering='crispEdges' fill='${rgb}' fill-opacity='${a.toFixed(3)}'>${rects.join("")}</svg>`;
  return `url("data:image/svg+xml,${encodeURIComponent(svg)}")`;
}

/** A pattern as a background image and size, drawn in `c`. */
export function patternCss(p: Theme["pattern"], c: string): { image: string; size: string } {
  switch (p) {
    case "dots": return { image: `radial-gradient(${c} 1px, transparent 1.2px)`, size: "14px 14px" };
    case "bold": return { image: `radial-gradient(${c} 2px, transparent 2.3px)`, size: "14px 14px" };
    case "checks": return { image: `conic-gradient(${c} 25%, transparent 0 50%, ${c} 0 75%, transparent 0)`, size: "16px 16px" };
    case "lines": return { image: `repeating-linear-gradient(${c} 0 2px, transparent 0 10px)`, size: "auto" };
    case "grid": return { image: `linear-gradient(${c} 1px, transparent 0), linear-gradient(90deg, ${c} 1px, transparent 0)`, size: "14px 14px" };
    case "squares": return { image: sprite(["##"], 5, c), size: "14px 14px" };
    case "plus": return { image: sprite(["..#..", ".###.", "..#.."], 5, c), size: "16px 16px" };
    case "hearts": return { image: sprite([".##.##.", "#######", "#######", ".#####.", "..###..", "...#..."], 3, c), size: "20px 20px" };
    case "stars": return { image: sprite(["...#...", "...#...", "..###..", "#######", "..###..", "...#...", "...#..."], 5, c), size: "24px 24px" };
    default: return { image: "none", size: "auto" };
  }
}

/** The whole look as CSS custom properties: roles, ground pattern and titles. Corners and cards go on data attributes. */
export function look(t: Theme): Record<string, string> {
  const r = roles(t);
  const p = patternCss(t.pattern, r["--dot"]);
  r["--pattern"] = p.image;
  r["--pattern-size"] = p.size;
  if (t.titles === "classic") Object.assign(r, { "--font-display": '"Montserrat Variable", system-ui, sans-serif', "--title-weight": "700", "--title-track": "-0.02em" });
  if (t.titles === "pixel") Object.assign(r, { "--font-display": "var(--font-pixel)", "--title-weight": "700", "--title-track": "0" });
  return r;
}

/** LAR in a hue of the student's choosing, in the shape of a portal theme. */
export const larLook = (h: number) => ({ ramp: [0.1, 0.2, 0.36, 0.56, 0.84].map((l) => hsl(h, 0.7, l)), accent: hsl(h, 0.8, 0.64) });

const BASE = { hue2: null, lar: null, pattern: "dots", aura: "full", corners: "step", cards: "fill", titles: "phone" } as const;

/** A whole theme from one hue and a night-to-day shade (0 to 100). */
export function seed(h: number, shade: number, name = "My theme", base: Partial<Theme> = {}): Theme {
  const day = shade >= 50;
  const k = shade / 100;
  return {
    ...BASE,
    hue2: (h + 28) % 360,
    name,
    accent: hsl(h, 0.84, day ? 0.42 : 0.62),
    ground: day ? hsl(h, 0.22, 0.86 + (k - 0.5) * 0.24) : hsl(h, 0.42, 0.03 + k * 0.2),
    card: day ? hsl(h, 0.3, 0.97) : hsl(h, 0.34, 0.08 + k * 0.2),
    ink: day ? hsl(h, 0.3, 0.1) : hsl(h, 0.28, 0.93),
    ...base,
  };
}

export const NIGHT: Theme = { ...BASE, name: "Night", accent: "#e8b04a", ground: "#0b0710", card: "#170b1a", ink: "#f4ecd8", hue2: 8 };
export const PRESETS: Theme[] = [
  NIGHT,
  { ...BASE, name: "Day", accent: "#b5412a", ground: "#f4f2ef", card: "#ffffff", ink: "#1c1517", hue2: 30 },
  { ...BASE, name: "Maroon Night", accent: "#f2c14e", ground: "#1a0a0e", card: "#2a1016", ink: "#f7ecec", hue2: 350 },
  { ...BASE, name: "Sakura", accent: "#e0417e", ground: "#fce9f0", card: "#fff7fa", ink: "#210816", hue2: 330, pattern: "hearts", corners: "round" },
  { ...BASE, name: "Tokyo Night", accent: "#7aa2f7", ground: "#12131b", card: "#1e1f2c", ink: "#c5cae6", hue2: 280, pattern: "stars" },
  { ...BASE, name: "Gruvbox", accent: "#fabd2f", ground: "#1d2021", card: "#2d2d2d", ink: "#ebdbb2", hue2: 20, pattern: "squares", aura: "soft" },
  { ...BASE, name: "Matrix", accent: "#00ff41", ground: "#000000", card: "#0d0f0d", ink: "#c9ffd6", hue2: 130, pattern: "lines", aura: "soft", corners: "sharp", titles: "pixel" },
];

const NAMES_A = ["Kape", "Jeepney", "Mango", "Halo-Halo", "Lagoon", "Sampaguita", "Ube", "Taho", "Sunset", "Midnight", "Lakbay", "Tala", "Sinag", "Pandesal", "Bagyo"];
const NAMES_B = ["Night", "Neon", "Float", "Dream", "Glow", "Pop", "Run", "Sky", "Mode", "Drift", "Bloom", "Static"];

/** The dice: a whole theme and a name, mostly night. `rand` is injectable for tests. */
export function roll(rand: () => number = Math.random): { hue: number; shade: number; t: Theme } {
  const pick = <T>(a: readonly T[]): T => a[Math.floor(rand() * a.length)];
  const h = Math.floor(rand() * 360);
  const shade = rand() < 0.72 ? Math.floor(rand() * 30) : 60 + Math.floor(rand() * 40);
  const t = seed(h, shade, `${pick(NAMES_A)} ${pick(NAMES_B)}`, {
    hue2: (h + pick([24, 40, 150, 200, 320])) % 360,
    lar: rand() < 0.5 ? null : (h + pick([0, 30, 180])) % 360,
    pattern: pick(PATTERNS),
    aura: pick(AURA),
    corners: pick(CORNERS),
    cards: pick(CARDS),
    titles: pick(["phone", "phone", "classic", "pixel"] as const),
  });
  return { hue: h, shade, t };
}
