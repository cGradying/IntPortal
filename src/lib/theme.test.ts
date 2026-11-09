import { beforeEach, describe, expect, it, vi } from "vitest";

// state.svelte.ts reaches for the page and storage; a bare stand-in of each is enough here.
const store = vi.hoisted(() => {
  const data = new Map<string, string>();
  const style = Object.assign([] as string[], { setProperty() {}, removeProperty() {} });
  Object.assign(globalThis, {
    localStorage: { getItem: (k: string) => data.get(k) ?? null, setItem: (k: string, v: string) => data.set(k, v), removeItem: (k: string) => data.delete(k) },
    document: { documentElement: { style, dataset: {} as Record<string, string> } },
  });
  return data;
});
vi.mock("@tauri-apps/api/core", () => ({ invoke: vi.fn() }));
vi.mock("@tauri-apps/plugin-notification", () => ({ Schedule: {}, cancel: vi.fn(), isPermissionGranted: vi.fn(), onAction: vi.fn(), pending: vi.fn(), requestPermission: vi.fn() }));

import { contrast } from "./rooms";
import { PRESETS, roles, roll, seed, type Theme } from "./theme";
import { decodeTheme, encodeTheme } from "./themeCode";
import { app, deleteTheme, saveTheme, setRoom } from "./state.svelte";

const LAGOON: Theme = { name: "Lagoon Drift", accent: "#3fb4c9", ground: "#0b2238", card: "#12304a", ink: "#e6f7f5", hue2: 170, lar: 190, pattern: "plus", aura: "full", corners: "round", cards: "tint", titles: "classic" };
const LAGOON_CODE = "IPT1.AoMGeIY_tMkLIjgSMErm9_UMTGFnb29uIERyaWZ0jQ";

