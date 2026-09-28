// The app's one piece of shared state: the snapshot from the core, today's
// reading of it, and sync status. Screens read `app`; only this file writes.
import { invoke } from "@tauri-apps/api/core";
import { Schedule, cancel, isPermissionGranted, pending, requestPermission } from "@tauri-apps/plugin-notification";
import { api, moment, type Snapshot, type Today } from "./api";
import { applyRoom } from "./rooms";

export type Tab = "today" | "schedule" | "grades" | "you";
export type SyncState = "idle" | "syncing" | "ok" | "failed";

export const app = $state({
  snapshot: null as Snapshot | null,
  today: null as Today | null,
  tab: "today" as Tab,
  sync: "idle" as SyncState,
  syncError: null as string | null,
  /** Bumps on every successful sync, so moments can react to it. */
  syncCount: 0,
  room: read("room") || "night",
  /** Minutes before class; 0 turns reminders off. */
  reminderLead: Number(read("reminderLead") ?? 10),
  /** What is queued with the platform right now. */
  queued: { count: 0, next: null as null | { title: string; at: Date }, error: "" },
});

function read(key: string): string | null {
  try {
    return localStorage.getItem(key);
  } catch {
    return null;
  }
}

function write(key: string, value: string) {
  try {
    localStorage.setItem(key, value);
  } catch {
    // Storage off: the choice lasts this session only.
  }
}

/** Replace every pending class reminder with the next week's. iOS keeps at
 *  most 64 pending, so a week is the horizon; each launch and sync renews it. */
export async function scheduleReminders() {
  try {
    // Not cancelAll(): on iOS it sends no id list and the plugin refuses to decode it.
    const queued = await pending();
    if (queued.length) await cancel(queued.map((n) => n.id));
    app.queued = { count: 0, next: null, error: "" };
    if (!app.snapshot || app.reminderLead <= 0) return;
    let allowed = await isPermissionGranted();
    if (!allowed) allowed = (await requestPermission()) === "granted";
    if (!allowed) return;
    const list = (await api.reminders(moment(), app.reminderLead, 7)).slice(0, 60);
    const when = (r: { date: string; minute: number }) => {
      const [y, m, d] = r.date.split("-").map(Number);
      return new Date(y, m - 1, d, Math.floor(r.minute / 60), r.minute % 60);
    };
    // The iOS plugin reads the ISO string's trailing Z as literal text and
    // takes the digits as local time, so hand it local wall-clock digits.
    const asLocalDigits = (d: Date) => new Date(d.getTime() - d.getTimezoneOffset() * 60_000);
    let ok = 0;
    let lastError = "";
    for (const r of list) {
      try {
        // Awaited notify, not sendNotification(): that one drops its promise, so failures go unseen.
        await invoke("plugin:notification|notify", { options: { id: r.id, title: r.title, body: r.body, schedule: Schedule.at(asLocalDigits(when(r))) } });
        ok++;
      } catch (e) {
        lastError = typeof e === "string" ? e : JSON.stringify(e);
      }
    }
    app.queued = { count: ok, next: list[0] ? { title: list[0].title, at: when(list[0]) } : null, error: ok < list.length ? lastError : "" };
  } catch (e) {
    // Reminders are best effort; the app works without them. Say why on You.
    app.queued = { count: 0, next: null, error: typeof e === "string" ? e : JSON.stringify(e) };
  }
}

export function setReminderLead(minutes: number) {
  app.reminderLead = minutes;
  write("reminderLead", String(minutes));
  scheduleReminders();
}

export async function refreshToday() {
  if (!app.snapshot) return;
  try {
    app.today = await api.today(moment(), app.sync === "failed" ? app.syncError : null);
  } catch {
    // The glance keeps its last line.
  }
}

export async function adopt(snap: Snapshot) {
  app.snapshot = snap;
  await refreshToday();
  scheduleReminders();
}

export async function syncNow() {
  if (app.sync === "syncing") return;
  app.sync = "syncing";
  try {
    await adopt(await api.sync());
    app.sync = "ok";
    app.syncError = null;
    app.syncCount++;
  } catch (e) {
    app.sync = "failed";
    app.syncError = String(e).includes("reach") ? "Couldn't reach SIS" : String(e);
    await refreshToday();
  }
}

export function setRoom(room: string) {
  app.room = room;
  applyRoom(room);
  write("room", room);
}

let ticker: ReturnType<typeof setInterval> | undefined;

/** Re-read today on the minute boundary, so countdowns stay honest. */
export function startClock() {
  clearInterval(ticker);
  const kick = () => {
    refreshToday();
    ticker = setInterval(refreshToday, 60_000);
  };
  setTimeout(kick, (60 - new Date().getSeconds()) * 1000);
}
