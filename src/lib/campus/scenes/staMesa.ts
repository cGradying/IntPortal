// PUP Sta. Mesa, the A. Mabini Campus, seen from Teresa Street. Checked against
// Wikimedia Commons photos (docs/specs/reference/campus-looks.md): the Main
// Building's cream wings striped with maroon corridor bands, the flag in front,
// the white Mabini Obelisk on its round island, the Pylon's three grey slabs
// lettered P-U-P on a brick plinth, the lagoon's Intramuros-style stone arch and
// its green water, the Makati skyline far off, and the PNR line by the road.
import type { SceneDef } from "../paint";
import { BASE, GROUND, ROAD, lamp, skyline, tree } from "./kit";

const scene: SceneDef = {
  id: "sta-mesa",
  label: "PUP Sta. Mesa",
  road: ROAD,
  palette: {
    ...BASE,
    wall: { c: "#ece5d3", k: 0.55 },
    wing: { c: "#cfc3a9", k: 0.55 },
    recess: { c: "#a89c86", k: 0.55 },
    band: { c: "#8e2b2b", k: 0.55 },
    bandDk: { c: "#6a1c22", k: 0.55 },
    core: { c: "#ddd4c0", k: 0.55 },
    obelisk: { c: "#eeeae0", k: 0.5 },
    obeliskSh: { c: "#bdb7a8", k: 0.5 },
    pylon: { c: "#d9d7cf", k: 0.5 },
    pylonSh: { c: "#adaaa1", k: 0.5 },
    letter: { c: "#3b3833", k: 0.3 },
    plinth: { c: "#8a4a3a", k: 0.55 },
    plaza: { c: "#9c7a68", k: 0.6 },
    stone: { c: "#8d887e", k: 0.55 },
    stoneDk: { c: "#6c675e", k: 0.55 },
    lagoon: { c: "#4f7a55", k: 0.6 },
    archIn: { c: "#3a3832", k: 0.4 },
    rail: { c: "#3a383c", k: 0.3 },
    ballast: { c: "#6b6258", k: 0.5 },
    flagBlue: { c: "#1d3f8f", k: 0.4 },
    flagRed: { c: "#c3262f", k: 0.4 },
    flagWhite: { c: "#f2efe6", k: 0.4 },
    star: { c: "#f2c14e", k: 0.2 },
  },
  draw(p) {
    skyline(p, 11, 0, 192, 58, 16);

    // The Main Building: two receding wings and the centre block, six floors
    // of cantilevered corridors, each a maroon band over a shaded recess.
    const fh = 6;
    const top = GROUND - 6 * fh;
    const block = (x: number, w: number, wall: string) => {
      p.rect(wall, x, top, w, 6 * fh);
      for (let f = 0; f < 6; f++) {
        const fy = top + f * fh;
        p.rect("band", x, fy, w, 2);
        p.rect("recess", x, fy + 2, w, 1);
        p.windows("glass", x + 2, fy + 3, Math.floor((w - 2) / 4), 1, 4, 0, 2, 2);
      }
      p.rect("bandDk", x - 1, top - 2, w + 2, 2);
    };
    block(34, 48, "wing");
    block(120, 50, "wing");
    block(82, 38, "wall");
    // The centre stands a little proud of the wings.
    p.rect("band", 81, top - 4, 40, 2);
    p.rect("bandDk", 81, top - 5, 40, 1);
    p.rect("recess", 82, top, 1, 6 * fh);
    p.rect("recess", 119, top, 1, 6 * fh);
    // The core rising from the middle of the roof.
    p.rect("core", 95, top - 10, 12, 5);
    p.rect("bandDk", 94, top - 11, 14, 1);

    // The flag, in front of the centre.
    p.rect("obelisk", 100, 10, 1, GROUND - 10);
    p.rect("flagWhite", 101, 10, 1, 4);
    p.rect("flagWhite", 102, 11, 1, 2);
    p.rect("flagBlue", 102, 10, 5, 1);
    p.rect("flagBlue", 103, 11, 4, 1);
    p.rect("flagRed", 103, 12, 4, 1);
    p.rect("flagRed", 102, 13, 5, 1);

    // Acacias at the edges of the plaza.
    tree(p, 22, GROUND, 12, 14);
    tree(p, 170, GROUND, 14, 16);
    tree(p, 182, GROUND, 9, 11);

    // The Mabini Obelisk: a white shaft, the gold star at its head, on a round planted island.
    p.rect("obelisk", 65, 20, 4, GROUND - 23);
    p.rect("obeliskSh", 68, 20, 1, GROUND - 23);
    p.rect("obelisk", 66, 18, 2, 2);
    p.rect("star", 66, 14, 2, 1);
    p.rect("star", 65, 15, 4, 2);
    p.rect("star", 66, 17, 2, 1);
    p.rect("grass", 57, GROUND - 3, 20, 3);
    p.rect("leaf", 58, GROUND - 4, 5, 1);
    p.rect("leaf", 71, GROUND - 4, 5, 1);
    p.rect("plinth", 63, GROUND - 3, 8, 3);
    p.rect("obeliskSh", 63, GROUND - 3, 8, 1);

    // The Pylon: three slabs, P, U, P, on a brick plinth by the gate.
    const slab = (x: number, y: number, ch: string) => {
      p.rect("pylon", x, y, 5, GROUND - 2 - y);
      p.rect("pylonSh", x + 4, y, 1, GROUND - 2 - y);
      p.text("letter", x + 1, y + 3, ch);
    };
    slab(5, 26, "P");
    slab(11, 22, "U");
    slab(17, 25, "P");
    p.rect("plinth", 3, GROUND - 2, 21, 2);

    // The lagoon's arched stone gate and its green water.
    // Crenellated like the walls of Intramuros, with a stepped gable over the arch.
    p.rect("stone", 146, 56, 46, 8);
    for (let x = 146; x < 192; x += 4) p.rect("stone", x, 54, 2, 2);
    p.poly("stone", [159, 56, 159, 51, 163, 51, 163, 47, 167, 47, 167, 44, 175, 44, 175, 47, 179, 47, 179, 51, 183, 51, 183, 56]);
    p.rect("stoneDk", 146, 57, 46, 1);
    p.rect("stoneDk", 167, 44, 8, 1);
    p.poly("archIn", [166, 64, 166, 55, 168, 52, 174, 52, 176, 55, 176, 64]);
    p.water("lagoon", 167, 61, 9, 3);

    // Freedom Plaza, the PNR line, Teresa Street.
    p.rect("plaza", 0, GROUND, 192, 2);
    p.water("lagoon", 146, GROUND, 46, 2);
    p.rect("curb", 0, GROUND + 2, 192, 1);
    p.rect("rail", 0, GROUND + 3, 192, 1);
    p.rect("ballast", 0, GROUND + 4, 192, 2);
    for (let x = 2; x < 192; x += 5) p.rect("rail", x, GROUND + 5, 2, 1);
    p.rect("road", 0, GROUND + 6, 192, 10);
    for (let x = 0; x < 192; x += 12) p.rect("roadLine", x, 78, 6, 1);
    lamp(p, 40, GROUND);
    lamp(p, 140, GROUND);
  },
};

export default scene;
