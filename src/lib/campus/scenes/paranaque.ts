// PUP Parañaque, Sto. Niño. From Wikimedia Commons photos (Santo Niño,
// Parañaque Metro series): a four-storey cream building with stacked dark green
// panels up its middle, a pediment over the entrance and the open steel frame
// of a roof deck on top; out front, a cream wall with green posts and the
// campus name in steel letters.
import type { SceneDef } from "../paint";
import { BASE, GROUND, ROAD, skyline, street, tree } from "./kit";

const scene: SceneDef = {
  id: "paranaque",
  label: "PUP Parañaque",
  road: ROAD,
  palette: {
    ...BASE,
    cream: { c: "#e6dcb8", k: 0.55 },
    creamSh: { c: "#c9bd98", k: 0.55 },
    green: { c: "#3f5f45", k: 0.5 },
    greenDk: { c: "#2c4532", k: 0.5 },
    steel: { c: "#5e6670", k: 0.4 },
    letters: { c: "#626a73", k: 0.4 },
    sign: { c: "#d8d3c6", k: 0.5 },
  },
  draw(p) {
    skyline(p, 7, 0, 192, 58, 10);

    const fh = 7;
    const top = GROUND - 4 * fh;
    p.rect("cream", 52, top, 96, 4 * fh);
    p.rect("creamSh", 146, top, 2, 4 * fh);
    for (let f = 0; f < 4; f++) {
      const fy = top + f * fh;
      p.rect("creamSh", 52, fy, 96, 1);
      p.windows("glass", 55, fy + 3, 6, 1, 5, 0, 3, 2);
      p.windows("glass", 119, fy + 3, 6, 1, 5, 0, 3, 2);
      if (f < 3) p.rect("green", 86, fy + 1, 28, 4);
    }
    // The roof deck's open steel frame.
    p.rect("steel", 52, top - 6, 96, 1);
    p.rect("steel", 52, top - 1, 96, 1);
    for (let x = 52; x <= 146; x += 8) p.rect("steel", x, top - 6, 1, 6);
    // The pediment and the sign over the entrance.
    p.poly("greenDk", [82, GROUND - 7, 100, GROUND - 14, 118, GROUND - 7]);
    p.poly("cream", [86, GROUND - 7, 100, GROUND - 12, 114, GROUND - 7]);
    p.rect("sign", 84, GROUND - 7, 32, 3);
    p.rect("glass", 94, GROUND - 4, 12, 4);

    tree(p, 150, GROUND, 12, 15);
    tree(p, 170, GROUND, 14, 18);

    // The front wall: green posts, the name in steel letters.
    p.rect("cream", 2, GROUND - 9, 46, 9);
    p.rect("creamSh", 2, GROUND - 2, 46, 2);
    p.rect("green", 2, GROUND - 11, 3, 11);
    p.rect("green", 45, GROUND - 11, 3, 11);
    p.text("letters", 8, GROUND - 7, "PARAÑAQUE");
    street(p);
  },
};

export default scene;
