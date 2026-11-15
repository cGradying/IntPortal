// The shared kit: the street every scene stands on, trees, hills, the PUP
// gate and a 2-3 storey branch building (verified against PUP Sto. Tomas's
// gate: two white pillars under a maroon beam with white letters).
import type { Paint, Painter } from "../paint";
import { textWidth } from "../paint";

/** Ground line: buildings stand on it, the sidewalk starts here. */
export const GROUND = 64;
/** The jeepney's lane. */
export const ROAD = 71;

export const BASE: Record<string, Paint> = {
  road: { c: "#2e2e33", k: 0.3 },
  roadLine: { c: "#b9a86a", k: 0.4 },
  curb: "#8a8074",
  grass: "#3c6b3a",
  trunk: "#4a3222",
  leaf: "#2f6b3a",
  leafHi: "#3f8a4a",
  leafDk: "#24502d",
  maroon: { c: "#7a1128", k: 0.55 },
  gold: { c: "#e0b03a", k: 0.35 },
  white: { c: "#e9e4d6", k: 0.5 },
  wall: { c: "#ece6d8", k: 0.55 },
  wallSh: { c: "#cfc6b2", k: 0.55 },
  glass: { c: "#2a0a10", k: 0.3 },
  roofRed: { c: "#8b2b38", k: 0.55 },
  roofSlate: { c: "#4a4d55", k: 0.5 },
  far: { c: "#22202e", k: 0.3, far: 0.5 },
  farHi: { c: "#2e3a40", k: 0.3, far: 0.38 },
  pole: { c: "#5b5650", k: 0.4 },
  wire: { c: "#2b2a2e", k: 0.2 },
  lampHead: { c: "#d6d0bd", k: 0.5 },
};

/** Sidewalk, grass verge and the road with its lane line. */
export function street(p: Painter, walk = "curb") {
  p.rect(walk, 0, GROUND, 192, 3);
  p.rect("grass", 0, GROUND + 3, 192, 3);
  p.rect("road", 0, GROUND + 6, 192, 10);
  for (let x = 0; x < 192; x += 12) p.rect("roadLine", x, 78, 6, 1);
}

/** A broad tree on `ground`: a canopy `w` wide that grows with its height `h`. */
export function tree(p: Painter, x: number, ground: number, w = 10, h = 10) {
  const crown = Math.max(6, Math.round(h * 0.6));
  const top = ground - h;
  p.rect("trunk", x + Math.floor(w / 2) - 1, top + crown - 1, 2, h - crown + 1);
  p.rect("leaf", x + 2, top, w - 4, 1);
  p.rect("leaf", x, top + 1, w, crown - 2);
  p.rect("leafHi", x + 2, top, Math.max(2, Math.floor(w / 3)), 1);
  p.rect("leafHi", x + 1, top + 1, Math.max(2, Math.floor(w / 4)), 1);
  p.rect("leafDk", x + 1, top + crown - 1, w - 2, 1);
  if (crown > 9) p.rect("leafDk", x + Math.floor(w / 2), top + 3, Math.floor(w / 2) - 1, crown - 5);
}

/** A coconut palm. */
export function palm(p: Painter, x: number, ground: number, h = 22) {
  const top = ground - h;
  p.rect("trunk", x, top + 2, 1, h - 2);
  p.rect("leaf", x - 4, top + 1, 9, 1);
  p.rect("leaf", x - 5, top + 2, 2, 1);
  p.rect("leaf", x + 4, top + 2, 2, 1);
  p.rect("leafHi", x - 2, top, 5, 1);
  p.rect("leaf", x - 6, top + 3, 1, 1);
  p.rect("leaf", x + 6, top + 3, 1, 1);
}

/** A street lamp; its head lights at night. */
export function lamp(p: Painter, x: number, ground: number) {
  p.rect("pole", x, ground - 12, 1, 12);
  p.rect("pole", x, ground - 12, 3, 1);
  p.lamp("lampHead", x + 2, ground - 11, 2, 1);
}

