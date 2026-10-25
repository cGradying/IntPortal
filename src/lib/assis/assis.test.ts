import { beforeEach, describe, expect, it, vi } from "vitest";

// A stand-in for the Rust side: each test sets `backend[command]`; every call is recorded.
const backend: Record<string, (args: any) => unknown> = {};
const calls: [string, any][] = [];
vi.mock("@tauri-apps/api/core", () => ({
  Channel: class {
    onmessage: (m: any) => void = () => {};
  },
  invoke: vi.fn(async (cmd: string, args?: any) => {
    calls.push([cmd, args]);
    const h = backend[cmd];
    if (!h) throw new Error(`no handler for ${cmd}`);
    return h(args);
  }),
}));
vi.mock("@tauri-apps/plugin-notification", () => ({
  Schedule: { at: (d: Date) => ({ at: d }) },
  cancel: vi.fn(),
  isPermissionGranted: vi.fn(),
  pending: vi.fn(),
  requestPermission: vi.fn(),
}));

import { invoke } from "@tauri-apps/api/core";
import { cancel, isPermissionGranted, pending as devicePending } from "@tauri-apps/plugin-notification";
import { app, scheduleReminders } from "../state.svelte";
import { apply, confirmCards, discardCards, ask, assis, dismiss, explain, indexNotes, install, larStyle, newChat, noteAi, open, refresh, remove, setLarStyle, STYLE_MAX, stop, type ModelInfo } from "./assis.svelte";

const settle = () => new Promise((r) => setTimeout(r, 0));
const ran = (cmd: string) => calls.filter(([c]) => c === cmd);
function deferred<T>() {
  let resolve!: (v: T) => void, reject!: (e: unknown) => void;
  const promise = new Promise<T>((a, b) => ((resolve = a), (reject = b)));
  return { promise, resolve, reject };
}

const model = (o: Partial<ModelInfo>): ModelInfo => ({ id: "m", name: "M", chat: true, bytes: 1000, installed: true, default: true, fits: "ok", loaded: true, ...o });
const chat = (o: Partial<ModelInfo> = {}) => model({ id: "chat", name: "Chat", ...o });
const embed = (o: Partial<ModelInfo> = {}) => model({ id: "embed", name: "Embed", chat: false, default: false, bytes: 500, ...o });

let disk: ModelInfo[];
beforeEach(() => {
  for (const k of Object.keys(backend)) delete backend[k];
  calls.length = 0;
  disk = [chat(), embed()];
  backend.ai_models = () => structuredClone(disk);
  backend.ai_load = () => undefined;
  backend.ai_cancel = () => undefined;
  backend.ai_clear_history = () => undefined;
  backend.ai_index = () => undefined;
  Object.assign(assis, { models: structuredClone(disk), busy: "", done: 0, total: 0, error: "", open: false, chat: [] });
  app.editing = null;
  app.notes = [];
});

const reply = (text: string, extra: object = {}) => ({ reply: text, proposal: null, sources: [], ...extra });

