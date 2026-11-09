import { describe, expect, it } from "vitest";
import page from "../../routes/+page.svelte?raw";
import orb from "./AssisOrb.svelte?raw";
import { CELLS, FILL, FORMS, crystalMode, isResting, REST_MS, neuronForm, restCube, restTones, useGlass, viewMatrix } from "./crystal";

describe("the crystal (046 C1b to C1d2)", () => {
  it("c1c_no_cube_until_installed", () => {
    expect(crystalMode("today", false)).toBeNull();
    expect(crystalMode("today", true)).toBe("cube");
    expect(crystalMode("study", false)).toBe("plus");
    expect(crystalMode("study", true)).toBe("plus");
  });

  it("c1d2_low_ram_never_starts_webgl", () => {
    expect(useGlass(false, true, true)).toBe(false);
    expect(useGlass(false, false, true)).toBe(true);
  });

  it("c1d_no_webgl_or_reduce_motion_is_the_still_image", () => {
    expect(useGlass(false, false, false)).toBe(false);
    expect(useGlass(true, false, true)).toBe(false);
  });

  it("c1b2_settles_and_wakes", () => {
    expect(isResting(REST_MS + 1, 0, false, 0)).toBe(true);
    expect(isResting(REST_MS - 1, 0, false, 0), "just moved").toBe(false);
    expect(isResting(REST_MS + 1, 0, true, 0), "LAR is thinking").toBe(false);
    expect(isResting(REST_MS + 1, 0, false, 0.5), "still folding").toBe(false);
  });

  it("c1b3_every_form_is_27_boxes_inside_the_chip", () => {
    for (const make of FORMS)
      for (let i = 0; i < 50; i++) {
        const form = make();
        expect(form).toHaveLength(27);
        for (const b of form) {
          expect(b.c).toHaveLength(3);
          expect(b.h).toHaveLength(3);
          expect(Math.max(...b.c.map(Math.abs))).toBeLessThan(2.6);
        }
      }
  });

  it("c1b3_roots_grow_downward_from_the_top", () => {
    const form = neuronForm(true);
    expect(form[0].c[1]).toBe(1.5);
  });

  it("c1b_the_plus_is_two_bars", () => {
    expect(CELLS).toHaveLength(27);
    expect(CELLS.filter((c) => c.bar)).toHaveLength(2);
  });

  it("c1b2_rest_uses_the_rooms_tokens", () => {
    const t = restTones(0x170b1a, 0xf4ecd8, 0xf5b227);
    expect(t.gold).toBe("#f5b227");
    // Top lightest at night, and three tones in all.
    expect(new Set(t.faces).size).toBe(3);
    const faces = restCube(t);
    // Three visible sides of nine squares.
    expect(faces).toHaveLength(27);
    expect(new Set(faces.map((f) => f.fill)).size).toBe(3);
    expect(faces.some((f) => f.dot)).toBe(true);
    expect(FILL).toBeGreaterThan(0);
  });

  it("the view matrix is a rotation", () => {
    const m = viewMatrix(0.7, 0.3, 0.2);
    const col = (i: number) => m.slice(i * 3, i * 3 + 3);
    for (let i = 0; i < 3; i++) expect(Math.hypot(...col(i))).toBeCloseTo(1);
    const dot = col(0).reduce((a, v, i) => a + v * col(1)[i], 0);
    expect(dot).toBeCloseTo(0);
  });

  it("c1b_page_padding_clears_the_chip", () => {
    const bottom = (src: string, re: RegExp) => Number(re.exec(src)?.[1]);
    const CHIP = 48;
    const orbAt = bottom(orb, /\.orb \{[^}]*bottom: calc\(var\(--safe-bottom\) \+ (\d+)px\)/);
    const orbDock = bottom(orb, /data-glance="dock"\]\) \.orb \{[^}]*\+ (\d+)px/);
    const pad = bottom(page, /main \{[^}]*calc\(var\(--safe-bottom\) \+ (\d+)px\)/);
    const padDock = bottom(page, /data-glance="dock"\] main \{[^}]*\+ (\d+)px/);
    expect(pad).toBeGreaterThanOrEqual(orbAt + CHIP + 8);
    expect(padDock).toBeGreaterThanOrEqual(orbDock + CHIP + 8);
  });
});
