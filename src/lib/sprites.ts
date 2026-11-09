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

