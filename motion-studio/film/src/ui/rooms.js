// The app's 15 rooms (themes) — a port of intportal-app/src/lib/rooms.ts:
// three hand-tuned rooms from app.css plus the legacy palettes run through
// the same derive() contrast clamps. Each room is a map of CSS roles.
const hex = (h) => [1, 3, 5].map((i) => parseInt(h.slice(i, i + 2), 16));
const toHex = (c) => "#" + c.map((v) => Math.round(v).toString(16).padStart(2, "0")).join("");
const mix = (a, b, t) => toHex(hex(a).map((v, i) => v + (hex(b)[i] - v) * t));
function lum(h) {
  const [r, g, b] = hex(h).map((v) => { const s = v / 255; return s <= 0.03928 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4; });
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}
const contrast = (a, b) => { const [x, y] = [lum(a), lum(b)].sort((p, q) => q - p); return (x + 0.05) / (y + 0.05); };
function push(fg, bg, ratio, toward) {
  let c = fg;
  for (let i = 1; i <= 20 && contrast(c, bg) < ratio; i++) c = mix(fg, toward, i / 20);
  return c;
}

const NIGHT = { name: "Night", ground: "#19191c", ground2: "#202024", card: "#26262a", card2: "#2d2d32", sunk: "#1f1f23", edge: "rgba(255,255,255,.07)", edge2: "rgba(255,255,255,.13)",
  ink: "#efeff1", ink2: "#a9a9b1", ink3: "#7c7c85", gold: "#f5b227", onGold: "#1b1406", maroon: "#7a1128", good: "#58c792", bad: "#f07a6e", island: "#0e0e10",
  dot: "rgba(245,178,39,.07)", s: ["#e0697e", "#e8866f", "#e0b04a", "#b58ad0", "#5fbf9c", "#7ea3e0"], dark: true };
const DAY = { name: "Day", ground: "#f4f2ef", ground2: "#ebe8e3", card: "#ffffff", card2: "#f8f6f3", sunk: "#efece7", edge: "rgba(28,21,23,.08)", edge2: "rgba(28,21,23,.16)",
  ink: "#1c1517", ink2: "#554c4f", ink3: "#766c6f", gold: "#b8860b", onGold: "#ffffff", maroon: "#6d0e1f", good: "#1e7249", bad: "#b42318", island: "#1c1517",
  dot: "rgba(122,17,40,.07)", s: ["#7a1128", "#b13e34", "#8f6410", "#5c315f", "#2e5a4f", "#3f517a"], dark: false };
const MAROON = { name: "Maroon Night", ground: "#1a0a0e", ground2: "#230d13", card: "#2a1016", card2: "#34141c", sunk: "#200c11", edge: "rgba(255,220,200,.08)", edge2: "rgba(255,220,200,.15)",
  ink: "#f7ecec", ink2: "#ddb9be", ink3: "#a98289", gold: "#f2c14e", onGold: "#2a0d06", maroon: "#6d0e1f", good: "#58c792", bad: "#f07a6e", island: "#0f0507",
  dot: "rgba(245,178,39,.08)", s: ["#e0697e", "#e8866f", "#e0b04a", "#c490d6", "#6fcfa8", "#8fb0e8"], dark: true };

