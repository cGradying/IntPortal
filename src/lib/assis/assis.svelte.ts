// LAR's brain, as the UI sees it: which model is on the phone, the chat, and
// what happens when the student confirms a proposal. The model runs in Rust;
// nothing here writes until Apply.
import { Channel, invoke } from "@tauri-apps/api/core";
import { Schedule, cancel as unring, isPermissionGranted, requestPermission } from "@tauri-apps/plugin-notification";
import { api, isoDate, moment, sessionId, type Card, type FoundClass, type Mark, type OwnClass, type OwnDeadline, type Slot, type Snapshot } from "../api";
import { adopt, app } from "../state.svelte";
import { classesOf } from "../ownClass";
import { tidy, type Draft } from "./cards";
import {
  appended,
  existingText,
  forgetLarReminder,
  isChange,
  larReminderList,
  newDeck,
  noteFor,
  looksFilipino,
  noteTarget,
  notificationsOff,
  reminderAt,
  reminderId,
  rememberLarReminder,
  weekOf,
  withNotes,
  type CalendarChange,
  type Proposal,
} from "./apply";

export interface ModelInfo {
  id: string;
  name: string;
  chat: boolean;
  bytes: number;
  installed: boolean;
  default: boolean;
  fits: "ok" | "warn" | "refuse";
  loaded: boolean;
  /** No longer offered; listed only while it is on the phone (spec 021 C13). */
  legacy?: boolean;
}

export interface Source {
  key: string;
  title: string;
}

/**
 * One step LAR really took for a turn, as it happened (spec 048 C12). `wake` is the app's own model load;
 * the rest come from `ai_ask`. Session-only: a turn restored from history has none.
 */
export type Step = { step: "wake" | "read" | "search" | "nothing" | "search_off" | "write" } | { step: "found"; found: Source[]; quote: string };

/** What the rules took a question for; the chat picks its follow-ups by it (spec 048 C18). */
export type Intent = "ask" | "note" | "remind" | "cards" | "due" | "classes" | "grades" | "calendar";

export interface Msg {
  from: "me" | "lar";
  text: string;
  /** This session's turns only: what LAR did for this answer, in order. */
  steps?: Step[];
  /** This session's turns only. */
  intent?: Intent;
  proposal?: Proposal;
  /** The notes LAR was shown for this answer; each opens that note. */
  sources?: Source[];
  /** Answered from what the model knows, not the student's notes (spec 021 C16). */
  known?: boolean;
  /** pending until the student answers the card. */
  state?: "pending" | "done" | "dismissed";
  problem?: string;
  /** Shown instead of "Done" when the action worked but needs the student to do something (notifications off). */
  notice?: string;
  /** make_cards: the cards LAR wrote, shown to edit before anything is saved. */
  cards?: Draft[];
  /** The answer stopped at its limit; `more` counts the Keep going taps so far (at most 2, spec 062 C25). */
  more?: number;
  cut?: boolean;
  /** A note change was applied and can still be undone from the card (spec 062 C14). */
  undo?: boolean;
  /** save_note: the student opened the note's title and body to change them before saving (spec 062 C5). */
  editing?: boolean;
  /** save_note: the key it was saved under, for Open note (spec 063 C1). */
  saved?: string;
  /** A note change was put back with Undo (spec 063 C5). */
  undone?: boolean;
  /** pick_note: the row tapped, kept marked (spec 063 C6). */
  picked?: string;
  /** A calendar change applied (spec 064 C16): how to put it back, and the item as LAR left it, so a later
   *  change by hand ends the Undo. */
  restore?: Restore;
  after?: string;
}

/** How Undo puts back one calendar change, through the same commands the screens use (spec 064 C16). */
export type Restore =
  /** An own deadline as it was; null deletes the one LAR added. */
  | { do: "own"; id: string; own: OwnDeadline | null }
  | { do: "done"; id: string }
  /** `week`: the week's Monday, null for the term. The value before; null clears it. */
  | { do: "mark"; session: string; week: string | null; mark: Mark | null }
  | { do: "move"; session: string; week: string | null; slot: Slot | null }
  /** The own class as it was, saved over `code`; `code` null re-adds a deleted one. */
  | { do: "class"; code: string | null; cls: OwnClass }
  /** Cancels the reminder LAR moved it to, and rings the old one again. */
  | { do: "reminder"; cancel: number | null; put: { id: number; date: string; text: string } };

export const CHANGED = "That changed since I read it. Ask me again.";
const NOT_SAVED = "Couldn't save that. Try again.";

