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
    building(p, 4, GROUND, 58, 4, "flat");
    building(p, 114, GROUND, 72, 3, "gable");
    // Zonta Park's trees, either side of the gate.
    for (const [x, w, h] of [[64, 7, 11], [104, 8, 12], [184, 7, 10]]) tree(p, x, GROUND, w, h);
    gate(p, 88, GROUND, "PUP TAGUIG");
    street(p);
  },
};

export default scene;