/** A utility pole with its sagging wire to `to`. */
export function wires(p: Painter, x: number, to: number, ground: number) {
  p.rect("pole", x, ground - 20, 1, 20);
  p.rect("pole", x - 2, ground - 19, 5, 1);
  for (let i = x + 1; i < to; i++) {
    const t = (i - x) / (to - x);
    p.rect("wire", i, ground - 19 + Math.round(Math.sin(t * Math.PI) * 3), 1, 1);
  }
}

/** A far skyline of towers, tinted by the horizon; a few windows light at night. */
export function skyline(p: Painter, seed: number, from = 0, to = 192, base = 58, tall = 18) {
  let s = seed;
  const rnd = () => (s = (s * 16807) % 2147483647) / 2147483647;
  for (let x = from; x < to; ) {
    const w = Math.min(to - x, 5 + Math.floor(rnd() * 8));
    const h = 4 + Math.floor(rnd() * tall);
    p.rect("far", x, base - h, w, h);
    if (w > 3 && h > 6 && rnd() < 0.5) p.lamp("far", x + 2, base - h + 3, 1, 1);
    x += w + (rnd() < 0.3 ? 2 : 0);
  }
}

/** A ridge line across the frame: `pts` are x, y pairs of its top, filled down to `base`. */
export function ridge(p: Painter, c: string, pts: number[], base = 60) {
  p.poly(c, [pts[0], base, ...pts, pts[pts.length - 2], base]);
}

/** The PUP gate: two white pillars under a maroon beam with the campus in white. */
export function gate(p: Painter, cx: number, ground: number, label: string, beam = "maroon", ink = "white", pillar = "white") {
  const w = textWidth(label) + 6;
  const x = Math.round(cx - w / 2);
  const top = ground - 22;
  p.rect(pillar, x, top, 3, 22);
  p.rect(pillar, x + w - 3, top, 3, 22);
  p.rect("wallSh", x + 2, top + 9, 1, 13);
  p.rect("wallSh", x + w - 1, top + 9, 1, 13);
  p.rect(beam, x, top + 1, w, 7);
  p.text(ink, x + 3, top + 2, label);
  // The gate's leaves, open.
  for (let i = x + 4; i < x + 9; i += 2) p.rect("pole", i, ground - 9, 1, 9);
  for (let i = x + w - 5; i > x + w - 10; i -= 2) p.rect("pole", i, ground - 9, 1, 9);
  p.rect("pole", x + 3, ground - 9, 6, 1);
  p.rect("pole", x + w - 9, ground - 9, 6, 1);
  return { x, w };
}

/** A branch building: `storeys` floors of maroon-banded corridors, windows, a roof. */
export function building(p: Painter, x: number, ground: number, w: number, storeys: number, roof: "gable" | "flat" = "gable", o: { band?: string; trim?: string; roofC?: string } = {}) {
  const band = o.band ?? "maroon";
  const fh = 7;
  const top = ground - storeys * fh;
  p.rect("wall", x, top, w, storeys * fh);
  p.rect("wallSh", x + w - 2, top, 2, storeys * fh);
  for (let s = 0; s < storeys; s++) {
    const fy = top + s * fh;
    p.rect(band, x, fy, w, 1);
    p.windows("glass", x + 3, fy + 3, Math.floor((w - 6) / 5), 1, 5, 0, 3, 3);
  }
  p.rect(o.trim ?? "gold", x, ground - 1, w, 1);
  p.rect("glass", x + Math.floor(w / 2) - 2, ground - 5, 4, 5);
  if (roof === "gable") p.poly(o.roofC ?? "roofRed", [x - 2, top, x + w / 2, top - 7, x + w + 2, top]);
  else p.rect(o.roofC ?? band, x - 1, top - 2, w + 2, 2);
  return top;
}