export const assis = $state({
  models: [] as ModelInfo[],
  /** What the phone is doing for LAR right now. */
  busy: "" as "" | "downloading" | "waking" | "thinking" | "cards",
  done: 0,
  total: 0,
  /** The install view (spec 021 C6): open from Add until done, failed or paused. */
  install: { open: false, files: [] as ModelInfo[], file: 0, speed: 0, waiting: "", ready: false },
  /** The model is taking long to wake: the sheet says the phone is slow instead of sitting on "Waking up". */
  slow: false,
  error: "",
  open: false,
  chat: [] as Msg[],
  /** What this screen adds to the crystal's + menu, after Ask LAR. */
  menu: [] as { label: string; run: () => void }[],
  /** Set by the note editor: the crystal's + opens its tool sheet instead of the menu (046 C11). */
  plus: null as null | (() => void),
});

/** The model a new install gets (the catalog's default chat model). */
export const defaultChat = () => assis.models.find((m) => m.chat && m.default) ?? assis.models.find((m) => m.chat);
/**
 * The model that answers: the default when it is installed, else the other offered model the student
 * chose, else a legacy one an earlier version left (it keeps working until its student taps Update),
 * else the default, so "Add IntAssis" has a target. Nothing is stored: it follows from what is on the phone.
 */
export const chatModel = () => {
  const d = defaultChat();
  if (d?.installed) return d;
  const on = assis.models.filter((m) => m.chat && m.installed);
  return on.find((m) => !m.legacy) ?? on[0] ?? runnable();
};
/** The offered chat model this phone has the RAM for: the default, else the other one, else the default (spec 021 C2). */
const runnable = () => {
  const d = defaultChat();
  return d?.fits !== "refuse" ? d : (choices().find((m) => m.fits !== "refuse") ?? d);
};
/** True when no offered chat model fits this phone's RAM: Add is never offered, nothing is downloaded. */
export const noRoom = () => runnable()?.fits === "refuse";
export const RAM_LINE = "This phone doesn't have enough memory (RAM) for LAR's brain. Storage won't help.";
/** The small model that finds the student's notes. */
export const embedModel = () => assis.models.find((m) => !m.chat);
export const installed = () => assis.models.some((m) => m.chat && m.installed);
/** Only a legacy chat model is on the phone: the card offers Update (C13). A chosen Qwen3 1.7B is not asked. */
export const updatable = () => installed() && !assis.models.some((m) => m.chat && m.installed && !m.legacy);
/** The offered chat models, for the choice on the IntAssis card (C11). */
export const choices = () => assis.models.filter((m) => m.chat && !m.legacy);
export const mb = (bytes: number) => (bytes >= 1e9 ? `${(bytes / 1e9).toFixed(2)} GB` : `${Math.round(bytes / 1e6)} MB`);

/** What a download is, piece by piece from the sizes the phone reports: "Chat model 1.11 GB + note search 310 MB, use Wi-Fi". */
export function downloadSizes(todo: ModelInfo[]): string {
  const parts = todo.map((m) => `${m.chat ? "chat model" : "note search"} ${mb(m.bytes)}`);
  if (!parts.length) return "";
  const text = parts.join(" + ");
  return `${text[0].toUpperCase()}${text.slice(1)}, use Wi-Fi`;
}

const say = (e: unknown) => (typeof e === "string" ? e : (e as { message?: string })?.message ?? JSON.stringify(e));

export async function refresh() {
  try {
    assis.models = await invoke<ModelInfo[]>("ai_models");
  } catch {
    assis.models = []; // Linux or a build without the commands: IntAssis stays hidden
  }
}

const INSTALLING = "intassisInstalling";
/** The chat model an install is bringing, kept while it runs so a cut-off install carries on with the same one. */
const flag = (id: string | false) => {
  try {
    if (id) localStorage.setItem(INSTALLING, id);
    else localStorage.removeItem(INSTALLING);
  } catch {}
};
const flagged = (): string | null => {
  try {
    return localStorage.getItem(INSTALLING);
  } catch {
    return null;
  }
};

/** Free storage against what is left to come (spec 021 C1). The line to show, or "" when it fits or the phone doesn't say. */
export function spaceLine(need: number, free: number | null): string {
  if (free === null || free >= need) return "";
  return `IntAssis needs ${mb(need)} free. This phone has ${mb(free)}. Free up ${mb(need - free)} and try again.`;
}

/** Bytes per second over a sliding window of about five seconds. */
export function speedOf(samples: { t: number; done: number }[]): number {
  if (samples.length < 2) return 0;
  const a = samples[0], b = samples[samples.length - 1];
  return b.t > a.t ? ((b.done - a.done) * 1000) / (b.t - a.t) : 0;
}

/** "about 4 min left", from what is left and the speed. */
export function etaLine(left: number, speed: number): string {
  if (speed <= 0) return "";
  const s = left / speed;
  if (s < 60) return "less than a minute left";
  const m = Math.round(s / 60);
  return m < 60 ? `about ${m} min left` : `about ${Math.floor(m / 60)} h ${m % 60} min left`;
}

/**
 * The whole install in one Rust call, one bar over every file. The download goes on when the student
 * leaves the app (spec 021 C3–C5); a dropped connection is waited out in Rust (C7). True when every file arrived.
 */
