import { describe, expect, it } from "vitest";
import { luminance } from "../rooms";
import { TOUR } from "./tour";

const stop = (id: string) => TOUR.find((s) => s.id === id)!;

describe("the welcome tour", () => {
  it("has three stops in order", () => {
    expect(TOUR.map((s) => s.id)).toEqual(["inside", "does", "yours"]);
    expect(TOUR.map((s) => s.tab)).toEqual(["Inside", "What it does", "Make it yours"]);
  });

  it("peeks each page of the portal in its order", () => {
    expect(stop("inside").items.map((i) => [i.id, i.label, i.act])).toEqual([
      ["today", "Today", { kind: "peek", page: 0 }],
      ["schedule", "Schedule", { kind: "peek", page: 1 }],
      ["grades", "Grades", { kind: "peek", page: 2 }],
      ["study", "Study", { kind: "peek", page: 3 }],
    ]);
  });

  it("offers only dark rooms, then the school", () => {
    const items = stop("yours").items;
    const rooms = items.filter((i) => i.act.kind === "room");
    expect(rooms.map((i) => i.id)).toEqual(["night", "maroon", "astraMoon", "tokyoNight", "dracula", "nord"]);
    for (const r of rooms) expect(luminance(r.swatch![0])).toBeLessThan(0.1);
    expect(items.at(-1)).toEqual({ id: "school", label: "Your school", act: { kind: "school" } });
  });

  it("gives LAR a short line for every say", () => {
    const lines = TOUR.flatMap((s) => s.items).flatMap((i) => (i.act.kind === "say" ? [i.act.line] : []));
    expect(lines).toHaveLength(5);
    for (const l of lines) {
      expect(l.trim().length).toBeGreaterThan(0);
      expect(l.length).toBeLessThan(100);
    }
  });

  it("gives every item a unique id within its stop", () => {
    for (const s of TOUR) expect(new Set(s.items.map((i) => i.id)).size).toBe(s.items.length);
  });
});
