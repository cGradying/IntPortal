// PUP Sto. Tomas, Batangas, at the foot of Mt Makiling (Wikipedia; the city's
// own site). From Wikimedia Commons ("PUP Santo Tomas, Batangas, Apr 2024"):
// two white gate pillars under a maroon beam lettered in white, palms, and a
// white multi-storey building inside.
import type { SceneDef } from "../paint";
import { textWidth } from "../paint";
import { BASE, GROUND, ROAD, gate, palm, ridge, street, tree } from "./kit";

const scene: SceneDef = {
  id: "sto-tomas",
  label: "PUP Sto. Tomas",
  road: ROAD,
  palette: {
    ...BASE,
    makiling: { c: "#2f5a3a", k: 0.35, far: 0.42 },
    foothill: { c: "#3a6b42", k: 0.45, far: 0.2 },
    face: { c: "#eeece6", k: 0.55 },
    faceSh: { c: "#c9c6bd", k: 0.55 },
  },
  draw(p) {
    // Makiling's long ridge of peaks fills the sky behind the campus.
    ridge(p, "makiling", [0, 46, 18, 38, 34, 30, 46, 25, 56, 29, 70, 26, 86, 17, 98, 21, 116, 28, 140, 34, 166, 42, 192, 47], 60);
    ridge(p, "foothill", [0, 54, 40, 50, 90, 53, 140, 49, 192, 52], 60);
    // The white building inside, three floors of balconies.
    p.rect("face", 128, GROUND - 26, 58, 26);
    for (let f = 0; f < 3; f++) {
      p.rect("faceSh", 128, GROUND - 26 + f * 8, 58, 2);
      p.windows("glass", 131, GROUND - 22 + f * 8, 11, 1, 5, 0, 3, 3);
    }
    p.rect("roofRed", 127, GROUND - 28, 60, 2);
    tree(p, 112, GROUND, 10, 16);
    palm(p, 16, GROUND, 28);
    palm(p, 120, GROUND, 22);
    // The wall and the gate.
    const label = "PUP STO. TOMAS";
    const gw = textWidth(label) + 6;
    const gx = Math.round(72 - gw / 2);
    p.rect("faceSh", 0, GROUND - 6, gx, 6);
    p.rect("face", 0, GROUND - 6, gx, 1);
    p.rect("faceSh", gx + gw, GROUND - 6, 128 - gx - gw, 6);
    p.rect("face", gx + gw, GROUND - 6, 128 - gx - gw, 1);
    gate(p, 72, GROUND, label);
    street(p);
  },
};

export default scene;