async function fetchAll(todo: ModelInfo[], target = todo[0]?.id ?? ""): Promise<boolean> {
  if (!todo.length || assis.busy) return false;
  assis.error = "";
  assis.busy = "downloading";
  const ids = todo.map((m) => m.id);
  try {
    const { need, free } = await invoke<{ need: number; free: number | null }>("ai_space", { ids });
    const short = spaceLine(need, free);
    if (short) {
      assis.error = short;
      assis.busy = "";
      return false;
    }
  } catch {} // an older shell without the check: the download says if storage runs out
  assis.done = 0;
  assis.total = todo.reduce((n, m) => n + m.bytes, 0);
  assis.install = { open: true, files: todo, file: 0, speed: 0, waiting: "", ready: false };
  flag(target);
  const samples: { t: number; done: number }[] = [];
  try {
    const onProgress = new Channel<{ done: number; total: number; file: number; waiting: string | null }>();
    onProgress.onmessage = (p) => {
      assis.install.waiting = p.waiting ?? "";
      assis.install.file = p.file;
      if (p.waiting) return;
      assis.done = p.done;
      const t = Date.now();
      samples.push({ t, done: p.done });
      while (samples.length > 2 && t - samples[0].t > 5000) samples.shift();
      assis.install.speed = speedOf(samples);
    };
    await invoke("ai_download", { ids, onProgress });
    flag(false);
    assis.install.ready = true;
    await refresh();
    return true;
  } catch (e) {
    const why = say(e);
    flag(false); // paused, storage full, a bad file, a gone server: the student decides, not a relaunch
    if (why === "paused") assis.install.open = false;
    else assis.error = why;
    await refresh();
    return false;
  } finally {
    assis.busy = "";
  }
}

/**
 * The one-time download: LAR's brain (the default, or `id` when the student switches models), then the
 * model that finds their notes, whichever is missing. The phone holds one chat model: once the new one has
 * arrived, any other goes; until then the old one keeps answering. History, the notes index and the settings
 * are not touched.
 */
export async function install(id?: string) {
  const chat = assis.models.find((m) => m.chat && m.id === id) ?? runnable();
  // Checked before a byte comes, not after 1.5 GB: the model would only be refused when it loads.
  if (chat?.fits === "refuse") {
    assis.error = RAM_LINE;
    return;
  }
  const todo = [chat, embedModel()].filter((m): m is ModelInfo => !!m && !m.installed);
  if (!chat || !todo.length || !(await fetchAll(todo, chat.id))) return;
  const others = assis.models.filter((m) => m.chat && m.installed && m.id !== chat.id);
  if (assis.models.find((m) => m.id === chat.id)?.installed && others.length) {
    for (const old of others) await invoke("ai_delete", { id: old.id }).catch(() => {});
    await refresh();
  }
}

/** Adds only the note search, for a phone whose chat model is already on it. */
export const addSearch = () => fetchAll([embedModel()].filter((m): m is ModelInfo => !!m && !m.installed));

/** Pause: what arrived stays, and the next Add carries on from it. Nothing restarts it by itself. */
export function cancelDownload() {
  flag(false);
  return invoke("ai_pause_download");
}

/** Closes the install view; a running download goes on and the IntAssis card shows its bar. */
export const closeInstall = () => (assis.install.open = false);

export async function remove() {
  try {
    // The search model is always asked: its delete also takes the old one (nomic) an earlier version left.
    for (const m of assis.models) if (m.installed || !m.chat) await invoke("ai_delete", { id: m.id });
    await invoke("ai_clear_history");
    assis.chat = [];
    assis.open = false;
  } catch (e) {
    assis.error = say(e);
  }
  await refresh();
}

/** "Waking up" says the phone is slow after this long. */
export const WAKE_SLOW_MS = 15_000;
/** After this long the wait ends with an explanation. The load goes on; the next wake joins it. */
export const WAKE_GIVE_UP_MS = 150_000;

const tooSlow = (fil: boolean) =>
  fil
    ? "Matagal akong magising. Baka kulang ang memory ng phone. Isara ang ibang apps at subukan ulit."
    : "I'm taking too long to wake up. The phone may be low on memory. Close other apps and try again.";

let loading: Promise<void> | null = null; // one load at a time: a second ai_load would only answer "busy"
let sleepAfterWake = false;

/**
 * Loads the model when LAR is opened. iOS ends an app holding 1 GB in the background, so it is let go in `sleep`.
 * `fil`: the student writes Filipino, so a failure is told in Filipino.
 * The wait is bounded: past `WAKE_SLOW_MS` the sheet says the phone is slow, past `WAKE_GIVE_UP_MS` it stops and says why.
 */
