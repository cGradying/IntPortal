// Typed wrappers over the Tauri commands in src-tauri/src/lib.rs.
// See docs/design/core-api.md.
import { invoke } from "@tauri-apps/api/core";

export type Weekday = "Monday" | "Tuesday" | "Wednesday" | "Thursday" | "Friday" | "Saturday" | "Sunday";
export const WEEKDAYS: Weekday[] = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"];

export interface ClassSession {
  subject_code: string;
  description: string;
  faculty: string;
  day: Weekday;
  start: number;
  end: number;
  occurrence: number;
}

export interface SubjectGrade {
  subject_code: string;
  description: string;
  faculty: string;
  units: number;
  section_code: string;
  final_grade: string;
  grade_status: string;
  occurrence: number;
}

export interface GradeReport {
  subjects: SubjectGrade[];
  summary: Record<string, string>;
  school_year: string | null;
  semester: string | null;
}

export type Mark = "in_person" | "online" | "vacant";

/** A note with its one-line preview. `key` is `class:<code>` or `day:<date>`. */
export interface NoteItem {
  key: string;
  text: string;
  title: string | null;
  updated: number;
  preview: string;
}

export type Rating = "again" | "hard" | "good" | "easy";

export interface Memory {
  due: number;
  stability: number;
  difficulty: number;
  reps: number;
  lapses: number;
  last_review: number | null;
}

export interface Card {
  id: string;
  front: string;
  back: string;
  accepted: string[];
  memory: Memory;
}

export interface Deck {
  id: string;
  name: string;
  subject: string | null;
  cards: Card[];
}

export interface StudyOverview {
  decks: { id: string; name: string; subject: string | null; cards: number; due: number }[];
  due: number;
  streak: number;
  reviews_today: number;
}

export type ItemKind = "lecture" | "quiz" | "exam" | "project";

export interface SyllabusItem {
  id: string;
  topic: string;
  kind: ItemKind;
  week: number | null;
  date: string | null;
  done: boolean;
}

export interface Component {
  name: string;
  weight: number;
  score: number | null;
}

export interface Plan {
  items: SyllabusItem[];
  grading: Component[];
  target: number | null;
}

export interface Tally {
  weight_total: number;
  earned: number;
  scored_weight: number;
  standing: number | null;
  equivalent: number | null;
  needed: number | null;
  target: number;
}

export interface Goals {
  target_gpa: number | null;
  program_units: number | null;
}

/** Where the target GPA stands against the unposted subjects. */
export type Reach =
  | { kind: "settled" }
  | { kind: "out_of_reach" }
  | { kind: "secured" }
  | { kind: "needs"; average: number; subjects: number };

export interface TermGpa {
  school_year: string | null;
  semester: string | null;
  gpa: number;
  units: number;
}

export interface Standing {
  term_gpa: number | null;
  cumulative_gpa: number | null;
  units_done: number;
  past: TermGpa[];
  personal_best: boolean;
  reach: Reach | null;
  goals: Goals;
}

/** Term-wide values, and single-week overrides keyed by that week's Monday. */
export interface Layers<T> {
  term: Record<string, T>;
  weekly: Record<string, Record<string, T>>;
}

/** Where a moved class meets instead. */
export interface Slot {
  day: Weekday;
  start: number;
  end: number;
}

/** One session on one date after marks and moves. `id` is the original session's. */
export interface Meeting {
  id: string;
  session: ClassSession;
  date: string;
  mark: Mark;
  moved: boolean;
}

export interface Snapshot {
  sessions: ClassSession[];
  grades: GradeReport | null;
  history: GradeReport[];
  marks: Layers<Mark> & { moved: Layers<Slot> };
  colors: Record<string, string>;
  goals: Goals;
  syllabus: Record<string, Plan>;
  host: string | null;
  last_synced: string | null;
}

export interface Moment {
  date: string;
  minute: number;
}

export type Phase = "past" | "in_session" | "upcoming";

export interface Today {
  agenda: {
    items: (Meeting & { phase: Phase })[];
    tomorrow_first: ClassSession | null;
    free_minutes_left: number;
  };
  next: { session: ClassSession; date: string; is_now: boolean; minutes_away: number } | null;
  countdown: string | null;
  glance: Glance;
  glance_line: string;
}

/** The core's `Glance`, tagged by `kind`. */
export type Glance =
  | { kind: "in_session"; code: string; until: string }
  | { kind: "next_today"; code: string; when: string }
  | { kind: "sync_trouble"; message: string }
  | { kind: "thinking" }
  | { kind: "day_done"; tomorrow: string | null };

export interface Reminder {
  id: number;
  date: string;
  minute: number;
  title: string;
  body: string;
}

