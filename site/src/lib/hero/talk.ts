// Spec 058 C12 and 059 C1: what LAR says on the website, and the sculpture the
// portal sends out for each line. The app's own lines, first his hellos, then
// his tips, leaving out the ones about the app's landing (swipe the portal, tap
// the portal, sign in and he'll handle it).
import { LINES } from "$app_lib/lar/lines";

const fits = (text: string) => !/swipe|I-tap|ako na bahala/.test(text);

// Which sculpture stands for a line, by what it talks about; first match wins.
const FORM_OF: [RegExp, string][] = [
  [/nakikiliti/, "heart"],
  [/offline/, "phone"],
  [/keychain/, "lock"],
  [/notes/i, "book"],
  [/flashcards/i, "cards"],
  [/paalalahanan/, "bell"],
  [/deadlines/i, "calendar"],
  [/minutes/, "hourglass"],
  [/LAR|Robot/, "crystal"],
];
const formOf = (text: string) => FORM_OF.find(([re]) => re.test(text))?.[1] ?? null;

export type Line = { text: string; form: string | null };
export const talk: Line[] = [
  { text: "Tara, pasok!", form: null },
  ...LINES.filter((l) => l.topic === "tap" && fits(l.text)).map((l) => ({ text: l.text, form: formOf(l.text) })),
  ...LINES.filter((l) => l.topic === "tip" && fits(l.text)).map((l) => ({ text: l.text, form: formOf(l.text) })),
];
