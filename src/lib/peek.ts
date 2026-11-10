// Peeking through the portal on the landing (spec 010 C36–C37): what is on the
// other side, page by page, with LAR naming each. Sample data only: nothing
// here is the student's until they sign in.

export type PeekPage = "today" | "schedule" | "grades" | "study";

export const PAGES: { id: PeekPage; title: string; lar: string }[] = [
  { id: "today", title: "Today", lar: "Today: next class mo at ang mga due, isang tingin lang." },
  { id: "schedule", title: "Schedule", lar: "Buong linggo mo, kahit walang signal sa jeep." },
  { id: "grades", title: "Grades", lar: "Lalabas dito ang grades mo pag nag-post na si Prof." },
  { id: "study", title: "Study", lar: "Notes at flashcards, para ready ka sa exam." },
];

/** Each page stays this long before the next one turns. */
export const PAGE_MS = 3600;

/** The page after `page`, or null once the last one has been seen (the peek closes). */
export const nextPage = (page: number): number | null => (page + 1 < PAGES.length ? page + 1 : null);

/** A touch is a tap, not a swipe, when the finger barely moved and let go quickly. */
export const isTap = (dx: number, dy: number, ms: number) => Math.hypot(dx, dy) < 10 && ms < 400;