export async function wake(fil = false): Promise<boolean> {
  const m = chatModel();
  if (!m?.installed) return false;
  if (m.loaded) return true;
  assis.busy = "waking";
  const slow = setTimeout(() => (assis.slow = true), WAKE_SLOW_MS);
  let giveUp: ReturnType<typeof setTimeout> | undefined;
  loading ??= invoke<void>("ai_load", { id: m.id, fil })
    .then(refresh) // so a load that finishes after we gave up still shows as loaded
    .finally(() => (loading = null));
  try {
    await Promise.race([loading, new Promise((_, no) => (giveUp = setTimeout(() => no(tooSlow(fil)), WAKE_GIVE_UP_MS)))]);
    return true;
  } catch (e) {
    assis.error = say(e);
    return false;
  } finally {
    clearTimeout(slow);
    clearTimeout(giveUp);
    assis.slow = false;
    assis.busy = "";
    if (sleepAfterWake) {
      sleepAfterWake = false;
      if (globalThis.document?.hidden) sleep();
    }
  }
}

export async function sleep() {
  // Letting go of a model that is still loading would queue behind the load and drop it the moment it lands.
  if (assis.busy === "waking") {
    sleepAfterWake = true;
    return;
  }
  await invoke("ai_unload").catch(() => {});
  await refresh();
}

/** Notes edited since LAR last looked get embedded, so the next question can find them. */
export function indexNotes() {
  // Not while a model loads or answers: on a small phone they would fight for memory, and the next question indexes anyway.
  if (installed() && !assis.busy) invoke("ai_index").catch(() => {});
}

/** The chat is kept on the phone, so it is still there after the app was closed. */
/** A saved turn as a chat message; LAR's answers keep the chips they had (spec 020 C2, #180). */
export const fromTurn = (t: { role: string; text: string; sources?: Source[] }): Msg =>
  t.role === "me" ? { from: "me", text: t.text } : { from: "lar", text: t.text, sources: t.sources?.length ? t.sources : undefined };

async function loadHistory() {
  if (assis.chat.length) return;
  try {
    const turns = await invoke<{ role: string; text: string; sources?: Source[] }[]>("ai_history");
    if (!assis.chat.length) assis.chat = turns.map(fromTurn);
  } catch {
    // An empty chat is fine.
  }
}

export async function newChat() {
  await invoke("ai_clear_history").catch(() => {});
  assis.chat = [];
}

export async function open() {
  assis.open = true;
  assis.error = "";
  loadHistory();
  await wake(); // before indexing: loading both models at once was the 4 GB phone's ANR
  indexNotes();
}

let stopped = false;
/** Stop writing; the words so far stay. */
export function stop() {
  stopped = true;
  invoke("ai_cancel").catch(() => {});
}

const STYLE_KEY = "larStyle";
/** The most characters of the student's own note on how LAR talks; the core cuts at the same length. */
export const STYLE_MAX = 200;

/** The student's own note on how LAR should talk, kept on this phone. It only shapes tone: LAR's rules come first. */
export function larStyle(): string {
  try {
    return (localStorage.getItem(STYLE_KEY) ?? "").slice(0, STYLE_MAX);
  } catch {
    return "";
  }
}

export function setLarStyle(text: string) {
  const clean = text.trim().slice(0, STYLE_MAX);
  try {
    if (clean) localStorage.setItem(STYLE_KEY, clean);
    else localStorage.removeItem(STYLE_KEY);
  } catch {
    // Storage off: the note lasts until the app closes.
  }
}

/** `openKey`: the note the question is about (the open one, or the one picked from "Which note?"). */
export async function ask(text: string, openKey: string | null = app.editing?.key ?? null, echo = true, pick: string | null = null) {
  const message = text.trim();
  if (!message || assis.busy) return;
  if (echo) assis.chat.push({ from: "me", text: message });
  stopped = false;
  // A change to the week is read by rules alone, so the model isn't woken for it (spec 064 C17).
  const change = await invoke<boolean>("ai_is_change", { message }).catch(() => false);
  const asleep = !change && !chatModel()?.loaded;
  const awake = change || (await wake(looksFilipino(message)));
  if (stopped) return; // Stop while the model was waking: no reply at all
  if (!awake) {
    assis.chat.push({ from: "lar", text: assis.error || "I couldn't wake up. Try again." });
    return;
  }
  assis.busy = "thinking";
  assis.chat.push({ from: "lar", text: "" });
  const reply = assis.chat[assis.chat.length - 1];
  if (asleep) reply.steps = [{ step: "wake" }];
  const onText = new Channel<string>();
  onText.onmessage = (words) => (reply.text += words);
  const onStep = new Channel<Step>();
  // A new array each time: pushing into the one just assigned would miss the state proxy and lose the first step.
  onStep.onmessage = (s) => (reply.steps = [...(reply.steps ?? []), s]);
  try {
    const r = await invoke<{ reply: string; proposal: Proposal | null; sources: Source[]; intent: Intent; known?: boolean; more?: boolean }>("ai_ask", {
      now: moment(),
      message,
      openKey,
      style: larStyle() || null,
      utcOffset: -new Date().getTimezoneOffset(),
      onText,
      onStep,
      reminders: larReminderList(),
      pick,
    });
    reply.text = r.reply;
    reply.intent = r.intent;
    reply.sources = r.sources.length ? r.sources : undefined;
    reply.known = r.known || undefined;
    if (r.more) [reply.cut, reply.more] = [true, 0];
    if (r.proposal) [reply.proposal, reply.state] = [withNotes(r.proposal, app.notes), "pending"];
  } catch (e) {
    // Stopping cuts the JSON short, which is not a failure the student needs told about.
    reply.text = stopped ? reply.text || "Stopped." : say(e);
  } finally {
    assis.busy = "";
  }
}

