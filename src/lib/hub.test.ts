import { describe, expect, it } from "vitest";
import type { Portal } from "./api";
import { remember, search, sections } from "./hub";

const p = (id: string, name: string, school: string, region: string) => ({ id, name, school, region }) as Portal;
const all = [
  p("sis", "SIS", "Polytechnic University of the Philippines", "NCR"),
  p("bulsu", "BulSU", "Bulacan State University", "Central Luzon"),
  p("basc", "BASC", "Bulacan Agricultural State College", "Central Luzon"),
  p("isatu", "ISAT U", "Iloilo Science and Technology University", "Western Visayas"),
  p("up", "UP", "University of the Philippines", "NCR"),
];

describe("search", () => {
  it("matches short name, school and region, ignoring case, spaces and accents", () => {
    expect(search(all, "bul").map((x) => x.id)).toEqual(["bulsu", "basc"]);
    expect(search(all, "isatu").map((x) => x.id)).toEqual(["isatu"]);
    expect(search(all, "visayas").map((x) => x.id)).toEqual(["isatu"]);
    expect(search(all, "Ñcr").map((x) => x.id)).toEqual(["sis", "up"]);
  });
  it("needs every word", () => {
    expect(search(all, "bulacan college").map((x) => x.id)).toEqual(["basc"]);
  });
  it("puts short names that start with the query first", () => {
    expect(search(all, "up").map((x) => x.id)[0]).toBe("up");
  });
});

describe("sections", () => {
  it("shows recent, then the region without repeats, then A–Z", () => {
    const s = sections(all, "", ["bulsu"], "Central Luzon");
    expect(s[0]).toMatchObject({ title: "Recent" });
    expect(s[0].items.map((x) => x.id)).toEqual(["bulsu"]);
    expect(s[1].items.map((x) => x.id)).toEqual(["basc"]);
    expect(s.slice(2).map((x) => x.letter)).toEqual(["B", "I", "P", "U"]);
    expect(s.slice(2).flatMap((x) => x.items).length).toBe(all.length);
  });
  it("is one list of results while searching", () => {
    expect(sections(all, "bul", ["sis"], "NCR")).toEqual([{ title: "Results", items: search(all, "bul") }]);
  });
  it("puts the portals that open now first, as their own section, and still lists them A–Z", () => {
    const mixed = all.map((x) => ({ ...x, status: x.id === "sis" ? "ready" : "soon" }) as Portal);
    const s = sections(mixed, "", ["bulsu"], "Central Luzon");
    expect(s[0]).toMatchObject({ title: "Open now" });
    expect(s[0].items.map((x) => x.id)).toEqual(["sis"]);
    expect(s[1]).toMatchObject({ title: "Recent" });
    expect(sections(mixed, "", [], "NCR")[1].items.map((x) => x.id)).toEqual(["up"]);
    expect(s.slice(3).flatMap((x) => x.items).length).toBe(all.length);
  });
  it("has no Open now section while searching, or when every school opens", () => {
    const ready = all.map((x) => ({ ...x, status: "ready" }) as Portal);
    expect(sections(ready, "", [])[0].letter).toBe("B");
  });
  it("skips recent ids the core no longer lists", () => {
    expect(sections(all, "", ["gone"])[0].letter).toBe("B");
  });
});

describe("remember", () => {
  it("moves the pick to the front and keeps five", () => {
    expect(remember(["a", "b", "c", "d", "e"], "c")).toEqual(["c", "a", "b", "d", "e"]);
    expect(remember(["a", "b", "c", "d", "e"], "f")).toEqual(["f", "a", "b", "c", "d"]);
  });
});
