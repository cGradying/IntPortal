// The intro (spec 049): a new student pages through the app one feature at a time before the
// sign-in form, and each page does its thing on the stage. Pure data and small pure helpers, so
// the order, the copy and the sample maths are testable; Landing draws it and wires each act.
import { HAND_TUNED, PALETTES } from "../rooms";
import { cleanName } from "../profile";
import { interval } from "../interval";
import type { TermPoint } from "../gpaTrend";

export type PageId = "hello" | "school" | "today" | "deadlines" | "study" | "offline" | "look" | "reminders" | "signin";

/** What a page does on the stage (049 C7): Landing runs these. */
export type Act =
  /** LAR answers in his bubble. */
  | "say"
  /** LAR hops and waves. */
  | "cheer"
  /** The portal rings out from its centre. */
  | "ring"
  /** The portal wall opens to pick another school. */
  | "wall"
  /** The portal's mouth opens onto this page's live view and stays open while the page does. */
  | "mouth"
  /** The whole landing wears a look. */
  | "room"
  /** The phone is asked for notifications. */
  | "remind"
  /** The app opens on sample data. */
  | "demo";

/** Where LAR waits while the page is up: beside the portal, or under it. */
export type Spot = "left" | "right" | "below";

export interface IntroPage {
  id: PageId;
  title: string;
  line: string;
  /** What LAR says as the page arrives; {you} is the student's name, or "iskolar". */
  lar: string;
  spot: Spot;
  acts: Act[];
}

export const PAGES: IntroPage[] = [
  { id: "hello", title: "Student IntPortal", line: "Your PUP schedule, grades and deadlines, on your phone.", lar: "", spot: "below", acts: ["say", "cheer"] },
  { id: "school", title: "Where do you study?", line: "Pick your campus, so LAR knows your school.", lar: "Saan ka, {you}? Pili ka lang.", spot: "right", acts: ["ring", "wall", "say"] },
  { id: "today", title: "Your next class, counting down", line: "Drag the clock and watch Up next turn into In session.", lar: "Silipin mo sa portal.", spot: "below", acts: ["mouth"] },
  { id: "deadlines", title: "Tick it off", line: "Every due date in one list, with a heads-up before it.", lar: "Subukan mo, i-tick mo.", spot: "left", acts: ["say"] },
  { id: "study", title: "Grades and study", line: "GPA by term, and cards that come back on time.", lar: "Tap the card, {you}.", spot: "right", acts: ["say"] },
  { id: "offline", title: "Works with no signal", line: "Your login stays in the phone's keychain. No IntPortal server: the app talks only to PUP SIS.", lar: "Kahit sa jeep, walang problema.", spot: "left", acts: ["say"] },
  { id: "look", title: "Make it yours", line: "Pick a look. The whole app wears it.", lar: "Ano'ng bagay sa'yo?", spot: "right", acts: ["room", "say"] },
  { id: "reminders", title: "A heads-up before class?", line: "A nudge 10 minutes before each class, and the evening before a deadline. Change it any time on You.", lar: "Ako na ang bahala sa paalala.", spot: "below", acts: ["remind"] },
  { id: "signin", title: "Sign in", line: "", lar: "Tara, {you}. Sign in na.", spot: "below", acts: ["demo"] },
];

export const SIGNIN = PAGES.findIndex((p) => p.id === "signin");

/** The page after or before `i`, held inside the intro. */
export const step = (i: number, by: 1 | -1) => Math.max(0, Math.min(PAGES.length - 1, i + by));

/** A horizontal swipe on the page: 1 forward, -1 back, 0 not a swipe. */
export function swipe(dx: number, dy: number): 1 | -1 | 0 {
  if (Math.abs(dx) < 48 || Math.abs(dx) < Math.abs(dy) * 1.5) return 0;
  return dx < 0 ? 1 : -1;
}

/** A line with the student's name in it, or "iskolar" without one. */
export const fillName = (line: string, name: string) => line.replaceAll("{you}", cleanName(name) || "iskolar");

/** What LAR types as the student types their name. */
export const helloLine = (name: string) => {
  const n = cleanName(name);
  return n ? `Hi, ${n}! Ako si LAR.` : "";
};

/** What LAR says when a campus is picked. */
export const campusLine = (campus: string) => `PUP ${campus}! Kilala ko 'yan.`;

// Today (049 C9): one sample class, and a clock the student drags.
export const CLASS = { code: "COMP 20073", title: "Data Structures", room: "S512", start: 7.5 * 3600, end: 9 * 3600 };
/** The slider's ends and where it starts, in seconds after midnight. */
export const CLOCK = { from: 6.75 * 3600, to: 9.25 * 3600, start: 7.25 * 3600 };

export type Phase = "next" | "now" | "over";

/** "35:12", or "1:05:30" past an hour. */
export function countdown(secs: number): string {
  const s = Math.max(0, Math.floor(secs));
  const [h, m, r] = [Math.floor(s / 3600), Math.floor((s % 3600) / 60), s % 60];
  const two = (v: number) => String(v).padStart(2, "0");
  return h ? `${h}:${two(m)}:${two(r)}` : `${m}:${two(r)}`;
}

/** "7:12 AM". */
export function clock(at: number): string {
  const m = Math.floor(at / 60);
  const h = Math.floor(m / 60) % 24;
  return `${((h + 11) % 12) + 1}:${String(m % 60).padStart(2, "0")} ${h < 12 ? "AM" : "PM"}`;
}

/** The sample class at `at` seconds after midnight. */
export function todayAt(at: number): { phase: Phase; label: string; left: number; sub: string } {
  if (at < CLASS.start) return { phase: "next", label: "Up next", left: CLASS.start - at, sub: "Starts in" };
  if (at < CLASS.end) return { phase: "now", label: "In session", left: CLASS.end - at, sub: "Ends in" };
  return { phase: "over", label: "Done", left: 0, sub: "Free until 10:30 AM" };
}

// Grades and Study (049 C11).
export const TERMS: TermPoint[] = [
  { label: "1st 24", term: "1st Semester 2024-2025", v: 1.75 },
  { label: "2nd 24", term: "2nd Semester 2024-2025", v: 1.62 },
  { label: "1st 25", term: "1st Semester 2025-2026", v: 1.5 },
  { label: "2nd 25", term: "2nd Semester 2025-2026", v: 1.42 },
];
const DAY = 86_400;
export const RATINGS = [
  { id: "again", label: "Again", secs: 600 },
  { id: "good", label: "Good", secs: 3 * DAY },
  { id: "easy", label: "Easy", secs: 8 * DAY },
].map((r) => ({ ...r, short: interval(r.secs) }));

/** The six dark looks: the landing is the night ground, and a light one would wash the portal out. */
export const LOOKS: { room: string; name: string; swatch: [string, string, string] }[] = [
  ...HAND_TUNED.filter((r) => r.id === "night" || r.id === "maroon").map((r) => ({ room: r.id, name: r.name, swatch: r.swatch as [string, string, string] })),
  ...(["astraMoon", "tokyoNight", "dracula", "nord"] as const).map((id) => {
    const p = PALETTES[id];
    return { room: id, name: p.name, swatch: [p.canvasBottom, p.panel, p.accent] as [string, string, string] };
  }),
];

/** FirstRun after sign-in (049 C16): only the AI choice is left, so it shows only on a build that has AI. */
export const showFirstRun = (welcomed: boolean, ai: unknown) => !welcomed && !!ai;
