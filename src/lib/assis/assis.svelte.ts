// LAR's brain, as the UI sees it: which model is on the phone, the chat, and
// what happens when the student confirms a proposal. The model runs in Rust;
// nothing here writes until Apply.
import { Channel, invoke } from "@tauri-apps/api/core";
import { Schedule, isPermissionGranted, requestPermission } from "@tauri-apps/plugin-notification";
import { api, isoDate, moment } from "../api";
import { app } from "../state.svelte";
import { tidy, type Draft } from "./cards";
import { appended, existingText, newDeck, noteFor, looksFilipino, noteTarget, notificationsOff, reminderAt, reminderId, rememberLarReminder, type Proposal } from "./apply";

export interface ModelInfo {
  id: string;
  name: string;
  chat: boolean;
  bytes: number;
  installed: boolean;
  default: boolean;
  fits: "ok" | "warn" | "refuse";
  loaded: boolean;
}

export interface Source {
  key: string;
  title: string;
}

export interface Msg {
  from: "me" | "lar";
  text: string;
  proposal?: Proposal;
  /** The notes LAR was shown for this answer; each opens that note. */
  sources?: Source[];
  /** pending until the student answers the card. */
  state?: "pending" | "done" | "dismissed";
  problem?: string;
  /** Shown instead of "Done" when the action worked but needs the student to do something (notifications off). */
  notice?: string;
  /** make_cards: the cards LAR wrote, shown to edit before anything is saved. */
  cards?: Draft[];
}

export const assis = $state({
  models: [] as ModelInfo[],
  /** What the phone is doing for LAR right now. */
  busy: "" as "" | "downloading" | "waking" | "thinking" | "cards",
  done: 0,
  total: 0,
  /** The model is taking long to wake: the sheet says the phone is slow instead of sitting on "Waking up". */
  slow: false,
  error: "",
  open: false,
  chat: [] as Msg[],
});

/** The model a new install gets (the catalog's default chat model). */
export const defaultChat = () => assis.models.find((m) => m.chat && m.default) ?? assis.models.find((m) => m.chat);
/**
 * The model that answers: the default when it is installed, else whichever chat model is
 * (a phone that has the old default keeps working until its student taps Update), else the
 * default, so "Add IntAssis" has a target. Nothing is stored: it follows from what is on the phone.
 */
export const chatModel = () => {
  const d = defaultChat();
  return d?.installed ? d : assis.models.find((m) => m.chat && m.installed) ?? d;
};
/** The small model that finds the student's notes. */
export const embedModel = () => assis.models.find((m) => !m.chat);
export const installed = () => assis.models.some((m) => m.chat && m.installed);
/** A chat model is on the phone but it is not the default: the card offers Update. */
export const updatable = () => installed() && !defaultChat()?.installed;
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

/** Downloads `todo` in order with one bar over all of them. True when every file arrived. Resumes if cut off; Pause keeps what arrived. */
async function fetchAll(todo: ModelInfo[]): Promise<boolean> {
  if (!todo.length || assis.busy) return false;
  assis.error = "";
  assis.busy = "downloading";
  assis.done = 0;
  assis.total = todo.reduce((n, m) => n + m.bytes, 0);
  let before = 0;
  try {
    for (const m of todo) {
      const onProgress = new Channel<{ done: number; total: number }>();
      onProgress.onmessage = (p) => (assis.done = before + p.done);
      await invoke("ai_download", { id: m.id, onProgress });
      before += m.bytes;
      await refresh();
    }
    return true;
  } catch (e) {
    assis.error = say(e) === "paused" ? "" : say(e);
    await refresh();
    return false;
  } finally {
    assis.busy = "";
  }
}

/**
 * The one-time download: LAR's brain, then the model that finds your notes, whichever is missing.
 * On a phone that has another chat model (the old default) this is the update: that model keeps
 * answering until the new one has arrived, then goes, so the phone holds one chat model. The chat
 * history, the notes index and the settings are not touched.
 */
export async function install() {
  const chat = defaultChat();
  const todo = [chat, embedModel()].filter((m): m is ModelInfo => !!m && !m.installed);
  const hadOther = updatable();
  if (!chat || !(await fetchAll(todo))) return;
  if (hadOther && defaultChat()?.installed) {
    for (const old of assis.models.filter((m) => m.chat && !m.default && m.installed)) await invoke("ai_delete", { id: old.id }).catch(() => {});
    await refresh();
  }
}