describe("asking LAR", () => {
  it("grows the reply word by word, then settles on the final text", async () => {
    const d = deferred<unknown>();
    let emit!: (w: string) => void;
    backend.ai_ask = (a) => ((emit = a.onText.onmessage), d.promise);
    const p = ask("  Ano ang due ko?  ");
    await settle();
    expect(assis.chat).toEqual([{ from: "me", text: "Ano ang due ko?" }, { from: "lar", text: "" }]);
    expect(assis.busy).toBe("thinking");
    emit("Walang ");
    emit("due.");
    expect(assis.chat[1].text).toBe("Walang due.");
    d.resolve(reply("Walang due ngayon."));
    await p;
    expect(assis.chat[1].text).toBe("Walang due ngayon.");
    expect(assis.busy).toBe("");
  });

  it("tells the core which note is open, and the question it sent", async () => {
    app.editing = { key: "class:MATH 101", heading: "MATH 101", title: null };
    backend.ai_ask = () => reply("ok");
    await ask("Summarize this note");
    const args = ran("ai_ask")[0][1];
    expect(args.openKey).toBe("class:MATH 101");
    expect(args.message).toBe("Summarize this note");
  });

  it("ignores an empty question, and one sent while LAR is already writing", async () => {
    backend.ai_ask = () => reply("ok");
    await ask("   ");
    assis.busy = "thinking";
    await ask("hello");
    expect(assis.chat).toEqual([]);
    expect(ran("ai_ask")).toHaveLength(0);
  });

  it("wakes the model first when it is installed but not loaded", async () => {
    disk = [chat({ loaded: false }), embed()];
    assis.models = structuredClone(disk);
    backend.ai_load = () => void (disk[0].loaded = true);
    backend.ai_ask = () => reply("hi");
    await ask("hi");
    expect(calls.map(([c]) => c).slice(0, 2)).toEqual(["ai_load", "ai_models"]);
    expect(assis.chat[1].text).toBe("hi");
  });

  it("says why when the model can't wake, and asks nothing", async () => {
    assis.models = [chat({ loaded: false }), embed()];
    backend.ai_load = () => Promise.reject({ message: "Not enough memory. Close other apps and try again." });
    await ask("hi");
    expect(assis.chat.map((m) => m.text)).toEqual(["hi", "Not enough memory. Close other apps and try again."]);
    expect(ran("ai_ask")).toHaveLength(0);
    expect(assis.busy).toBe("");
  });

  it("says so when IntAssis isn't installed", async () => {
    assis.models = [chat({ installed: false, loaded: false })];
    await ask("hi");
    expect(assis.chat[1]).toEqual({ from: "lar", text: "I couldn't wake up. Try again." });
  });

  it("shows the core's plain sentence when the answer fails, as a string or an object", async () => {
    backend.ai_ask = () => Promise.reject("LAR ran out of room for that. Try a shorter question.");
    await ask("one");
    expect(assis.chat[1].text).toBe("LAR ran out of room for that. Try a shorter question.");
    backend.ai_ask = () => Promise.reject({ message: "Hindi ko nabasa ang notes mo." });
    await ask("two");
    expect(assis.chat[3].text).toBe("Hindi ko nabasa ang notes mo.");
    expect(assis.busy).toBe("");
  });

  it("keeps the notes LAR was shown as chips with key and title", async () => {
    const sources = [{ key: "class:MATH 101", title: "MATH 101 · Mathematics" }, { key: "note:lar-1", title: "From LAR" }];
    backend.ai_ask = () => reply("See your notes.", { sources });
    await ask("limits?");
    expect(assis.chat[1].sources).toEqual(sources);
    backend.ai_ask = () => reply("No notes needed.");
    await ask("hello");
    expect(assis.chat[3].sources).toBeUndefined();
  });

  it("holds a proposal as pending until the student answers", async () => {
    const proposal = { kind: "add_note", subject: null, text: "bring calculator" };
    backend.ai_ask = () => reply("Add this?", { proposal });
    await ask("add a note");
    expect(assis.chat[1]).toMatchObject({ proposal, state: "pending" });
    dismiss(1);
    expect(assis.chat[1].state).toBe("dismissed");
  });
});

describe("Stop", () => {
  it("cancels the model and keeps the words so far, with no error bubble", async () => {
    const d = deferred<unknown>();
    let emit!: (w: string) => void;
    backend.ai_ask = (a) => ((emit = a.onText.onmessage), d.promise);
    const p = ask("explain heaps");
    await settle();
    emit("A heap is ");
    stop();
    expect(ran("ai_cancel")).toHaveLength(1);
    d.reject("EOF while parsing a value at line 1 column 11");
    await p;
    expect(assis.chat[1].text).toBe("A heap is ");
    expect(assis.busy).toBe("");
  });

  it("says Stopped when nothing had been written yet", async () => {
    const d = deferred<unknown>();
    backend.ai_ask = () => d.promise;
    const p = ask("hi");
    await settle();
    stop();
    d.reject("cancelled");
    await p;
    expect(assis.chat[1].text).toBe("Stopped.");
  });

  it("survives a rejected ai_cancel", () => {
    const rejected = Promise.reject("gone");
    const caught = vi.spyOn(rejected, "catch");
    vi.mocked(invoke).mockReturnValueOnce(rejected);
    stop();
    expect(caught).toHaveBeenCalled(); // an unhandled rejection otherwise
  });

  it("while the model is waking cancels the ask: no reply, no ai_ask", async () => {
    assis.models = [chat({ loaded: false }), embed()];
    const d = deferred<unknown>();
    backend.ai_load = () => d.promise;
    backend.ai_ask = () => reply("late");
    const p = ask("hi");
    await settle();
    expect(assis.busy).toBe("waking");
    stop();
    d.resolve(undefined);
    await p;
    expect(ran("ai_ask")).toHaveLength(0);
    expect(assis.chat).toEqual([{ from: "me", text: "hi" }]);
    expect(assis.busy).toBe("");
  });

  it("does not hide a real failure in the next question", async () => {
    stop(); // a Stop with nothing running
    backend.ai_ask = () => Promise.reject("Something broke. Try again.");
    await ask("hi");
    expect(assis.chat[1].text).toBe("Something broke. Try again.");
  });
});

