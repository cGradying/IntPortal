// @ts-expect-error type error without @types/node package
import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { build } from "./paint";
import { BRANCHES } from "./scenes/branch";
import { HAND_DRAWN, PUP_CAMPUSES, loadScene, pickScene } from "./scenes";
import { MOTIFS, school } from "./scenes/school";
import { H, SKY, W, bayer, hazeFor, litWindow, skyAt } from "./sky";

const rust = readFileSync(new URL("../../../crates/intportal-core/src/campus.rs", import.meta.url), "utf8");
const rustNames = [...rust.matchAll(/c\((?:Some\("[A-Z]{2}"\)|None), "([^"]+)"/g)].map((m) => m[1]);

describe("campus scenes", () => {
  it("every campus in campus.rs has a scene, by its exact name", () => {
    expect(rustNames).toHaveLength(25);
    expect([...PUP_CAMPUSES]).toEqual(rustNames);
    for (const name of rustNames) expect(name in HAND_DRAWN || name in BRANCHES, name).toBe(true);
  });

  const all = [
    ...PUP_CAMPUSES.map((name) => [name, () => loadScene(name)] as const),
    ...Object.keys(MOTIFS).map((motif) => [`school (${motif})`, async () => school({ id: "x", name: "PhilSCA", accent: "#5c6bc0", ramp: ["#101830"], motif: motif as keyof typeof MOTIFS })] as const),
  ];
  it.each(all)("%s stays inside 192x80 and uses only its palette", async (_, load) => {
    const b = build(await load());
    expect(b.errors).toEqual([]);
    expect(b.colours.length).toBeLessThanOrEqual(256);
    // Something is drawn, and the sky still shows.
    let sky = 0;
    for (let i = 0; i < W * H; i++) if (!b.cells[i * 4]) sky++;
    expect(sky).toBeGreaterThan(W * 20);
    expect(sky).toBeLessThan(W * H - W * 16);
  });

  it("the Sta. Mesa scene has windows for the lit class", async () => {
    const b = build(await loadScene("Sta. Mesa"));
    expect(b.windows).toBeGreaterThan(100);
    expect(litWindow("COMP 20073", b.windows)).toBeGreaterThanOrEqual(0);
    expect(litWindow("", b.windows)).toBe(-1);
  });

  it("a scene drawn outside the frame or in an unknown colour is caught", () => {
    const b = build({ id: "bad", label: "bad", road: 71, palette: { a: "#000000" }, draw: (p) => (p.rect("a", 190, 0, 4, 2), p.rect("nope", 0, 0, 1, 1)) });
    expect(b.errors).toHaveLength(2);
  });
});

describe("picking the campus", () => {
  it("the student number's campus, then the stored pick, then Sta. Mesa", () => {
    expect(pickScene("Ragay", "Taguig")).toBe("Ragay");
    expect(pickScene(null, "Taguig")).toBe("Taguig");
    expect(pickScene(null, "school:earist")).toBe("school:earist");
    expect(pickScene(undefined, "Nowhere")).toBe("Sta. Mesa");
    expect(pickScene("Nowhere", null)).toBe("Sta. Mesa");
    expect(pickScene(null, "school:<bad>")).toBe("Sta. Mesa");
  });
});

describe("the sky", () => {
  it("keeps the strip's keyframes", () => {
    expect(SKY.map((k) => k[0])).toEqual([0, 4.5, 5.75, 7, 9, 16, 17.25, 18.3, 19.5, 24]);
    expect(skyAt(0)).toEqual({ top: [10, 15, 44], bottom: [29, 39, 87], light: 0 });
    expect(skyAt(12)).toEqual({ top: [75, 144, 211], bottom: [197, 226, 241], light: 1 });
    // Values from the Canvas 2D strip this replaced.
    expect(skyAt(18.5)).toEqual({ top: [40, 42, 97], bottom: [173, 84, 120], light: 1 / 3 });
    expect(skyAt(6)).toEqual({ top: [46, 56, 105], bottom: [229, 160, 126], light: 1 / 3 });
    expect(skyAt(23.99).top).toEqual([10, 15, 44]);
  });

  it("dithers with the 4x4 Bayer matrix", () => {
    const m = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]];
    for (let y = 0; y < 4; y++) for (let x = 0; x < 4; x++) expect(bayer(x, y) * 16).toBe(m[y][x]);
  });

  it("hazes in the rainy months only", () => {
    expect(hazeFor(6)).toBeGreaterThan(0);
    expect(hazeFor(0)).toBe(0);
  });
});