const PALETTES = [
  ["Astra Moon", "#10b981", "#0e1525", "#060c18", "#060a13", "#f1f6fa", ["#10b981", "#06969c", "#51a3ec", "#8b73ec", "#ec9d3e", "#e96983"]],
  ["Sakura", "#e0417e", "#fff7fa", "#fce9f0", "#210816", "#fff7fa", ["#e0417e", "#f16d66", "#8b51a2", "#c9a227", "#378b85", "#343c51"]],
  ["Tokyo Night", "#7aa2f7", "#1a1b26", "#12131b", "#0e0f16", "#c5cae6", ["#7aa2f7", "#bd92f9", "#6ad8ef", "#9dcd6d", "#e09860", "#f7768e"]],
  ["Dracula", "#bd93f9", "#282a36", "#1d1f28", "#14151b", "#f8f8f2", ["#bd93f9", "#ff79c6", "#8be9fd", "#50fa7b", "#ffb86c", "#ff5555"]],
  ["Matrix", "#00ff41", "#0d0f0d", "#000000", "#000000", "#00ff41", ["#00ff41", "#00e5d4", "#ffb000", "#008f11", "#d3d3d3", "#28ad85"]],
  ["PUP Maroon", "#7a1128", "#fcfbfa", "#f2edec", "#140608", "#fcfbfa", ["#7a1128", "#b13e34", "#a37314", "#5c315f", "#2e5a4f", "#3f517a"]],
  ["Nord", "#88c0d0", "#2e3440", "#252933", "#1b1e25", "#eceff4", ["#88c0d0", "#81a1c1", "#5d81ac", "#a3be8c", "#ebcb8b", "#b48ead"]],
  ["Catppuccin", "#cba6f7", "#2e2f40", "#1e1e2e", "#171825", "#cdd6f4", ["#cba6f7", "#f4c2d8", "#92e1fa", "#a6e3a1", "#fab387", "#f38ba8"]],
  ["Gruvbox", "#fabd2f", "#282828", "#1d2021", "#191919", "#ebdbb2", ["#fabd2f", "#b8bb26", "#83a598", "#d3869b", "#fb4934", "#af80ca"]],
  ["Solarized Light", "#268bd2", "#fdf6e3", "#eee8d5", "#073642", "#eee8d5", ["#268bd2", "#849900", "#d53682", "#b58900", "#2aa198", "#6d71c4"]],
  ["One Dark", "#61afef", "#2c2e34", "#212227", "#1b1c20", "#abb2bf", ["#61afef", "#c678dd", "#56b6c2", "#98c379", "#d19a66", "#e06c75"]],
  ["Ivory", "#343c51", "#fdfbf6", "#f6f2ea", "#212125", "#fdfbf6", ["#343c51", "#b46047", "#a37e32", "#734f6a", "#536d4f", "#3e7377"]],
];

function derive([name, accent, top, bottom, panel, onPanel, subjects]) {
  const dark = lum(bottom) < 0.3;
  const card = dark ? mix(top, "#ffffff", 0.05) : mix(top, "#ffffff", 0.7);
  const far = dark ? "#ffffff" : "#000000";
  const inkBase = dark ? (lum(onPanel) > 0.3 ? onPanel : "#f2f2f2") : panel;
  const ink = push(inkBase, card, 7, far);
  const gold = push(accent, card, 3, far);
  const onGold = contrast("#ffffff", gold) >= contrast("#111111", gold) ? "#ffffff" : "#111111";
  const a = (h, x) => `${h}${Math.round(x * 255).toString(16).padStart(2, "0")}`;
  return {
    name, dark, ground: bottom, ground2: top, card, card2: dark ? mix(top, "#ffffff", 0.09) : mix(top, "#ffffff", 0.9),
    sunk: mix(bottom, dark ? "#000000" : panel, 0.06), edge: a(ink, 0.08), edge2: a(ink, 0.16), ink,
    ink2: push(mix(ink, card, 0.3), card, 4.5, ink), ink3: push(mix(ink, card, 0.48), card, 3, ink), gold, onGold,
    maroon: accent, good: dark ? "#58c792" : "#1e7249", bad: dark ? "#f07a6e" : "#b42318",
    island: dark ? mix(panel, "#000000", 0.3) : panel, dot: a(accent, 0.09), s: subjects.map((s) => push(s, card, 3, far)),
  };
}

export const ROOMS = [NIGHT, DAY, MAROON, ...PALETTES.map(derive)];
export const ROOM = Object.fromEntries(ROOMS.map((r) => [r.name, r]));

/** Apply a room as CSS variables on an element. */
export function applyRoom(node, r) {
  const vars = {
    "--ground": r.ground, "--ground2": r.ground2, "--card": r.card, "--card2": r.card2, "--sunk": r.sunk, "--edge": r.edge, "--edge2": r.edge2,
    "--ink": r.ink, "--ink2": r.ink2, "--ink3": r.ink3, "--gold": r.gold, "--on-gold": r.onGold, "--maroon": r.maroon, "--good": r.good,
    "--bad": r.bad, "--island": r.island, "--dot": r.dot,
  };
  r.s.forEach((c, i) => (vars[`--s${i + 1}`] = c));
  for (const k in vars) if (node.style.getPropertyValue(k) !== vars[k]) node.style.setProperty(k, vars[k]);
  node.dataset.room = r.name;
}
