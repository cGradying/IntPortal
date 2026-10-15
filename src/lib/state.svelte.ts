// The app's one piece of shared state: the snapshot from the core, today's
// reading of it, and sync status. Screens read `app`; only this file writes.
import { invoke } from "@tauri-apps/api/core";
import { Schedule, cancel, isPermissionGranted, pending, requestPermission } from "@tauri-apps/plugin-notification";
import { api, isoDate, localMs, moment, type Busy, type MabiniData, type NoteItem, type Snapshot, type Today } from "./api";
import { busyFrom, keepClasses } from "./devcal";
import { applyRoom } from "./rooms";
import { buzz } from "./haptics";

export type Tab = "today" | "schedule" | "grades" | "study" | "you";
export type SyncState = "idle" | "syncing" | "ok" | "failed";

export const app = $state({
  snapshot: null as Snapshot | null,
  today: null as Today | null,
  tab: "today" as Tab,
  sync: "idle" as SyncState,
  syncError: null as string | null,
  /** Bumps on every successful sync, so moments can react to it. */
  syncCount: 0,
  /** Which portals have a saved login on this phone. */
  sisConnected: false,
  mabiniConnected: false,
  /** What the last eMabini sync kept; null while not connected. */
  mabini: null as MabiniData | null,
  mabiniSync: "idle" as SyncState,
  mabiniError: null as string | null,
  /** The eMabini page (courses, deadlines, grades) is open. */
  mabiniPage: false,
  room: read("room") || "system",
  /** Minutes before class; 0 turns reminders off. */
  reminderLead: Number(read("reminderLead") ?? 10),
  /** Minute of the day for the evening-before deadline heads-up; -1 is off. */
  deadlineAt: Number(read("deadlineAt") ?? 19 * 60),
  /** Minute of the day for the study nudge; -1 is off. */
  studyAt: Number(read("studyAt") ?? -1),
  notes: [] as NoteItem[],
  /** The subject page open, if any. */
  subject: null as null | { code: string; description: string },
  /** The deck open on the Study tab, if any. */
  deck: null as string | null,
  /** The note open in the editor, if any. */
  editing: null as null | { key: string; heading: string; title: string | null },
  /** What is queued with the platform right now. */
  queued: { count: 0, next: null as null | { title: string; at: Date }, error: "" },
  /** Notifications allowed by the phone; null until checked. */
  notifications: null as boolean | null,
  /** Count the student's own calendar events as busy time. */
  calendarEvents: read("calendarEvents") === "1",
  /** Keep the classes in the phone's IntPortal calendar. */
  calendarClasses: read("calendarClasses") === "1",
  /** Today's own events, when calendarEvents is on. */
  busy: [] as Busy[],
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

/** Replace every pending reminder with the next week's. iOS keeps at most
 *  64 pending, so a week is the horizon; each launch and sync renews it.
 *  Only `ask` (the first-run step, or the student's tap) shows the system
 *  permission prompt, so it never appears out of nowhere at launch. */
export async function scheduleReminders(ask = false) {
  try {
    // Not cancelAll(): on iOS it sends no id list and the plugin refuses to decode it.
    const queued = await pending();
    if (queued.length) await cancel(queued.map((n) => n.id));
    app.queued = { count: 0, next: null, error: "" };
    const on = (m: number) => (m >= 0 ? m : null);
    if (!app.snapshot || (app.reminderLead <= 0 && app.deadlineAt < 0 && app.studyAt < 0)) return;
    let allowed = await isPermissionGranted();
    if (!allowed && ask) allowed = (await requestPermission()) === "granted";
    app.notifications = allowed;
    if (!allowed) return;
    const prefs = { deadlines: on(app.deadlineAt), study: on(app.studyAt), utc_offset: -new Date().getTimezoneOffset() };
    const list = (await api.reminders(moment(), app.reminderLead, 7, prefs)).slice(0, 60);
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
  scheduleReminders(true);
}

export function setDeadlineAt(minute: number) {
  app.deadlineAt = minute;
  write("deadlineAt", String(minute));
  scheduleReminders(true);
}

export function setStudyAt(minute: number) {
  app.studyAt = minute;
  write("studyAt", String(minute));
  scheduleReminders(true);
}

/** Hands the next class to the home-screen widget and the Live Activity.
 *  Only iOS has the glance plugin; elsewhere the call fails quietly. */
function pushGlance() {
  const t = app.today;
  if (!t) return;
  const n = t.next;
  const next = n && {
    code: n.session.subject_code,
    title: n.session.description,
    start: localMs(n.date, n.session.start),
    end: localMs(n.date, n.session.end),
    online: t.agenda.items.some((i) => i.session.subject_code === n.session.subject_code && i.session.start === n.session.start && i.mark === "online"),
  };
  invoke("plugin:glance|update", { next, line: t.glance_line }).catch(() => {});
}


export async function refreshToday() {
  if (!app.snapshot) return;
  try {
    app.busy = app.calendarEvents ? await busyFrom(new Date(), 1).catch(() => []) : [];
    app.today = await api.today(moment(), app.sync === "failed" ? app.syncError : null, app.busy);
    pushGlance();
  } catch {
    // The glance keeps its last line.
  }
}

export async function refreshNotes() {
  try {
    app.notes = await api.notes();
  } catch {
    // The list keeps what it had.
  }
}

export function openSubject(code: string, description: string) {
  app.subject = { code, description };
}

/** Shows a deck on the Study tab. */
export function openDeck(id: string) {
  app.tab = "study";
  app.deck = id;
}

export function openNote(key: string, heading: string, title: string | null = null) {
  app.editing = { key, heading, title };
}

export async function adopt(snap: Snapshot) {
  app.snapshot = snap;
  refreshNotes();
  await refreshToday();
  scheduleReminders();
  refreshClassCalendar();
}

/** A plugin's rejection arrives as an object with a message, a command's as a string. */
const reason = (e: unknown) => (typeof e === "string" ? e : ((e as { message?: string })?.message ?? JSON.stringify(e)));

/** Rewrites the IntPortal calendar when the classes or marks changed, or
 *  on a new day, so it always reaches eight weeks ahead. */
export async function refreshClassCalendar(force = false): Promise<string | null> {
  if (!app.calendarClasses || !app.snapshot) return null;
  const stamp = JSON.stringify([isoDate(new Date()), app.snapshot.sessions, app.snapshot.marks]);
  if (!force && read("calendarStamp") === stamp) return null;
  try {
    await keepClasses();
    write("calendarStamp", stamp);
    return null;
  } catch (e) {
    return reason(e);
  }
}

/** Turns a calendar setting on or off; the answer is what went wrong, if anything. */
export async function setCalendar(which: "calendarEvents" | "calendarClasses", on: boolean): Promise<string | null> {
  app[which] = on;
  write(which, on ? "1" : "0");
  if (which === "calendarEvents") {
    await refreshToday();
    return null;
  }
  if (on) return refreshClassCalendar(true);
  write("calendarStamp", "");
  return keepClasses(true).then(
    () => null,
    (e) => reason(e),
  );
}

/** Reads which portals have a login and, for eMabini, what was kept last time. */
export async function refreshLogins() {
  const [sis, mabini] = await Promise.all([api.hasLogin().catch(() => false), api.hasMabiniLogin().catch(() => false)]);
  app.sisConnected = sis;
  app.mabiniConnected = mabini;
  app.mabini = mabini ? await api.mabiniData().catch(() => null) : null;
}

export async function mabiniSyncNow() {
  if (app.mabiniSync === "syncing") return;
  app.mabiniSync = "syncing";
  try {
    app.mabini = await api.mabiniSync();
    app.mabiniSync = "ok";
    app.mabiniError = null;
    buzz.done();
  } catch (e) {
    app.mabiniSync = "failed";
    app.mabiniError = String(e).includes("reach") ? "Couldn't reach eMabini" : String(e);
    buzz.fail();
  }
}

export async function syncNow() {
  if (app.mabiniConnected) mabiniSyncNow();
  if (!app.sisConnected || app.sync === "syncing") return;
  app.sync = "syncing";
  try {
    await adopt(await api.sync());
    app.sync = "ok";
    app.syncError = null;
    app.syncCount++;
    buzz.done();
  } catch (e) {
    app.sync = "failed";
    buzz.fail();
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
