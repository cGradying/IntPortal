import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

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
import { cancel, isPermissionGranted, pending as devicePending, requestPermission } from "@tauri-apps/plugin-notification";
import { app, scheduleReminders } from "../state.svelte";
import { addSearch, apply, keepGoing, chatModel, embedModel, mb, confirmCards, discardCards, ask, assis, dismiss, explain, indexNotes, install, choices, larStyle, spaceLine, speedOf, etaLine, newChat, noRoom, downloadSizes, noteAi, open, refresh, remove, setLarStyle, STYLE_MAX, stop, updatable, wake, sleep, tidyScan, WAKE_GIVE_UP_MS, WAKE_SLOW_MS, type ModelInfo } from "./assis.svelte";

const settle = () => new Promise((r) => setTimeout(r, 0));
const ran = (cmd: string) => calls.filter(([c]) => c === cmd);
function deferred<T>() {
  let resolve!: (v: T) => void, reject!: (e: unknown) => void;
  const promise = new Promise<T>((a, b) => ((resolve = a), (reject = b)));
  return { promise, resolve, reject };
}

const model = (o: Partial<ModelInfo>): ModelInfo => ({ id: "m", name: "M", chat: true, bytes: 1000, installed: true, default: true, fits: "ok", loaded: true, ...o });
const chat = (o: Partial<ModelInfo> = {}) => model({ id: "chat", name: "Chat", ...o });
const gemma = (o: Partial<ModelInfo> = {}) => model({ id: "gemma", name: "Gemma", default: false, bytes: 800, legacy: true, ...o });
const qwen3 = (o: Partial<ModelInfo> = {}) => model({ id: "qwen3", name: "Qwen3 1.7B", default: false, bytes: 1100, ...o });
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

  it("c12: keeps the steps LAR really took on his turn, in order, with the intent", async () => {
    backend.ai_ask = (a) => {
      a.onStep.onmessage({ step: "read" });
      a.onStep.onmessage({ step: "search" });
      a.onStep.onmessage({ step: "found", found: [{ key: "card:7", title: "OOP" }], quote: "a promise" });
      a.onStep.onmessage({ step: "write" });
      return reply("An interface is a promise.", { intent: "ask" });
    };
    await ask("what is an interface?");
    expect(assis.chat[1].steps?.map((s) => s.step)).toEqual(["read", "search", "found", "write"]);
    expect(assis.chat[1].intent).toBe("ask");
  });

  it("c12: a turn that had to wake the model starts with the wake step", async () => {
    disk = [chat({ loaded: false }), embed()];
    assis.models = structuredClone(disk);
    backend.ai_load = () => (disk = [chat(), embed()], undefined);
    backend.ai_ask = (a) => (a.onStep.onmessage({ step: "read" }), reply("Walang due.", { intent: "due" }));
    await ask("ano ang due ko");
    expect(assis.chat[1].steps?.map((s) => s.step)).toEqual(["wake", "read"]);
  });

  it("c12: steps are session-only, so a turn from history has none", async () => {
    backend.ai_history = () => [{ role: "me", text: "hi" }, { role: "lar", text: "Hello!" }];
    await open();
    await settle();
    expect(assis.chat).toHaveLength(2);
    expect(assis.chat.every((m) => m.steps === undefined && m.intent === undefined)).toBe(true);
  });

  it("tells the core which note is open, and the question it sent", async () => {
    app.editing = { key: "class:MATH 101", heading: "MATH 101", title: null };
    backend.ai_ask = () => reply("ok");
    await ask("Summarize this note");
    const args = ran("ai_ask")[0][1];
    expect(args.openKey).toBe("class:MATH 101");
    expect(args.message).toBe("Summarize this note");
  });

  it("tells the core the phone's time zone, so eMabini deadlines fall on the right day", async () => {
    backend.ai_ask = () => reply("ok");
    await ask("ano ang due ko");
    expect(ran("ai_ask")[0][1].utcOffset).toBe(-new Date().getTimezoneOffset());
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

describe("waking on a slow phone", () => {
  beforeEach(() => {
    vi.useFakeTimers();
    assis.models = [chat({ loaded: false }), embed()];
    disk = [chat({ loaded: false }), embed()];
  });
  afterEach(() => {
    vi.useRealTimers();
    vi.unstubAllGlobals();
  });

  it("says the phone is slow after a while, then clears it", async () => {
    const d = deferred<unknown>();
    backend.ai_load = () => d.promise;
    const p = wake();
    await vi.advanceTimersByTimeAsync(WAKE_SLOW_MS + 1);
    expect([assis.busy, assis.slow]).toEqual(["waking", true]);
    d.resolve(undefined);
    expect(await p).toBe(true);
    expect([assis.busy, assis.slow]).toEqual(["", false]);
  });

  it("stops waiting with an explanation, in the student's language, and a later wake joins the same load", async () => {
    const d = deferred<unknown>();
    backend.ai_load = () => d.promise;
    const p = wake(true);
    await vi.advanceTimersByTimeAsync(WAKE_GIVE_UP_MS + 1);
    expect(await p).toBe(false);
    expect(assis.error).toBe("Matagal akong magising. Baka kulang ang memory ng phone. Isara ang ibang apps at subukan ulit.");
    expect([assis.busy, assis.slow]).toEqual(["", false]);
    const again = wake();
    expect(ran("ai_load")).toHaveLength(1); // no second ai_load: the core would answer "busy"
    disk[0].loaded = true;
    d.resolve(undefined);
    expect(await again).toBe(true);
    expect(ran("ai_load")).toHaveLength(1);
  });

  it("asks the core in the language of the question", async () => {
    backend.ai_load = () => undefined;
    backend.ai_ask = () => reply("ok");
    const p = ask("Ano ang due ko?");
    await vi.advanceTimersByTimeAsync(1);
    await p;
    expect(ran("ai_load")[0][1]).toEqual({ id: "chat", fil: true });
  });

  it("holds the sleep that arrives while the model loads and runs it once the app is still hidden", async () => {
    const d = deferred<unknown>();
    backend.ai_load = () => d.promise;
    backend.ai_unload = () => undefined;
    const p = wake();
    await sleep();
    expect(ran("ai_unload")).toHaveLength(0);
    vi.stubGlobal("document", { hidden: true });
    d.resolve(undefined);
    await p;
    await vi.advanceTimersByTimeAsync(1);
    expect(ran("ai_unload")).toHaveLength(1);
  });

  it("does not index while a model is loading", async () => {
    assis.busy = "waking";
    indexNotes();
    expect(ran("ai_index")).toHaveLength(0);
  });

  it("wakes the chat model before it indexes when the sheet opens", async () => {
    backend.ai_history = () => [];
    backend.ai_load = () => void (disk[0].loaded = true);
    await open();
    expect(calls.map(([c]) => c).filter((c) => c === "ai_load" || c === "ai_index")).toEqual(["ai_load", "ai_index"]);
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
  const fake = (a: any) => {
    let before = 0;
    for (const id of a.ids) {
      const m = disk.find((x) => x.id === id)!;
      a.onProgress.onmessage({ done: before + m.bytes, total: 1500, file: a.ids.indexOf(id), waiting: null });
      before += m.bytes;
      m.installed = true;
    }
  };
  beforeEach(() => {
    disk = [chat({ installed: false, loaded: false, bytes: 1000 }), embed({ installed: false, bytes: 500 })];
    assis.models = structuredClone(disk);
    backend.ai_space = () => ({ need: 2000, free: 10_000 });
    backend.ai_download = fake;
    const store = new Map<string, string>();
    vi.stubGlobal("localStorage", { getItem: (k: string) => store.get(k) ?? null, setItem: (k: string, v: string) => void store.set(k, v), removeItem: (k: string) => void store.delete(k) });
  });
  afterEach(() => vi.unstubAllGlobals());

  it("asks Rust for the whole install in one call, chat model first", async () => {
    await install();
    expect(ran("ai_download").map(([, a]) => a.ids)).toEqual([["chat", "embed"]]);
    expect(assis.models.every((m) => m.installed)).toBe(true);
    expect(assis.busy).toBe("");
    expect(assis.error).toBe("");
    expect(assis.install.ready).toBe(true);
  });

  it("opens the install view with every file and one bar over all of them", async () => {
    const seen: number[] = [];
    backend.ai_download = (a) => {
      expect(assis.install.open).toBe(true);
      expect(assis.install.files.map((m) => m.id)).toEqual(["chat", "embed"]);
      expect(assis.total).toBe(1500);
      a.onProgress.onmessage({ done: 400, total: 1500, file: 0, waiting: null });
      seen.push(assis.done);
      a.onProgress.onmessage({ done: 1400, total: 1500, file: 1, waiting: null });
      seen.push(assis.done);
      expect(assis.install.file).toBe(1);
      fake(a);
    };
    const p = install();
    expect(assis.busy).toBe("downloading");
    await p;
    expect(seen).toEqual([400, 1400]);
  });

  it("says when it waits out a dropped connection, without moving the bar back", async () => {
    backend.ai_download = (a) => {
      a.onProgress.onmessage({ done: 700, total: 1500, file: 0, waiting: null });
      a.onProgress.onmessage({ done: 0, total: 1500, file: 0, waiting: "No connection. It carries on when you're back online." });
      expect(assis.install.waiting).toMatch(/No connection/);
      expect(assis.done).toBe(700);
      fake(a);
    };
    await install();
  });

  it("does not start when storage is short, and says how much to free (C1)", async () => {
    backend.ai_space = () => ({ need: 1_900_000_000, free: 1_200_000_000 });
    await install();
    expect(ran("ai_download")).toHaveLength(0);
    expect(assis.error).toBe("IntAssis needs 1.90 GB free. This phone has 1.20 GB. Free up 700 MB and try again.");
  });

  it("downloads nothing when the phone lacks the RAM for any offered model (C2)", async () => {
    assis.models = [chat({ installed: false, fits: "refuse" }), embed({ installed: false })];
    await install();
    expect(ran("ai_download")).toHaveLength(0);
    expect(assis.error).toMatch(/enough memory \(RAM\)/);
    expect(noRoom()).toBe(true);
  });

  it("takes the other offered model when the default doesn't fit (C2)", async () => {
    assis.models = [chat({ installed: false, fits: "refuse" }), chat({ id: "small", default: false, installed: false }), embed({ installed: false })];
    expect(noRoom()).toBe(false);
    expect(chatModel().id).toBe("small");
    await install();
    expect(ran("ai_download").map(([, a]) => a.ids)).toEqual([["small", "embed"]]);
  });

  it("goes ahead when the phone doesn't say how much is free", async () => {
    backend.ai_space = () => ({ need: 1_900_000_000, free: null });
    await install();
    expect(ran("ai_download")).toHaveLength(1);
  });

  it("only fetches what is missing", async () => {
    disk[0].installed = true;
    assis.models = structuredClone(disk);
    await install();
    expect(ran("ai_download").map(([, a]) => a.ids)).toEqual([["embed"]]);
  });

  it("does nothing when both are installed, or something else is running", async () => {
    assis.models = [chat(), embed()];
    await install();
    assis.models = structuredClone(disk);
    assis.busy = "thinking";
    await install();
    expect(ran("ai_download")).toHaveLength(0);
  });

  it("surfaces a failure Rust couldn't wait out, and leaves the restart to the student", async () => {
    backend.ai_download = () => Promise.reject("Storage filled up. Free up some space, then tap Resume.");
    await install();
    expect(assis.error).toMatch(/Storage filled up/);
    expect(assis.busy).toBe("");
    expect(localStorage.getItem("intassisInstalling")).toBeNull();
  });

  it("treats Pause as quiet, closes the view, and doesn't carry on by itself", async () => {
    backend.ai_download = () => Promise.reject("paused");
    await install();
    expect(assis.error).toBe("");
    expect(assis.install.open).toBe(false);
    expect(localStorage.getItem("intassisInstalling")).toBeNull();
  });

  it("keeps the mark while it runs, so a cut-off install carries on at the next launch", async () => {
    const d = deferred<void>();
    backend.ai_download = () => d.promise;
    const p = install();
    await settle();
    expect(localStorage.getItem("intassisInstalling")).toBe("chat");
    d.resolve();
    await p;
    expect(localStorage.getItem("intassisInstalling")).toBeNull();
  });
});

describe("choosing the chat model (C11, C13)", () => {
  beforeEach(() => {
    backend.ai_space = () => ({ need: 0, free: null });
    backend.ai_delete = (a) => void (disk.find((m) => m.id === a.id)!.installed = false);
    backend.ai_download = (a) => {
      for (const id of a.ids) disk.find((m) => m.id === id)!.installed = true;
    };
  });

  it("offers the two current models, never a legacy one", () => {
    assis.models = [chat({ installed: false }), qwen3({ installed: false }), gemma(), embed()];
    expect(choices().map((m) => m.id)).toEqual(["chat", "qwen3"]);
  });

  it("keeps a chosen Qwen3 1.7B without asking to update", () => {
    assis.models = [chat({ installed: false }), qwen3(), embed()];
    expect(chatModel()?.id).toBe("qwen3");
    expect(updatable()).toBe(false);
  });

  it("switches: brings the other model, then lets the old one go", async () => {
    disk = [chat(), qwen3({ installed: false }), embed()];
    assis.models = structuredClone(disk);
    await install("qwen3");
    expect(ran("ai_download").map(([, a]) => a.ids)).toEqual([["qwen3"]]);
    expect(ran("ai_delete").map(([, a]) => a.id)).toEqual(["chat"]);
    expect(chatModel()?.id).toBe("qwen3");
  });

  it("does nothing for a model that is already there", async () => {
    disk = [chat(), qwen3(), embed()];
    assis.models = structuredClone(disk);
    await install("qwen3");
    expect(ran("ai_download")).toHaveLength(0);
    expect(ran("ai_delete")).toHaveLength(0);
  });
});

describe("install lines", () => {
  it("fits, or names what to free", () => {
    expect(spaceLine(1000, 5000)).toBe("");
    expect(spaceLine(1000, null)).toBe("");
    expect(spaceLine(2_000_000_000, 500_000_000)).toBe("IntAssis needs 2.00 GB free. This phone has 500 MB. Free up 1.50 GB and try again.");
  });

  it("speed over the window, and a readable time left", () => {
    expect(speedOf([{ t: 0, done: 0 }, { t: 2000, done: 4_000_000 }])).toBe(2_000_000);
    expect(speedOf([{ t: 0, done: 0 }])).toBe(0);
    expect(etaLine(1_000_000, 0)).toBe("");
    expect(etaLine(30_000_000, 1_000_000)).toBe("less than a minute left");
    expect(etaLine(600_000_000, 2_000_000)).toBe("about 5 min left");
    expect(etaLine(8_000_000_000, 1_000_000)).toBe("about 2 h 13 min left");
  });
});

// A phone that has the old default (Gemma) when the default becomes another model (Qwen, here "chat").
describe("updating from the old chat model", () => {
  beforeEach(() => {
    disk = [chat({ installed: false, loaded: false, bytes: 1100 }), gemma({ loaded: true }), embed()];
    assis.models = structuredClone(disk);
    backend.ai_delete = (a) => void (disk.find((m) => m.id === a.id)!.installed = false);
    backend.ai_space = () => ({ need: 0, free: null });
    backend.ai_download = (a) => {
      for (const id of a.ids) disk.find((m) => m.id === id)!.installed = true;
    };
  });

  it("keeps Gemma as the answering model while the default is not installed, and wakes that one", async () => {
    expect(chatModel()?.id).toBe("gemma");
    expect(updatable()).toBe(true);
    disk[1].loaded = false;
    assis.models = structuredClone(disk);
    backend.ai_models = () => structuredClone(disk);
    backend.ai_load = (a) => void (disk.find((m) => m.id === a.id)!.loaded = true);
    expect(await wake()).toBe(true);
    expect(ran("ai_load").map(([, a]) => a.id)).toEqual(["gemma"]);
  });

  it("answers with the default once it is installed, and with the only model when it is another", async () => {
    assis.models = [chat(), gemma(), embed()];
    expect(chatModel()?.id).toBe("chat");
    expect(updatable()).toBe(false);
    assis.models = [chat({ installed: false }), gemma({ installed: false }), embed()];
    expect(chatModel()?.id).toBe("chat"); // nothing installed: the default, so Add has a target
    expect(updatable()).toBe(false);
  });

  it("sizes a fresh install as the default chat model plus the search model", () => {
    assis.models = [chat({ installed: false, bytes: 1_107_409_472 }), gemma({ installed: false, bytes: 806_058_272 }), embed({ installed: false, bytes: 309_855_456 })];
    expect(mb((chatModel()?.bytes ?? 0) + (embedModel()?.bytes ?? 0))).toBe("1.42 GB"); // what FirstRun and the Add button show
  });

  it("downloads the new model and leaves Gemma alone until it has finished", async () => {
    let seenDuring: string[] = [];
    backend.ai_download = (a) => {
      seenDuring = [...seenDuring, ...ran("ai_delete").map(([, x]) => x.id)];
      for (const id of a.ids) disk.find((m) => m.id === id)!.installed = true;
    };
    await install();
    expect(ran("ai_download").map(([, a]) => a.ids)).toEqual([["chat"]]); // the embedder was already there
    expect(seenDuring).toEqual([]);
    expect(ran("ai_delete").map(([, a]) => a.id)).toEqual(["gemma"]);
    expect(chatModel()?.id).toBe("chat");
    expect(assis.models.filter((m) => m.installed).map((m) => m.id)).toEqual(["chat", "embed"]);
  });

  it("keeps the chat history and the search model through the update", async () => {
    assis.chat = [{ from: "me", text: "hi" }, { from: "lar", text: "hello" }];
    await install();
    expect(ran("ai_clear_history")).toHaveLength(0);
    expect(ran("ai_delete").map(([, a]) => a.id)).not.toContain("embed");
    expect(assis.chat).toHaveLength(2);
  });

  it("does not remove Gemma when the download is paused or fails", async () => {
    backend.ai_download = () => Promise.reject("paused");
    await install();
    backend.ai_download = () => Promise.reject("No connection. Check Wi-Fi and try again.");
    await install();
    expect(ran("ai_delete")).toHaveLength(0);
    expect(assis.models.find((m) => m.id === "gemma")?.installed).toBe(true);
    expect(chatModel()?.id).toBe("gemma");
  });

  it("also fetches the search model when it is missing, in the same update", async () => {
    disk[2].installed = false;
    assis.models = structuredClone(disk);
    await install();
    expect(ran("ai_download").map(([, a]) => a.ids)).toEqual([["chat", "embed"]]);
    expect(ran("ai_delete").map(([, a]) => a.id)).toEqual(["gemma"]);
  });

  it("adds only the search model on its own, without the update", async () => {
    disk[2].installed = false;
    assis.models = structuredClone(disk);
    await addSearch();
    expect(ran("ai_download").map(([, a]) => a.ids)).toEqual([["embed"]]);
    expect(ran("ai_delete")).toHaveLength(0);
  });

  it("leaves Gemma installed if it can not be deleted, and still ends on the new model", async () => {
    backend.ai_delete = () => Promise.reject("IntAssis is busy");
    await install();
    expect(assis.busy).toBe("");
    expect(assis.error).toBe("");
    expect(chatModel()?.id).toBe("chat"); // the default answers once installed, whatever else is on the phone
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

  it("asks the search model to delete even when only the old one is on the phone", async () => {
    // A phone updated from nomic: the new search model was never added, but the old file is still there.
    disk = [chat(), embed({ installed: false })];
    assis.models = structuredClone(disk);
    backend.ai_delete = () => undefined;
    await remove();
    expect(ran("ai_delete").map(([, a]) => a.id)).toEqual(["chat", "embed"]);
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
    app.notes = [{ key: "class:COMP 20073", text: "root is min", title: null, updated: 1, subject: null, pinned: false, preview: "" }];
    backend.ai_why = () => ({ why: "w", tip: "t" });
    expect(await explain("Root?", "Top", "bottom", "COMP 20073")).toEqual({ why: "w", tip: "t" });
    expect(ran("ai_why")[0][1]).toEqual({ front: "Root?", back: "Top", typed: "bottom", note: "root is min" });
    await explain("Root?", "Top", "bottom", null);
    expect(ran("ai_why")[1][1].note).toBeNull();
  });
});

describe("tidying a scan (spec 041 C25)", () => {
  it("asks the model only when IntAssis is installed, and says nothing when it is not", async () => {
    backend.clean_scan_ai = () => "Tidy text.";
    assis.models = [chat({ installed: false })];
    expect(await tidyScan("Tidy  text.")).toBeNull();
    expect(ran("clean_scan_ai")).toHaveLength(0);
    assis.models = [chat()];
    expect(await tidyScan("Tidy  text.")).toBe("Tidy text.");
    expect(ran("clean_scan_ai")[0][1]).toEqual({ text: "Tidy  text." });
    expect(assis.busy).toBe("");
  });

  it("gives null for no change, a failure, a failed wake, or a busy model, and never throws", async () => {
    backend.clean_scan_ai = () => "Same.";
    expect(await tidyScan("Same.")).toBeNull();
    backend.clean_scan_ai = () => Promise.reject("IntAssis is busy");
    expect(await tidyScan("x")).toBeNull();
    expect(assis.busy).toBe("");
    assis.models = [chat({ loaded: false })];
    backend.ai_load = () => Promise.reject("no memory");
    expect(await tidyScan("x")).toBeNull();
    expect(assis.error).toBe("");
    assis.models = [chat()];
    assis.busy = "thinking";
    expect(await tidyScan("x")).toBeNull();
  });
});

describe("applying a proposal", () => {
  const pending = (proposal: any) => (assis.chat = [{ from: "lar", text: "Sure.", proposal, state: "pending" }]);

  it("adds to the class note without overwriting it", async () => {
    app.notes = [{ key: "class:MATH 101", text: "Quiz Friday", title: null, updated: 1, subject: null, pinned: false, preview: "" }];
    backend.set_note = () => undefined;
    backend.notes = () => [];
    pending({ kind: "add_note", subject: "MATH 101", text: "Bring calculator" });
    await apply(0);
    expect(ran("set_note")[0][1]).toEqual({ key: "class:MATH 101", text: "Quiz Friday\n\nBring calculator", title: null });
    expect(assis.chat[0].state).toBe("done");
  });

  it("C5: saves a note from the chat as a new note, with its title and subject, as the student left it", async () => {
    backend.set_note = () => undefined;
    backend.set_note_subject = () => undefined;
    backend.notes = () => [];
    pending({ kind: "save_note", title: "Heaps", subject: "COMP 20073", text: "- A tree", partial: false });
    (assis.chat[0].proposal as any).text = "- A tree\n- Insert is O(log n)"; // edited in the card
    await apply(0);
    const [, saved] = ran("set_note")[0];
    expect(saved).toMatchObject({ text: "- A tree\n- Insert is O(log n)", title: "Heaps" });
    expect(saved.key).toMatch(/^note:/);
    expect(ran("set_note_subject")[0][1]).toEqual({ key: saved.key, subject: "COMP 20073" });
    expect(assis.chat[0]).toMatchObject({ state: "done", text: "Saved to your notes." });
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
    backend.ai_topic_cards = () => ({ cards: [{ front: "a", back: "b" }, { front: "c", back: "d" }], stopped: null });
    backend.save_deck = () => undefined;
    pending({ kind: "make_cards", topic: "Trees", count: 8 });
    await apply(0);
    expect(ran("save_deck")).toHaveLength(0);
    expect(assis.chat[0].cards).toEqual([{ front: "a", back: "b" }, { front: "c", back: "d" }]);
    expect(assis.chat[0].state).toBe("pending");
    expect(assis.busy).toBe("");
  });

  it("saves the deck with the student's edits and removals on confirm", async () => {
    backend.ai_topic_cards = () => ({ cards: [{ front: "a", back: "b" }, { front: "c", back: "d" }, { front: "e", back: "f" }], stopped: null });
    backend.save_deck = () => undefined;
    pending({ kind: "make_cards", topic: "Trees", count: 8 });
    await apply(0);
    assis.chat[0].cards![0].back = "edited";
    assis.chat[0].cards!.splice(1, 1);
    await confirmCards(0);
    const deck = ran("save_deck")[0][1].deck;
    expect(deck.name).toBe("Trees");
    expect(deck.cards.map((c: any) => [c.front, c.back])).toEqual([["a", "edited"], ["e", "f"]]);
    expect(assis.chat[0].text).toBe("Added 2 cards to Trees.");
    expect(assis.chat[0]).toMatchObject({ state: "done", cards: undefined });
  });

  it("says 1 card, not 1 cards", async () => {
    backend.ai_topic_cards = () => ({ cards: [{ front: "a", back: "b" }], stopped: null });
    backend.save_deck = () => undefined;
    pending({ kind: "make_cards", topic: "Trees", count: 8 });
    await apply(0);
    await confirmCards(0);
    expect(assis.chat[0].text).toBe("Made 1 card.");
  });

  it("asks the generator for the count the student asked for", async () => {
    backend.ai_topic_cards = () => ({ cards: [{ front: "a", back: "b" }], stopped: null });
    pending({ kind: "make_cards", topic: "Trees", count: 5 });
    await apply(0);
    expect(ran("ai_topic_cards")[0][1]).toMatchObject({ topic: "Trees", want: 5 });
  });

  it("says plainly when fewer cards than asked could be made, and drops the stale leading sentence", async () => {
    backend.ai_topic_cards = () => ({ cards: [{ front: "a", back: "b" }, { front: "c", back: "d" }, { front: "e", back: "f" }, { front: "g", back: "h" }], stopped: "no new cards", known: true });
    backend.save_deck = () => undefined;
    pending({ kind: "make_cards", topic: "Trees", count: 8 });
    assis.chat[0].text = "I'll make 8 flashcards on Trees. Confirm to start.";
    await apply(0);
    expect(assis.chat[0].text).toBe("I could make 4 of 8 on Trees. They're from what I know, not your notes, so check them before you save.");
    await confirmCards(0);
    expect(assis.chat[0].text).toBe("Added 4 cards to Trees.");
  });

  it("reads only the result once the cards are shown, when all were made", async () => {
    backend.ai_topic_cards = () => ({ cards: [{ front: "a", back: "b" }, { front: "c", back: "d" }], stopped: null });
    pending({ kind: "make_cards", topic: "Trees", count: 2 });
    assis.chat[0].text = "I'll make 2 flashcards on Trees. Confirm to start.";
    await apply(0);
    expect(assis.chat[0].text).toBe("Here are 2 cards on Trees.");
  });

  it("discarding the preview saves nothing and offers the proposal again", async () => {
    backend.ai_topic_cards = () => ({ cards: [{ front: "a", back: "b" }], stopped: null });
    pending({ kind: "make_cards", topic: "Trees", count: 8 });
    await apply(0);
    discardCards(0);
    expect(ran("save_deck")).toHaveLength(0);
    expect(assis.chat[0]).toMatchObject({ state: "pending", cards: undefined });
  });

  it("confirms nothing when every card was removed", async () => {
    backend.ai_topic_cards = () => ({ cards: [{ front: "a", back: "b" }], stopped: null });
    pending({ kind: "make_cards", topic: "Trees", count: 8 });
    await apply(0);
    assis.chat[0].cards!.length = 0;
    await confirmCards(0);
    expect(ran("save_deck")).toHaveLength(0);
  });

  it("explains when no cards could be made", async () => {
    backend.ai_topic_cards = () => ({ cards: [], stopped: null });
    pending({ kind: "make_cards", topic: "Trees", count: 8 });
    await apply(0);
    expect(assis.chat[0].problem).toMatch(/couldn't make good cards on Trees/);
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
    Object.assign(app, { reminderLead: 0, warmUp: false, afterClass: false, brief: false });
    await scheduleReminders();
    expect(queue).toHaveLength(1);
  });

  it("c16_brief_and_after_class_still_schedule_with_class_deadline_and_study_off", async () => {
    Object.assign(app, { reminderLead: 0, warmUp: false, afterClass: true, brief: true });
    await scheduleReminders();
    expect(queue.map((q) => q.id)).toContain(7);
  });
});

describe("a reminder needs the phone's permission to ring", () => {
  const remind = (text = "Bring ID", before = "remind me tomorrow", said = "Ready: reminder. Confirm to save.") => {
    assis.chat = [{ from: "me", text: before }, { from: "lar", text: said, proposal: { kind: "set_reminder", date: "2099-01-06", text }, state: "pending" }];
    return apply(1);
  };
  beforeEach(() => {
    const store = new Map<string, string>();
    vi.stubGlobal("localStorage", { getItem: (k: string) => store.get(k) ?? null, setItem: (k: string, v: string) => void store.set(k, v) });
    backend["plugin:notification|notify"] = () => undefined;
    vi.mocked(isPermissionGranted).mockReset();
    vi.mocked(requestPermission).mockReset();
    app.notifications = null;
  });

  it("schedules without asking when notifications are already allowed", async () => {
    vi.mocked(isPermissionGranted).mockResolvedValue(true);
    await remind();
    expect(requestPermission).not.toHaveBeenCalled();
    expect(ran("plugin:notification|notify")).toHaveLength(1);
    expect(assis.chat[1]).toMatchObject({ state: "done" });
    expect(assis.chat[1].notice).toBeUndefined();
  });

  it("asks first when they are not, and schedules once they say yes", async () => {
    vi.mocked(isPermissionGranted).mockResolvedValue(false);
    vi.mocked(requestPermission).mockResolvedValue("granted");
    await remind();
    expect(requestPermission).toHaveBeenCalledTimes(1);
    expect(ran("plugin:notification|notify")).toHaveLength(1);
    expect(assis.chat[1].notice).toBeUndefined();
    expect(app.notifications).toBe(true);
  });

  it("says plainly that it will not ring when they say no, in English", async () => {
    vi.mocked(isPermissionGranted).mockResolvedValue(false);
    vi.mocked(requestPermission).mockResolvedValue("denied");
    await remind();
    expect(assis.chat[1].state).toBe("done");
    expect(assis.chat[1].notice).toBe("I saved it, but notifications are off. Turn them on in Settings so it can ring.");
    expect(app.notifications).toBe(false);
  });

  it("says it in Filipino when the student wrote Filipino", async () => {
    vi.mocked(isPermissionGranted).mockResolvedValue(false);
    vi.mocked(requestPermission).mockResolvedValue("denied");
    await remind("Dalhin ang ID", "i-remind mo ako bukas", "Handa na ang paalala: Dalhin ang ID. I-confirm para i-save.");
    expect(assis.chat[1].notice).toBe("Na-save ko na, pero naka-off ang notifications. I-on mo sa Settings para tumunog ito.");
  });

  it("still saves the reminder when the phone refuses to queue it", async () => {
    vi.mocked(isPermissionGranted).mockResolvedValue(false);
    vi.mocked(requestPermission).mockResolvedValue("denied");
    backend["plugin:notification|notify"] = () => Promise.reject("not authorized");
    await remind();
    expect(assis.chat[1]).toMatchObject({ state: "done", problem: "" });
    expect(assis.chat[1].notice).toContain("notifications are off");
  });
});

describe("saying honestly what a download is", () => {
  it("itemises the chat model and the note search from the sizes the phone reports", () => {
    expect(downloadSizes([chat({ bytes: 1_110_000_000 }), embed({ bytes: 310_000_000 })])).toBe("Chat model 1.11 GB + note search 310 MB, use Wi-Fi");
  });

  it("names only what is still to come", () => {
    expect(downloadSizes([embed({ bytes: 310_000_000 })])).toBe("Note search 310 MB, use Wi-Fi");
    expect(downloadSizes([chat({ bytes: 810_000_000 })])).toBe("Chat model 810 MB, use Wi-Fi");
    expect(downloadSizes([])).toBe("");
  });
});

describe("history (#180)", () => {
  it("a saved answer comes back with the chips it had; my own lines never carry any", async () => {
    const { fromTurn } = await import("./assis.svelte");
    const trees = [{ key: "note:trees", title: "Trees" }];
    expect(fromTurn({ role: "lar", text: "A heap is a tree.", sources: trees })).toEqual({ from: "lar", text: "A heap is a tree.", sources: trees });
    expect(fromTurn({ role: "lar", text: "Hi.", sources: [] })).toEqual({ from: "lar", text: "Hi.", sources: undefined });
    expect(fromTurn({ role: "me", text: "What is a heap?", sources: trees })).toEqual({ from: "me", text: "What is a heap?" });
  });
});

describe("spec 062 C25: Keep going", () => {
  it("offers it under a cut answer, continues the same bubble, and stops offering after two", async () => {
    backend.ai_ask = () => reply("Recursion is a function", { more: true });
    await ask("explain recursion");
    expect(assis.chat[1]).toMatchObject({ text: "Recursion is a function", cut: true, more: 0 });
    let sent: any;
    backend.ai_more = (a) => ((sent = a), a.onText.onmessage("calling itself."), { text: "calling itself.", more: true });
    await keepGoing(1);
    expect(sent).toMatchObject({ message: "explain recursion", soFar: "Recursion is a function" });
    expect(assis.chat[1]).toMatchObject({ text: "Recursion is a function calling itself.", cut: true, more: 1 });
    await keepGoing(1);
    expect(assis.chat[1].more).toBe(2);
    const before = calls.length;
    await keepGoing(1);
    expect(calls.length).toBe(before, "no third Keep going");
  });

  it("is not offered under an answer that finished", async () => {
    backend.ai_ask = () => reply("A stack is last in, first out.");
    await ask("what is a stack?");
    expect(assis.chat[1].cut).toBeUndefined();
  });
});
