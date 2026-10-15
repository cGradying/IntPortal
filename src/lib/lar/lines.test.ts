import { describe, expect, it } from "vitest";
import { LINES, MEMORY, daypart, hold, pause, pick, remember, type Scene } from "./lines";
import { rng } from "./wander";

const sis: Scene = { hour: 9, portal: { id: "sis", name: "SIS", school: "Polytechnic University of the Philippines", ready: true }, typing: false };
const up: Scene = { ...sis, portal: { id: "up", name: "UP", school: "University of the Philippines", ready: false } };

describe("LAR's lines", () => {
  it("never repeats one of the last few", () => {
    const rand = rng(3);
    let recent: string[] = [];
    for (let i = 0; i < 200; i++) {
      const line = pick(sis, recent, rand)!;
      expect(recent).not.toContain(line);
      recent = remember(recent, line);
      expect(recent.length).toBeLessThanOrEqual(MEMORY);
    }
  });

  it("stays quiet while the student types, except to flag an error", () => {
    const typing = { ...sis, typing: true };
    expect(pick(typing, [], rng(1))).toBeNull();
    expect(pick(typing, [], rng(1), "error")).not.toBeNull();
  });

  it("answers a forced topic from that topic only", () => {
    const rand = rng(2);
    const taps = new Set(LINES.filter((l) => l.topic === "tap").map((l) => l.text));
    for (let i = 0; i < 20; i++) expect(taps.has(pick(sis, [], rand, "tap")!)).toBe(true);
  });

  it("talks about the portal on screen, and fills in a placeholder school's name", () => {
    const rand = rng(5);
    const said = Array.from({ length: 300 }, () => pick(up, [], rand)!);
    expect(said.some((s) => s.includes("University of the Philippines") || s.includes("UP"))).toBe(true);
    expect(said.some((s) => s.startsWith("SIS 'to"))).toBe(false);
    expect(said.every((s) => !s.includes("{"))).toBe(true);
  });

  it("greets by the time of day", () => {
    expect(daypart(7)).toBe("morning");
    expect(daypart(14)).toBe("afternoon");
    expect(daypart(21)).toBe("evening");
    const rand = rng(8);
    const night = Array.from({ length: 300 }, () => pick({ ...sis, hour: 21 }, [], rand, "greet")!);
    expect(night.every((s) => LINES.find((l) => l.text === s)?.when === "evening")).toBe(true);
  });

  it("paces itself: 7 to 15 s of quiet, and long enough to read", () => {
    const rand = rng(4);
    for (let i = 0; i < 50; i++) {
      const p = pause(rand);
      expect(p).toBeGreaterThanOrEqual(7);
      expect(p).toBeLessThanOrEqual(15);
    }
    expect(hold("Uy!")).toBeGreaterThan(2.5);
    expect(hold("x".repeat(60))).toBeGreaterThan(hold("x".repeat(20)));
  });
});
