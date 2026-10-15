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

export interface Msg {
  from: "me" | "lar";
  text: string;
  proposal?: Proposal;
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

/** The one-time download. Resumes if it was cut off; Cancel keeps what arrived. */
export async function install() {
  const m = chatModel();
  if (!m || assis.busy) return;
  assis.error = "";
  assis.busy = "downloading";
  assis.done = 0;
  assis.total = m.bytes;
  try {
    const onProgress = new Channel<{ done: number; total: number }>();
    onProgress.onmessage = (p) => {
      assis.done = p.done;
      assis.total = p.total;
    };
    await invoke("ai_download", { id: m.id, onProgress });
    await refresh();
  } catch (e) {
    assis.error = say(e) === "paused" ? "" : say(e);
    await refresh();
  } finally {
    assis.busy = "";
  }
}

export const cancelDownload = () => invoke("ai_cancel");

export async function remove() {
  const m = chatModel();
  if (!m) return;
  try {
    await invoke("ai_delete", { id: m.id });
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

export async function open() {
  assis.open = true;
  assis.error = "";
  await wake();
}

export async function ask(text: string) {
  const message = text.trim();
  if (!message || assis.busy) return;
  const history = assis.chat.reduce<[string, string][]>((h, m, i, all) => (m.from === "me" && all[i + 1]?.from === "lar" ? [...h, [m.text, all[i + 1].text]] : h), []);
  assis.chat.push({ from: "me", text: message });
  if (!(await wake())) {
    assis.chat.push({ from: "lar", text: assis.error || "I couldn't wake up. Try again." });
    return;
  }
  assis.busy = "thinking";
  try {
    const r = await invoke<{ reply: string; proposal: Proposal | null }>("ai_ask", { now: moment(), message, history });
    assis.chat.push({ from: "lar", text: r.reply, proposal: r.proposal ?? undefined, state: r.proposal ? "pending" : undefined });
  } catch (e) {
    assis.chat.push({ from: "lar", text: say(e) });
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
      msg.text = `${msg.text} Made ${found.cards.length} cards. Find them under Study.`;
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