export type CampusResolution =
  | { kind: "known"; campus: { code: string | null; name: string; region: string } }
  | { kind: "unknown_code"; code: string }
  | { kind: "incomplete" };

export interface Login {
  student_number: string;
  birth_month: number;
  birth_day: number;
  birth_year: number;
  password: string;
}

export const api = {
  snapshot: () => invoke<Snapshot>("snapshot"),
  hasLogin: () => invoke<boolean>("has_login"),
  signIn: (login: Login) => invoke<Snapshot>("sign_in", { login }),
  sync: () => invoke<Snapshot>("sync"),
  loadHistory: () => invoke<Snapshot>("load_history"),
  signOut: () => invoke<void>("sign_out"),
  setMark: (sessionId: string, week: string | null, mark: Mark | null) =>
    invoke<Snapshot>("set_mark", { sessionId, week, mark }),
  setMove: (sessionId: string, week: string | null, slot: Slot | null) =>
    invoke<Snapshot>("set_move", { sessionId, week, slot }),
  setColor: (subjectCode: string, color: string | null) => invoke<Snapshot>("set_color", { subjectCode, color }),
  week: (on: string) => invoke<Meeting[]>("week", { on }),
  setGoals: (goals: Goals) => invoke<Snapshot>("set_goals", { goals }),
  standing: () => invoke<Standing>("standing"),
  notes: () => invoke<NoteItem[]>("notes"),
  notesMarkdown: (key: string | null) => invoke<string>("notes_markdown", { key }),
  parseOutline: (text: string, today: string) => invoke<SyllabusItem[]>("parse_outline", { text, today }),
  setPlan: (subjectCode: string, plan: Plan) => invoke<Snapshot>("set_plan", { subjectCode, plan }),
  tally: (components: Component[], target: number) => invoke<Tally>("tally", { components, target }),
  due: (today: string, days: number) => invoke<[string, SyllabusItem][]>("due", { today, days }),
  study: (today: string) => invoke<StudyOverview>("study", { today }),
  deck: (id: string) => invoke<Deck>("deck", { id }),
  saveDeck: (deck: Deck) => invoke<Deck>("save_deck", { deck }),
  deleteDeck: (id: string) => invoke<void>("delete_deck", { id }),
  parseCards: (text: string) => invoke<Card[]>("parse_cards", { text }),
  reviewCard: (deckId: string, cardId: string, rating: Rating, today: string) =>
    invoke<{ deck: Deck }>("review_card", { deckId, cardId, rating, today }),
  checkAnswer: (card: Card, typed: string) => invoke<boolean>("check_answer", { card, typed }),
  distractors: (cards: Card[], index: number, seed: number) => invoke<string[]>("distractors", { cards, index, seed }),
  exportIcs: (from: string, until: string) => invoke<string>("export_ics", { from, until }),
  setNote: (key: string, text: string, title: string | null) => invoke<void>("set_note", { key, text, title }),
  today: (now: Moment, syncTrouble: string | null) => invoke<Today>("today", { now, syncTrouble }),
  reminders: (now: Moment, lead: number, days: number) => invoke<Reminder[]>("reminders", { now, lead, days }),
  campus: (studentNumber: string) => invoke<CampusResolution>("campus", { studentNumber }),
  demo: (today: string) => invoke<Snapshot>("demo", { today }),
};

const pad = (n: number) => String(n).padStart(2, "0");

export function isoDate(d: Date): string {
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}

export function moment(d = new Date()): Moment {
  return { date: isoDate(d), minute: d.getHours() * 60 + d.getMinutes() };
}

export function sessionId(s: ClassSession): string {
  const base = `${s.subject_code}-${WEEKDAYS.indexOf(s.day) + 1}-${s.start}-${s.end}`;
  return s.occurrence ? `${base}-${s.occurrence}` : base;
}

/** `8AM`, `2:30PM`, matching the core's `clock`. */
export function clock(minutes: number): string {
  const h24 = Math.floor(minutes / 60);
  const m = minutes % 60;
  const h = h24 % 12 || 12;
  const p = h24 >= 12 ? "PM" : "AM";
  return m ? `${h}:${pad(m)}${p}` : `${h}${p}`;
}

export function span(minutes: number): string {
  const h = Math.floor(minutes / 60);
  const m = minutes % 60;
  return h && m ? `${h}h ${m}m` : h ? `${h}h` : `${m}m`;
}

/** One of six subject colours, stable per code: the old app's character-sum seed. */
export function subjectColor(code: string, overrides: Record<string, string> = {}): string {
  if (overrides[code]) return overrides[code];
  let sum = 0;
  for (const ch of code) sum += ch.charCodeAt(0);
  return `var(--s${(sum % 6) + 1})`;
}
