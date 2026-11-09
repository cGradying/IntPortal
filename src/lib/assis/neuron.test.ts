import { describe, expect, it } from "vitest";
import { rng } from "../lar/wander";
import { axon, cellsOf, curve, dendrites, edgePoint, inward, path, pointAt, pulseAt } from "./neuron";

const box = { x: 0, y: 0, w: 300, h: 400 };
const soma = { x: 52, y: 360 };
const fan: [number, number] = [-Math.PI * 0.6, -Math.PI * 0.02];

describe("the neuron in LAR's window (046 C1d3)", () => {
  it("c1d3_a_path_knows_its_length_and_points", () => {
    const p = path([{ x: 0, y: 0 }, { x: 3, y: 4 }, { x: 3, y: 10 }]);
    expect(p.L).toBe(11);
    expect(p.cum).toEqual([0, 5, 11]);
    expect(pointAt(p, 2.5)).toEqual({ x: 1.5, y: 2 });
    expect(pointAt(p, 8)).toEqual({ x: 3, y: 7 });
    expect(pointAt(p, -4), "clamped to the start").toEqual({ x: 0, y: 0 });
    expect(pointAt(p, 99), "clamped to the end").toEqual({ x: 3, y: 10 });
  });

  it("c1d3_a_signal_is_on_its_path_only_while_it_travels", () => {
    const p = path([{ x: 0, y: 0 }, { x: 100, y: 0 }]);
    expect(pulseAt(p, 1, 200, 0.5), "not sent yet").toBeNull();
    expect(pulseAt(p, 1, 200, 1.25)).toEqual({ x: 50, y: 0 });
    expect(pulseAt(p, 1, 200, 1.5), "arrived").toBeNull();
  });

  it("c1d3_the_glass_is_three_by_three_cells", () => {
    const cells = cellsOf({ x: 14, y: 200, w: 300, h: 210 });
    expect(cells).toHaveLength(9);
    expect(cells[0]).toEqual({ x: 14, y: 200, w: 100, h: 70 });
    expect(cells[4]).toEqual({ x: 114, y: 270, w: 100, h: 70 });
    expect(cells[8]).toEqual({ x: 214, y: 340, w: 100, h: 70 });
  });

  it("c1d3_the_axon_lands_two_px_outside_its_source", () => {
    expect(edgePoint({ x: 100, y: 100, w: 50, h: 20 }, { x: 0, y: 110 })).toEqual({ x: 98, y: 110 });
    expect(edgePoint({ x: 100, y: 100, w: 50, h: 20 }, { x: 125, y: 300 })).toEqual({ x: 125, y: 122 });
  });

  it("c1d3_the_same_seed_grows_the_same_neuron", () => {
    const a = dendrites(soma, fan, box, rng(7));
    const b = dendrites(soma, fan, box, rng(7));
    expect(a.all.length).toBe(b.all.length);
    expect(a.all.map((x) => x.L)).toEqual(b.all.map((x) => x.L));
    expect(a.all.length).toBe(73);
    expect(a.tips.length).toBe(39);
    expect(a.all[0].L).toBeCloseTo(51.6109, 3);
  });

  it("c1d3_dendrites_stay_inside_the_glass_and_grow_from_him", () => {
    for (let s = 1; s < 40; s++) {
      const { all, tips } = dendrites(soma, fan, box, rng(s));
      expect(all.filter((b) => !b.parent)).toHaveLength(5);
      for (const b of all) {
        if (!b.parent) expect(b.pts[0]).toEqual(soma);
        else expect(b.pts[0]).toEqual(b.parent.pts[b.parent.pts.length - 1]);
        expect(b.dur).toBeCloseTo(b.L / 150);
        for (const q of b.pts.slice(1)) expect(q.x > 0 && q.x < 300 && q.y > 0 && q.y < 400).toBe(true);
      }
      for (const t of tips) {
        const home = inward(t);
        expect(home.pts[home.pts.length - 1], "a signal from a tip ends at the soma").toEqual(soma);
      }
    }
  });

  it("c1d3_a_curve_is_still_at_both_ends", () => {
    const c = curve({ x: 0, y: 0 }, { x: 120, y: 0 }, 20, rng(3));
    expect(c.pts[0]).toEqual({ x: 0, y: 0 });
    expect(c.pts[c.pts.length - 1].x).toBeCloseTo(120);
    expect(c.pts[c.pts.length - 1].y).toBeCloseTo(0);
    expect(c.pts).toHaveLength(21);
  });

  it("c1d3_the_axon_reaches_every_source", () => {
    const chip = { x: 30, y: 300, w: 140, h: 36 };
    const card = { x: 16, y: 80, w: 343, h: 90 };
    const parts = axon(soma, [chip, card], rng(11));
    // A trunk, then per source one collateral and four boutons.
    expect(parts).toHaveLength(11);
    expect(parts.filter((p) => p.target !== undefined).map((p) => p.target)).toEqual([0, 1]);
    const ends = parts.filter((p) => p.target !== undefined).map((p) => p.pts[p.pts.length - 1]);
    expect(ends[0].y).toBeCloseTo(edgePoint(chip, parts[0].pts[parts[0].pts.length - 1]).y);
    expect(ends[1].y).toBeCloseTo(172);
    expect(parts[0].pts[0]).toEqual(soma);
  });
});