describe("the chat history", () => {
  it("is restored when LAR opens after a relaunch", async () => {
    backend.ai_history = () => [{ role: "me", text: "hi" }, { role: "lar", text: "Hello!" }];
    await open();
    await settle();
    expect(assis.open).toBe(true);
    expect(assis.chat).toEqual([{ from: "me", text: "hi" }, { from: "lar", text: "Hello!" }]);
  });

  it("does not overwrite a chat already on screen", async () => {
    assis.chat = [{ from: "me", text: "now" }];
    backend.ai_history = () => [{ role: "me", text: "old" }];
    await open();
    await settle();
    expect(assis.chat).toEqual([{ from: "me", text: "now" }]);
  });

  it("opens with an empty chat if the history can't be read", async () => {
    backend.ai_history = () => Promise.reject("nope");
    await open();
    await settle();
    expect(assis.chat).toEqual([]);
  });

  it("New chat empties the screen and the saved history", async () => {
    assis.chat = [{ from: "me", text: "hi" }, { from: "lar", text: "hello" }];
    await newChat();
    expect(assis.chat).toEqual([]);
    expect(ran("ai_clear_history")).toHaveLength(1);
  });
});

describe("indexing notes", () => {
  it("runs when the sheet opens", async () => {
    backend.ai_history = () => [];
    await open();
    expect(ran("ai_index")).toHaveLength(1);
  });

  it("runs after an edit (indexNotes), but only when IntAssis is installed", () => {
    indexNotes();
    expect(ran("ai_index")).toHaveLength(1);
    assis.models = [chat({ installed: false })];
    indexNotes();
    expect(ran("ai_index")).toHaveLength(1);
  });

  it("never breaks the caller when indexing fails", async () => {
    backend.ai_index = () => Promise.reject("busy");
    expect(() => indexNotes()).not.toThrow();
    await settle();
  });
});

describe("installing IntAssis", () => {
  beforeEach(() => {
    disk = [chat({ installed: false, loaded: false, bytes: 1000 }), embed({ installed: false, bytes: 500 })];
    assis.models = structuredClone(disk);
    backend.ai_download = (a) => {
      a.onProgress.onmessage({ done: 10, total: 10 });
      disk.find((m) => m.id === a.id)!.installed = true;
    };
  });

  it("downloads the chat model and the search model, one after the other", async () => {
    await install();
    expect(ran("ai_download").map(([, a]) => a.id)).toEqual(["chat", "embed"]);
    expect(assis.models.every((m) => m.installed)).toBe(true);
    expect(assis.busy).toBe("");
    expect(assis.error).toBe("");
  });

  it("shows one bar over both: total is the sum, progress carries across models", async () => {
    const seen: number[] = [];
    backend.ai_download = (a) => {
      expect(assis.total).toBe(1500);
      a.onProgress.onmessage({ done: 400, total: 1000 });
      seen.push(assis.done);
      disk.find((m) => m.id === a.id)!.installed = true;
    };
    const p = install();
    expect(assis.busy).toBe("downloading");
    await p;
    expect(seen).toEqual([400, 1400]);
  });

  it("only fetches what is missing", async () => {
    disk[0].installed = true;
    assis.models = structuredClone(disk);
    await install();
    expect(ran("ai_download").map(([, a]) => a.id)).toEqual(["embed"]);
  });

  it("does nothing when both are installed, or a download is running", async () => {
    assis.models = [chat(), embed()];
    await install();
    assis.models = structuredClone(disk);
    assis.busy = "thinking";
    await install();
    expect(ran("ai_download")).toHaveLength(0);
  });

  it("surfaces a failure and lets the student try again", async () => {
    backend.ai_download = () => Promise.reject("No connection. Check Wi-Fi and try again.");
    await install();
    expect(assis.error).toBe("No connection. Check Wi-Fi and try again.");
    expect(assis.busy).toBe("");
    expect(ran("ai_download")).toHaveLength(1); // stops at the first failure
  });

  it("treats Pause as quiet, not as an error", async () => {
    backend.ai_download = () => Promise.reject("paused");
    await install();
    expect(assis.error).toBe("");
    expect(assis.busy).toBe("");
  });
});

