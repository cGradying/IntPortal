import { describe, expect, it } from "vitest";
import { PALETTES, contrast, derive, schoolRoles } from "./rooms";
import { THEMES } from "./lar/sprite";
// @ts-expect-error type error without @types/node package
import { readFileSync, readdirSync } from "node:fs";

const css = readFileSync(new URL("./app.css", import.meta.url), "utf8");

describe("derived rooms", () => {
  for (const [id, p] of Object.entries(PALETTES)) {
    it(`${id} keeps text readable on its cards`, () => {
      const r = derive(p);
      expect(contrast(r["--ink"], r["--card"])).toBeGreaterThanOrEqual(7);
      expect(contrast(r["--ink-2"], r["--card"])).toBeGreaterThanOrEqual(4.5);
      expect(contrast(r["--ink-3"], r["--card"])).toBeGreaterThanOrEqual(3);
      expect(contrast(r["--gold"], r["--card"])).toBeGreaterThanOrEqual(3);
      expect(contrast(r["--on-gold"], r["--gold"])).toBeGreaterThanOrEqual(3);
      for (let i = 1; i <= 6; i++) expect(contrast(r[`--s${i}`], r["--card"])).toBeGreaterThanOrEqual(3);
    });
  }

  it("light and dark rooms get the matching scheme", () => {
    expect(derive(PALETTES.ivory)["color-scheme"]).toBe("light");
    expect(derive(PALETTES.dracula)["color-scheme"]).toBe("dark");
  });

  it("contrast is the WCAG ratio", () => {
    expect(contrast("#000000", "#ffffff")).toBeCloseTo(21, 5);
    expect(contrast("#777777", "#ffffff")).toBeCloseTo(4.48, 2);
  });
});

describe("app.css", () => {
  it("c21_reduce_motion_stops_loops", () => {
    const reduce = css.slice(css.indexOf("prefers-reduced-motion: reduce"));
    expect(reduce.slice(0, reduce.indexOf("}"))).toContain("animation-iteration-count: 1 !important");
  });

  it("c6_controls_take_the_room_accent", () => {
    expect(css).toContain("accent-color: var(--gold)");
  });
});

describe("the environment (spec 045)", () => {
  const svelte = (f: string): string => readFileSync(new URL(f, import.meta.url), "utf8");
  it("c1_no_void_hex_outside_app_css: every .svelte file's style and markup reads tokens", () => {
    // The pixel-art palettes are the spec's exceptions (CampusStrip, Scene, Jeepney).
    const art = /(CampusStrip|Scene|Jeepney)\.svelte$/;
    const void_ = /#(0b0710|140c16|170b1a|1c1220|060307|060607|3a2446|34203f|2f2939|f4ecd8|fff6dc|f5b227|ffc94a|b87a10|1b1406)\b/i;
    const walk = (d: URL): URL[] =>
      readdirSync(d, { withFileTypes: true }).flatMap((e: { name: string; isDirectory(): boolean }) =>
        e.isDirectory() ? walk(new URL(`${e.name}/`, d)) : e.name.endsWith(".svelte") ? [new URL(e.name, d)] : []);
    const all = walk(new URL("./", import.meta.url));
    expect(all.length).toBeGreaterThan(40);
    for (const f of all) {
      if (art.test(f.href)) continue;
      // Markup and style; a script may carry a last-resort fallback.
      expect(readFileSync(f, "utf8").replace(/<script[\s\S]*?<\/script>/g, ""), f.href).not.toMatch(void_);
    }
  });
  it("c2_night_is_the_void: the Night room's ground is the landing's", () => {
    const night = css.slice(css.indexOf(':root[data-room="night"]'));
    expect(night).toMatch(/--ground: #0b0710;/);
    expect(night).toMatch(/--card: #170b1a;/);
  });
  it("c3_the_ground_moves_by_transform_only", () => {
    for (const k of ["aura1", "aura2"]) {
      const frames = css.slice(css.indexOf(`@keyframes ${k}`)).split("\n}")[0];
      expect(frames).toMatch(/transform:/);
      expect(frames).not.toMatch(/opacity|background|left:|top:/);
    }
  });
  for (const [id, t] of Object.entries(THEMES)) {
    for (const room of ["night", "day"] as const) {
      it(`c4_accent_contrast_on_every_room: ${id} reads in ${room}, on both card stops`, () => {
        const r = schoolRoles(t, room);
        // The .card gradient runs from --card-2 to --card.
        for (const card of room === "night" ? ["#170b1a", "#1d1022"] : ["#ffffff", "#f8f6f3"]) {
          expect(contrast(r["--gold"], card), card).toBeGreaterThanOrEqual(4.5);
        }
        expect(contrast(r["--on-gold"], r["--gold"])).toBeGreaterThanOrEqual(3);
      });
    }
  }
  it("c6_pixel_checkboxes: no system control left", () => {
    expect(css).toMatch(/input\[type="checkbox"\] \{\s*appearance: none;/);
  });
});
