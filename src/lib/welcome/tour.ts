// The welcome's tour (spec 010 C45): three stops under the portal that show a new student what
// IntPortal holds, what it does for them and how they make it theirs, each by doing it. Pure data,
// so the copy is testable; WelcomeTour draws it and Landing wires each action to the stage.
import { HAND_TUNED, PALETTES } from "../rooms";
import { PAGES, type PeekPage } from "../peek";

export type StopId = "inside" | "does" | "yours";

/** What tapping an item does. */
export type Act =
  /** Open the portal's peek on this page (010 C37). */
  | { kind: "peek"; page: number }
  /** LAR says this line in his bubble. */
  | { kind: "say"; line: string }
  /** Wear this room now, and keep it for the app (You › Theme). */
  | { kind: "room"; room: string }
  /** Open the portal wall to choose a school (010 C13a). */
  | { kind: "school" };

export interface Item {
  id: string;
  label: string;
  act: Act;
  /** Room items: the three colours their swatch shows, ground first. */
  swatch?: [string, string, string];
}

export interface Stop {
  id: StopId;
  /** The tab's name. */
  tab: string;
  /** One line under the tabs: what this stop is, and what to tap. */
  lead: string;
  items: Item[];
}

const peekItem = (id: PeekPage): Item => {
  const page = PAGES.findIndex((p) => p.id === id);
  return { id, label: PAGES[page].title, act: { kind: "peek", page } };
};

/** Dark rooms only: the landing is the night ground, and a light one would wash the portal out. */
const ROOMS: { room: string; name: string; swatch: [string, string, string] }[] = [
  ...HAND_TUNED.filter((r) => r.id === "night" || r.id === "maroon").map((r) => ({ room: r.id, name: r.name, swatch: r.swatch as [string, string, string] })),
  ...(["astraMoon", "tokyoNight", "dracula", "nord"] as const).map((id) => {
    const p = PALETTES[id];
    return { room: id, name: p.name, swatch: [p.canvasBottom, p.panel, p.accent] as [string, string, string] };
  }),
];

export const TOUR: Stop[] = [
  {
    id: "inside",
    tab: "Inside",
    lead: "Tap one to see it through the portal.",
    items: (["today", "schedule", "grades", "study"] as const).map(peekItem),
  },
  {
    id: "does",
    tab: "What it does",
    lead: "Tap one and LAR tells you.",
    items: [
      { id: "remind", label: "Reminders", act: { kind: "say", line: "Bago mag-klase, may paalala ka. Gumagana kahit offline." } },
      { id: "due", label: "Deadlines", act: { kind: "say", line: "Ilista ang mga due mo, i-tick pag tapos. Ako na bahala sa paalala." } },
      { id: "offline", label: "Works offline", act: { kind: "say", line: "Walang signal sa jeep? Bukas pa rin ang schedule, grades at notes mo." } },
      { id: "private", label: "Stays on your phone", act: { kind: "say", line: "Nasa phone mo lang ang login at data mo. PUP lang ang kinakausap ko." } },
      { id: "coach", label: "LAR's nudges", act: { kind: "say", line: "Isang tip lang sa isang pagkakataon: ano ang susunod, ano ang malapit nang due." } },
    ],
  },
  {
    id: "yours",
    tab: "Make it yours",
    lead: "Pick a look. It stays when you sign in.",
    items: [
      ...ROOMS.map((r) => ({ id: r.room, label: r.name, act: { kind: "room", room: r.room } as Act, swatch: r.swatch })),
      { id: "school", label: "Your school", act: { kind: "school" } },
    ],
  },
];