describe("removing IntAssis", () => {
  it("deletes both models, empties the chat and closes the sheet", async () => {
    assis.chat = [{ from: "me", text: "hi" }];
    assis.open = true;
    backend.ai_delete = (a) => void (disk.find((m) => m.id === a.id)!.installed = false);
    await remove();
    expect(ran("ai_delete").map(([, a]) => a.id)).toEqual(["chat", "embed"]);
    expect(ran("ai_clear_history")).toHaveLength(1);
    expect(assis.chat).toEqual([]);
    expect(assis.open).toBe(false);
    expect(assis.models.some((m) => m.installed)).toBe(false);
  });

  it("keeps the chat and shows the problem if a delete fails", async () => {
    assis.chat = [{ from: "me", text: "hi" }];
    backend.ai_delete = () => Promise.reject({ message: "Couldn't remove the files." });
    await remove();
    expect(assis.error).toBe("Couldn't remove the files.");
    expect(assis.chat).toHaveLength(1);
  });
});

describe("models list", () => {
  it("is empty (IntAssis hidden) when the commands don't exist", async () => {
    delete backend.ai_models;
    await refresh();
    expect(assis.models).toEqual([]);
  });
});

describe("Ask AI in a note", () => {
  it("streams words to the caller and returns the final text", async () => {
    backend.ai_note = (a) => {
      a.onText.onmessage("Short ");
      a.onText.onmessage("version");
      return "Short version.";
    };
    const words: string[] = [];
    const out = await noteAi("summarize", "long note", null, null, (w) => words.push(w));
    expect(words).toEqual(["Short ", "version"]);
    expect(out).toBe("Short version.");
    expect(ran("ai_note")[0][1]).toMatchObject({ mode: "summarize", text: "long note", selection: null, question: null });
    expect(assis.busy).toBe("");
  });

  it("passes the selection and question, and frees the model state on failure", async () => {
    backend.ai_note = () => Promise.reject("Too long for me. Select less.");
    await expect(noteAi("ask", "n", "sel", "why?", () => {})).rejects.toBe("Too long for me. Select less.");
    expect(ran("ai_note")[0][1]).toMatchObject({ selection: "sel", question: "why?" });
    expect(assis.busy).toBe("");
  });

  it("rejects with the reason when the model can't wake", async () => {
    assis.models = [chat({ installed: false })];
    await expect(noteAi("tidy", "n", null, null, () => {})).rejects.toThrow("I couldn't wake up. Try again.");
  });
});

describe("Why?", () => {
  it("grounds the explanation in the student's own class note", async () => {
    app.notes = [{ key: "class:COMP 20073", text: "root is min", title: null, updated: 1, preview: "" }];
    backend.ai_why = () => ({ why: "w", tip: "t" });
    expect(await explain("Root?", "Top", "bottom", "COMP 20073")).toEqual({ why: "w", tip: "t" });
    expect(ran("ai_why")[0][1]).toEqual({ front: "Root?", back: "Top", typed: "bottom", note: "root is min" });
    await explain("Root?", "Top", "bottom", null);
    expect(ran("ai_why")[1][1].note).toBeNull();
  });
});

