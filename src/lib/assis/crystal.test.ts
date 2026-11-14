import { describe, expect, it } from "vitest";
import page from "../../routes/+page.svelte?raw";
import orb from "./AssisOrb.svelte?raw";
import { crystalMode, dithered, drawChip, restTones } from "./crystal";

describe("the crystal (046 C1b to C1d2)", () => {
  it("c1c_no_cube_until_installed", () => {
    expect(crystalMode("today", false)).toBeNull();
    expect(crystalMode("today", true)).toBe("cube");
    expect(crystalMode("study", false)).toBe("plus");
    expect(crystalMode("today", true, true)).toBe("plus"); // the note editor's tools (046 C11)
    expect(crystalMode("study", true)).toBe("plus");
  });

  it("c1b_the_corners_dither_out_in_16_steps", () => {
    const count = (p: number) => { let n = 0; for (let y = 0; y < 4; y++) for (let x = 0; x < 4; x++) if (dithered(x, y, p)) n++; return n; };
    expect(count(0)).toBe(0);
    expect(count(1)).toBe(16);
    expect(count(0.5)).toBe(8);
  });

  it("c1b2_rest_uses_the_rooms_tokens", () => {
    const t = restTones(0x170b1a, 0xf4ecd8, 0xf5b227);
    expect(t.gold).toBe("#f5b227");
    expect(new Set(t.faces).size).toBe(3);
  });

  it("c1b3_the_sweep_shows_in_plus_mode_and_the_menu_is_an_x", () => {
    const t = restTones(0x170b1a, 0xf4ecd8, 0xf5b227);
    const run = (step: number, open = false) => {
      const log: string[] = [];
      const ctx = { fillStyle: "", clearRect() {}, fillRect(x: number, y: number) { log.push(`${x},${y},${this.fillStyle}`); } };
      drawChip(ctx as unknown as CanvasRenderingContext2D, t, 0, step, open);
      return log.join("|");
    };
    expect(run(5)).not.toBe(run(0));
    expect(run(0, true)).not.toBe(run(0));
  });

  it("c1d_no_webgl_left", () => {
    expect(orb).not.toMatch(/webgl|mountCrystal/i);
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
