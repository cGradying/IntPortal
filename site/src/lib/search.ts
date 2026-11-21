// Spec 058 C2: the site's search. A small index built from the same content the
// pages read, matched by word prefixes. ponytail: linear scan over ~100 items;
// a real index only if the site grows past a few thousand.
import type { Feature, Release } from "./content/types";
import type { HelpItem } from "./content/help";
import { releaseId } from "./content/changelog";

export type Kind = "page" | "feature" | "help" | "release";
export type Hit = { kind: Kind; title: string; line: string; href: string; text: string };

export const KINDS: { kind: Kind; name: string }[] = [
  { kind: "page", name: "Pages" },
  { kind: "feature", name: "Features" },
  { kind: "help", name: "Help" },
  { kind: "release", name: "Releases" },
];

export const PAGES: Hit[] = [
  ["/", "Home", "The portal, the app in six screens, and every download"],
  ["/features", "Features", "Everything in IntPortal, by tab"],
  ["/download", "Download", "Android, iPhone, Mac, Windows, Linux"],
  ["/help", "Help", "Installing it, questions, and fixes"],
  ["/changelog", "What's new", "Every release, newest first"],
  ["/roadmap", "Roadmap", "Shipped, building, next and later"],
  ["/privacy", "Privacy", "What stays on your phone, and the few places it reaches"],
  ["/about", "About", "Made by one student"],
  ["/reel", "The reel", "The opening film"],
].map(([href, title, line]) => ({ kind: "page" as const, href, title, line, text: "" }));

const words = (s: string) => s.toLowerCase().normalize("NFKD").replace(/[\u0300-\u036f]/g, "").split(/[^a-z0-9.]+/).filter(Boolean);

/** Release notes are Markdown; the result line is plain. */
const plain = (md: string) => md.replace(/\[([^\]]+)\]\([^)]+\)/g, "$1").replace(/[*`_]/g, "");

/** The body only needs its distinct words: matching is by word prefix. */
const bag = (...parts: string[]) => [...new Set(words(parts.join(" ")))].join(" ");

export function buildIndex(features: Feature[], groups: { id: string; name: string }[], faq: HelpItem[], releases: Release[]): Hit[] {
  const group = (id: string) => groups.find((g) => g.id === id)?.name ?? "";
  return [
    ...PAGES,
    ...features.map((f) => ({ kind: "feature" as const, title: f.name, line: f.line, href: `/features/${f.slug}`, text: bag(group(f.group), ...f.body) })),
    ...faq.map((h) => ({ kind: "help" as const, title: h.q, line: h.a, href: `/help#${h.id}`, text: "" })),
    ...releases.map((r) => ({ kind: "release" as const, title: `IntPortal ${r.version}`, line: plain(r.intro || r.items[0] || ""), href: `/changelog#${releaseId(r.version)}`, text: bag(...r.items) })),
  ];
}

/** 3 when every word starts a word of the title, 2 of the line, 1 of the rest; 0 is no match. */
export function score(hit: Hit, query: string): number {
  const q = words(query);
  if (!q.length) return 0;
  const tiers = [words(hit.title), words(hit.line), words(hit.text)];
  let worst = 3;
  for (const w of q) {
    const tier = tiers.findIndex((t) => t.some((x) => x.startsWith(w)));
    if (tier < 0) return 0;
    worst = Math.min(worst, 3 - tier);
  }
  return worst;
}

/** Hits by kind, best first, at most `cap` each; the kind with the best hit
 *  comes first, and kinds with no hits are left out. */
export function search(index: Hit[], query: string, cap = 6): Map<Kind, Hit[]> {
  if (!words(query).length) return new Map([["page", index.filter((h) => h.kind === "page")]]);
  const scored = index.map((h, i) => ({ h, i, s: score(h, query) })).filter((x) => x.s > 0);
  scored.sort((a, b) => b.s - a.s || a.i - b.i);
  const kinds = KINDS.map(({ kind }) => kind).filter((k) => scored.some((x) => x.h.kind === k));
  const best = (k: Kind) => scored.find((x) => x.h.kind === k)!.s;
  kinds.sort((a, b) => best(b) - best(a));
  return new Map(kinds.map((k) => [k, scored.filter((x) => x.h.kind === k).slice(0, cap).map((x) => x.h)]));
}
