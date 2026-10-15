import rust from "../../../crates/intportal-core/src/portal.rs?raw";
import { describe, expect, it } from "vitest";
import {
  ANTENNA, BOX, CUBE, H, LAR_PAL, MITT, MOODS, SPARKLE, STATES, STREAK, THEMES, THUMB, VISOR, VOID, W, ZZZ,
  blinkAt, bodyGrid, contrast, cubeAngle, dotsGrid, extents, faceGrid, mosaic, pose, redGrid, rows, tint,
  type PoseOpts, type State,
} from "./sprite";

const keys = (g: (string | null)[][]) => g.flat().filter((k): k is string => k !== null);
const hexRe = /^#[0-9a-f]{6}$/i;
/** Options a renderer would pass for a state that has just begun. */
const opts = (state: State, since: number, from?: State): PoseOpts => ({ from, since, k: Math.min(1, since / 1.1), vx: 40, vy: -10 });

describe("LAR's sprite", () => {
  it("is a 26 × 23 body", () => {
    const g = bodyGrid();
    expect(g.length).toBe(H);
    expect(g.every((row) => row.length === W)).toBe(true);
    expect(H).toBe(23);
    expect(W).toBe(26);
  });

  it("only paints colours from his palette", () => {
    const parts = [
      bodyGrid(), ...MOODS.map(faceGrid), dotsGrid(0), dotsGrid(2), redGrid(),
      ...[MITT, THUMB, ANTENNA, CUBE, STREAK, ...ZZZ, ...SPARKLE].map(rows),
    ];
    const bad = new Set<string>();
    for (const g of parts) for (const k of keys(g)) if (!(k in LAR_PAL)) bad.add(k);
    expect([...bad]).toEqual([]);
  });

  it("keeps every face, dot and flicker inside the visor, so moods swap without touching the body", () => {
    const stray: string[] = [];
    const grids = [...MOODS.map((m) => [m, faceGrid(m)] as const), ["dots", dotsGrid(1)] as const, ["red", redGrid()] as const];
    for (const [name, g] of grids)
      g.forEach((row, y) =>
        row.forEach((k, x) => {
          if (k && (x < VISOR.x0 || x > VISOR.x1 || y < VISOR.y0 || y > VISOR.y1)) stray.push(`${name}@${x},${y}`);
        }),
      );
    expect(stray).toEqual([]);
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

  it("blocks a sprite down for the spawn without leaving the palette", () => {
    const g = bodyGrid();
    const m = mosaic(g, 4);
    expect(m.length).toBe(H);
    expect(keys(m).length).toBeGreaterThan(100);
    expect(keys(m).every((k) => k in LAR_PAL)).toBe(true);
    expect(mosaic(g, 1)).toBe(g);
  });
});

describe("tint", () => {
  it("gives a valid palette for every portal, rim readable on the void, body untouched", () => {
    const bad: string[] = [];
    for (const [id, theme] of Object.entries(THEMES)) {
      const pal = tint(theme);
      if (Object.keys(pal).join() !== Object.keys(LAR_PAL).join()) bad.push(`${id}: keys`);
      for (const [k, v] of Object.entries(pal)) if (!hexRe.test(v)) bad.push(`${id}.${k}=${v}`);
      if (contrast(pal.m, VOID) < 3) bad.push(`${id}: rim ${pal.m} ${contrast(pal.m, VOID).toFixed(2)}:1`);
      for (const k of ["o", "d", "k", "b", "B", "L", "g", "G", "w"] as const) if (pal[k] !== LAR_PAL[k]) bad.push(`${id}.${k} moved`);
    }
    expect(bad).toEqual([]);
  });

  it("makes each portal look like its own", () => {
    const rims = new Set(Object.values(THEMES).map((t) => tint(t).m));
    const studs = new Set(Object.values(THEMES).map((t) => tint(t).t));
    expect(rims.size).toBe(6);
    expect(studs.size).toBe(6);
  });

  it("gives gold portals a rim that is not gold, since his eyes are", () => {
    for (const id of ["sis", "bulsu"] as const) expect(tint(THEMES[id]).m).not.toBe(THEMES[id].accent);
    expect(tint(THEMES.mabini).m).toBe(THEMES.mabini.accent);
  });

  it("matches the Rust portal registry", () => {
    const rs = rust;
    const bad: string[] = [];
    for (const [id, t] of Object.entries(THEMES)) {
      const want = `ramp: [${t.ramp.map((c) => `"${c}"`).join(", ")}], accent: "${t.accent}"`;
      if (!rs.includes(want)) bad.push(id);
    }
    expect(bad).toEqual([]);
  });
});

describe("pose", () => {
  it("keeps every part of every state inside one fixed box over four seconds", () => {
    const out: string[] = [];
    for (const state of STATES)
      for (const [vx, vy] of [[40, 0], [-60, 30], [0, -60]])
        for (let t = 0; t < 4; t += 1 / 30) {
          const p = pose(state, t, { vx, vy, k: Math.min(1, t / 1.1), since: t });
          for (const [name, pts] of Object.entries(extents(p)))
            for (const [x, y] of pts)
              if (x < BOX.x0 || x > BOX.x1 || y < BOX.y0 || y > BOX.y1) out.push(`${state}/${name} ${x.toFixed(1)},${y.toFixed(1)} @${t.toFixed(2)}`);
        }
    expect(out.slice(0, 8)).toEqual([]);
  });

  it("moves no part more than one sprite pixel per frame, within a state or switching between any two", () => {
    const out: string[] = [];
    const ts = [1.37, 2.13, 3.61];
    const solid = (p: ReturnType<typeof pose>) => Object.entries(extents(p)).filter(([n]) => /^(body|antenna|mitt|cube)/.test(n));
    for (const a of STATES)
      for (const b of STATES)
        for (const t0 of ts) {
          let prev = null as ReturnType<typeof solid> | null;
          // A second before the switch to a second and a half after it.
          for (let f = -60; f <= 90; f++) {
            const t = t0 + f / 60;
            const since = f / 60;
            const p = f < 0 ? pose(a, t, opts(a, t)) : pose(b, t, a === b ? opts(b, t) : opts(b, since, a));
            const now = solid(p);
            if (prev)
              now.forEach(([name, pts], i) =>
                pts.forEach(([x, y], j) => {
                  const d = Math.hypot(x - prev![i][1][j][0], y - prev![i][1][j][1]);
                  if (d > 1) out.push(`${a}>${b}@${t0} f${f} ${name} ${d.toFixed(2)}`);
                }),
              );
            prev = now;
          }
        }
    expect(out.slice(0, 8)).toEqual([]);
  });

  it("starts the error shake at nothing and lets it die within 0.4 s", () => {
    const x = (s: number) => pose("error", 5 + s, { since: s }).body.x;
    expect(x(0)).toBe(0);
    let peak = 0;
    for (let s = 0; s < 0.4; s += 1 / 60) peak = Math.max(peak, Math.abs(x(s)));
    expect(peak).toBeGreaterThan(1);
    expect(peak).toBeLessThanOrEqual(2);
    expect(pose("error", 5.5, { since: 0.5 }).body.x).toBe(0);
    expect(pose("error", 5.1, { since: 0.1 }).red).toBe(true);
  });

  it("resolves from blocks to the sharp sprite as k runs 0 to 1", () => {
    const lv = [0, 0.25, 0.5, 0.75, 1].map((k) => pose("spawn", 1, { k }).resolve);
    expect(lv[0]).toBeGreaterThan(lv[2]);
    expect(lv.at(-1)).toBe(1);
    expect(lv).toEqual([...lv].sort((p, q) => q - p));
  });

  it("gives each state its look: leaning, shut eyes, dots, zzz, wow, hop", () => {
    expect(pose("fly", 1, { vx: 60 }).body.rot).toBeGreaterThan(8);
    expect(pose("fly", 1, { vx: -60 }).body.rot).toBeLessThan(-8);
    expect(pose("fly", 1, { vx: 60 }).antenna.rot).toBeLessThan(-20);
    expect(pose("think", 1).mood).toBe("focus");
    expect(new Set([0, 0.3, 0.6, 0.9].map((t) => pose("think", t).dots))).toEqual(new Set([0, 1, 2]));
    expect(pose("sleep", 1).mood).toBe("sleep");
    expect(pose("sleep", 1).zzz.length).toBeGreaterThan(0);
    expect(pose("error", 1, { since: 9 }).mood).toBe("wow");
    const ys = [0, 0.1, 0.2, 0.3, 0.4].map((t) => pose("happy", t).body.y);
    expect(Math.min(...ys)).toBeLessThan(-3);
  });

  it("parks the cube where it will rest, and brings it back up to speed", () => {
    const still = [4, 5, 6].map((t) => cubeAngle("sleep", t));
    expect(new Set(still).size).toBe(1);
    const from = (s: number) => cubeAngle("sleep", 10 + s, { from: "idle", since: s });
    const tau = Math.PI * 2;
    expect((((from(9) - still[0]) % tau) + tau) % tau).toBeCloseTo(0, 5);
    expect(from(9)).toBe(from(10));
    const wake = (s: number) => cubeAngle("idle", 20 + s, { from: "sleep", since: s });
    expect(wake(0)).toBeCloseTo(still[0], 5);
    expect(wake(3) - wake(2)).toBeCloseTo(2.2, 1);
  });
});
