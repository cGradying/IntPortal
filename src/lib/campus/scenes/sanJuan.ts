// PUP San Juan, Addition Hills. From the campus photo on pup.edu.ph/sanjuan: a
// tall building whose two gridded wings meet at a brick-red centre panel with
// the gold PUP star over the name, a glass lobby at its foot, in a dense
// residential street with utility wires.
import type { SceneDef } from "../paint";
import { BASE, GROUND, ROAD, street, tree, wires } from "./kit";

const scene: SceneDef = {
  id: "san-juan",
  label: "PUP San Juan",
  road: ROAD,
  palette: {
    ...BASE,
    face: { c: "#d9d6cd", k: 0.55 },
    pier: { c: "#7a5a46", k: 0.55 },
    slab: { c: "#a9a397", k: 0.55 },
    brick: { c: "#9a553a", k: 0.55 },
    brickDk: { c: "#7b4130", k: 0.55 },
    star: { c: "#f2c14e", k: 0.2 },
    name: { c: "#efe3c6", k: 0.4 },
    lobby: { c: "#5d7f84", k: 0.5 },
    house: { c: "#c9bfa9", k: 0.55 },
    house2: { c: "#b8a98f", k: 0.55 },
    roof: { c: "#6f4a3c", k: 0.55 },
    roof2: { c: "#4f6170", k: 0.5 },
  },
  draw(p) {
    // Neighbours: two-storey houses either side.
    const house = (x: number, w: number, h: number, wall: string, roof: string) => {
      p.rect(wall, x, GROUND - h, w, h);
      p.rect(roof, x - 1, GROUND - h - 2, w + 2, 2);
      p.windows("glass", x + 2, GROUND - h + 3, Math.floor((w - 2) / 5), 1, 5, 0, 3, 2);
    };
    house(1, 16, 14, "house", "roof");
    house(19, 18, 18, "house2", "roof2");
    house(158, 16, 16, "house2", "roof");
    house(176, 15, 12, "house", "roof2");

    // The wings: six floors, a slab line, brown piers, a grid of windows.
    const fh = 7;
    const top = GROUND - 6 * fh;
    for (const [x, w] of [[42, 46], [108, 46]]) {
      p.rect("face", x, top, w, 6 * fh);
      for (let f = 0; f < 6; f++) {
        p.rect("slab", x, top + f * fh, w, 1);
        p.windows("glass", x + 3, top + f * fh + 2, Math.floor((w - 4) / 4), 1, 4, 0, 3, 4);
      }
      for (let px = x; px <= x + w - 2; px += 11) p.rect("pier", px, top, 2, 6 * fh);
      p.rect("slab", x - 1, top - 1, w + 2, 1);
    }
    // The centre panel, taller than the wings, with the star and the name.
    p.rect("brick", 88, top - 8, 20, 6 * fh + 8);
    p.rect("brickDk", 106, top - 8, 2, 6 * fh + 8);
    p.rect("star", 97, top - 5, 1, 1);
    p.rect("star", 96, top - 4, 3, 1);
    p.rect("star", 97, top - 3, 1, 1);
    p.text("name", 92, top + 3, "PUP");
    p.rect("lobby", 91, GROUND - 13, 14, 13);
    p.rect("slab", 91, GROUND - 7, 14, 1);

    tree(p, 34, GROUND, 9, 12);
    tree(p, 150, GROUND, 9, 11);
    wires(p, 40, 160, GROUND);
    street(p);
  },
};

export default scene;
