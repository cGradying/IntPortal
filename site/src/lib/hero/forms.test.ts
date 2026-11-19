import { describe, expect, it } from "vitest";
import { FORMS, MAX } from "./forms";

describe("portal forms (059)", () => {
  for (const f of Object.values(FORMS)) {
    it(`${f.id} fits one mesh, sits centred and uses the ramp`, () => {
      expect(f.voxels.length).toBeGreaterThan(8);
      expect(f.voxels.length).toBeLessThanOrEqual(MAX);
      const xs = f.voxels.map((v) => v.x);
      expect(Math.abs(Math.max(...xs) + Math.min(...xs))).toBeLessThanOrEqual(1);
      for (const v of f.voxels) expect(v.tone).toBeGreaterThanOrEqual(0), expect(v.tone).toBeLessThanOrEqual(4);
      expect(new Set(f.voxels.map((v) => `${v.x},${v.y},${v.z}`)).size).toBe(f.voxels.length);
      const front = Math.max(...f.voxels.map((v) => v.z));
      for (const v of f.voxels.filter((v) => v.z === front)) expect(v.tone, `${f.id} front`).toBeGreaterThanOrEqual(2);
    });
  }
});
