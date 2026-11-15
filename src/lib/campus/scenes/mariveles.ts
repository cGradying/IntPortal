// PUP Bataan, in the Freeport Area of Bataan, Mariveles (pup.edu.ph). Mt
// Mariveles, Bataan's highest peak, stands over the town and the bay at its
// southern foot (Wikipedia, geography). The building is the shared kit's.
import type { SceneDef } from "../paint";
import { BASE, GROUND, ROAD, building, gate, ridge, street, tree } from "./kit";

const scene: SceneDef = {
  id: "mariveles",
  label: "PUP Bataan, Mariveles",
  road: ROAD,
  palette: {
    ...BASE,
    mountain: { c: "#2f5a46", k: 0.35, far: 0.42 },
    bay: { c: "#2f6a8a", k: 0.55, far: 0.2 },
    shed: { c: "#8d949b", k: 0.5 },
    shedDk: { c: "#6c737a", k: 0.5 },
  },
  draw(p) {
    ridge(p, "mountain", [0, 52, 26, 38, 50, 26, 62, 19, 68, 22, 74, 16, 80, 20, 88, 18, 104, 28, 132, 40, 170, 50, 192, 54], 60);
    p.water("bay", 128, 52, 64, 8);
    // Freeport sheds.
    p.rect("shed", 0, GROUND - 10, 34, 10);
    p.rect("shedDk", 0, GROUND - 12, 36, 2);
    p.rect("shedDk", 4, GROUND - 6, 8, 6);
    building(p, 110, GROUND, 66, 3, "gable");
    tree(p, 96, GROUND, 10, 13);
    tree(p, 180, GROUND, 11, 14);
    gate(p, 66, GROUND, "PUP BATAAN");
    street(p);
  },
};

export default scene;