export type NoteMode = "summarize" | "tidy" | "explain" | "ask";

/** "Ask AI" in a note: the words stream to `onText`; the result is text to insert or swap in. */
export async function noteAi(mode: NoteMode, text: string, selection: string | null, question: string | null, onText: (words: string) => void): Promise<string> {
  if (!(await wake(looksFilipino(text)))) throw new Error(assis.error || "I couldn't wake up. Try again.");
  assis.busy = "thinking";
  const ch = new Channel<string>();
  ch.onmessage = onText;
  try {
    return await invoke<string>("ai_note", { mode, text, selection, question, onText: ch });
  } finally {
    assis.busy = "";
  }
}

/** After a wrong card answer: why the right one is right, from the card and the student's own note. */
export async function explain(front: string, back: string, typed: string, subject: string | null): Promise<{ why: string; tip: string }> {
  if (!(await wake())) throw new Error(assis.error || "I couldn't wake up. Try again.");
  assis.busy = "thinking";
  try {
    return await invoke<{ why: string; tip: string }>("ai_why", { front, back, typed, note: noteFor(app.notes, subject) ?? null });
  } finally {
    assis.busy = "";
  }
}

/**
 * Spec 041 C25: the model's tidy of a scan's text, or null when IntAssis isn't on, is busy, fails or
 * changes nothing. Never throws and never says why: the scan already has its deterministic text.
 */
export async function tidyScan(text: string): Promise<string | null> {
  if (!installed() || assis.busy) return null;
  try {
    if (!(await wake())) {
      assis.error = "";
      return null;
    }
    assis.busy = "thinking";
    try {
      const out = (await invoke<string>("clean_scan_ai", { text })).trim();
      return out && out !== text.trim() ? out : null;
    } finally {
      assis.busy = "";
    }
  } catch {
    return null;
  }
}

/**
 * Spec 061 C12: classes the model finds in a schedule the rules couldn't read, or null when IntAssis
 * isn't installed, won't wake or is busy. An empty list means it looked and found nothing.
 */
export async function timetableByAi(text: string): Promise<FoundClass[] | null> {
  if (!installed() || assis.busy) return null;
  try {
    if (!(await wake())) {
      assis.error = "";
      return null;
    }
    assis.busy = "thinking";
    try {
      return await invoke<FoundClass[]>("read_timetable_ai", { text });
    } finally {
      assis.busy = "";
    }
  } catch {
    return null;
  }
}

/** A PDF's text, read on the phone. The bytes go as the raw request body (see `ai_pdf_text`). */
export const pdfText = (bytes: Uint8Array) => invoke<string>("ai_pdf_text", bytes);

/** Proposed cards from a note's text. Nothing is saved here; the deck page asks the student first. */
export async function cardsFrom(text: string, want: number, quiz = false): Promise<Draft[]> {
  if (!(await wake())) throw new Error(assis.error || "I couldn't wake up. Try again.");
  assis.busy = "cards";
  try {
    return (await invoke<{ cards: Draft[] }>("ai_cards", { text, want, quiz })).cards;
  } finally {
    assis.busy = "";
  }
}

/** Spec 062 C25: under an answer that stopped at its limit, at most twice. The next part streams into the same bubble. */
export const MORE_MAX = 2;

export async function keepGoing(i: number) {
  const reply = assis.chat[i];
  const question = assis.chat.slice(0, i).findLast((m) => m.from === "me")?.text;
  // The shell extends the newest LAR turn only.
  if (assis.chat.findLastIndex((m) => m.from === "lar") !== i) return;
  if (!reply?.cut || (reply.more ?? 0) >= MORE_MAX || !question || assis.busy) return;
  if (!(await wake())) return void (reply.problem = assis.error || "I couldn't wake up. Try again.");
  assis.busy = "thinking";
  stopped = false;
  const before = reply.text;
  const glue = /\s$/.test(before) ? "" : " ";
  let first = true;
  const onText = new Channel<string>();
  onText.onmessage = (words) => {
    reply.text += first && !/^[\s,.;:]/.test(words) ? glue + words : words;
    first = false;
  };
  try {
    const r = await invoke<{ text: string; more: boolean }>("ai_more", { message: question, soFar: before, onText });
    if (first && r.text) reply.text = before + glue + r.text; // nothing streamed: show it whole
    reply.cut = r.more;
    reply.more = (reply.more ?? 0) + 1;
  } catch (e) {
    if (!stopped) reply.problem = say(e);
  } finally {
    assis.busy = "";
  }
}

