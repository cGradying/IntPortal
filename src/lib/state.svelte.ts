// The app's one piece of shared state: the snapshot from the core, today's
// reading of it, and sync status. Screens read `app`; only this file writes.
import { invoke } from "@tauri-apps/api/core";
import { Schedule, cancel, isPermissionGranted, onAction, pending, requestPermission } from "@tauri-apps/plugin-notification";
import { api, isoDate, localMs, moment, type Busy, type MabiniData, type NoteItem, type Snapshot, type Today } from "./api";
import { busyFrom, keepClasses } from "./devcal";
import { applyRoom } from "./rooms";
import type { Theme } from "./theme";
import { decodeTheme, encodeTheme } from "./themeCode";
import { buzz } from "./haptics";
import { friendly } from "./errors";
import { larReminderIds } from "./assis/apply";
import { oneOf, parseCards, type Cards } from "./you";

export type Tab = "today" | "schedule" | "grades" | "study" | "you";
export type SyncState = "idle" | "syncing" | "ok" | "failed";

export const app = $state({
  snapshot: null as Snapshot | null,
  today: null as Today | null,
  /** Spec 047 C5: the tab the app opens on. */
  tab: oneOf(read("opensOn"), ["today", "schedule", "study"]) as Tab,
  opensOn: oneOf(read("opensOn"), ["today", "schedule", "study"]),
  /** C6: Today's card order and the ones hidden. */
  cards: parseCards(read("todayCards")),
  /** C7, C8: lists, the dive, done effects and the moving ground. */
  density: oneOf(read("density"), ["comfy", "compact"]),
  dive: oneOf(read("dive"), ["full", "short", "off"]),
  effects: oneOf(read("effects"), ["full", "calm", "off"]),
  ground: read("ground") !== "still",
  sync: "idle" as SyncState,
  syncError: null as string | null,
  /** Bumps on every successful sync, so moments can react to it. */
  syncCount: 0,
  /** Which portals have a saved login on this phone. */
  sisConnected: false,
  /** The portal turned the saved login down (spec 040 C5); only a new password clears it. */
  sisRejected: false,
  mabiniRejected: false,
  /** A You page to open when the tab shows (set by "Update password"). */
  openYou: "",
  mabiniConnected: false,
  /** What the last eMabini sync kept; null while not connected. */
  mabini: null as MabiniData | null,
  mabiniSync: "idle" as SyncState,
  mabiniError: null as string | null,
  /** The eMabini page (courses, deadlines, grades) is open. */
  mabiniPage: false,
  room: read("room") || "system",
  /** The student's own themes (spec 047 C14); a room id of `theme:<id>` wears one. */
  themes: loadThemes(),
  /** The theme maker is open. */
  themeMaker: false,
  /** The text style in You: IntPortal's own, or the original Classic. */
  textStyle: read("textStyle") === "classic" ? "classic" : "intportal",
  /** Minutes before class; 0 turns reminders off. */
  reminderLead: Number(read("reminderLead") ?? 10),
  /** Minute of the day for the evening-before deadline heads-up; -1 is off. */
  deadlineAt: Number(read("deadlineAt") ?? 19 * 60),
  /** Minute of the day for the study nudge; -1 is off. */
  studyAt: Number(read("studyAt") ?? -1),
  /** Spec 042 C16: extras that ride the daily budget; on unless turned off. */
  warmUp: read("warmUp") !== "off",
  afterClass: read("afterClass") !== "off",
  brief: read("brief") !== "off",
  notes: [] as NoteItem[],
  /** The subject page open, if any. */
  subject: null as null | { code: string; description: string; tab?: "grading" | "outline"; item?: string },
  /** The deck open on the Study tab, if any. */
  deck: null as string | null,
  /** The note open in the editor, if any. */
  /** `subject` files a new freeform note on its first save with text (046 C2). */
  /** `entry`: open on today's dated entry (046 C14a). */
  editing: null as null | { key: string; heading: string; title: string | null; subject?: string; entry?: boolean },
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
    const lar = larReminderIds(); // reminders LAR set for the student stay queued
    const stale = queued.filter((n) => !lar.has(n.id));
    if (stale.length) await cancel(stale.map((n) => n.id));
    app.queued = { count: 0, next: null, error: "" };
    const on = (m: number) => (m >= 0 ? m : null);
    if (!app.snapshot || (app.reminderLead <= 0 && app.deadlineAt < 0 && app.studyAt < 0)) return;
    let allowed = await isPermissionGranted();
    if (!allowed && ask) allowed = (await requestPermission()) === "granted";
    app.notifications = allowed;
    if (!allowed) return;
    const prefs = { deadlines: on(app.deadlineAt), study: on(app.studyAt), utc_offset: -new Date().getTimezoneOffset(), warm_up: app.warmUp, after_class: app.afterClass, brief: app.brief };
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
        await invoke("plugin:notification|notify", { options: { id: r.id, title: r.title, body: r.body, schedule: Schedule.at(asLocalDigits(when(r))), extra: { open: r.open } } });
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

/** Spec 042 C16: one switch per extra. */
export function setExtra(key: "warmUp" | "afterClass" | "brief", on: boolean) {
  app[key] = on;
  write(key, on ? "on" : "off");
  scheduleReminders(true);
}

/** Routes notification taps for the app's lifetime; desktop and tests have none. */
export function listenForTaps() {
  onAction((n) => openFromNotification(n.extra?.open as string | undefined)).catch(() => {});
}

/** Where a tapped notification goes (spec 042 C7, C9): a subject's cards, a class note, or Today. */
export async function openFromNotification(open: string | null | undefined) {
  const [what, ...rest] = (open ?? "").split(":");
  if (what === "study") {
    const code = rest[0];
    const deck = (await api.study(isoDate(new Date())).catch(() => null))?.decks.find((d) => d.subject === code && d.due > 0);
    if (deck) return openDeck(deck.id);
  }
  if (what === "subject" && rest[0]) {
    const desc = app.snapshot?.sessions.find((s) => s.subject_code === rest[0])?.description ?? "";
    return openSubject(rest[0], desc, "outline", rest[1]);
  }
  if (what === "note" && rest[0] === "class") {
    const code = rest.slice(1).join(":");
    const name = app.snapshot?.sessions.find((s) => s.subject_code === code)?.description ?? "";
    // After class: straight to that meeting's dated entry (046 C14a).
    return openNote(`class:${code}`, code, name || null, undefined, true);
  }
  app.tab = "today";
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

/** `tab` and `item` open a deadline on its outline (spec 040 C11). */
export function openSubject(code: string, description: string, tab?: "grading" | "outline", item?: string) {
  app.subject = { code, description, tab, item };
}

/** Shows a deck on the Study tab. */
export function openDeck(id: string) {
  app.tab = "study";
  app.deck = id;
}

export function openNote(key: string, heading: string, title: string | null = null, subject?: string, entry = false) {
  app.editing = { key, heading, title, subject, entry };
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
  // Deadlines live in the same calendar (spec 041 C21, C22): what feeds them is in the stamp too.
  const s = app.snapshot;
  const stamp = JSON.stringify([isoDate(new Date()), s.sessions, s.marks, s.syllabus, s.own_deadlines, s.done, app.mabini?.deadlines.map((d) => [d.id, d.due])]);
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
  app.sisRejected = sis && (await api.triesLeft().catch(() => null))?.rejected === true;
  app.mabiniRejected = mabini && (await api.mabiniTriesLeft().catch(() => null))?.rejected === true;
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
    refreshClassCalendar();
    scheduleReminders();
  } catch (e) {
    app.mabiniSync = "failed";
    app.mabiniError = friendly(e);
    app.mabiniRejected = (await api.mabiniTriesLeft().catch(() => null))?.rejected === true;
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
    app.syncError = friendly(e);
    app.sisRejected = (await api.triesLeft().catch(() => null))?.rejected === true;
    await refreshToday();
  }
}

export function setTextStyle(style: string) {
  app.textStyle = style === "classic" ? "classic" : "intportal";
  if (app.textStyle === "classic") document.documentElement.dataset.type = "classic";
  else delete document.documentElement.dataset.type;
  write("textStyle", app.textStyle);
}

export interface SavedTheme {
  id: string;
  theme: Theme;
}

/** Kept as share codes, so whatever is stored goes through the same strict check as a pasted one. */
function loadThemes(): SavedTheme[] {
  try {
    const list: unknown = JSON.parse(read("themes") ?? "[]");
    if (!Array.isArray(list)) return [];
    return list.flatMap((x) => {
      const theme = typeof x?.id === "string" && typeof x?.code === "string" ? decodeTheme(x.code) : null;
      return theme ? [{ id: x.id as string, theme }] : [];
    });
  } catch {
    return [];
  }
}

function writeThemes() {
  write("themes", JSON.stringify(app.themes.map((s) => ({ id: s.id, code: encodeTheme(s.theme) }))));
}

const themeOf = (room: string) => (room.startsWith("theme:") ? (app.themes.find((s) => `theme:${s.id}` === room)?.theme ?? null) : null);

/** The theme the app wears, when it is one of the student's. */
export const activeTheme = () => themeOf(app.room);

/** Saves a new theme, or replaces the one with `id`, and returns its id. A worn theme re-applies. */
export function saveTheme(theme: Theme, id?: string): string {
  const saved = { id: id ?? `t${Date.now().toString(36)}`, theme: { ...theme } };
  const i = app.themes.findIndex((s) => s.id === saved.id);
  app.themes = i < 0 ? [...app.themes, saved] : app.themes.map((s, j) => (j === i ? saved : s));
  writeThemes();
  if (app.room === `theme:${saved.id}`) setRoom(app.room);
  return saved.id;
}

/** Deleting the theme the app wears falls back to Night (C14). */
export function deleteTheme(id: string) {
  app.themes = app.themes.filter((s) => s.id !== id);
  writeThemes();
  if (app.room === `theme:${id}`) setRoom("night");
}

/** The saved themes as stored (`[{id, code}]`), for a backup. */
export function themesForBackup(): unknown[] {
  try {
    const list: unknown = JSON.parse(read("themes") ?? "[]");
    return Array.isArray(list) ? list : [];
  } catch {
    return [];
  }
}

/** Adds a backup's themes to the phone's: the file's win on the same id, the phone's others stay.
 *  Each goes through the same strict check as a pasted code. */
export function restoreThemes(list: unknown[]) {
  const incoming = list.flatMap((x) => {
    const t = x as { id?: unknown; code?: unknown };
    const theme = typeof t?.id === "string" && typeof t?.code === "string" ? decodeTheme(t.code) : null;
    return theme ? [{ id: t.id as string, theme }] : [];
  });
  const ids = new Set(incoming.map((s) => s.id));
  app.themes = [...app.themes.filter((s) => !ids.has(s.id)), ...incoming];
  writeThemes();
  if (app.room.startsWith("theme:") && !themeOf(app.room)) setRoom("night");
}

/** Erase everything takes the themes too. */
export function forgetThemes() {
  app.themes = [];
  writeThemes();
  if (app.room.startsWith("theme:")) setRoom("night");
}

export type Look = { opensOn: "today" | "schedule" | "study"; density: "comfy" | "compact"; dive: "full" | "short" | "off"; effects: "full" | "calm" | "off"; ground: boolean; cards: Cards };

/** Spec 047 C5–C8: one app-side choice. Lists, effects and the ground show
 *  as attributes on the page, which app.css, burst and Confetti read. */
export function setLook<K extends keyof Look>(key: K, value: Look[K]) {
  (app as Look)[key] = value;
  if (key === "cards") write("todayCards", JSON.stringify(value));
  else if (key === "ground") write("ground", value ? "on" : "still");
  else write(key, String(value));
  applyLook();
}

export function applyLook() {
  const d = document.documentElement.dataset;
  d.density = app.density;
  d.effects = app.effects;
  d.ground = app.ground ? "on" : "still";
}

export function setRoom(room: string) {
  const theme = themeOf(room);
  if (room.startsWith("theme:") && !theme) room = "night";
  app.room = room;
  applyRoom(room, theme);
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