/** A small seeded generator, so the dice sweep is the same every run. */
function mulberry(a: number) {
  return () => {
    a |= 0;
    a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

const bytes = (code: string) => [...atob(code.slice(5).replace(/-/g, "+").replace(/_/g, "/"))].map((c) => c.charCodeAt(0));
const pack = (b: number[]) => "IPT1." + btoa(String.fromCharCode(...b)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
/** Rewrites bytes and fixes the checksum, so only the change under test is wrong. */
const tamper = (code: string, f: (b: number[]) => number[]) => {
  const b = f(bytes(code).slice(0, -1));
  return pack([...b, b.reduce((a, v) => (a + v) & 255, 0)]);
};

describe("spec 047 C16: share codes", () => {
  it("c16_code_round_trip", () => {
    expect(encodeTheme(LAGOON)).toBe(LAGOON_CODE);
    // Hues travel in 255 steps, so 170 comes back as 169.
    expect(decodeTheme(LAGOON_CODE)).toEqual({ ...LAGOON, hue2: 169 });
    expect(encodeTheme(decodeTheme(LAGOON_CODE)!)).toBe(LAGOON_CODE);
  });

  it("keeps a no-LAR theme and a multi-byte name", () => {
    const t: Theme = { ...PRESETS[0], name: "Ube Glow 💜", hue2: 8 };
    expect(decodeTheme(encodeTheme(t))).toEqual(t);
  });

  it("cuts the name at 24 characters", () => {
    expect(decodeTheme(encodeTheme({ ...LAGOON, name: "x".repeat(30) }))?.name).toBe("x".repeat(24));
  });
});

describe("spec 047 C17: bad codes change nothing", () => {
  it("c17_bad_code_refused", () => {
    const bad = [
      "", // empty
      "IPT2." + LAGOON_CODE.slice(5), // wrong prefix
      LAGOON_CODE.toLowerCase(), // wrong prefix and body
      LAGOON_CODE + "<", // not base64url
      LAGOON_CODE.slice(0, -4), // cut: the name length no longer matches
      LAGOON_CODE + "AA", // extra bytes
      tamper(LAGOON_CODE, (b) => [...b, 0]), // extra byte with a good checksum
      pack(bytes(LAGOON_CODE).with(-1, (bytes(LAGOON_CODE).at(-1)! + 1) & 255)), // bad checksum
      tamper(LAGOON_CODE, (b) => b.with(0, 1)), // version 1
      tamper(LAGOON_CODE, (b) => b.with(0, 3)), // version 3
      tamper(LAGOON_CODE, (b) => b.with(1, (b[1] & 0xf0) | 10)), // pattern 10 doesn't exist
      tamper(LAGOON_CODE, (b) => b.with(1, (b[1] & 0xcf) | 0x30)), // pools 3 doesn't exist
      tamper(LAGOON_CODE, (b) => b.with(2, 3)), // cards 3 doesn't exist
      tamper(LAGOON_CODE, (b) => b.with(2, 0x10)), // unused bits set
      tamper(LAGOON_CODE, (b) => [...b.slice(0, 17), 2, 0xc3, 0x28]), // not UTF-8
      tamper(LAGOON_CODE, (b) => [...b.slice(0, 17), 3, 0x61, 0x0a, 0x62]), // a control character
      tamper(LAGOON_CODE, (b) => [...b.slice(0, 17), 25, ...new Array(25).fill(0x61)]), // 25 characters
      "IPT1.AAAA", // too short
    ];
    for (const code of bad) expect(decodeTheme(code), code).toBeNull();
  });

  it("markup in a name stays a plain name", () => {
    const t = decodeTheme(encodeTheme({ ...LAGOON, name: "<img src=x onerror=1>" }));
    expect(t?.name).toBe("<img src=x onerror=1>");
    expect(Object.keys(t!).sort()).toEqual(["accent", "aura", "card", "cards", "corners", "ground", "hue2", "ink", "lar", "name", "pattern", "titles"]);
  });
});

describe("spec 047 C13: every theme reads", () => {
  const meets = (t: Theme) => {
    const r = roles(t);
    const label = `${t.name} ${t.accent} ${t.ground} ${t.card} ${t.ink} ${t.cards}`;
    expect(contrast(r["--ink"], r["--card"]), label).toBeGreaterThanOrEqual(7);
    expect(contrast(r["--ink"], r["--ground"]), label).toBeGreaterThanOrEqual(7);
    expect(contrast(r["--ink-2"], r["--card"]), label).toBeGreaterThanOrEqual(4.5);
    expect(contrast(r["--gold"], r["--card"]), label).toBeGreaterThanOrEqual(3);
    for (let i = 1; i <= 6; i++) expect(contrast(r[`--s${i}`], r["--card"]), label).toBeGreaterThanOrEqual(3);
  };

  it("c13_every_theme_meets_contrast: the presets", () => PRESETS.forEach(meets));

  it("c13_every_theme_meets_contrast: 2000 dice rolls", () => {
    const rand = mulberry(47);
    for (let i = 0; i < 2000; i++) meets(roll(rand).t);
  });

  it("c13_every_theme_meets_contrast: fine-tuned colours anywhere, every card style", () => {
    const rand = mulberry(13);
    const any = () => "#" + [0, 0, 0].map(() => Math.floor(rand() * 256).toString(16).padStart(2, "0")).join("");
    for (let i = 0; i < 2000; i++) meets({ ...seed(0, 10), accent: any(), ground: any(), card: any(), ink: any(), cards: (["fill", "outline", "tint"] as const)[i % 3] });
    meets({ ...seed(0, 10), accent: "#777777", ground: "#777777", card: "#777777", ink: "#777777" });
  });

  it("the dice are mostly night and always named", () => {
    const rand = mulberry(1);
    const rolls = Array.from({ length: 200 }, () => roll(rand));
    expect(rolls.every((r) => /^\S+ \S+$/.test(r.t.name))).toBe(true);
    expect(rolls.filter((r) => r.shade < 50).length).toBeGreaterThan(120);
  });
});

describe("spec 047 C14: saved themes", () => {
  beforeEach(() => {
    app.themes = [];
    app.room = "night";
  });

  it("deleting the theme the app wears falls back to Night", () => {
    const id = saveTheme(LAGOON);
    setRoom(`theme:${id}`);
    expect(app.room).toBe(`theme:${id}`);
    expect(JSON.parse(store.get("themes")!)).toEqual([{ id, code: LAGOON_CODE }]);
    deleteTheme(id);
    expect(app.room).toBe("night");
    expect(app.themes).toEqual([]);
    expect(store.get("room")).toBe("night");
  });

  it("deleting another theme leaves the worn one on", () => {
    const keep = saveTheme(LAGOON, "a");
    saveTheme(PRESETS[3], "b");
    setRoom(`theme:${keep}`);
    deleteTheme("b");
    expect(app.room).toBe("theme:a");
    expect(app.themes.map((s) => s.id)).toEqual(["a"]);
  });

  it("a room naming a theme that is gone wears Night", () => {
    setRoom("theme:gone");
    expect(app.room).toBe("night");
  });
});
