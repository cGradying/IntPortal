// Spec 059: what comes out of the portal. Small voxel sculptures, like the forms
// LAR's crystal takes in the app (spec 046 C1b3), each standing for what he is
// talking about. Drawn as layers, front to back; each row top to bottom. A digit
// is a tone of the SIS ramp (0 dark maroon to 4 pale gold), "." is empty. Front
// faces stay at tone 2 or lighter, so nothing sinks into the swirl behind.
import { RAMP } from "./portal";

export type Voxel = { x: number; y: number; z: number; tone: number };
export type Form = { id: string; voxels: Voxel[] };

/** At most this many voxels in a form: one instanced mesh holds them all. */
export const MAX = 72;

const DRAWN: Record<string, string[][]> = {
  // LAR's crystal, as a gem: what he carries from the other side.
  crystal: [
    ["..4..", ".434.", "43334", ".323.", "..2.."],
    ["..3..", ".323.", "32223", ".212.", "..1.."],
  ],
  // A heart, for when he's tickled.
  heart: [
    [".44.44.", "4444444", "4444444", ".44444.", "..444..", "...4..."],
    [".22.22.", "2222222", "2222222", ".22222.", "..222..", "...2..."],
  ],
  // A phone with the class on it, working with no signal.
  phone: [
    ["22222", "23332", "24442", "23332", "23332", "22222", "22422"],
    ["00000", "00000", "00000", "00000", "00000", "00000", "00000"],
  ],
  // A padlock: the login in the phone's keychain.
  lock: [
    [".444.", "4...4", "4...4", "33333", "33.33", "33.33", "33333"],
    [".333.", "3...3", "3...3", "22222", "22222", "22222", "22222"],
  ],
  // An open notebook.
  book: [
    ["4444.4444", "4333.3334", "4444.4444", "4333.3334", "4444.4444"],
    ["....1....", "....1....", "....1....", "....1....", "111111111"],
  ],
  // A stack of flashcards, the top one gold.
  cards: [
    ["44444..", "43334..", "44444..", "44444..", "......."],
    [".......", ".22222.", ".22222.", ".22222.", ".22222."],
    [".......", "..11111", "..11111", "..11111", "..11111"],
  ],
  // A bell: a reminder before class.
  bell: [
    ["..4..", ".444.", ".444.", "44444", "44444", "33333", "..2.."],
    ["..3..", ".333.", ".333.", "33333", "33333", "22222", "....."],
  ],
  // A calendar page with today marked: deadlines on Today.
  calendar: [
    [".4.4.", "22222", "33333", "33343", "33333", "33333"],
    [".....", "11111", "11111", "11111", "11111", "11111"],
  ],
  // An hourglass: three tries every fifteen minutes.
  hourglass: [
    ["22222", ".444.", "..4..", "..3..", ".333.", "22222"],
    ["22222", ".333.", "..3..", "..2..", ".222.", "22222"],
  ],
};

function parse(layers: string[][]): Voxel[] {
  const out: Voxel[] = [];
  const h = layers[0].length;
  const w = Math.max(...layers.flat().map((r) => r.length));
  const d = layers.length;
  layers.forEach((rows, z) =>
    rows.forEach((row, r) =>
      [...row].forEach((ch, x) => {
        const tone = "01234".indexOf(ch);
        if (tone < 0) return;
        // Centred on the origin; y up, z toward the viewer for the front layer.
        out.push({ x: x - (w - 1) / 2, y: (h - 1) / 2 - r, z: (d - 1) / 2 - z, tone });
      }),
    ),
  );
  return out;
}

export const FORMS: Record<string, Form> = Object.fromEntries(Object.entries(DRAWN).map(([id, layers]) => [id, { id, voxels: parse(layers) }]));

export const TONE = RAMP;
