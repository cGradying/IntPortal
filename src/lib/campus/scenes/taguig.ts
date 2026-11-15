// PUP Taguig, Lower Bicutan: a ten-hectare campus on Gen. Santos Avenue with
// Building A (Marichu Tiñga) and the Cayetano Building around Zonta Park
// (pup.edu.ph/taguig, Wikipedia). The buildings' faces are not confirmed, so
// they are the shared kit's; the park and the spread are what's drawn.
import type { SceneDef } from "../paint";
import { BASE, GROUND, ROAD, building, gate, ridge, street, tree } from "./kit";

const scene: SceneDef = {
  id: "taguig",
  label: "PUP Taguig",
  road: ROAD,
  palette: { ...BASE, hillFar: { c: "#4c6f6a", k: 0.35, far: 0.6 } },
  draw(p) {
    ridge(p, "hillFar", [0, 50, 50, 47, 110, 50, 192, 46], 58);
    building(p, 16, GROUND, 62, 4, "flat");
    building(p, 112, GROUND, 74, 3, "gable");
    // Zonta Park's trees across the front.
    for (const [x, w, h] of [[2, 10, 12], [80, 12, 15], [94, 10, 12], [150, 9, 11], [180, 11, 14]]) tree(p, x, GROUND, w, h);
    gate(p, 64, GROUND, "PUP TAGUIG");
    street(p);
  },
};

export default scene;