/** Adds only the note search, for a phone whose chat model is already on it. */
export const addSearch = () => fetchAll([embedModel()].filter((m): m is ModelInfo => !!m && !m.installed));

export const cancelDownload = () => invoke("ai_cancel");

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
async function loadHistory() {
  if (assis.chat.length) return;
  try {
    const turns = await invoke<{ role: string; text: string }[]>("ai_history");
    if (!assis.chat.length) assis.chat = turns.map((t) => ({ from: t.role === "me" ? "me" : "lar", text: t.text }));
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

export async function ask(text: string) {
  const message = text.trim();
  if (!message || assis.busy) return;
  assis.chat.push({ from: "me", text: message });
  stopped = false;
  const awake = await wake(looksFilipino(message));
  if (stopped) return; // Stop while the model was waking: no reply at all
  if (!awake) {
    assis.chat.push({ from: "lar", text: assis.error || "I couldn't wake up. Try again." });
    return;
  }
  assis.busy = "thinking";
  assis.chat.push({ from: "lar", text: "" });
  const reply = assis.chat[assis.chat.length - 1];
  const onText = new Channel<string>();
  onText.onmessage = (words) => (reply.text += words);
  try {
    const r = await invoke<{ reply: string; proposal: Proposal | null; sources: Source[] }>("ai_ask", { now: moment(), message, openKey: app.editing?.key ?? null, style: larStyle() || null, utcOffset: -new Date().getTimezoneOffset(), onText });
    reply.text = r.reply;
    reply.sources = r.sources.length ? r.sources : undefined;
    if (r.proposal) [reply.proposal, reply.state] = [r.proposal, "pending"];
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

/** A PDF's text, read on the phone. The bytes go as the raw request body (see `ai_pdf_text`). */
export const pdfText = (bytes: Uint8Array) => invoke<string>("ai_pdf_text", bytes);

/** Proposed cards from a note's text. Nothing is saved here; the deck page asks the student first. */
export async function cardsFrom(text: string, want: number): Promise<{ front: string; back: string }[]> {
  if (!(await wake())) throw new Error(assis.error || "I couldn't wake up. Try again.");
  assis.busy = "cards";
  try {
    return (await invoke<{ cards: { front: string; back: string }[] }>("ai_cards", { text, want })).cards;
  } finally {
    assis.busy = "";
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
    } else if (p.kind === "set_reminder") {
      const id = reminderId(p.text, p.date);
      // Same rule as scheduleReminders: look first, ask once, and never say it will ring when it cannot.
      let allowed = await isPermissionGranted();
      if (!allowed) allowed = (await requestPermission()) === "granted";
      app.notifications = allowed;
      try {
        await invoke("plugin:notification|notify", {
          options: { id, title: "LAR", body: p.text, schedule: Schedule.at(asLocalDigits(reminderAt(p.date))) },
        });
        rememberLarReminder(id, reminderAt(p.date));
      } catch (e) {
        if (allowed) throw e; // a refusal is expected while they are off; anything else is a real failure
      }
      msg.notice = allowed ? undefined : notificationsOff(looksFilipino(msg.text, p.text, assis.chat[i - 1]?.text));
    } else {
      assis.busy = "cards";
      const found = await invoke<{ cards: { front: string; back: string }[]; stopped: string | null }>("ai_cards", { text: `Topic: ${p.topic}`, want: p.count });
      if (!found.cards.length) throw new Error("I couldn't make cards for that. Try a note's own text instead.");
      // The confirm sentence ("Confirm to start.") is spent: from here the bubble says what was made.
      const n = found.cards.length;
      msg.text = n < p.count ? `I could make ${n} of ${p.count} from what I know.` : `Here ${n === 1 ? "is 1 card" : `are ${n} cards`} on ${p.topic}.`;
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

/** Back out of the preview: nothing was saved, and the offer stands. */
export function discardCards(i: number) {
  assis.chat[i].cards = undefined;
}

/** The iOS notification plugin reads the ISO string's trailing Z as text and takes the digits as local time. */
const asLocalDigits = (d: Date) => new Date(d.getTime() - d.getTimezoneOffset() * 60_000);

/** Wire once: let the model go when the app is hidden, and look for it at launch. */
export function watchAssis() {
  refresh();
  document.addEventListener("visibilitychange", () => {
    if (globalThis.document?.hidden) sleep();
  });
}

