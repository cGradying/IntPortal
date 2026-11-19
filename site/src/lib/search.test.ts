import { describe, expect, it } from "vitest";
import { FAQ, FIXES } from "./content/help";
import { FEATURES, GROUPS } from "./content/features";
import { parseChangelog } from "./content/changelog";
import md from "../../../CHANGELOG.md?raw";
import { buildIndex, score, search, type Hit } from "./search";

const index = buildIndex(FEATURES, GROUPS, [...FAQ, ...FIXES], parseChangelog(md));
const hit = (title: string, line = "", text = ""): Hit => ({ kind: "feature", title, line, text, href: "/x" });

describe("score (058 C2)", () => {
  it("matches word prefixes, every word required", () => {
    expect(score(hit("Class colours"), "col")).toBe(3);
    expect(score(hit("Class colours"), "olours")).toBe(0);
    expect(score(hit("Class colours"), "class blue")).toBe(0);
  });
  it("ranks the title over the line over the body", () => {
    expect(score(hit("Due", "deadlines"), "due")).toBe(3);
    expect(score(hit("Due", "deadlines"), "dead")).toBe(2);
    expect(score(hit("Due", "", "syllabus"), "syll")).toBe(1);
    expect(score(hit("Due", "deadlines"), "due dead")).toBe(2);
  });
  it("ignores case and accents", () => {
    expect(score(hit("Parañaque"), "paranaque")).toBe(3);
  });
});

describe("search (058 C2)", () => {
  it("lists the pages for an empty query", () => {
    const r = search(index, "  ");
    expect([...r.keys()]).toEqual(["page"]);
    expect(r.get("page")!.length).toBeGreaterThan(5);
  });
  it("finds a feature, a help answer and a release", () => {
    expect(search(index, "due").get("feature")?.[0].title).toBe("Due");
    expect(search(index, "app store").get("help")?.[0].href).toBe("/help#q-why-isnt-it-on-the-app-store");
    expect(search(index, "0.5.0").get("release")?.[0].href).toBe("/changelog#v0.5.0");
  });
  it("caps each group and leaves out empty ones", () => {
    const r = search(index, "a");
    for (const hits of r.values()) expect(hits.length).toBeLessThanOrEqual(6);
    expect(search(index, "zzzzqq").size).toBe(0);
  });
  it("puts the group with the best hit first", () => {
    expect([...search(index, "app store").keys()][0]).toBe("help");
    expect([...search(index, "due").keys()][0]).toBe("feature");
  });
  it("puts title hits first", () => {
    const f = search(index, "deadline").get("feature")!;
    expect(f[0].title.toLowerCase()).toContain("deadline");
  });
});

it("keeps help ids unique", () => {
  const ids = [...FAQ, ...FIXES].map((h) => h.id);
  expect(new Set(ids).size).toBe(ids.length);
});
