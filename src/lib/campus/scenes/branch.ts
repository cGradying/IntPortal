// The shared branch scene: a PUP gate with the campus's name, a 2-3 storey
// banded building and the campus's own backdrop. Backdrops follow the place's
// geography (docs/specs/reference/campus-looks.md); nothing here claims a
// building's exact look.
import type { Paint, Painter, SceneDef } from "../paint";
import { textWidth } from "../paint";
import { BASE, GROUND, ROAD, building, gate, palm, ridge, skyline, street, tree } from "./kit";

type Back = "fields" | "hills" | "sea" | "lake" | "city" | "town";
interface Branch {
  back: Back;
  /** A lone volcano or peak behind the fields: its x and height. */
  peak?: [number, number];
  storeys: number;
  roof: "gable" | "flat";
  /** What the gate says, when it isn't the campus name. */
  sign?: string;
  palms?: boolean;
}

export const BRANCHES: Record<string, Branch> = {
  Pulilan: { back: "fields", storeys: 2, roof: "flat" },
  "Sta. Maria": { back: "hills", storeys: 3, roof: "gable" },
  // Mt Arayat rises alone over the Nueva Ecija plain.
  Cabiao: { back: "fields", peak: [40, 30], storeys: 2, roof: "gable" },
  Maragondon: { back: "hills", storeys: 2, roof: "gable" },
  Alfonso: { back: "hills", storeys: 3, roof: "gable" },
  Biñan: { back: "city", storeys: 3, roof: "flat" },
  Calauan: { back: "fields", peak: [150, 24], storeys: 2, roof: "gable", palms: true },
  "San Pedro": { back: "city", storeys: 3, roof: "flat" },
  "Sta. Rosa": { back: "city", storeys: 3, roof: "flat", sign: "STA. ROSA" },
  Talisay: { back: "lake", storeys: 2, roof: "gable", palms: true },
  Mulanay: { back: "sea", storeys: 2, roof: "gable", palms: true },
  Lopez: { back: "town", storeys: 3, roof: "gable", palms: true },
  Unisan: { back: "sea", storeys: 2, roof: "gable", palms: true },
  Bansud: { back: "hills", peak: [36, 34], storeys: 3, roof: "gable", palms: true },
  Sablayan: { back: "sea", storeys: 2, roof: "gable", palms: true },
  Leyte: { back: "town", storeys: 2, roof: "gable", palms: true },
};

const PALETTE: Record<string, Paint> = {
  ...BASE,
  paddy: { c: "#5d8a3e", k: 0.6, far: 0.15 },
  paddyHi: { c: "#7aa24a", k: 0.6, far: 0.15 },
  hill: { c: "#3d6a45", k: 0.4, far: 0.35 },
  hillFar: { c: "#4c6f6a", k: 0.35, far: 0.55 },
  peak: { c: "#3f5f5a", k: 0.35, far: 0.5 },
  sea: { c: "#2f6a8a", k: 0.55, far: 0.2 },
  roofs: { c: "#7d4a3a", k: 0.55 },
  house: { c: "#cbbfa5", k: 0.55 },
};

function backdrop(p: Painter, b: Branch) {
  if (b.peak) {
    const [x, h] = b.peak;
    ridge(p, "peak", [x - 34, 58, x - 8, 58 - h + 4, x - 2, 58 - h, x + 4, 58 - h + 2, x + 34, 58], 58);
  }
  switch (b.back) {
    case "fields":
      ridge(p, "hillFar", [0, 54, 40, 52, 90, 54, 150, 51, 192, 53], 58);
      for (let y = 56; y < GROUND; y += 2) p.rect(y % 4 === 0 ? "paddy" : "paddyHi", 0, y, 192, 2);
      break;
    case "hills":
      ridge(p, "hillFar", [0, 40, 30, 32, 62, 38, 100, 30, 140, 37, 170, 33, 192, 38], 58);
      ridge(p, "hill", [0, 50, 40, 44, 80, 50, 130, 45, 192, 50], 60);
      break;
    case "sea":
    case "lake":
      p.water("sea", 0, 48, 192, 12);
      if (b.back === "lake") {
        // A ridge on the far shore and a small volcano island in the water.
        ridge(p, "hillFar", [0, 40, 50, 36, 110, 38, 192, 41], 48);
        p.poly("peak", [2, 53, 10, 47, 14, 46, 18, 47, 26, 53]);
      } else p.rect("hillFar", 0, 47, 192, 1);
      break;
    case "city":
      skyline(p, 29, 0, 192, 58, 14);
      break;
    case "town":
      ridge(p, "hillFar", [0, 46, 60, 42, 130, 45, 192, 41], 58);
      for (let x = 0; x < 192; x += 22) {
        p.rect("house", x + 2, 54, 12, 6);
        p.poly("roofs", [x, 54, x + 8, 49, x + 16, 54]);
      }
      break;
  }
}

export function branch(name: string): SceneDef {
  const b = BRANCHES[name] ?? { back: "town", storeys: 2, roof: "gable" };
  return {
    id: `branch-${name.normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/-$/, "")}`,
    label: `PUP ${name}`,
    road: ROAD,
    palette: PALETTE,
    draw(p) {
      backdrop(p, b);
      building(p, 104, GROUND, 70, b.storeys, b.roof);
      if (b.palms) {
        palm(p, 98, GROUND, 24);
        palm(p, 184, GROUND, 20);
      } else {
        tree(p, 92, GROUND, 10, 13);
        tree(p, 178, GROUND, 12, 15);
      }
      if (b.back !== "lake") tree(p, 6, GROUND, 10, 12);
      // The perimeter wall, open at the gate.
      const label = `PUP ${b.sign ?? name}`;
      const gw = textWidth(label) + 6;
      const gx = Math.round(54 - gw / 2);
      for (const [x0, x1] of [[0, gx], [gx + gw, 104]]) {
        p.rect("wallSh", x0, GROUND - 5, x1 - x0, 5);
        p.rect("wall", x0, GROUND - 5, x1 - x0, 1);
      }
      gate(p, 54, GROUND, label);
      street(p);
    },
  };
}
