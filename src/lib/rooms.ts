// Rooms: the legacy app's themes, each restyling the whole app. The three
// hand-tuned rooms live in app.css; the rest are the legacy Theme.swift
// palettes as data, and `derive` turns each into the full set of roles with
// contrast clamps (the port of `Palette.Roles.derived(from:)`).

export interface Palette {
  name: string;
  accent: string;
  canvasTop: string;
  canvasBottom: string;
  panel: string;
  onPanel: string;
  subjects: string[];
}

type RGB = [number, number, number];

const hex = (h: string): RGB => [1, 3, 5].map((i) => parseInt(h.slice(i, i + 2), 16)) as RGB;
const toHex = (c: RGB) => "#" + c.map((v) => Math.round(v).toString(16).padStart(2, "0")).join("");
const mix = (a: string, b: string, t: number) => toHex(hex(a).map((v, i) => v + (hex(b)[i] - v) * t) as RGB);

export function luminance(h: string): number {
  const [r, g, b] = hex(h).map((v) => {
    const s = v / 255;
    return s <= 0.03928 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4;
  });
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

export function contrast(a: string, b: string): number {
  const [x, y] = [luminance(a), luminance(b)].sort((p, q) => q - p);
  return (x + 0.05) / (y + 0.05);
}

/** Moves `fg` toward `toward` until it reaches `ratio` against `bg`. */
function push(fg: string, bg: string, ratio: number, toward: string): string {
  let c = fg;
  for (let i = 1; i <= 20 && contrast(c, bg) < ratio; i++) c = mix(fg, toward, i / 20);
  return c;
}

export const HAND_TUNED = [
  { id: "night", name: "Night", swatch: ["#19191c", "#26262a", "#f5b227"] },
  { id: "day", name: "Day", swatch: ["#f4f2ef", "#ffffff", "#6d0e1f"] },
  { id: "maroon", name: "Maroon Night", swatch: ["#1a0a0e", "#2a1016", "#f2c14e"] },
];

// Straight from Theme.swift (legacy), one entry per room.
export const PALETTES: Record<string, Palette> = {
  pupMaroon: { name: "PUP Maroon", accent: "#7a1128", canvasTop: "#fcfbfa", canvasBottom: "#f2edec", panel: "#140608", onPanel: "#fcfbfa", subjects: ["#7a1128", "#b13e34", "#a37314", "#5c315f", "#2e5a4f", "#3f517a"] },
  ivory: { name: "Ivory", accent: "#343c51", canvasTop: "#fdfbf6", canvasBottom: "#f6f2ea", panel: "#212125", onPanel: "#fdfbf6", subjects: ["#343c51", "#b46047", "#a37e32", "#734f6a", "#536d4f", "#3e7377"] },
  astraMoon: { name: "Astra Moon", accent: "#10b981", canvasTop: "#0e1525", canvasBottom: "#060c18", panel: "#060a13", onPanel: "#f1f6fa", subjects: ["#10b981", "#06969c", "#51a3ec", "#8b73ec", "#ec9d3e", "#e96983"] },
  sakura: { name: "Sakura", accent: "#e0417e", canvasTop: "#fff7fa", canvasBottom: "#fce9f0", panel: "#210816", onPanel: "#fff7fa", subjects: ["#e0417e", "#f16d66", "#8b51a2", "#c9a227", "#378b85", "#343c51"] },
  monochrome: { name: "Monochrome", accent: "#111111", canvasTop: "#ffffff", canvasBottom: "#f2f2f2", panel: "#111111", onPanel: "#ffffff", subjects: ["#1a1a1a", "#3d3d3d", "#5c5c5c", "#7a7a7a", "#999999", "#b8b8b8"] },
  matrix: { name: "Matrix", accent: "#00ff41", canvasTop: "#0d0f0d", canvasBottom: "#000000", panel: "#000000", onPanel: "#00ff41", subjects: ["#00ff41", "#00e5d4", "#ffb000", "#008f11", "#d3d3d3", "#28ad85"] },
  dracula: { name: "Dracula", accent: "#bd93f9", canvasTop: "#282a36", canvasBottom: "#1d1f28", panel: "#14151b", onPanel: "#f8f8f2", subjects: ["#bd93f9", "#ff79c6", "#8be9fd", "#50fa7b", "#ffb86c", "#ff5555"] },
  nord: { name: "Nord", accent: "#88c0d0", canvasTop: "#2e3440", canvasBottom: "#252933", panel: "#1b1e25", onPanel: "#eceff4", subjects: ["#88c0d0", "#81a1c1", "#5d81ac", "#a3be8c", "#ebcb8b", "#b48ead"] },
  gruvbox: { name: "Gruvbox", accent: "#fabd2f", canvasTop: "#282828", canvasBottom: "#1d2021", panel: "#191919", onPanel: "#ebdbb2", subjects: ["#fabd2f", "#b8bb26", "#83a598", "#d3869b", "#fb4934", "#af80ca"] },
  solarizedDark: { name: "Solarized Dark", accent: "#268bd2", canvasTop: "#073642", canvasBottom: "#002b36", panel: "#052932", onPanel: "#eee8d5", subjects: ["#268bd2", "#849900", "#d53682", "#b58900", "#2aa198", "#6d71c4"] },
  solarizedLight: { name: "Solarized Light", accent: "#268bd2", canvasTop: "#fdf6e3", canvasBottom: "#eee8d5", panel: "#073642", onPanel: "#eee8d5", subjects: ["#268bd2", "#849900", "#d53682", "#b58900", "#2aa198", "#6d71c4"] },
  tokyoNight: { name: "Tokyo Night", accent: "#7aa2f7", canvasTop: "#1a1b26", canvasBottom: "#12131b", panel: "#0e0f16", onPanel: "#c5cae6", subjects: ["#7aa2f7", "#bd92f9", "#6ad8ef", "#9dcd6d", "#e09860", "#f7768e"] },
  catppuccin: { name: "Catppuccin", accent: "#cba6f7", canvasTop: "#2e2f40", canvasBottom: "#1e1e2e", panel: "#171825", onPanel: "#cdd6f4", subjects: ["#cba6f7", "#f4c2d8", "#92e1fa", "#a6e3a1", "#fab387", "#f38ba8"] },
  oneDark: { name: "One Dark", accent: "#61afef", canvasTop: "#2c2e34", canvasBottom: "#212227", panel: "#1b1c20", onPanel: "#abb2bf", subjects: ["#61afef", "#c678dd", "#56b6c2", "#98c379", "#d19a66", "#e06c75"] },
};

/** Every CSS role for a palette room. */
export function derive(p: Palette): Record<string, string> {
  const dark = luminance(p.canvasBottom) < 0.3;
  const ground = p.canvasBottom;
  const card = dark ? mix(p.canvasTop, "#ffffff", 0.05) : mix(p.canvasTop, "#ffffff", 0.7);
  const card2 = dark ? mix(p.canvasTop, "#ffffff", 0.09) : mix(p.canvasTop, "#ffffff", 0.9);
  const inkBase = dark ? (luminance(p.onPanel) > 0.3 ? p.onPanel : "#f2f2f2") : p.panel;
  const far = dark ? "#ffffff" : "#000000";
  const ink = push(inkBase, card, 7, far);
  const gold = push(p.accent, card, 3, far);
  const onGold = contrast("#ffffff", gold) >= contrast("#111111", gold) ? "#ffffff" : "#111111";
  const alpha = (h: string, a: number) => `${h}${Math.round(a * 255).toString(16).padStart(2, "0")}`;
  const roles: Record<string, string> = {
    "color-scheme": dark ? "dark" : "light",
    "--ground": ground,
    "--ground-2": p.canvasTop,
    "--dot": alpha(p.accent, 0.09),
    "--card": card,
    "--card-2": card2,
    "--sunk": mix(ground, dark ? "#000000" : p.panel, 0.06),
    "--edge": alpha(ink, 0.08),
    "--edge-2": alpha(ink, 0.16),
    "--ink": ink,
    "--ink-2": push(mix(ink, card, 0.3), card, 4.5, ink),
    "--ink-3": push(mix(ink, card, 0.48), card, 3, ink),
    "--gold": gold,
    "--gold-soft": alpha(gold, 0.16),
    "--on-gold": onGold,
    "--maroon": p.accent,
    "--maroon-2": mix(p.accent, far, 0.15),
    "--good": dark ? "#58c792" : "#1e7249",
    "--bad": dark ? "#f07a6e" : "#b42318",
    "--island": dark ? mix(p.panel, "#000000", 0.3) : p.panel,
    "--shadow": dark ? "0 10px 30px rgba(0,0,0,.4)" : "0 10px 30px rgba(40,30,30,.12)",
  };
  p.subjects.forEach((s, i) => (roles[`--s${i + 1}`] = push(s, card, 3, far)));
  return roles;
}

export function applyRoom(id: string) {
  const root = document.documentElement;
  const palette = PALETTES[id];
  for (const k of [...root.style]) if (k.startsWith("--") || k === "color-scheme") root.style.removeProperty(k);
  root.dataset.room = palette ? "derived" : id;
  if (palette) for (const [k, v] of Object.entries(derive(palette))) root.style.setProperty(k, v);
}
