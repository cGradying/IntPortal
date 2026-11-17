// The talk (spec 049): before the portal, a new student has a short conversation with LAR. This
// file is the whole conversation as data: what LAR says at each step, what the student can answer,
// what each answer makes LAR say and do, and where it leads. `play` turns the answers given so far
// into the thread on screen, so Back is just one answer fewer. Talk.svelte draws it.
import { HAND_TUNED, PALETTES } from "../rooms";
import { cleanFocus, cleanName, type Focus } from "../profile";
import { interval } from "../interval";
import type { TermPoint } from "../gpaTrend";

export type StepId = "name" | "campus" | "focus" | "today" | "deadlines" | "grades" | "study" | "offline" | "look" | "reminders" | "privacy" | "how" | "bye";

/** A demo the student can touch, shown in the thread under LAR's line. */
export type Card = "today" | "deadlines" | "grades" | "study" | "offline" | "nudge";

/** How the student answers: reply chips, or the step's own control. */
export type Ask = "chips" | "name" | "campus" | "focus" | "look";

/** What an answer does besides being said. Talk runs these. */
export type Act =
  /** LAR hops and waves. */
  | "cheer"
  /** LAR thinks it over. */
  | "think"
  /** The portal wall opens once the student is at the portal, to pick another school. */
  | "wall"
  /** The phone is asked for notifications. */
  | "remind"
  /** Reminders stay off. */
  | "quiet";

export interface Reply {
  id: string;
  /** The chip's words; a step with its own control (a name, a campus) says the answer itself. */
  label: string;
  /** The one gold action of the step. */
  gold?: boolean;
  /** What LAR answers. {you} is the student's name, {campus} their campus. */
  says: string[];
  act?: Act;
  /** The step this answer leads to, when it leaves the usual order. */
  to?: StepId;
}

export interface Step {
  id: StepId;
  /** What LAR says as the step opens. */
  lar: string[];
  card?: Card;
  ask: Ask;
  replies: Reply[];
}

const next = (label: string): Reply[] => [{ id: "next", label, gold: true, says: [] }];

export const STEPS: Record<StepId, Step> = {
  name: {
    id: "name",
    lar: ["Uy! Ako si LAR, galing sa kabilang side ng portal.", "Bago tayo pumasok: what should I call you?"],
    ask: "name",
    replies: [
      { id: "named", label: "Send", gold: true, says: ["Hi, {you}! Tanda ko na 'yan."], act: "cheer" },
      { id: "skip", label: "Iskolar na lang", says: ["Sige, iskolar na lang muna."] },
    ],
  },
  campus: {
    id: "campus",
    lar: ["Saan ka nag-aaral, {you}?"],
    ask: "campus",
    replies: [
      { id: "pup", label: "", says: ["PUP {campus}! Kilala ko 'yan."], act: "cheer" },
      { id: "other", label: "Another school", says: ["Sige! Pipili tayo sa portal wall pagdating doon."], act: "wall" },
    ],
  },
  focus: {
    id: "focus",
    lar: ["Ano'ng pinaka-kailangan mo araw-araw? Pili ka, kahit ilan."],
    ask: "focus",
    replies: [
      { id: "picked", label: "'Yan na", gold: true, says: ["Sige, 'yan ang uunahin ko."], act: "cheer" },
      { id: "all", label: "Lahat", gold: true, says: ["Lahat? Sige, isa-isahin natin."], act: "cheer" },
    ],
  },
  today: { id: "today", lar: ["Ganito ko ipapakita ang next class mo. I-drag mo ang oras."], card: "today", ask: "chips", replies: next("Ayos") },
  deadlines: { id: "deadlines", lar: ["Lahat ng due mo, isang listahan. Subukan mo, i-tick mo."], card: "deadlines", ask: "chips", replies: next("Tapos!") },
  grades: { id: "grades", lar: ["GPA mo kada term, isang linya. Sample lang 'to, ha."], card: "grades", ask: "chips", replies: next("Nice") },
  study: { id: "study", lar: ["May flashcards din. I-tap mo ang card, tapos i-rate mo."], card: "study", ask: "chips", replies: next("Gets") },
  offline: { id: "offline", lar: ["Walang signal sa jeep? I-on mo 'to, tingnan mo."], card: "offline", ask: "chips", replies: next("Solid") },
  look: {
    id: "look",
    lar: ["Ano'ng bagay sa'yo, {you}? Isuot mo."],
    ask: "look",
    replies: [{ id: "worn", label: "Ito na", gold: true, says: ["Ayan, bagay. Ganyan na ang kulay ng app mo."], act: "cheer" }],
  },
  reminders: {
    id: "reminders",
    lar: ["Paalalahanan kita 10 minutes bago bawat klase, at gabi bago ang deadline?"],
    card: "nudge",
    ask: "chips",
    replies: [
      { id: "later", label: "Not now", says: ["Sige. Nasa You tab lang 'yan pag gusto mo na."], act: "quiet" },
      { id: "allow", label: "Allow reminders", gold: true, says: ["Ayos! Magsisimula 'yan pag naka-sign in ka na."], act: "remind" },
    ],
  },
  privacy: {
    id: "privacy",
    lar: ["Last na. Ang login mo, sa phone mo lang: nasa keychain, at ang portal lang ng school mo ang kinakausap ko."],
    ask: "chips",
    replies: [
      { id: "how", label: "Paano?", says: [], act: "think", to: "how" },
      { id: "ok", label: "Got it", gold: true, says: [] },
    ],
  },
  how: {
    id: "how",
    lar: ["Ako ang nagsa-sign in para sa'yo, gaya ng sa browser. Walang IntPortal account, walang server.", "Pagkatapos, offline na: nasa phone na ang schedule, grades at notes mo."],
    ask: "chips",
    replies: [{ id: "ok", label: "Got it", gold: true, says: [], to: "bye" }],
  },
  bye: { id: "bye", lar: ["Tara, {you}, pasok na tayo!"], ask: "chips", replies: [] },
};

