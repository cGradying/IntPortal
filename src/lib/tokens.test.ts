import { describe, expect, it } from "vitest";
// @ts-expect-error type error without @types/node package
import { readFileSync, readdirSync } from "node:fs";
// @ts-expect-error type error without @types/node package
import { fileURLToPath } from "node:url";
import { scan } from "../../scripts/tap-targets.mjs";
import { PALETTES, contrast, schoolRoles, setSchool } from "./rooms";
import { THEMES } from "./lar/sprite";

const root = fileURLToPath(new URL("..", import.meta.url));
const css = readFileSync(new URL("./app.css", import.meta.url), "utf8");

function svelteFiles(dir = root): string[] {
  return readdirSync(dir, { withFileTypes: true }).flatMap((e: { name: string; isDirectory(): boolean }) => {
    const p = `${dir}${e.name}`;
    return e.isDirectory() ? svelteFiles(`${p}/`) : p.endsWith(".svelte") ? [p] : [];
  });
}
const files = svelteFiles().map((p) => ({ name: p.slice(root.length), src: readFileSync(p, "utf8") }));
const style = (src: string) => src.split("<style")[1] ?? "";

describe("spec 045 tokens", () => {
  it("c3_ground_pauses_when_backgrounded", () => {
    expect(css).toMatch(/:root\[data-hidden\] \.dots::before,\s*:root\[data-hidden\] \.dots::after \{\s*animation-play-state: paused;/);
  });

  it("c4_school_sets_the_accent: a school's theme reaches both rooms' pools and accent", () => {
    for (const [id, t] of Object.entries(THEMES)) for (const room of ["night", "day"] as const) {
      const r = schoolRoles(t, room);
      expect(contrast(r["--gold"], room === "night" ? "#170b1a" : "#ffffff"), `${id} ${room}`).toBeGreaterThanOrEqual(3);
    }
    expect(typeof setSchool).toBe("function");
    expect(Object.keys(PALETTES).length).toBeGreaterThan(0);
  });

  it("c8_c11_seven_text_roles", () => {
    for (const r of ["display", "title", "headline", "body", "label", "caption", "numeral"]) expect(css, r).toMatch(new RegExp(`--text-${r}: min\\(`));
  });

  it("c20_tokens_exist", () => {
    for (const t of ["--ease-spring", "--t-quick: 0.16s", "--t-move: 0.32s", "--t-flow: 0.36s", "--t-hero: 0.55s"]) expect(css).toContain(t);
  });

  it("c20_no_raw_durations: components use tokens, stepped pixel animations aside", () => {
    // Files other open PRs own (2026-11-14) still carry token-sized literals; they move to tokens when those merge.
    const owned = /^lib\/(Landing|NoteEditor|ClassSheet|DueCard|WeekGrid)\.svelte$|^lib\/screens\/(Today|Schedule|You)\.svelte$/;
    // Off-scale literals (0.2s, 0.3s, 0.4s, ...) are tuned per component and need a design call to snap; the count can only fall.
    const offScale = 76;
    let off = 0;
    for (const f of files) {
      for (const line of style(f.src).split("\n")) {
        if (!/^\s*(transition|animation)\s*:/.test(line) || line.includes("steps(") || line.includes("t-ok")) continue;
        for (const m of line.matchAll(/(?<![\w.-])([0-9.]+)m?s\b/g)) {
          if (["0.16", "0.32", "0.36", "0.55"].includes(m[1]) && !owned.test(f.name)) expect.fail(`${f.name}: ${line.trim()} should use a --t- token`);
        }
        if (/(?<![\w.-])[0-9.]+m?s\b/.test(line)) off++;
        expect(line.includes("cubic-bezier(0.34, 1.56") && !owned.test(f.name), `${f.name}: use --ease-spring`).toBe(false);
      }
    }
    expect(off).toBeLessThanOrEqual(offScale);
  });

  it("c21_press_is_only_a_colour_change_under_reduce_motion", () => {
    const reduce = css.slice(css.indexOf("prefers-reduced-motion: reduce"));
    expect(reduce).toMatch(/:active \{\s*scale: none !important;/);
    expect(reduce).toMatch(/:active \{\s*filter: brightness/);
  });

  it("c17_study_session_does_not_celebrate", () => {
    expect(files.find((f) => f.name === "lib/StudySession.svelte")!.src).not.toContain("Confetti");
  });

  it("040_c7_no_button_rule_under_44px", () => {
    expect(scan()).toEqual([]);
  });
});
