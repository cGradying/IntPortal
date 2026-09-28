import { describe, expect, it } from "vitest";
import { ISKO, ISKO_COLORS, ISKO_WAVE, JEEP, JEEP_COLORS } from "./sprites";

describe("sprites", () => {
  it.each([
    ["jeep", JEEP, JEEP_COLORS, 18, 7],
    ["isko", ISKO, ISKO_COLORS, 14, 20],
    ["isko waving", ISKO_WAVE, ISKO_COLORS, 14, 20],
  ] as const)("%s is a clean rectangle with every colour defined", (_, rows, colors, w, h) => {
    expect(rows.length).toBe(h);
    for (const row of rows) {
      expect(row.length).toBe(w);
      for (const c of row) if (c !== ".") expect(colors[c], `colour ${c}`).toBeDefined();
    }
  });
});
