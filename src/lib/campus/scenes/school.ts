// Another school in the hub: a generic campus in that school's accent, its
// portal motif as a crest over the gate. No school's real buildings are claimed.
import type { SceneDef } from "../paint";
import { BASE, GROUND, ROAD, building, gate, ridge, street, tree } from "./kit";

export interface SchoolLook {
  id: string;
  /** The short name on the gate. */
  name: string;
  accent: string;
  ramp: string[];
  motif: "swirl" | "ripple" | "bloom" | "rain" | "lattice" | "aurora";
}

/** 7x7 crests, one per portal motif. */
export const MOTIFS: Record<SchoolLook["motif"], string[]> = {
  swirl: ["..###..", ".#...#.", "#..##.#", "#.#..##", "#.#....", ".#.#...", "..#...."],
  ripple: ["...#...", "..#.#..", ".#.#.#.", "#.#.#.#", ".#.#.#.", "..#.#..", "...#..."],
  bloom: ["...#...", ".#.#.#.", "..###..", "###.###", "..###..", ".#.#.#.", "...#..."],
  rain: ["#...#..", "..#...#", "#...#..", "..#...#", "#...#..", "..#...#", "#...#.."],
  lattice: ["#.#.#.#", ".#...#.", "#.#.#.#", "...#...", "#.#.#.#", ".#...#.", "#.#.#.#"],
  aurora: [".......", "##.....", "..##...", "....###", "##.....", "..###..", ".....##"],
};

const luminance = (h: string) => {
  const [r, g, b] = [1, 3, 5].map((i) => parseInt(h.slice(i, i + 2), 16) / 255);
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
};

export function school(look: SchoolLook): SceneDef {
  const accent = /^#[0-9a-f]{6}$/i.test(look.accent) ? look.accent : "#e8b04a";
  const deep = look.ramp.find((c) => /^#[0-9a-f]{6}$/i.test(c) && luminance(c) < 0.35) ?? "#3b1220";
  const sign = look.name.toUpperCase().replace(/[^A-Z0-9 .-]/g, "").slice(0, 12) || "CAMPUS";
  return {
    id: `school-${look.id}`,
    label: look.name,
    road: ROAD,
    palette: {
      ...BASE,
      accent: { c: accent, k: 0.45 },
      deep: { c: deep, k: 0.55 },
      ink: { c: luminance(accent) > 0.55 ? "#241a14" : "#f4efe4", k: 0.3 },
      hill: { c: "#3d6a45", k: 0.4, far: 0.35 },
      hillFar: { c: "#4c6f6a", k: 0.35, far: 0.55 },
    },
    draw(p) {
      ridge(p, "hillFar", [0, 42, 40, 36, 90, 41, 140, 34, 192, 40], 58);
      ridge(p, "hill", [0, 52, 60, 47, 120, 51, 192, 46], 60);
      building(p, 104, GROUND, 70, 3, "gable", { band: "accent", roofC: "deep", trim: "accent" });
      tree(p, 92, GROUND, 10, 13);
      tree(p, 178, GROUND, 12, 15);
      tree(p, 4, GROUND, 10, 12);
      const g = gate(p, 54, GROUND, sign, "accent", "ink");
      MOTIFS[look.motif].forEach((row, y) => [...row].forEach((ch, x) => ch === "#" && p.rect("accent", g.x + Math.floor(g.w / 2) - 3 + x, GROUND - 31 + y, 1, 1)));
      street(p);
    },
  };
}
