import { describe, expect, it } from "vitest";
import { ANTENNA, CUBE, H, LAR_PAL, MITT, MOODS, THUMB, VISOR, W, blinkAt, bodyGrid, faceGrid } from "./sprite";

const keys = (g: (string | null)[][]) => g.flat().filter((k): k is string => k !== null);

describe("LAR's sprite", () => {
  it("is a 26 × 23 body", () => {
    const g = bodyGrid();
    expect(g.length).toBe(H);
    expect(g.every((row) => row.length === W)).toBe(true);
    expect(H).toBe(23);
    expect(W).toBe(26);
  });

  it("only paints colours from his palette", () => {
    const parts = [bodyGrid(), ...MOODS.map(faceGrid), ...[MITT, THUMB, ANTENNA, CUBE].map((rows) => rows.map((r) => [...r].map((c) => (c === "." ? null : c))))];
    for (const g of parts) for (const k of keys(g)) expect(LAR_PAL).toHaveProperty(k);
  });

  it("keeps every face inside the visor, so moods swap without touching the body", () => {
    for (const mood of MOODS) {
      faceGrid(mood).forEach((row, y) =>
        row.forEach((k, x) => {
          if (!k) return;
          expect(x).toBeGreaterThanOrEqual(VISOR.x0);
          expect(x).toBeLessThanOrEqual(VISOR.x1);
          expect(y).toBeGreaterThanOrEqual(VISOR.y0);
          expect(y).toBeLessThanOrEqual(VISOR.y1);
        }),
      );
    }
  });

  it("gives each mood its own face", () => {
    const faces = new Set(MOODS.map((m) => JSON.stringify(faceGrid(m))));
    expect(faces.size).toBe(MOODS.length);
  });

  it("blinks briefly and then looks back", () => {
    const seen = new Set<string>();
    for (let t = 0; t < 6; t += 0.01) seen.add(blinkAt(t));
    expect(seen).toEqual(new Set(["open", "blink"]));
    let closed = 0;
    for (let t = 0; t < 6; t += 0.01) if (blinkAt(t) === "blink") closed++;
    expect(closed / 600).toBeLessThan(0.08);
  });
});