/** "Which note do you mean?": ask the same thing again about the note tapped (spec 062 C8). */
export function pickNote(i: number, key: string) {
  const p = assis.chat[i].proposal;
  if (p?.kind !== "pick_note" || assis.chat[i].state !== "pending") return;
  [assis.chat[i].state, assis.chat[i].picked] = ["done", key];
  return ask(p.ask, key, false);
}

/** "Which one do you mean?" for the week (spec 064 C12): the same request again, about the row tapped. */
export function pickItem(i: number, id: string) {
  const p = assis.chat[i].proposal;
  if (p?.kind !== "pick_item" || assis.chat[i].state !== "pending") return;
  [assis.chat[i].state, assis.chat[i].picked] = ["done", id];
  return ask(p.ask, null, false, id);
}

/** Undo on an applied note card: the note goes back to how it was before LAR's change. */
export async function undoChange(i: number) {
  const msg = assis.chat[i];
  const p = msg.proposal;
  if (msg.restore && msg.undo) return undoCalendar(msg);
  if (!p || !("key" in p) || !msg.undo) return;
  try {
    await api.undoLarNote(p.key);
    app.notes = await api.notes();
    [msg.undo, msg.undone, msg.problem] = [false, true, ""];
  } catch (e) {
    const why = say(e);
    // The student edited the note since: there is nothing left to put back, so the button goes (063 Errors).
    if (why === "There's nothing to undo.") [msg.undo, msg.notice] = [false, why];
    else msg.problem = why;
  }
}

export function dismiss(i: number) {
  assis.chat[i].state = "dismissed";
}

/** The student said yes. Only now does anything change, through the same commands the app already uses. */
export async function apply(i: number) {
  const msg = assis.chat[i];
  const p = msg.proposal;
  if (!p || msg.state !== "pending") return;
  msg.problem = "";
  try {
    if (p.kind === "add_note") {
      const { key, title } = noteTarget(p, isoDate(new Date()));
      await api.setNote(key, appended(existingText(app.notes, key), p.text), title);
      app.notes = await api.notes();
    } else if (p.kind === "save_note") {
      const key = `note:${crypto.randomUUID()}`;
      await api.setNote(key, p.text.trim(), p.title.trim() || "Notes from our chat");
      if (p.subject) await api.setNoteSubject(key, p.subject);
      app.notes = await api.notes();
      [msg.text, msg.saved, msg.editing] = ["Saved to your notes.", key, false];
    } else if (p.kind === "edit_note" || p.kind === "rename_note" || p.kind === "move_note" || p.kind === "delete_note") {
      const change =
        p.kind === "edit_note" ? { text: p.after } : p.kind === "rename_note" ? { title: p.title } : p.kind === "move_note" ? { subject: p.subject } : { delete: true };
      await api.larNoteChange(p.key, change);
      app.notes = await api.notes();
      msg.undo = true;
    } else if (p.kind === "pick_note" || p.kind === "pick_item") {
      return;
    } else if (isChange(p)) {
      return await applyCalendar(msg, p);
    } else if (p.kind === "new_class") {
      // A class has too many fields for one card: the editor opens with what LAR read (spec 064 C10).
      const start = p.start ?? 8 * 60;
      app.classEditor = { was: null, cls: { code: "", name: p.name, room: "", teacher: "", meetings: [{ days: p.day ? [p.day] : [], start, end: Math.min(start + 90, 24 * 60 - 1) }] } };
    } else if (p.kind === "set_reminder") {
      const allowed = await ring(reminderId(p.text, p.date), p.text, p.date);
      msg.notice = allowed ? undefined : notificationsOff(looksFilipino(msg.text, p.text, assis.chat[i - 1]?.text));
    } else if (p.kind === "make_cards") {
      assis.busy = "cards";
      const found = await invoke<{ cards: Draft[]; stopped: string | null; known?: boolean }>("ai_topic_cards", { topic: p.topic, want: p.count, quiz: !!p.quiz });
      if (!found.cards.length) throw new Error(`I couldn't make good cards on ${p.topic}. Try a narrower topic, or make them from a note.`);
      // The confirm sentence ("Confirm to start.") is spent: from here the bubble says what was made.
      const n = found.cards.length;
      msg.text = n < p.count ? `I could make ${n} of ${p.count} on ${p.topic}.` : `Here ${n === 1 ? "is 1 card" : `are ${n} cards`} on ${p.topic}.`;
      const quizzing = found.cards.filter((c) => c.wrong?.length).length;
      if (p.quiz) msg.text += ` ${quizzing} of them have wrong answers for the quiz.`;
      // Cards with no note behind them come from the model alone: say so, so the student checks them (C16).
      if (found.known) msg.text += " They're from what I know, not your notes, so check them before you save.";
      msg.cards = found.cards; // Shown for the student to edit; confirmCards saves.
      return;
    }
    msg.state = "done";
  } catch (e) {
    msg.problem = say(e);
  } finally {
    if (assis.busy === "cards") assis.busy = "";
  }
}

