// LAR's brain, as the UI sees it: which model is on the phone, the chat, and
// what happens when the student confirms a proposal. The model runs in Rust;
// nothing here writes until Apply.
import { Channel, invoke } from "@tauri-apps/api/core";
import { Schedule } from "@tauri-apps/plugin-notification";
import { api, isoDate, moment } from "../api";
import { app } from "../state.svelte";
import { appended, existingText, newDeck, noteFor, noteTarget, reminderAt, reminderId, type Proposal } from "./apply";

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
}

export const assis = $state({
  models: [] as ModelInfo[],
  /** What the phone is doing for LAR right now. */
  busy: "" as "" | "downloading" | "waking" | "thinking" | "cards",
  done: 0,
  total: 0,
  error: "",
  open: false,
  chat: [] as Msg[],
});

export const chatModel = () => assis.models.find((m) => m.chat && m.default) ?? assis.models.find((m) => m.chat);
/** The small model that finds the student's notes. */
export const embedModel = () => assis.models.find((m) => !m.chat);
export const installed = () => assis.models.some((m) => m.chat && m.installed);
export const mb = (bytes: number) => (bytes >= 1e9 ? `${(bytes / 1e9).toFixed(2)} GB` : `${Math.round(bytes / 1e6)} MB`);

const say = (e: unknown) => (typeof e === "string" ? e : (e as { message?: string })?.message ?? JSON.stringify(e));

export async function refresh() {
  try {
    assis.models = await invoke<ModelInfo[]>("ai_models");
  } catch {
    assis.models = []; // Linux or a build without the commands: IntAssis stays hidden
  }
}

/** The one-time download: LAR's brain, then the small model that finds your notes. Resumes if it was cut off; Pause keeps what arrived. */
export async function install() {
  const chat = chatModel();
  const todo = [chat, embedModel()].filter((m): m is ModelInfo => !!m && !m.installed);
  if (!chat || !todo.length || assis.busy) return;
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
  } catch (e) {
    assis.error = say(e) === "paused" ? "" : say(e);
    await refresh();
  } finally {
    assis.busy = "";
  }
}

export const cancelDownload = () => invoke("ai_cancel");

export async function remove() {
  try {
    for (const m of assis.models) if (m.installed) await invoke("ai_delete", { id: m.id });
    await invoke("ai_clear_history");
    assis.chat = [];
    assis.open = false;
  } catch (e) {
    assis.error = say(e);
  }
  await refresh();
}

/** Loads the model when LAR is opened. iOS ends an app holding 1 GB in the background, so it is let go in `sleep`. */
export async function wake(): Promise<boolean> {
  const m = chatModel();
  if (!m?.installed) return false;
  if (m.loaded) return true;
  assis.busy = "waking";
  try {
    await invoke("ai_load", { id: m.id });
    await refresh();
    return true;
  } catch (e) {
    assis.error = say(e);
    return false;
  } finally {
    assis.busy = "";
  }
}

export async function sleep() {
  await invoke("ai_unload").catch(() => {});
  await refresh();
}

/** Notes edited since LAR last looked get embedded, so the next question can find them. */
export function indexNotes() {
  if (installed()) invoke("ai_index").catch(() => {});
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
  indexNotes();
  await wake();
}

let stopped = false;
/** Stop writing; the words so far stay. */
export function stop() {
  stopped = true;
  invoke("ai_cancel").catch(() => {});
}

export async function ask(text: string) {
  const message = text.trim();
  if (!message || assis.busy) return;
  assis.chat.push({ from: "me", text: message });
  stopped = false;
  const awake = await wake();
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
    const r = await invoke<{ reply: string; proposal: Proposal | null; sources: Source[] }>("ai_ask", { now: moment(), message, openKey: app.editing?.key ?? null, onText });
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
  if (!(await wake())) throw new Error(assis.error || "I couldn't wake up. Try again.");
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
      await invoke("plugin:notification|notify", {
        options: { id: reminderId(p.text, p.date), title: "LAR", body: p.text, schedule: Schedule.at(asLocalDigits(reminderAt(p.date))) },
      });
    } else {
      assis.busy = "cards";
      const found = await invoke<{ cards: { front: string; back: string }[]; stopped: string | null }>("ai_cards", { text: `Topic: ${p.topic}`, want: 8 });
      if (!found.cards.length) throw new Error("I couldn't make cards for that. Try a note's own text instead.");
      await api.saveDeck(newDeck(crypto.randomUUID(), p.topic, null, found.cards));
      msg.text = `${msg.text} Made ${found.cards.length} ${found.cards.length === 1 ? "card" : "cards"}. Find them under Study.`;
    }
    msg.state = "done";
  } catch (e) {
    msg.problem = say(e);
  } finally {
    if (assis.busy === "cards") assis.busy = "";
  }
}

/** The iOS notification plugin reads the ISO string's trailing Z as text and takes the digits as local time. */
const asLocalDigits = (d: Date) => new Date(d.getTime() - d.getTimezoneOffset() * 60_000);

/** Wire once: let the model go when the app is hidden, and look for it at launch. */
export function watchAssis() {
  refresh();
  document.addEventListener("visibilitychange", () => {
    if (document.hidden) sleep();
  });
}

