import { describe, expect, it } from "vitest";
import { FLAME, FLAME_COLORS, JEEP, JEEP_COLORS } from "./sprites";

describe("sprites", () => {
  it.each([
    ["jeep", JEEP, JEEP_COLORS, 18, 7],
    ["flame", FLAME[0], FLAME_COLORS, 7, 9],
    ["flame, flicker", FLAME[1], FLAME_COLORS, 7, 9],
  ] as const)("%s is a clean rectangle with every colour defined", (_, rows, colors, w, h) => {
    expect(rows.length).toBe(h);
    for (const row of rows) {
      expect(row.length).toBe(w);
      for (const c of row) if (c !== ".") expect(colors[c], `colour ${c}`).toBeDefined();
    }
  });
});
