import { describe, expect, it } from "vitest";
import { sourceTarget } from "./sources";

describe("sourceTarget", () => {
  it("opens a deck for card:<deck id>", () => expect(sourceTarget("card:d-1")).toEqual({ kind: "deck", id: "d-1" }));
  it("opens a subject for plan:<code>", () => expect(sourceTarget("plan:COMP 20073")).toEqual({ kind: "subject", code: "COMP 20073" }));
  it("opens notes for every other key", () => {
    for (const k of ["note:abc", "class:COMP 20073", "card:", "plan:"]) expect(sourceTarget(k)).toEqual({ kind: "note" });
  });
});
