// @ts-nocheck
// Spec 040 C7: lists CSS rules on buttons that set a height, min-height or width under 44 px.
// A heuristic (a 44 pt hit area can come from padding or a parent), so it flags and a person reads.
// Run: node scripts/tap-targets.mjs   (exit 1 if anything is flagged and not on the allowlist)
import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

// Follow-up: these files belong to other open PRs (2026-11-14); fix their targets when those merge.
const SKIP = /^(ClassSheet|NoteEditor|Schedule|Today|You|Landing|DueCard|WeekGrid)\.svelte$/;
const BUTTONY = /(^|[\s,>.])(button|\.(back|x|chip|close|tap|btn|tab|swatch|term)s?)\b|\[role="?(button|tab)"?\]/;

function* walk(dir) {
  for (const e of readdirSync(dir, { withFileTypes: true })) {
    const p = join(dir, e.name);
    if (e.isDirectory()) yield* walk(p);
    else if (p.endsWith(".svelte")) yield p;
  }
}

export function scan(root = fileURLToPath(new URL("../src", import.meta.url))) {
  const hits = [];
  for (const f of walk(root)) {
    if (SKIP.test(f.split("/").pop())) continue;
    const style = readFileSync(f, "utf8").split("<style")[1];
    if (!style) continue;
    for (const m of style.matchAll(/([^{}]+)\{([^{}]*)\}/g)) {
      const [, sel, body] = m;
      if (!BUTTONY.test(sel.trim().split(/[\s>]+/).pop())) continue;
      for (const d of body.matchAll(/(?:^|;|\s)(height|min-height|width|min-width):\s*(\d+)px/g)) {
        if (+d[2] < 44) hits.push(`${f.replace(root + "/", "")}: ${sel.trim().replace(/\s+/g, " ")} { ${d[1]}: ${d[2]}px }`);
      }
    }
  }
  return hits;
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  const hits = scan();
  console.log(hits.join("\n") || "no button rule under 44 px");
  process.exit(hits.length ? 1 : 0);
}