/** What the student can care about most, and the demo that shows it. */
export const FOCUS: { id: Focus; label: string; step: StepId }[] = [
  { id: "classes", label: "Classes", step: "today" },
  { id: "deadlines", label: "Deadlines", step: "deadlines" },
  { id: "grades", label: "Grades", step: "grades" },
  { id: "study", label: "Studying", step: "study" },
];

/** The steps in order: the demos the student picked come first, as they picked them. */
export function route(focus: readonly string[] = []): StepId[] {
  const picks = cleanFocus(focus);
  const demos = [...picks, ...FOCUS.map((f) => f.id).filter((f) => !picks.includes(f))].map((f) => FOCUS.find((x) => x.id === f)!.step);
  return ["name", "campus", "focus", ...demos, "offline", "look", "reminders", "privacy", "bye"];
}

/** One answer: which reply, and what it carried (the name, the campus, the picks comma-joined, the look's name). */
export interface Answer {
  reply: string;
  value?: string;
}

export type Item = { who: "lar"; text: string } | { who: "you"; text: string } | { who: "card"; card: Card; step: StepId };

export interface Thread {
  items: Item[];
  /** The step waiting for an answer. */
  step: Step;
  /** LAR has said his last line: time to go in. */
  done: boolean;
  /** The act of the newest answer. */
  act?: Act;
  name: string;
  campus: string;
  focus: Focus[];
  /** The student's school is not PUP: the wall opens at the portal. */
  wall: boolean;
}

/** A line with the student's name (or "iskolar") and campus in it. */
export const fill = (line: string, name: string, campus = "") => line.replaceAll("{you}", cleanName(name) || "iskolar").replaceAll("{campus}", campus);

/** What the student's own bubble says for an answer. */
function said(step: Step, reply: Reply, a: Answer): string {
  if (step.ask === "focus" && reply.id === "picked") return cleanFocus((a.value ?? "").split(",")).map((f) => FOCUS.find((x) => x.id === f)!.label).join(", ");
  if (reply.id === "named" || reply.id === "pup" || reply.id === "worn") return a.value || reply.label;
  return reply.label;
}

/** The conversation after `answers`: every bubble so far, and the step now asking. An answer that fits no reply ends the list there. */
export function play(answers: readonly Answer[]): Thread {
  const t: Thread = { items: [], step: STEPS.name, done: false, name: "", campus: "", focus: [], wall: false };
  const open = (s: Step) => {
    for (const text of s.lar) t.items.push({ who: "lar", text: fill(text, t.name, t.campus) });
    if (s.card) t.items.push({ who: "card", card: s.card, step: s.id });
  };
  open(t.step);
  for (const a of answers) {
    const step = t.step;
    const reply = step.replies.find((r) => r.id === a.reply);
    if (!reply) break;
    if (reply.id === "named") t.name = cleanName(a.value ?? "");
    if (reply.id === "pup") t.campus = a.value ?? "";
    if (step.id === "campus") t.wall = reply.id === "other";
    if (reply.id === "picked") t.focus = cleanFocus((a.value ?? "").split(","));
    t.items.push({ who: "you", text: said(step, reply, a) });
    for (const text of reply.says) t.items.push({ who: "lar", text: fill(text, t.name, t.campus) });
    t.act = reply.act;
    const order = route(t.focus);
    t.step = STEPS[reply.to ?? order[order.indexOf(step.id) + 1] ?? "bye"];
    open(t.step);
  }
  t.done = t.step.id === "bye";
  return t;
}

// Today: one sample class, and a clock the student drags.
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

// Grades and Study.
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
/** A look the landing and the talk can wear on their ground. */
export const isDarkLook = (room: string) => LOOKS.some((l) => l.room === room);

/** FirstRun after sign-in (049 C16): only the AI choice is left, so it shows only on a build that has AI. */
export const showFirstRun = (welcomed: boolean, ai: unknown) => !welcomed && !!ai;