/** Rings a reminder LAR set at 8 AM on `date`, and keeps it with its text (064 C11). False: notifications are off. */
async function ring(id: number, text: string, date: string): Promise<boolean> {
  // Same rule as scheduleReminders: look first, ask once, and never say it will ring when it cannot.
  let allowed = await isPermissionGranted();
  if (!allowed) allowed = (await requestPermission()) === "granted";
  app.notifications = allowed;
  try {
    await invoke("plugin:notification|notify", { options: { id, title: "LAR", body: text, schedule: Schedule.at(asLocalDigits(reminderAt(date))) } });
    rememberLarReminder(id, reminderAt(date), text);
  } catch (e) {
    if (allowed) throw e; // a refusal is expected while they are off; anything else is a real failure
  }
  return allowed;
}

const ownOf = (id: string) => app.snapshot?.own_deadlines.find((o) => o.id === id.replace(/^own:/, ""));
const layer = <T>(l: { term: Record<string, T>; weekly: Record<string, Record<string, T>> } | undefined, session: string, week: string | null): T | null =>
  (week ? l?.weekly[session]?.[week] : l?.term[session]) ?? null;
const classOf = (code: string) => classesOf(app.snapshot?.sessions ?? []).find((c) => c.code === code);
const same = (a: unknown, b: unknown) => JSON.stringify(a) === JSON.stringify(b);
const reminderOf = (id: number) => larReminderList().find((r) => r.id === id);

/** The item an Undo would put back, as it is now: compared with how LAR left it before Undo runs. */
function itemNow(r: Restore): string {
  switch (r.do) {
    case "own":
      return JSON.stringify(ownOf(r.id) ?? null);
    case "done":
      return JSON.stringify(app.snapshot?.done.includes(r.id) ?? false);
    case "mark":
      return JSON.stringify(layer(app.snapshot?.marks, r.session, r.week));
    case "move":
      return JSON.stringify(layer(app.snapshot?.marks.moved, r.session, r.week));
    case "class":
      return JSON.stringify(classOf(r.code ?? r.cls.code) ?? null);
    case "reminder":
      return JSON.stringify(r.cancel == null ? null : (reminderOf(r.cancel) ?? null));
  }
}

class Changed extends Error {}

/** Spec 064 C15: the change, through the commands the screens use; then Today, Schedule and the phone calendar follow. */
async function applyCalendar(msg: Msg, p: CalendarChange) {
  let restore: Restore;
  const take = async (snap: Snapshot) => adopt(snap);
  try {
    switch (p.kind) {
      case "add_deadline": {
        const before = new Set(app.snapshot?.own_deadlines.map((o) => o.id));
        const snap = await api.saveOwn({ id: "", title: p.title, subject: p.subject, kind: p.deadline, date: p.date });
        await take(snap);
        restore = { do: "own", id: snap.own_deadlines.find((o) => !before.has(o.id))?.id ?? "", own: null };
        break;
      }
      case "change_deadline":
      case "delete_deadline": {
        const old = ownOf(p.id);
        if (!old || old.title !== p.name || old.date !== (p.kind === "change_deadline" ? p.was : p.date)) throw new Changed();
        await take(p.kind === "change_deadline" ? await api.saveOwn({ ...old, title: p.title, date: p.date }) : await api.deleteOwn(old.id));
        restore = { do: "own", id: old.id, own: { ...old } };
        break;
      }
      case "done_deadline":
        if (app.snapshot?.done.includes(p.id)) throw new Changed();
        await take(await api.setDone(p.id, true));
        restore = { do: "done", id: p.id };
        break;
      case "mark_class":
      case "move_class": {
        const week = p.week ? weekOf(p.week) : null;
        if (!app.snapshot?.sessions.some((s) => sessionId(s) === p.session)) throw new Changed();
        if (p.kind === "mark_class") {
          restore = { do: "mark", session: p.session, week, mark: layer(app.snapshot?.marks, p.session, week) };
          await take(await api.setMark(p.session, week, p.mark));
        } else {
          restore = { do: "move", session: p.session, week, slot: layer(app.snapshot?.marks.moved, p.session, week) };
          await take(await api.setMove(p.session, week, p.slot));
        }
        break;
      }
      case "change_own_class":
        if (!same(classOf(p.was.code), p.was)) throw new Changed();
        await take(await api.saveClass(p.was.code, p.class));
        restore = { do: "class", code: p.class.code, cls: p.was };
        break;
      case "delete_own_class": {
        const cls = classOf(p.code);
        if (!cls) throw new Changed();
        await take(await api.deleteClass(p.code));
        restore = { do: "class", code: null, cls };
        break;
      }
      case "move_reminder":
      case "delete_reminder": {
        const r = reminderOf(p.id);
        if (!r || r.text !== p.text) throw new Changed();
        await unring([p.id]).catch(() => {});
        forgetLarReminder(p.id);
        const put = { id: p.id, date: isoDate(new Date(r.at)), text: r.text };
        if (p.kind === "delete_reminder") restore = { do: "reminder", cancel: null, put };
        else {
          const id = reminderId(p.text, p.date);
          if (!(await ring(id, p.text, p.date))) msg.notice = notificationsOff(false);
          restore = { do: "reminder", cancel: id, put };
        }
        break;
      }
    }
  } catch (e) {
    if (e instanceof Changed) [msg.state, msg.notice] = ["done", CHANGED];
    else msg.problem = NOT_SAVED;
    return;
  }
  [msg.restore, msg.after, msg.undo, msg.state] = [restore, itemNow(restore), true, "done"];
}

