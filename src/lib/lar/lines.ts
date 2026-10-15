// What LAR says while he wanders the landing: short Taglish lines about the
// app, picked at random by context, never repeating the last few, never
// while the student is typing. Pure, so the picking is testable.
import type { Rand } from "./wander";

export type Topic = "greet" | "tip" | "portal" | "tap" | "error" | "busy" | "signed";
export type Daypart = "morning" | "afternoon" | "evening";

export interface Line {
  text: string;
  topic: Topic;
  when?: Daypart;
  /** Only for this portal id; "soon" means any portal that is not ready. */
  portal?: string;
}

export const LINES: Line[] = [
  { topic: "greet", when: "morning", text: "Magandang umaga, iskolar! Kape muna bago klase?" },
  { topic: "greet", when: "morning", text: "Maaga ka ah. Silipin natin ang unang klase mo." },
  { topic: "greet", when: "afternoon", text: "Hapon na! Tara, tingnan natin kung ano ang next." },
  { topic: "greet", when: "afternoon", text: "Kumain ka na? Ako, portal energy lang." },
  { topic: "greet", when: "evening", text: "Gabi na, iskolar. Bukas ulit ang laban." },
  { topic: "greet", when: "evening", text: "Review muna konti bago matulog?" },

  { topic: "tip", text: "Pag naka-sign in ka na, gumagana ako kahit offline." },
  { topic: "tip", text: "Nasa keychain lang ng phone mo ang login mo. Promise." },
  { topic: "tip", text: "May notes per class. Para 'di makalimutan ang sabi ni Ma'am." },
  { topic: "tip", text: "Gawa tayo ng flashcards bago exam? Nasa Study tab." },
  { topic: "tip", text: "Kaya kitang paalalahanan bago bawat klase." },
  { topic: "tip", text: "I-swipe mo ang portal para makita ang ibang schools." },
  { topic: "tip", text: "Ang Mabini deadlines mo, lalabas din sa Today." },
  { topic: "tip", text: "Tatlong try lang kada 15 minutes, para safe ang account mo." },

  { topic: "portal", portal: "sis", text: "SIS 'to. Schedule at grades mo, nandito lahat." },
  { topic: "portal", portal: "mabini", text: "eMabini: courses at deadlines mo sa Open University." },
  { topic: "portal", portal: "soon", text: "{school}? Bubuksan pa namin 'yan. Abangan!" },
  { topic: "portal", portal: "soon", text: "Hindi pa bukas ang {name}. Pero ang ganda ng portal, 'di ba?" },

  { topic: "tap", text: "Uy! Ako si LAR, galing sa kabilang side ng portal." },
  { topic: "tap", text: "Lakbay-Aral Robot, at your service!" },
  { topic: "tap", text: "Hehe, nakikiliti ako." },
  { topic: "tap", text: "Kailangan mo ng tulong? Sign in lang, ako na bahala." },

  { topic: "error", text: "Ay, hindi pumasok. Check mo ulit ang details, ha?" },
  { topic: "error", text: "Hmm, ayaw pa. Dahan-dahan lang, may limit ang tries." },

  { topic: "busy", text: "Kumokonek na ako sa portal... sandali lang." },

  { topic: "signed", text: "Ayos! Nandito na lahat. Step through na tayo!" },
  { topic: "signed", text: "Welcome back, iskolar. Tara?" },
];

export const daypart = (hour: number): Daypart => (hour < 12 ? "morning" : hour < 18 ? "afternoon" : "evening");

export interface Scene {
  hour: number;
  portal: { id: string; name: string; school: string; ready: boolean };
  /** The student has a field focused: LAR stays quiet. */
  typing: boolean;
}

/** How many recent lines he avoids repeating. */
export const MEMORY = 6;

/** Pick a line for `topic`, or for idle chatter when no topic is forced. */
export function pick(scene: Scene, recent: string[], rand: Rand, topic?: Topic, lines: Line[] = LINES): string | null {
  if (scene.typing && topic !== "error") return null;
  const dp = daypart(scene.hour);
  const fits = (l: Line) => {
    if (l.when && l.when !== dp) return false;
    if (l.portal) return l.portal === "soon" ? !scene.portal.ready : l.portal === scene.portal.id;
    return true;
  };
  // Idle chatter: mostly tips, sometimes the portal or the time of day.
  const want: Topic[] = topic ? [topic] : rand() < 0.55 ? ["tip"] : rand() < 0.6 ? ["portal"] : ["greet"];
  const pool = lines.filter((l) => want.includes(l.topic) && fits(l));
  const isFresh = (l: Line) => !recent.includes(fill(l.text, scene));
  let from = pool.filter(isFresh);
  // A topic that is used up hands idle chatter to any other fresh line.
  if (!from.length && !topic) from = lines.filter((l) => ["tip", "portal", "greet"].includes(l.topic) && fits(l) && isFresh(l));
  if (!from.length) from = pool;
  if (!from.length) return null;
  return fill(from[Math.floor(rand() * from.length)].text, scene);
}

const fill = (text: string, s: Scene) => text.replace("{school}", s.portal.school).replace("{name}", s.portal.name);

/** Remember a line, keeping only the last few. */
export const remember = (recent: string[], line: string) => [...recent, line].slice(-MEMORY);

/** Seconds of quiet before he speaks again. */
export const pause = (rand: Rand) => 7 + rand() * 8;

/** Seconds a line stays up: long enough to read. */
export const hold = (line: string) => 2.5 + line.length * 0.045;
