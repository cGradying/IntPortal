import { parseChangelog } from "$lib/content/changelog";
import recorded from "$lib/content/roadmap-fallback.json";
import { fetchIssues, roadmap, type GhIssue } from "$lib/content/roadmap";
import changelog from "../../../../CHANGELOG.md?raw";
import specIndex from "../../../../docs/specs/README.md?raw";

/** Spec 057 C13. Open issues are asked of GitHub at build time; the recorded list stands in when
 *  it doesn't answer, as the releases do in +layout.server.ts. */
export async function load() {
  const live = await fetchIssues();
  if (!live) console.warn("GitHub didn't answer; the roadmap uses src/lib/content/roadmap-fallback.json");
  return { items: roadmap(specIndex, live ?? (recorded as GhIssue[]), parseChangelog(changelog)) };
}
