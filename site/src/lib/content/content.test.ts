import { describe, expect, it } from "vitest";
import changelogMd from "../../../../CHANGELOG.md?raw";
import specIndex from "../../../../docs/specs/README.md?raw";
import { parseChangelog, releaseId } from "./changelog";
import { FEATURES, GROUPS } from "./features";
import recorded from "./roadmap-fallback.json";
import { roadmap, specRows, type GhIssue } from "./roadmap";

const media = import.meta.glob("/static/media/*", { query: "?url", eager: true });
const specFiles = Object.keys(import.meta.glob("../../../../docs/specs/*.md")).map((p) => p.split("/").pop()!.replace(/\.md$/, ""));
const releases = parseChangelog(changelogMd);

describe("057 C9 the feature directory", () => {
  it("has every group once, in the issue's order, each with a name and a line", () => {
    expect(GROUPS.map((g) => g.id)).toEqual(["signin", "today", "schedule", "grades", "study", "lar", "you", "outside", "everywhere"]);
    for (const g of GROUPS) expect(g.name && g.line, g.id).toBeTruthy();
  });
  it("lists 35 to 50 features, and every group has some", () => {
    expect(FEATURES.length).toBeGreaterThanOrEqual(35);
    expect(FEATURES.length).toBeLessThanOrEqual(50);
    for (const g of GROUPS) expect(FEATURES.some((f) => f.group === g.id), g.id).toBe(true);
  });
  it("gives each feature unique kebab-case slug", () => {
    const slugs = FEATURES.map((f) => f.slug);
    expect(new Set(slugs).size).toBe(slugs.length);
    for (const s of slugs) expect(s).toMatch(/^[a-z0-9]+(-[a-z0-9]+)*$/);
  });
});

describe("057 C10 every feature's page", () => {
  it("has a name, a line, 2 to 4 paragraphs and 2 to 5 steps", () => {
    for (const f of FEATURES) {
      expect(f.name && f.line, f.slug).toBeTruthy();
      expect(f.body.length, f.slug).toBeGreaterThanOrEqual(2);
      expect(f.body.length, f.slug).toBeLessThanOrEqual(4);
      expect(f.steps.length, f.slug).toBeGreaterThanOrEqual(2);
      expect(f.steps.length, f.slug).toBeLessThanOrEqual(5);
      for (const t of [f.line, ...f.body, ...f.steps]) expect(t.trim(), f.slug).toBe(t);
    }
  });
  it("arrived in a version the changelog has, and cites a spec that exists", () => {
    const versions = new Set(releases.map((r) => r.version));
    for (const f of FEATURES) {
      if (f.since) expect(versions.has(f.since), `${f.slug} since ${f.since}`).toBe(true);
      if (f.spec) expect(specFiles, f.slug).toContain(f.spec);
    }
  });
  it("shows only media that exists in static/media, with alt text", () => {
    for (const f of FEATURES.filter((f) => f.media)) {
      const m = f.media!;
      expect(Object.keys(media), f.slug).toContain(`/static${m.src}`);
      if (m.poster) expect(Object.keys(media), f.slug).toContain(`/static${m.poster}`);
      expect(m.video ?? false, f.slug).toBe(m.src.endsWith(".mp4"));
      expect(m.alt, f.slug).toBeTruthy();
    }
  });
  it("claims no counts, ratings or reviews (PRODUCT.md)", () => {
    const text = FEATURES.flatMap((f) => [f.line, ...f.body]).join(" ");
    const claims = text.match(/★|\b\d[\d,.]*k?\+? (students|users|downloads|installs)\b|\brated \d|\btestimonial|\b(students|users) (love|trust)/gi);
    expect(claims).toBeNull();
  });
});

describe("057 C12 parseChangelog", () => {
  it("reads every release of the real CHANGELOG.md, newest first", () => {
    expect(releases.length).toBe((changelogMd.match(/^## \d/gm) ?? []).length);
    for (const r of releases) {
      expect(r.version).toMatch(/^\d+\.\d+\.\d+$/);
      expect(r.date).toMatch(/^\d{4}-\d{2}-\d{2}$/);
    }
    const dates = releases.map((r) => r.date);
    expect([...dates].sort().reverse()).toEqual(dates);
  });
  it("splits a release into intro, items and known gaps", () => {
    const r = releases.find((r) => r.version === "0.5.0")!;
    expect(r.date).toBe("2026-11-17");
    expect(r.intro).toMatch(/^IntAssis, rebuilt/);
    expect(r.items[0]).toMatch(/^Adding IntAssis keeps going/);
    expect(r.gaps.some((g) => /real phone/.test(g))).toBe(true);
    expect(r.items.some((i) => /^Known gaps/.test(i))).toBe(false);
  });
  it("keeps an empty release and one with no intro or gaps", () => {
    expect(releases.find((r) => r.version === "0.1.1")).toEqual({ version: "0.1.1", date: "2026-10-10", intro: "", items: [], gaps: [] });
    const old = releases.find((r) => r.version === "0.1.0")!;
    expect(old.intro).toBe("");
    expect(old.items.length).toBeGreaterThan(20);
    expect(old.gaps).toEqual([]);
  });
  it("names each version's anchor", () => expect(releaseId("0.5.0")).toBe("v0.5.0"));
});

describe("057 C13 roadmap", () => {
  const items = roadmap(specIndex, recorded as GhIssue[], releases);
  const lane = (l: string) => items.filter((i) => i.lane === l);

  it("ships every release with its real date, newest first, linking its changelog anchor", () => {
    expect(lane("shipped").map((i) => [i.date, i.href])).toEqual(releases.map((r) => [r.date, `/changelog#v${r.version}`]));
    for (const i of lane("shipped")) expect(i.line, i.title).toBeTruthy();
  });
  it("builds the approved specs and leaves draft specs for later", () => {
    const statuses = new Map(specRows(specIndex).map((s) => [s.id, s.status]));
    for (const i of items.filter((i) => i.kind === "spec")) {
      const id = i.href.split("/").pop()!.replace(/\.md$/, "");
      expect(i.lane, id).toBe(statuses.get(id)!.startsWith("draft") ? "later" : "building");
    }
    expect(lane("building").map((i) => i.title)).toContain("The website, second edition");
    expect(lane("later").map((i) => i.title)).toContain("IntPortal in any browser, signed in");
  });
  it("puts open P0 and P1 issues next and P2 later, in a student's words", () => {
    expect(lane("next").find((i) => i.href.endsWith("/142"))?.title).toBe("Quiz me from my notes");
    expect(lane("later").find((i) => i.href.endsWith("/26"))?.title).toBe("App Store and Play Store");
  });
  it("leaves out the map, internal work and features that already shipped", () => {
    const hrefs = items.map((i) => i.href);
    for (const n of [1, 61, 62, 64, 65, 67, 68, 141, 205, 231, 326]) expect(hrefs.some((h) => h.endsWith(`/issues/${n}`)), `#${n}`).toBe(false);
  });
  it("keeps the lanes in order and every item says something", () => {
    const order = ["shipped", "building", "next", "later"];
    const seen = items.map((i) => order.indexOf(i.lane));
    expect([...seen].sort((a, b) => a - b)).toEqual(seen);
    for (const i of items) expect(i.title && i.line && i.href, JSON.stringify(i)).toBeTruthy();
  });
});