describe("applying a proposal", () => {
  const pending = (proposal: any) => (assis.chat = [{ from: "lar", text: "Sure.", proposal, state: "pending" }]);

  it("adds to the class note without overwriting it", async () => {
    app.notes = [{ key: "class:MATH 101", text: "Quiz Friday", title: null, updated: 1, preview: "" }];
    backend.set_note = () => undefined;
    backend.notes = () => [];
    pending({ kind: "add_note", subject: "MATH 101", text: "Bring calculator" });
    await apply(0);
    expect(ran("set_note")[0][1]).toEqual({ key: "class:MATH 101", text: "Quiz Friday\n\nBring calculator", title: null });
    expect(assis.chat[0].state).toBe("done");
  });

  it("does nothing for a card already answered", async () => {
    pending({ kind: "add_note", subject: null, text: "x" });
    assis.chat[0].state = "dismissed";
    await apply(0);
    expect(calls).toHaveLength(0);
  });

  it("keeps the card pending and shows the problem when saving fails", async () => {
    backend.set_note = () => Promise.reject("Disk is full.");
    pending({ kind: "add_note", subject: null, text: "x" });
    await apply(0);
    expect(assis.chat[0]).toMatchObject({ state: "pending", problem: "Disk is full." });
  });

  it("shows the cards LAR wrote first and saves nothing until the student confirms", async () => {
    backend.ai_cards = () => ({ cards: [{ front: "a", back: "b" }, { front: "c", back: "d" }], stopped: null });
    backend.save_deck = () => undefined;
    pending({ kind: "make_cards", topic: "Trees" });
    await apply(0);
    expect(ran("save_deck")).toHaveLength(0);
    expect(assis.chat[0].cards).toEqual([{ front: "a", back: "b" }, { front: "c", back: "d" }]);
    expect(assis.chat[0].state).toBe("pending");
    expect(assis.busy).toBe("");
  });

  it("saves the deck with the student's edits and removals on confirm", async () => {
    backend.ai_cards = () => ({ cards: [{ front: "a", back: "b" }, { front: "c", back: "d" }, { front: "e", back: "f" }], stopped: null });
    backend.save_deck = () => undefined;
    pending({ kind: "make_cards", topic: "Trees" });
    await apply(0);
    assis.chat[0].cards![0].back = "edited";
    assis.chat[0].cards!.splice(1, 1);
    await confirmCards(0);
    const deck = ran("save_deck")[0][1].deck;
    expect(deck.name).toBe("Trees");
    expect(deck.cards.map((c: any) => [c.front, c.back])).toEqual([["a", "edited"], ["e", "f"]]);
    expect(assis.chat[0].text).toBe("Sure. Made 2 cards. Find them under Study.");
    expect(assis.chat[0]).toMatchObject({ state: "done", cards: undefined });
  });

  it("says 1 card, not 1 cards", async () => {
    backend.ai_cards = () => ({ cards: [{ front: "a", back: "b" }], stopped: null });
    backend.save_deck = () => undefined;
    pending({ kind: "make_cards", topic: "Trees" });
    await apply(0);
    await confirmCards(0);
    expect(assis.chat[0].text).toBe("Sure. Made 1 card. Find them under Study.");
  });

  it("discarding the preview saves nothing and offers the proposal again", async () => {
    backend.ai_cards = () => ({ cards: [{ front: "a", back: "b" }], stopped: null });
    pending({ kind: "make_cards", topic: "Trees" });
    await apply(0);
    discardCards(0);
    expect(ran("save_deck")).toHaveLength(0);
    expect(assis.chat[0]).toMatchObject({ state: "pending", cards: undefined });
  });

  it("confirms nothing when every card was removed", async () => {
    backend.ai_cards = () => ({ cards: [{ front: "a", back: "b" }], stopped: null });
    pending({ kind: "make_cards", topic: "Trees" });
    await apply(0);
    assis.chat[0].cards!.length = 0;
    await confirmCards(0);
    expect(ran("save_deck")).toHaveLength(0);
  });

  it("explains when no cards could be made", async () => {
    backend.ai_cards = () => ({ cards: [], stopped: null });
    pending({ kind: "make_cards", topic: "Trees" });
    await apply(0);
    expect(assis.chat[0].problem).toMatch(/couldn't make cards/);
    expect(assis.chat[0].state).toBe("pending");
    expect(assis.busy).toBe("");
  });
});

describe("how LAR talks to me", () => {
  let store: Map<string, string>;
  beforeEach(() => {
    store = new Map();
    vi.stubGlobal("localStorage", { getItem: (k: string) => store.get(k) ?? null, setItem: (k: string, v: string) => void store.set(k, v), removeItem: (k: string) => void store.delete(k) });
  });

  it("keeps the note trimmed and cut at 200 characters, and an empty note removes it", () => {
    setLarStyle("  Call me Ate.  ");
    expect(larStyle()).toBe("Call me Ate.");
    setLarStyle("x".repeat(500));
    expect(larStyle()).toHaveLength(STYLE_MAX);
    expect(STYLE_MAX).toBe(200);
    setLarStyle("   ");
    expect(larStyle()).toBe("");
    expect(store.has("larStyle")).toBe(false);
  });

  it("sends the note with the question, and null when there is none", async () => {
    backend.ai_ask = () => reply("ok");
    await ask("hello");
    expect(ran("ai_ask")[0][1].style).toBeNull();
    setLarStyle("Taglish, a bit playful");
    await ask("hello again");
    expect(ran("ai_ask")[1][1].style).toBe("Taglish, a bit playful");
  });

  it("asks without a note when storage is off", async () => {
    vi.stubGlobal("localStorage", { getItem: () => { throw new Error("off"); }, setItem: () => { throw new Error("off"); }, removeItem: () => { throw new Error("off"); } });
    backend.ai_ask = () => reply("ok");
    setLarStyle("kept this session only?");
    await ask("hello");
    expect(ran("ai_ask")[0][1].style).toBeNull();
  });
});

describe("LAR reminders and the weekly reschedule", () => {
  // A phone's queue: notify adds, cancel removes, pending lists. Like iOS, pending carries no title we rely on.
  let queue: { id: number; schedule: unknown }[];
  beforeEach(() => {
    const store = new Map<string, string>();
    vi.stubGlobal("localStorage", { getItem: (k: string) => store.get(k) ?? null, setItem: (k: string, v: string) => void store.set(k, v) });
    queue = [];
    backend["plugin:notification|notify"] = ({ options }) => void (queue = queue.filter((q) => q.id !== options.id).concat({ id: options.id, schedule: options.schedule }));
    backend.reminders = () => [{ id: 7, title: "MATH 101", body: "in 10 min", date: "2099-01-05", minute: 480 }];
    vi.mocked(devicePending).mockImplementation(async () => structuredClone(queue) as any);
    vi.mocked(cancel).mockImplementation(async (ids: any) => void (queue = queue.filter((q) => !ids.includes(q.id))));
    vi.mocked(isPermissionGranted).mockResolvedValue(true);
    Object.assign(app, { snapshot: {}, reminderLead: 10, deadlineAt: -1, studyAt: -1 });
  });

  it("keeps a reminder LAR set when the app reschedules class reminders", async () => {
    const at = "2099-01-06";
    assis.chat = [{ from: "lar", text: "Sure.", proposal: { kind: "set_reminder", date: at, text: "Bring ID" }, state: "pending" }];
    await apply(0);
    const larId = queue[0].id;
    queue.push({ id: 7, schedule: "old class reminder" });
    await scheduleReminders();
    expect(queue.map((q) => q.id).sort()).toEqual([larId, 7].sort());
  });

  it("still cancels class reminders that are not LAR's", async () => {
    queue.push({ id: 99, schedule: "stale" });
    await scheduleReminders();
    expect(queue.map((q) => q.id)).toEqual([7]);
  });

  it("keeps LAR's reminder even when class reminders are off", async () => {
    assis.chat = [{ from: "lar", text: "Sure.", proposal: { kind: "set_reminder", date: "2099-01-06", text: "Bring ID" }, state: "pending" }];
    await apply(0);
    Object.assign(app, { reminderLead: 0 });
    await scheduleReminders();
    expect(queue).toHaveLength(1);
  });
});
