import { describe, expect, it } from "vitest";
import { GESTURES, MOODS, PAL, VIEW, blinkAt, lar, toSvg } from "./vector";

const nums = (d: string) => (d.match(/-?\d+(\.\d+)?/g) ?? []).map(Number);

describe("vector LAR", () => {
  it("draws a face for every mood, and moods differ", () => {
    const faces = MOODS.map((mood) => JSON.stringify(lar({ mood }).filter((s) => s.fill === PAL.gold || s.stroke === PAL.gold || (typeof s.fill === "object" && s.fill.kind === "linear"))));
    expect(new Set(faces).size).toBe(MOODS.length);
  });

  it("has no outline: nothing strokes the dark outline colour", () => {
    expect(lar().some((s) => s.stroke === "#1a0f20")).toBe(false);
  });

  it("keeps every gesture inside the drawing box, all through a wave", () => {
    // Arc flags break x/y pairing, so check against the box's widest extent.
    const all = GESTURES.flatMap((gesture) => Array.from({ length: 30 }, (_, k) => lar({ gesture, t: k / 10 })).flat().flatMap((s) => nums(s.d)));
    expect(all.reduce((a, b) => Math.min(a, b))).toBeGreaterThanOrEqual(Math.min(VIEW.x, VIEW.y));
    expect(all.reduce((a, b) => Math.max(a, b))).toBeLessThanOrEqual(Math.max(VIEW.x + VIEW.w, VIEW.y + VIEW.h));
  });

  it("holds still at t = 0 and moves with the clock", () => {
    expect(lar({ t: 0 })).toEqual(lar({ t: 0 }));
    expect(lar({ t: 0.5 })).not.toEqual(lar({ t: 0 }));
  });

  it("fills the belly window from the portal's ramp", () => {
    const ramp = ["#000001", "#000002", "#000003", "#000004", "#000005"];
    expect(JSON.stringify(lar({ ramp }))).toContain("#000005");
  });

  it("renders SVG with unique gradient ids per instance", () => {
    const svg = toSvg(lar(), "a");
    expect(svg.startsWith("<svg")).toBe(true);
    expect(toSvg(lar(), "b")).not.toContain('id="a-');
  });

  it("blinks briefly", () => {
    const closed = Array.from({ length: 1000 }, (_, i) => blinkAt(i / 100)).filter((m) => m === "blink").length;
    expect(closed).toBeGreaterThan(5);
    expect(closed).toBeLessThan(80);
  });
});

describe("turning", () => {
  it("slides the face toward the side he faces and stays in the box", () => {
    const eyeX = (turn: number) => {
      const eye = lar({ turn }).find((s) => typeof s.fill === "object" && s.fill.kind === "linear")!;
      return Number(eye.d.slice(1).split(" ")[0]);
    };
    expect(eyeX(1)).toBeGreaterThan(eyeX(0));
    expect(eyeX(-1)).toBeLessThan(eyeX(0));
    const all = [-1, 1].flatMap((turn) => lar({ turn, gesture: "point" }).flatMap((s) => nums(s.d)));
    expect(all.reduce((a, b) => Math.max(a, b))).toBeLessThanOrEqual(VIEW.x + VIEW.w);
  });
});
