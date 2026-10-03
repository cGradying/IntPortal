// The phone's own calendar, through the calendar plugin. Only iOS has it;
// elsewhere every call fails and the app acts as if access were off.
import { invoke } from "@tauri-apps/api/core";
import { api, isoDate, localMs, moment, type Busy } from "./api";

export type Access = "granted" | "write_only" | "not_asked" | "denied";

const access = (cmd: string) =>
  invoke<{ status: Access }>(`plugin:calendar|${cmd}`)
    .then((r) => r.status)
    .catch((): Access => "denied");

export const calendarAccess = () => access("status");
/** Shows the system prompt the first time; after that it only reports. */
export const askForCalendar = () => access("request");

/** Today's own timed events as busy spans; all-day events don't block time. */
export async function busyToday(): Promise<Busy[]> {
  const from = new Date();
  from.setHours(0, 0, 0, 0);
  const to = new Date(from);
  to.setDate(to.getDate() + 1);
  const r = await invoke<{ events: { title: string; start: number; end: number; allDay: boolean }[] }>("plugin:calendar|events", {
    from: from.getTime(),
    to: to.getTime(),
  });
  return r.events.filter((e) => !e.allDay).map((e) => ({ from: moment(new Date(e.start)), to: moment(new Date(e.end)), title: e.title }));
}

/** How far ahead the IntPortal calendar holds classes. Each sync renews it. */
const DAYS = 56;

/** Replaces the IntPortal calendar's next eight weeks with the classes,
 *  or with nothing when the student turns it off. */
export async function keepClasses(none = false) {
  const from = new Date();
  from.setHours(0, 0, 0, 0);
  const to = new Date(from);
  to.setDate(to.getDate() + DAYS);
  const events = (none ? [] : await api.classEvents(isoDate(from), DAYS)).map((e) => ({
    title: e.title,
    notes: e.notes,
    start: localMs(e.date, e.start),
    end: localMs(e.date, e.end),
  }));
  await invoke("plugin:calendar|sync_classes", { from: from.getTime(), to: to.getTime(), events });
}
