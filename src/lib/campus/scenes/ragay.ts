// PUP Ragay, Camarines Sur: "atop a hill overlooking the municipality of Ragay"
// (pup.edu.ph/about/campuses). The building is the white four-storey block on
// pup.edu.ph/ragay; Ragay Gulf lies below the town (Wikipedia, geography).
import type { SceneDef } from "../paint";
import { BASE, GROUND, ROAD, palm, ridge, street, tree } from "./kit";

const scene: SceneDef = {
  id: "ragay",
  label: "PUP Ragay",
  road: ROAD,
  palette: {
    ...BASE,
    gulf: { c: "#2f6a8a", k: 0.55, far: 0.25 },
    shore: { c: "#4c6f6a", k: 0.35, far: 0.55 },
    hill: { c: "#3d7040", k: 0.55 },
    hillDk: { c: "#2f5a34", k: 0.55 },
    path: { c: "#9c8f74", k: 0.55 },
    face: { c: "#f0eee8", k: 0.55 },
    band: { c: "#9ea3a6", k: 0.5 },
    house: { c: "#cbbfa5", k: 0.55 },
    roofs: { c: "#7d4a3a", k: 0.55 },
    flagBlue: { c: "#1d3f8f", k: 0.4 },
    flagRed: { c: "#c3262f", k: 0.4 },
    flagWhite: { c: "#f2efe6", k: 0.4 },
  },
  draw(p) {
    p.water("gulf", 0, 44, 192, 16);
    ridge(p, "shore", [0, 43, 30, 40, 70, 42, 110, 39, 192, 43], 44);
    // The hill, the campus on its crown.
    p.poly("hill", [40, GROUND, 82, 40, 100, 34, 192, 34, 192, GROUND]);
    p.poly("hillDk", [40, GROUND, 82, 40, 88, 40, 60, GROUND]);
    // The drive winding up to the campus.
    for (const [x, y, w] of [[150, 60, 30], [176, 56, 4], [120, 52, 60], [116, 48, 4], [116, 44, 50], [162, 40, 4], [112, 36, 54]]) p.rect("path", x, y, w, 1);
    for (const [x, y] of [[86, 46], [100, 44], [132, 54], [96, 58], [172, 46]]) {
      p.rect("hillDk", x, y, 6, 3);
      p.rect("leafHi", x + 1, y, 2, 1);
    }
    const top = 34 - 4 * 6;
    p.rect("face", 112, top, 64, 24);
    for (let f = 0; f < 4; f++) {
      p.rect("band", 112, top + f * 6, 64, 1);
      p.windows("glass", 115, top + f * 6 + 2, 12, 1, 5, 0, 3, 3);
    }
    p.rect("band", 111, top - 1, 66, 1);
    p.rect("flagWhite", 104, top - 4, 1, 28);
    p.rect("flagBlue", 105, top - 4, 5, 1);
    p.rect("flagWhite", 105, top - 3, 1, 1);
    p.rect("flagRed", 105, top - 2, 5, 1);
    p.rect("flagRed", 106, top - 3, 4, 1);
    for (const x of [92, 180]) tree(p, x, 34, 9, 10);
    // The town at the foot of the hill.
    for (let x = 0; x < 60; x += 15) {
      p.rect("house", x + 1, GROUND - 7, 11, 7);
      p.poly("roofs", [x, GROUND - 7, x + 6, GROUND - 11, x + 13, GROUND - 7]);
    }
    palm(p, 64, GROUND, 18);
    street(p);
  },
};

export default scene;
