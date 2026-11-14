// @ts-nocheck
// The measurable half of DESIGN.md's rules: in a component's <style>, a type size, an interface
// duration and a corner radius come from the tokens in src/lib/app.css, never a literal.
// Run: node scripts/style-lint.mjs            (exit 1 if anything is flagged)
//      node scripts/style-lint.mjs --report   (counts by value, to plan a cleanup)
import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";

// Pixel art and its stage: sizes there are the art's own grid, not interface type.
const ART = /^(src\/lib\/)?(CampusStrip|Scene|Jeepney|Confetti|PixelIcon)\.svelte$/;
// Ambient loops (the ground's drift, a blinking cursor) run for seconds and are not interface motion.
const AMBIENT_S = 1;

function* walk(dir) {
  for (const e of readdirSync(dir, { withFileTypes: true })) {
    const p = join(dir, e.name);
    if (e.isDirectory()) yield* walk(p);
    else if (p.endsWith(".svelte")) yield p;
  }
}

const seconds = (v) => (v.endsWith("ms") ? parseFloat(v) / 1000 : parseFloat(v));

export function scan(file, text) {
  const out = [];
  const style = /<style[^>]*>([\s\S]*?)<\/style>/.exec(text);
  if (!style || ART.test(file)) return out;
  const base = text.slice(0, style.index).split("\n").length;
  style[1].split("\n").forEach((line, i) => {
    const at = base + i;
    const decl = /^\s*([a-z-]+)\s*:\s*(.+?);?\s*$/.exec(line);
    if (!decl) return;
    const [, prop, value] = decl;
    // A size relative to its parent (em, %) or handed in by a variable is fine; a literal px or rem is not.
    const sized = prop === "font" ? value.split("/")[0] : value;
    if ((prop === "font-size" || prop === "font") && /\d(px|rem)\b/.test(sized.replace(/var\([^)]*\)/g, ""))) out.push({ file, at, rule: "type", value });
    if (prop === "border-radius" && !/^(0|50%|999px|inherit|var\(--radius[a-z-]*\))( (0|var\(--radius[a-z-]*\)))*$/.test(value)) out.push({ file, at, rule: "radius", value });
    // A loop that never ends is ambience and a stepped one is pixel art; neither is interface motion.
    if (/^(transition|animation)(-duration)?$/.test(prop) && !/infinite|steps\(/.test(value)) {
      // A stagger worked out in calc() is a delay, not a duration.
      for (const m of value.replace(/calc\((?:[^()]|\([^()]*\))*\)/g, "").matchAll(/(?<![\w.-])(\d*\.?\d+m?s)\b/g)) {
        if (seconds(m[1]) > 0 && seconds(m[1]) <= AMBIENT_S) out.push({ file, at, rule: "motion", value: m[1] });
      }
    }
  });
  return out;
}

if (process.argv[1]?.endsWith("style-lint.mjs")) {
  const found = [...walk("src")].flatMap((f) => scan(f, readFileSync(f, "utf8")));
  if (process.argv.includes("--report")) {
    for (const rule of ["type", "motion", "radius"]) {
      const by = {};
      found.filter((f) => f.rule === rule).forEach((f) => (by[f.value] = (by[f.value] ?? 0) + 1));
      console.log(`\n${rule}: ${found.filter((f) => f.rule === rule).length}`);
      Object.entries(by).sort((a, b) => b[1] - a[1]).slice(0, 40).forEach(([v, n]) => console.log(String(n).padStart(4), v));
    }
  } else {
    found.forEach((f) => console.error(`${f.file}:${f.at}: ${f.rule}: ${f.value}`));
    if (found.length) {
      console.error(`\n${found.length} literal(s). Use the tokens in src/lib/app.css (--text-*, --t-*, --radius*).`);
      process.exit(1);
    }
    console.log("Type sizes, interface durations and corner radii all come from tokens.");
  }
}
