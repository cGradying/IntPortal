// The portal hub (spec 010 C13a): every school the core lists, searchable,
// with the ones the student picked lately and the ones in their region on
// top. Pure, so the lists are testable; PortalHub draws them.
import type { Portal } from "./api";

export interface Section {
  title: string;
  /** The A–Z rail jumps to sections that have a letter. */
  letter?: string;
  items: Portal[];
}

/** Lower case, without accents or punctuation, so "Ñ" finds "n" and "ISAT U" finds "isatu". */
const norm = (s: string) =>
  s
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9 ]/g, "");

/** Portals matching every word of `q`, short names that start with it first. */
export function search(portals: Portal[], q: string): Portal[] {
  const words = norm(q).split(/\s+/).filter(Boolean);
  if (!words.length) return portals;
  const hay = (p: Portal) => norm(`${p.name} ${p.name.replace(/\s/g, "")} ${p.school} ${p.region} ${p.id}`);
  const hits = portals.filter((p) => words.every((w) => hay(p).includes(w)));
  const lead = (p: Portal) => (norm(p.name).replace(/\s/g, "").startsWith(words.join("")) ? 0 : 1);
  return hits.sort((a, b) => lead(a) - lead(b));
}

/** The hub's lists: search results, or recent, the region, then A–Z by school. */
export function sections(portals: Portal[], q: string, recent: string[], region?: string): Section[] {
  if (q.trim()) return [{ title: "Results", items: search(portals, q) }];
  const byId = new Map(portals.map((p) => [p.id, p]));
  const out: Section[] = [];
  const mine = recent.map((id) => byId.get(id)).filter((p): p is Portal => !!p);
  if (mine.length) out.push({ title: "Recent", items: mine });
  const near = region ? portals.filter((p) => p.region === region && !recent.includes(p.id)) : [];
  if (near.length) out.push({ title: region!, items: near });
  const sorted = [...portals].sort((a, b) => a.school.localeCompare(b.school));
  for (const p of sorted) {
    const letter = norm(p.school)[0]?.toUpperCase() ?? "#";
    const last = out.at(-1);
    if (last?.letter === letter) last.items.push(p);
    else out.push({ title: letter, letter, items: [p] });
  }
  return out;
}

/** `id` first, at most five, no repeats. */
export const remember = (recent: string[], id: string) => [id, ...recent.filter((r) => r !== id)].slice(0, 5);

const KEY = "intportal.hub.recent";
export function loadRecent(): string[] {
  try {
    const v = JSON.parse(localStorage.getItem(KEY) ?? "[]");
    return Array.isArray(v) ? v.filter((x) => typeof x === "string") : [];
  } catch {
    return [];
  }
}
export function saveRecent(ids: string[]) {
  try {
    localStorage.setItem(KEY, JSON.stringify(ids));
  } catch {
    // Private mode or storage off: the hub just forgets.
  }
}
