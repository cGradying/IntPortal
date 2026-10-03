// Pixel sprites shared by the campus scene and the island.

/** A PUP jeepney, 18x7, facing right. */
export const JEEP = [
  "....gggggggggg....",
  "...wwwwwwwwwwwww..",
  "..wbbwbbwbbwbbrr..",
  "..rrrrrrrrrrrrrrss",
  "..yyyyyyyyyyyyyyss",
  "..rrrrrrrrrrrrrrrs",
  "...kk........kk...",
];

export const JEEP_COLORS: Record<string, string> = {
  g: "#c9a227",
  w: "#e9e4d6",
  b: "#2c3e57",
  r: "#b3202a",
  y: "#f2c14e",
  s: "#c7ccd3",
  k: "#141414",
};

/** Isko, the Iskolar ng Bayan: 14x20, white PUP polo with a maroon
 *  collar, gold lanyard and ID. Two frames: standing, and waving. */
const ISKO_BODY = [
  "..rrWwgwwWrr..",
  ".WwwwwgwwwwwW.",
  ".WwwwwgwwwwwW.",
  ".FWwwwiiwwwWF.",
  "..Wwwwiiwwww..",
  "..WwwwwwwwwW..",
  "..pppppppppp..",
  "..ppppP.pppp..",
  "..pppp..pppp..",
  "..Pppp..Pppp..",
  ".kkkkk..kkkkk.",
];

export const ISKO = [
  "....hhhhhh....",
  "...hHHhhhhh...",
  "..hhhhhhhhhh..",
  "..hhffffffhh..",
  "..hffeffefhh..",
  "...ffffffff...",
  "...ffffffff...",
  "....fffmff....",
  ".....FffF.....",
  ...ISKO_BODY,
];

export const ISKO_WAVE = [
  "....hhhhhh..f.",
  "...hHHhhhhh.f.",
  "..hhhhhhhhhhf.",
  "..hhffffffhhW.",
  "..hffeffefhhW.",
  "...ffffffff.W.",
  "...ffffffffWW.",
  "....fffmff.W..",
  ".....FffF.W...",
  "..rrWwgwwWrr..",
  ".WwwwwgwwwwW..",
  ".WwwwwgwwwwW..",
  ".FWwwwiiwwwW..",
  ...ISKO_BODY.slice(4),
];

/** Both arms up: a finished study session, a goal met. */
export const ISKO_CHEER = [
  ".f..hhhhhh..f.",
  ".f.hHHhhhhh.f.",
  ".fhhhhhhhhhhf.",
  ".WhhffffffhhW.",
  ".WhffeffefhhW.",
  ".W.ffffffff.W.",
  ".WWffffffffWW.",
  "..W.fffmff.W..",
  "...W.FffF.W...",
  "..rrWwgwwWrr..",
  "..WwwwgwwwwW..",
  "..WwwwgwwwwW..",
  "..WwwwiiwwwW..",
  ...ISKO_BODY.slice(4),
];

/** The study streak's flame, 7x9: two frames that flicker. */
export const FLAME = [
  ["...r...", "..rr...", "..rrr..", ".rryrr.", ".ryyyr.", "rryywyr", "ryywwyr", "ryywwyr", ".rryyr."],
  ["....r..", "...rr..", "..rrr..", ".rryrr.", ".ryyyrr", "rryyyyr", "ryywwyr", "ryywwyr", ".rryyr."],
] as const;

export const FLAME_COLORS: Record<string, string> = {
  r: "#c2403a",
  y: "#f5b227",
  w: "#fff1c4",
};

export const ISKO_COLORS: Record<string, string> = {
  h: "#1d1717",
  H: "#3a2f2c",
  f: "#e0a77c",
  F: "#c4865c",
  e: "#1d1717",
  m: "#9b4a3c",
  w: "#f4f1ea",
  W: "#cfc8bb",
  r: "#7a1128",
  g: "#f2c14e",
  i: "#f2c14e",
  p: "#2c3346",
  P: "#1f2433",
  k: "#141414",
};