/** Spec 064 C16: puts back exactly what was there, unless the student changed it by hand since. */
async function undoCalendar(msg: Msg) {
  const r = msg.restore!;
  if (itemNow(r) !== msg.after) return void ([msg.undo, msg.notice] = [false, "There's nothing to undo."]);
  try {
    switch (r.do) {
      case "own":
        await adopt(r.own ? await api.saveOwn(r.own) : await api.deleteOwn(r.id));
        break;
      case "done":
        await adopt(await api.setDone(r.id, false));
        break;
      case "mark":
        await adopt(await api.setMark(r.session, r.week, r.mark));
        break;
      case "move":
        await adopt(await api.setMove(r.session, r.week, r.slot));
        break;
      case "class":
        await adopt(await api.saveClass(r.code, r.cls));
        break;
      case "reminder":
        if (r.cancel != null) {
          await unring([r.cancel]).catch(() => {});
          forgetLarReminder(r.cancel);
        }
        await ring(r.put.id, r.put.text, r.put.date);
        break;
    }
    [msg.undo, msg.undone, msg.problem] = [false, true, ""];
  } catch {
    msg.problem = NOT_SAVED;
  }
}

/** The student kept these cards (edited or not). Only now is the deck saved. */
export async function confirmCards(i: number) {
  const msg = assis.chat[i];
  const p = msg.proposal;
  if (p?.kind !== "make_cards" || msg.state !== "pending" || !msg.cards) return;
  const cards = tidy(msg.cards, []);
  if (!cards.length) return;
  msg.problem = "";
  try {
    await api.saveDeck(newDeck(crypto.randomUUID(), p.topic, null, cards));
    msg.text = cards.length === 1 ? "Made 1 card." : `Added ${cards.length} cards to ${p.topic}.`;
    msg.cards = undefined;
    msg.state = "done";
  } catch (e) {
    msg.problem = say(e);
  }
}

/**
 * "Write wrong answers" on an old deck (spec 062 C20): one call per 8 cards without them, `onBatch` after
 * each with the cards done so far. `stop()` returning true ends it between batches; what's done is kept (C29).
 */
export async function writeWrongAnswers(cards: Card[], onBatch: (done: Card[]) => Promise<void> | void, stop: () => boolean): Promise<void> {
  if (!(await wake())) throw new Error(assis.error || "I couldn't wake up. Try again.");
  const todo = cards.filter((c) => !c.wrong?.length);
  assis.busy = "cards";
  try {
    for (let k = 0; k < todo.length && !stop(); k += 8) {
      const part = todo.slice(k, k + 8);
      const got = await invoke<string[][]>("ai_wrong_answers", { cards: part.map((c) => ({ front: c.front, back: c.back })) });
      part.forEach((c, n) => got[n]?.length === 3 && (c.wrong = got[n]));
      await onBatch(part);
    }
  } finally {
    assis.busy = "";
  }
}

/** Back out of the preview: nothing was saved, and the offer stands. */
export function discardCards(i: number) {
  assis.chat[i].cards = undefined;
}

/** The iOS notification plugin reads the ISO string's trailing Z as text and takes the digits as local time. */
const asLocalDigits = (d: Date) => new Date(d.getTime() - d.getTimezoneOffset() * 60_000);

/** Wire once: let the model go when the app is hidden, and look for it at launch. */
export function watchAssis() {
  // An install the system cut off (the app was ended mid-download) carries on without a tap (spec 021 C7).
  const resume = () => {
    const id = flagged();
    if (id && !assis.busy) install(id);
  };
  refresh().then(resume);
  document.addEventListener("visibilitychange", () => {
    if (globalThis.document?.hidden) sleep();
    else resume();
  });
}

