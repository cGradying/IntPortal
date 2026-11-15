// PUP Quezon City, Commonwealth. From the campus photo on
// pup.edu.ph/quezoncity: a small three-slab PUP pylon under a heavy canopy of
// trees, the buildings mostly hidden behind it.
import type { SceneDef } from "../paint";
import { BASE, GROUND, ROAD, street, tree } from "./kit";

const scene: SceneDef = {
  id: "quezon-city",
  label: "PUP Quezon City",
  road: ROAD,
  palette: {
    ...BASE,
    pylon: { c: "#d9d7cf", k: 0.5 },
    pylonSh: { c: "#adaaa1", k: 0.5 },
    letter: { c: "#4a3428", k: 0.3 },
    plinth: { c: "#8a4a3a", k: 0.55 },
  },
  draw(p) {
    // The buildings, behind the trees.
    p.rect("wall", 40, GROUND - 22, 112, 22);
    for (let f = 0; f < 3; f++) {
      p.rect("maroon", 40, GROUND - 22 + f * 7, 112, 1);
      p.windows("glass", 43, GROUND - 19 + f * 7, 22, 1, 5, 0, 3, 3);
    }
    p.rect("roofRed", 38, GROUND - 25, 116, 3);
    // The canopy: big trees shoulder to shoulder.
    for (const [x, w, h] of [[0, 16, 30], [14, 18, 36], [30, 14, 27], [118, 16, 32], [132, 20, 38], [150, 16, 30], [166, 18, 34], [182, 10, 24]]) tree(p, x, GROUND, w, h);
    for (const [x, w, h] of [[52, 12, 22], [66, 14, 26], [104, 12, 24]]) tree(p, x, GROUND, w, h);
    // The pylon, small, lettered P-U-P.
    const slab = (x: number, y: number, ch: string) => {
      p.rect("pylon", x, y, 5, GROUND - 2 - y);
      p.rect("pylonSh", x + 4, y, 1, GROUND - 2 - y);
      p.text("letter", x + 1, y + 2, ch);
    };
    slab(84, 44, "P");
    slab(90, 41, "U");
    slab(96, 43, "P");
    p.rect("plinth", 82, GROUND - 2, 21, 2);
    street(p);
  },
};

export default scene;
