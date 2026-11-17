import { parseChangelog } from "$lib/content/changelog";
import recorded from "$lib/content/roadmap-fallback.json";
import { fetchIssues, roadmap, unlisted, type GhIssue } from "$lib/content/roadmap";
import changelog from "../../../../CHANGELOG.md?raw";
import specIndex from "../../../../docs/specs/README.md?raw";

/** Spec 057 C13. Open issues are asked of GitHub at build time; the recorded list stands in when
 *  it doesn't answer, as the releases do in +layout.server.ts. */
export async function load() {
  const live = await fetchIssues();
  if (!live) console.warn("GitHub didn't answer; the roadmap uses src/lib/content/roadmap-fallback.json");
  const issues = live ?? (recorded as GhIssue[]);
  const quiet = unlisted(issues);
  if (quiet.length) console.warn(`Not on the roadmap until roadmap.ts gives them a line: ${quiet.join("; ")}`);
  return { items: roadmap(specIndex, issues, parseChangelog(changelog)) };
}
