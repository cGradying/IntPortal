// Spec 057 C12: the repo's CHANGELOG.md as releases, newest first (the file's own order).
import type { Release } from "./types";

/** The anchor of a version on /changelog, also used by the roadmap's Shipped lane. */
export const releaseId = (version: string) => `v${version}`;

/**
 * Each `## 0.4.0 (2026-11-17)` section: the lines before its first bullet are the intro, the bullets
 * after "Known gaps:" are its gaps, every other bullet is an item. Items stay as written (Markdown,
 * PR numbers and all); the page decides how to show them.
 */
export function parseChangelog(md: string): Release[] {
  const releases: Release[] = [];
  for (const section of md.split(/^## /m).slice(1)) {
    const [head, ...lines] = section.split("\n");
    const m = head.match(/^v?(\d+\.\d+\.\d+\S*)\s+\((\d{4}-\d{2}-\d{2})\)/);
    if (!m) continue;
    const r: Release = { version: m[1], date: m[2], intro: "", items: [], gaps: [] };
    const intro: string[] = [];
    let inGaps = false;
    for (const line of lines) {
      const t = line.trim();
      if (/^known gaps:?$/i.test(t)) inGaps = true;
      else if (t.startsWith("- ")) (inGaps ? r.gaps : r.items).push(t.slice(2).trim());
      else if (t && !inGaps && !r.items.length) intro.push(t);
    }
    r.intro = intro.join(" ");
    releases.push(r);
  }
  return releases;
}
