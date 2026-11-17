import { describe, expect, it, vi } from "vitest";
// @ts-expect-error type error without @types/node package
import { readFileSync, readdirSync } from "node:fs";
// @ts-expect-error type error without @types/node package
import { fileURLToPath } from "node:url";
import { scan } from "../../scripts/tap-targets.mjs";
import { applyRoom, schoolRoles, setSchool } from "./rooms";
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
  it("no token is defined in terms of itself (a cycle makes every use of it invalid)", () => {
    const loops = [...css.matchAll(/(--[\w-]+):([^;]*);/g)].filter(([, name, value]) => value.includes(`var(${name})`)).map(([, name]) => name);
    expect(loops).toEqual([]);
  });

  it("text typed into a field is never under 16 px, so iOS does not zoom the page", () => {
    expect(css).toMatch(/--text-input: max\(16px, [^;]+\);/);
  });

  it("c3_css_pauses_the_ground_when_data_hidden (rule is present)", () => {
    expect(css).toMatch(/:root\[data-hidden\] \.dots::before,\s*:root\[data-hidden\] \.dots::after \{\s*animation-play-state: paused;/);
  });

  it("c4_school_sets_the_accent: setSchool changes --gold and the pools on the root", () => {
    const props = new Map<string, string>();
    const root = {
      dataset: {} as Record<string, string>,
      style: {
        setProperty: (k: string, v: string) => void props.set(k, v),
        removeProperty: (k: string) => void props.delete(k),
        *[Symbol.iterator]() { yield* props.keys(); },
      },
    };
    vi.stubGlobal("document", { documentElement: root });
    try {
      applyRoom("night");
      const pup = props.get("--gold");
      setSchool(THEMES.mabini);
      expect(props.get("--gold")).toBe(schoolRoles(THEMES.mabini, "night")["--gold"]);
      expect(props.get("--gold")).not.toBe(pup);
      expect(props.get("--aura-a")).toBe(schoolRoles(THEMES.mabini, "night")["--aura-a"]);
      setSchool(THEMES.sis);
      expect(props.get("--gold")).toBe(pup);
    } finally {
      vi.unstubAllGlobals();
    }
  });

  it("c8_c11_text_role_tokens_exist (css presence)", () => {
    for (const r of ["display", "title", "headline", "body", "label", "caption", "numeral"]) expect(css, r).toMatch(new RegExp(`--text-${r}: min\\(`));
  });

  it("c20_motion_tokens_exist (css presence)", () => {
    for (const t of ["--ease-spring", "--t-quick: 0.16s", "--t-move: 0.32s", "--t-flow: 0.36s", "--t-hero: 0.55s", "--t-exit: 0.2s", "--shift: 12px", "--ease-in", "--ease-sheet"]) expect(css).toContain(t);
  });

  it("c20_no_raw_durations: components use tokens, stepped pixel animations aside", () => {
    // Files other open PRs own (2026-11-14) still carry token-sized literals; they move to tokens when those merge.
    const owned = /^lib\/(Landing|NoteEditor|ClassSheet|DueCard|WeekGrid)\.svelte$|^lib\/screens\/(Today|Schedule|You)\.svelte$/;
    // Off-scale literals (0.2s, 0.3s, 0.4s, ...) are tuned per component and need a design call to snap; the count can only fall.
    const offScale = 9; // was 77 as a cap; 9 is what is left (one is the screens' own) after the motion vocabulary
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

  it("c21_reduce_motion_press_rule_is_colour_only (css presence)", () => {
    const reduce = css.slice(css.indexOf("prefers-reduced-motion: reduce"));
    expect(reduce).toMatch(/:not\(:disabled\):is\(:active, \[data-press\]\) \{\s*scale: none !important;\s*transform: none !important;\s*translate: none !important;\s*filter: brightness/);
  });

  // Spec 055 C11: the session celebrates with its own game kit, never the app's Confetti.
  it("c17_study_session_uses_its_own_kit", () => {
    expect(files.find((f) => f.name === "lib/StudySession.svelte")!.src).not.toContain("Confetti");
  });

  // Component tests aren't set up in this repo, so the Done and Due rules are guarded on the source.
  it("c18_due_card_has_no_lar_and_no_burst_or_hop", () => {
    const src = files.find((f) => f.name === "lib/DueCard.svelte")!.src;
    for (const banned of ["lar/Lar", "<Lar", "burst", "fieldPulse", "sinkTiles", "hop", "combo"]) expect(src).not.toContain(banned);
  });

  it("040_c7_no_button_rule_under_44px", () => {
    expect(scan()).toEqual([]);
  });
});
