// PLACEHOLDER until #326 lands.
import { error } from "@sveltejs/kit";
import { FEATURES, GROUPS } from "$lib/content/features";
export const entries = () => FEATURES.map((f) => ({ slug: f.slug }));
export function load({ params }) {
  const feature = FEATURES.find((f) => f.slug === params.slug);
  if (!feature) error(404, "No feature by that name");
  const siblings = FEATURES.filter((f) => f.group === feature.group);
  const i = siblings.indexOf(feature);
  return { feature, group: GROUPS.find((g) => g.id === feature.group)!, prev: siblings[i - 1] ?? null, next: siblings[i + 1] ?? null };
}
