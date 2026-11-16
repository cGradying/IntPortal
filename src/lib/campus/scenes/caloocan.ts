// PUP Caloocan, Deparo, North Caloocan: a new six-storey building (Inquirer and
// Manila Bulletin on the 2023 groundbreaking) among row houses. Its finished
// facade is not confirmed, so it is drawn plain: white floors, grey fins.
import type { SceneDef } from "../paint";
import { BASE, GROUND, ROAD, gate, street, tree, wires } from "./kit";

const scene: SceneDef = {
  id: "caloocan",
  label: "PUP Caloocan",
  road: ROAD,
  palette: {
    ...BASE,
    face: { c: "#eceae4", k: 0.55 },
    fin: { c: "#9a9ea3", k: 0.5 },
    house: { c: "#cbbfa5", k: 0.55 },
    house2: { c: "#d6c8a2", k: 0.55 },
    roof: { c: "#6f4a3c", k: 0.55 },
    roof2: { c: "#43606f", k: 0.5 },
  },
  draw(p) {
    const fh = 6;
    const top = GROUND - 6 * fh;
    p.rect("face", 70, top, 72, 6 * fh);
    for (let f = 0; f < 6; f++) p.windows("glass", 72, top + f * fh + 2, 14, 1, 5, 0, 3, 3);
    for (let x = 70; x <= 140; x += 5) p.rect("fin", x, top, 1, 6 * fh);
    p.rect("maroon", 69, top - 2, 74, 2);
    p.rect("glass", 101, GROUND - 6, 10, 6);
    // Row houses down the street.
    for (let x = 146; x < 190; x += 15) {
      p.rect(x % 2 ? "house" : "house2", x, GROUND - 13, 13, 13);
      p.rect(x % 2 ? "roof" : "roof2", x - 1, GROUND - 15, 15, 2);
      p.windows("glass", x + 2, GROUND - 10, 2, 1, 5, 0, 3, 2);
    }
    tree(p, 2, GROUND, 11, 14);
    wires(p, 144, 190, GROUND);
    gate(p, 40, GROUND, "PUP CALOOCAN");
    street(p);
  },
};

export default scene;
