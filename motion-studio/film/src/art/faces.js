// Pixel student faces for the Face ID ending: 20x24 portraits built from
// traits (skin, hair style and colour, glasses, hijab, cap, shirt) so every
// person reads as a different person. Outlined, 2-tone shading, no smoothing.
const W = 20, H = 24;
export const SKIN = [["#f6d3b3", "#dcae8a"], ["#e8b98f", "#c9936a"], ["#d19a6a", "#b07a4e"], ["#b0784a", "#8d5b34"], ["#8a5a36", "#6a4126"], ["#5e3a22", "#472a17"]];

export const PEOPLE = [
  { skin: 1, hair: "short", hc: "#1c1414", glasses: "#2a2a33", shirt: "#7a1128", name: "Migs" },
  { skin: 2, hair: "long", hc: "#140e0e", shirt: "#f5b227", blush: 1, name: "Aya" },
  { skin: 4, hair: "curly", hc: "#1a1210", shirt: "#2f9e8f", name: "Jun" },
  { skin: 2, hair: "hijab", hc: "#2f7d57", shirt: "#2f7d57", name: "Noor" },
  { skin: 3, hair: "cap", hc: "#241814", cap: "#3b6fd4", shirt: "#e4e4ea", name: "Paolo" },
  { skin: 5, hair: "braids", hc: "#120c0c", shirt: "#8663a8", blush: 1, name: "Tala" },
  { skin: 0, hair: "bun", hc: "#3a261c", glasses: "#b87a10", shirt: "#c2403a", name: "Bea" },
  { skin: 3, hair: "buzz", hc: "#2a1e18", shirt: "#44464f", name: "Rafa" },
  { skin: 0, hair: "bob", hc: "#c05bb5", shirt: "#1f2a44", blush: 1, name: "Kim" },
  { skin: 2, hair: "pony", hc: "#2b1a12", shirt: "#e0697e", earring: "#f5b227", name: "Lia" },
];

function face(p) {
  const g = Array.from({ length: H }, () => Array(W).fill(null));
  const [sk, sk2] = SKIN[p.skin];
  const set = (x, y, c) => { if (x >= 0 && x < W && y >= 0 && y < H) g[y][x] = c; };
  const inHead = (x, y) => ((x - 9.5) / 6.3) ** 2 + ((y - 11.5) / 7.6) ** 2 <= 1;
  // shoulders + neck
  for (let y = 19; y < H; y++) for (let x = 0; x < W; x++) {
    const w = 4 + (y - 19) * 2.2;
    if (Math.abs(x - 9.5) <= w) set(x, y, p.shirt);
  }
  for (let y = 17; y < 21; y++) for (let x = 8; x <= 11; x++) set(x, y, sk2);
  // head
  for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) if (inHead(x, y)) set(x, y, x > 12 ? sk2 : sk);
  // hair
  const hair = (x, y) => set(x, y, p.hc);
  const top = (limit) => { for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) if (((x - 9.5) / 7.1) ** 2 + ((y - 10.5) / 8.2) ** 2 <= 1 && y < limit(x)) hair(x, y); };
  const brow = 9;
  if (p.hair === "hijab") {
    for (let y = 0; y < 22; y++) for (let x = 0; x < W; x++) {
      const outer = ((x - 9.5) / 8.4) ** 2 + ((y - 12) / 9.6) ** 2 <= 1;
      const opening = ((x - 9.5) / 4.6) ** 2 + ((y - 12.5) / 5.6) ** 2 <= 1;
      if (outer && !opening) set(x, y, (x + y) % 5 === 0 ? "#276a49" : p.hc);
    }
  } else {
    if (p.hair === "buzz") top(() => 6);
    else top((x) => (x < 4 || x > 15 ? 13 : 7 - (x > 9 && x < 13 ? 1 : 0)));
    if (p.hair === "long" || p.hair === "braids") for (let y = 7; y < 22; y++) { for (const x of [2, 3, 16, 17]) hair(x, y); }
    if (p.hair === "braids") for (let y = 12; y < 23; y += 2) { set(2, y, "#3a2a2a"); set(17, y, "#3a2a2a"); }
    if (p.hair === "bob") for (let y = 7; y < 16; y++) { for (const x of [2, 3, 16, 17]) hair(x, y); }
    if (p.hair === "bun") for (let y = 0; y < 4; y++) for (let x = 7; x < 13; x++) if (((x - 9.5) / 2.6) ** 2 + ((y - 1.8) / 2) ** 2 <= 1) hair(x, y);
    if (p.hair === "pony") for (let y = 6; y < 18; y++) { hair(17, y); if (y > 8 && y < 15) hair(18, y); }
    if (p.hair === "curly") for (let k = 0; k < 16; k++) { const a = (k / 16) * Math.PI - Math.PI; const x = Math.round(9.5 + Math.cos(a) * 7.6), y = Math.round(9 + Math.sin(a) * 8.4); hair(x, y); hair(x, y + 1); if (k % 2) hair(x + (x < 10 ? -1 : 1), y + 1); }
    if (p.hair === "cap") {
      for (let y = 1; y < 7; y++) for (let x = 3; x < 17; x++) if (((x - 9.5) / 7) ** 2 + ((y - 7) / 6) ** 2 <= 1) set(x, y, p.cap);
      for (let x = 0; x < 11; x++) set(x, 7, p.cap);
      set(9, 1, "#fff");
    }
  }
  // features
  const ey = 12;
  for (const x of [6, 12]) { set(x, ey, "#1a1216"); set(x + 1, ey, "#1a1216"); set(x, ey - 1, "#1a1216"); set(x + 1, ey - 1, "#fff"); }
  if (p.hair !== "hijab" || true) { set(6, brow + 0, p.hair === "hijab" ? "#1a1216" : p.hc); set(7, brow, p.hair === "hijab" ? "#1a1216" : p.hc); set(12, brow, p.hair === "hijab" ? "#1a1216" : p.hc); set(13, brow, p.hair === "hijab" ? "#1a1216" : p.hc); }
  if (p.glasses) {
    for (const x0 of [5, 11]) { for (let x = x0; x < x0 + 4; x++) { set(x, ey - 2, p.glasses); set(x, ey + 1, p.glasses); } set(x0, ey - 1, p.glasses); set(x0, ey, p.glasses); set(x0 + 3, ey - 1, p.glasses); set(x0 + 3, ey, p.glasses); }
    set(9, ey - 1, p.glasses); set(10, ey - 1, p.glasses);
  }
  set(9, 14, sk2); // nose
  for (const [x, y] of [[8, 16], [9, 17], [10, 17], [11, 16]]) set(x, y, "#7a2c2c");
  if (p.blush) { set(5, 14, "#f08a8a"); set(14, 14, "#f08a8a"); }
  if (p.earring) { set(3, 15, p.earring); set(16, 15, p.earring); }
  // outline
  const out = g.map((r) => r.slice());
  for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
    if (g[y][x]) continue;
    if ([[1, 0], [-1, 0], [0, 1], [0, -1]].some(([a, b]) => g[y + b]?.[x + a])) out[y][x] = "#140d14";
  }
  return out;
}

/** A 20x24 canvas for person i (drawn once). */
export function faceCanvas(i) {
  const c = document.createElement("canvas");
  c.width = W; c.height = H;
  c.className = "px";
  const x = c.getContext("2d");
  face(PEOPLE[i % PEOPLE.length]).forEach((row, y) => row.forEach((col, xx) => { if (col) { x.fillStyle = col; x.fillRect(xx, y, 1, 1); } }));
  return c;
}
export const FACE_W = W, FACE_H = H;
