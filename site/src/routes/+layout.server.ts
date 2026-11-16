import recorded from "$lib/fallback.json";
import { fetchRelease, pick, type GhRelease } from "$lib/releases";

/** The release, asked of GitHub at build time; the last known one when it doesn't
 *  answer (051 C9). A server load, so only the picked release lands in the page. */
export async function load() {
  const live = await fetchRelease();
  if (!live) console.warn("GitHub didn't answer; using src/lib/fallback.json");
  return { release: live ?? pick(recorded as GhRelease[]) };
}
