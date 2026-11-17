import { error } from "@sveltejs/kit";
import { FEATURES, GROUPS } from "$lib/content/features";
import type { EntryGenerator } from "./$types";

/** Every feature's page is prerendered (spec 057 C10). */
export const entries: EntryGenerator = () => FEATURES.map((f) => ({ slug: f.slug }));

/** The feature, its group, and Previous and Next within that group. */
export function load({ params }) {
  const feature = FEATURES.find((f) => f.slug === params.slug);
  if (!feature) error(404, "No feature by that name.");
  const siblings = FEATURES.filter((f) => f.group === feature.group);
  const at = siblings.indexOf(feature);
  return { feature, group: GROUPS.find((g) => g.id === feature.group)!, prev: siblings[at - 1] ?? null, next: siblings[at + 1] ?? null };
}
