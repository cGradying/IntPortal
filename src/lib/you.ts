// Spec 047 C1–C8: You's rows, its search and the app-side choices behind
// Layout and Motion. Pure, so the matching and the card moves are tested.

export type PageId = "accounts" | "theme" | "layout" | "motion" | "reminders" | "calendar" | "assis" | "notes" | "backup" | "privacy";

/** C1: the rows, grouped. */
export const GROUPS: [string, [PageId, string][]][] = [
  ["Account", [["accounts", "Accounts"]]],
  ["Look", [["theme", "Theme"], ["layout", "Layout"], ["motion", "Motion and effects"]]],
  ["Alerts", [["reminders", "Reminders"], ["calendar", "Calendar"]]],
  ["Data", [["assis", "IntAssis"], ["notes", "Notes"], ["backup", "Backup and data"], ["privacy", "Privacy"]]],
];

/** C2: every setting, the page it lives on, and the words a student might
 *  type for it, in English and common Taglish. */
export const SETTINGS: { name: string; page: PageId; words: string }[] = [
  { name: "SIS", page: "accounts", words: "sync login password account portal sis schedule grades i-sync" },
  { name: "eMabini", page: "accounts", words: "mabini courses lms sync login password account" },
  { name: "Sign out", page: "accounts", words: "logout log out sign out mag-logout labas umalis" },
  { name: "Rooms", page: "theme", words: "theme colour color kulay room dark light madilim maliwanag tema itsura look" },
  { name: "Make a theme", page: "theme", words: "theme custom share code qr gawa tema kulay" },
  { name: "Text style", page: "theme", words: "font classic montserrat letra sulat text typeface" },
  { name: "App opens on", page: "layout", words: "start first tab open bukas home simula" },
  { name: "Lists", page: "layout", words: "compact comfy density dense siksik maluwag size laki" },
  { name: "Today's cards", page: "layout", words: "cards order hide show reorder itago ayos due up next plan term events" },
  { name: "The dive", page: "motion", words: "dive portal opening animation intro launch galaw" },
  { name: "Done effects", page: "motion", words: "confetti sparks effects celebrate calm galaw" },
  { name: "Moving ground", page: "motion", words: "ground background pools motion animation galaw likod" },
  { name: "Haptics", page: "motion", words: "vibrate vibration buzz haptic panginig yanig" },
  { name: "Sounds", page: "motion", words: "sound audio tunog ingay blips" },
  { name: "Class reminders", page: "reminders", words: "class klase reminder notification paalala abiso nudge minutes" },
  { name: "Deadline reminders", page: "reminders", words: "deadline due quiz exam project pasahan takdang notification paalala" },
  { name: "Study reminders", page: "reminders", words: "study flashcards aral review notification paalala" },
  { name: "Warm-up", page: "reminders", words: "warm-up warm up class reminder" },
  { name: "Note after class", page: "reminders", words: "note after class tala sulat" },
  { name: "Sunday brief", page: "reminders", words: "sunday brief week linggo summary" },
  { name: "Notifications", page: "reminders", words: "notifications allow permission abiso paalala" },
  { name: "Keep classes in my calendar", page: "calendar", words: "calendar kalendaryo classes klase sync" },
  { name: "Show my own events", page: "calendar", words: "events calendar busy kalendaryo lakad" },
  { name: "Add classes to calendar", page: "calendar", words: "export ics last day calendar petsa kalendaryo" },
  { name: "IntAssis", page: "assis", words: "ai lar chat model download assistant tanong" },
  { name: "Notes", page: "notes", words: "notes tala sulat export search" },
  { name: "Backup", page: "backup", words: "backup export restore new phone save i-save lipat" },
  { name: "Space used", page: "backup", words: "storage space size laki espasyo memory" },
  { name: "Lock", page: "privacy", words: "lock face id passcode fingerprint kandado susi privacy" },
  { name: "Erase everything", page: "privacy", words: "erase delete reset burahin bura tanggal wipe" },
];

const fold = (s: string) => s.toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "");

/** Settings whose name or words hold every word of the query. */
export function searchSettings(query: string) {
  const words = fold(query).split(/\s+/).filter(Boolean);
  if (!words.length) return [];
  return SETTINGS.filter((s) => {
    const hay = fold(`${s.name} ${s.words}`);
    return words.every((w) => hay.includes(w));
  });
}

/** C3: what is wrong on a row, if anything; shown on the row itself. */
export function rowProblem(
  page: PageId,
  s: { sisRejected: boolean; mabiniRejected: boolean; mabiniError: string | null; notifications: boolean | null; remindersOn: boolean; queuedError: string; lockError: string },
): string | null {
  if (page === "accounts") {
    if (s.sisRejected || s.mabiniRejected) return "Login turned down";
    if (s.mabiniError) return "eMabini didn't sync";
  }
  if (page === "reminders" && s.remindersOn) {
    if (s.notifications === false) return "Notifications off";
    if (s.queuedError) return "Couldn't schedule";
  }
  if (page === "privacy" && s.lockError) return "Lock not set";
  return null;
}

/** C6: Today's cards. Your events live inside Today's list, so they hide but don't move. */
export type CardId = "next" | "due" | "coach" | "term" | "events";
export const CARD_NAMES: Record<CardId, string> = { next: "Up next", due: "Due", coach: "LAR's plan", term: "This term", events: "Your events" };
export const MOVABLE: CardId[] = ["next", "due", "coach", "term"];
export interface Cards {
  order: CardId[];
  hidden: CardId[];
}

/** A stored choice, or every card shown in the usual order. */
export function parseCards(raw: string | null): Cards {
  let v: Partial<Cards> = {};
  try {
    v = JSON.parse(raw ?? "{}") ?? {};
  } catch {
    // A damaged value falls back to the usual order.
  }
  const order = (Array.isArray(v.order) ? v.order : []).filter((c, i, a): c is CardId => MOVABLE.includes(c) && a.indexOf(c) === i);
  const hidden = (Array.isArray(v.hidden) ? v.hidden : []).filter((c): c is CardId => c in CARD_NAMES);
  return { order: [...order, ...MOVABLE.filter((c) => !order.includes(c))], hidden };
}

/** Swaps a card with its neighbour; past either end nothing moves. */
export function moveCard(order: CardId[], i: number, by: -1 | 1): CardId[] {
  const j = i + by;
  if (j < 0 || j >= order.length) return order;
  const next = [...order];
  [next[i], next[j]] = [next[j], next[i]];
  return next;
}

export function toggleCard(c: Cards, id: CardId): Cards {
  return { ...c, hidden: c.hidden.includes(id) ? c.hidden.filter((x) => x !== id) : [...c.hidden, id] };
}

/** A stored value if it's one of `options`, else the first option. */
export function oneOf<T extends string>(raw: string | null, options: readonly T[]): T {
  return options.includes(raw as T) ? (raw as T) : options[0];
}
