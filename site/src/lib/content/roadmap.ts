// Spec 057 C13: the roadmap's four lanes, from the changelog, the spec index and the open issues.
import { REPO, REPO_URL } from "$lib/releases";
import { releaseId } from "./changelog";
import type { Release, RoadItem } from "./types";

/** The fields the roadmap reads from GitHub's issues API. */
export type GhIssue = { number: number; title: string; html_url: string; labels: { name: string }[]; pull_request?: unknown };

export const ISSUES_URL = `https://api.github.com/repos/${REPO}/issues?state=open&per_page=100`;
const SPECS_URL = `${REPO_URL}/blob/main/docs/specs`;

/**
 * What an open issue means to a student. Only issues listed here show: a new issue stays off until
 * someone writes its line (the build warns, see `unlisted`). `null` marks one looked at and left off:
 * internal work, or a feature that already shipped while its issue stayed open.
 */
const ISSUES: Record<number, { title: string; line: string } | null> = {
  142: { title: "Quiz me from my notes", line: "Pick a note and LAR quizzes you on it." },
  130: { title: "eMabini fixes", line: "Fix a rejected eMabini login without starting over, and clearer eMabini wording." },
  66: { title: "Accessibility pass", line: "Every screen checked for screen readers, large text and Reduce Motion." },
  269: { title: "Quiz me on a syllabus row", line: "Tap a lecture in your syllabus and study it right there." },
  82: { title: "A syllabus from a course title", line: "Type a course name or paste its text and LAR drafts the outline for you to check." },
  205: { title: "Deadlines in Android's calendar", line: "Checking that each deadline lands on the right day in your Android calendar, all-day or at its due time." },
  26: { title: "App Store and Play Store", line: "Install IntPortal from the stores instead of a file. Needs store accounts first." },
  24: { title: "Home-screen widget", line: "Your next class on the home screen. Waits on a paid Apple developer account." },
  62: null, // typed errors inside the app
  93: null, // a flag inside the syllabus planner
  270: null, // parked design ideas
  326: null, // the website's own content; spec 057 stands for it
  141: null, // shipped in 0.5.0 (Qwen3 1.7B is the option on the IntAssis card)
  80: null, // shipped in 0.1.4 (Ask AI in a note)
  81: null, // shipped in 0.1.4 (cards from a note or PDF, Why?)
  92: null, // shipped in 0.1.4 (the same, in the note editor and decks)
};

/** Specs in a student's words; others read their file name and the index's Covers column. */
const SPECS: Record<string, { title: string; line: string }> = {
  "056-web-app": { title: "IntPortal in any browser, signed in", line: "The same app in any browser, signed in, with your data kept in the browser." },
  "057-website-v2": { title: "The website, second edition", line: "A 3D portal you can dive through, a page for every feature, help, the changelog, this roadmap and About." },
};

/** Releases whose changelog has no intro for students; newer ones say it in their intro. */
const RELEASES: Record<string, string> = {
  "0.2.1": "A new intro before sign-in, your campus in pixels, and a much smaller app.",
  "0.2.0": "A welcome before sign-in, the portal wall, and a clearer Today and Grades.",
  "0.1.10": "LAR's chat button became a pixel chip.",
  "0.1.9": "The pixel week, one Due list, formatted notes, themes, backup and LAR planning your day.",
  "0.1.8": "A smarter LAR that says when it doesn't know, and better note search.",
  "0.1.7": "The portal hub: about 100 schools to pick from.",
  "0.1.6": "LAR in your school's colours, and the tile portal.",
  "0.1.5": "Flashcards from a PDF.",
  "0.1.4": "eMabini, and LAR answering from your notes.",
  "0.1.3": "IntAssis: ask LAR, on your phone.",
  "0.1.2": "Android beta builds, and the groundwork for IntAssis.",
  "0.1.1": "Sign-in tries all eight SIS servers, and an empty server no longer wipes your schedule.",
  "0.1.0": "The first build: schedule, grades, notes, decks, reminders and your next class on the Lock Screen.",
};

const INTERNAL = new Set(["wayfinder:map", "type:refactor", "type:chore", "role:qa"]);

/** The spec index's table rows: `| [057-website-v2](057-website-v2.md) | approved | Covers |`. */
export function specRows(md: string) {
  return [...md.matchAll(/^\|\s*\[([\w-]+)\]\(([^)]+)\)\s*\|\s*([^|]+?)\s*\|\s*([^|]+?)\s*\|$/gm)].map(([, id, file, status, covers]) => ({ id, file, status, covers }));
}

const humanize = (id: string) => {
  const words = id.replace(/^\d+-/, "").replace(/-/g, " ");
  return words.charAt(0).toUpperCase() + words.slice(1);
};

const firstSentence = (s: string) => s.replace(/\s*\(#[\d#, –-]+\)\s*$/, "").split(/(?<=\.)\s/)[0];

/**
 * Shipped is every release with its date, newest first. Building is each spec marked approved or
 * building. Next is open P0 and P1 issues; Later is draft specs and open P2 issues. An issue with no
 * priority, a pull request and internal work stay off.
 */
export function roadmap(specIndexMd: string, issues: GhIssue[], releases: Release[]): RoadItem[] {
  const shipped: RoadItem[] = releases.map((r) => ({
    title: `IntPortal ${r.version}`,
    line: RELEASES[r.version] ?? firstSentence(r.intro || r.items[0] || ""),
    lane: "shipped",
    href: `/changelog#${releaseId(r.version)}`,
    kind: "release",
    date: r.date,
  }));
  const specs = specRows(specIndexMd).flatMap(({ id, file, status, covers }): RoadItem[] => {
    const lane = /^(approved|building)\b/.test(status) ? "building" : /^draft\b/.test(status) ? "later" : null;
    return lane ? [{ title: SPECS[id]?.title ?? humanize(id), line: SPECS[id]?.line ?? covers, lane, href: `${SPECS_URL}/${file}`, kind: "spec" }] : [];
  });
  const open = issues.flatMap((i): RoadItem[] => {
    const said = ISSUES[i.number];
    const labels = new Set(i.labels.map((l) => l.name));
    const lane = labels.has("P0") || labels.has("P1") ? "next" : labels.has("P2") ? "later" : null;
    return said && lane && !i.pull_request ? [{ ...said, lane, href: i.html_url, kind: "issue" }] : [];
  });
  const order = { shipped: 0, building: 1, next: 2, later: 3 };
  return [...shipped, ...specs, ...open].sort((a, b) => order[a.lane] - order[b.lane]);
}

/** Open issues with a priority that nobody has written a line for yet, so the build can say so. */
export const unlisted = (issues: GhIssue[]) =>
  issues.filter((i) => !i.pull_request && !(i.number in ISSUES) && !i.labels.some((l) => INTERNAL.has(l.name)) && i.labels.some((l) => /^P[012]$/.test(l.name))).map((i) => `#${i.number} ${i.title}`);

/** Open issues from GitHub; null when it doesn't answer. */
export async function fetchIssues(get: typeof fetch = fetch): Promise<GhIssue[] | null> {
  try {
    const res = await get(ISSUES_URL, { headers: { Accept: "application/vnd.github+json" } });
    return res.ok ? ((await res.json()) as GhIssue[]) : null;
  } catch {
    return null;
  }
}
