// Spec 058 C12: what LAR says on the website when tapped. The app's own lines,
// first his hellos, then his tips, leaving out the ones about the app's landing
// (swipe the portal, tap the portal, sign in and he'll handle it).
import { LINES } from "$app_lib/lar/lines";

const fits = (text: string) => !/swipe|I-tap|ako na bahala/.test(text);
export const talk = [
  "Tara, pasok!",
  ...LINES.filter((l) => l.topic === "tap" && fits(l.text)).map((l) => l.text),
  ...LINES.filter((l) => l.topic === "tip" && fits(l.text)).map((l) => l.text),
];
