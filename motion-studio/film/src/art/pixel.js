// Pixel-art helpers: char-map sprites → 1px-per-cell canvases, drawn at an
// integer CSS scale with nearest-neighbour sampling.

export function pixelCanvas(rows, palette) {
  const w = Math.max(...rows.map((r) => r.length));
  const h = rows.length;
  const c = document.createElement("canvas");
  c.width = w;
  c.height = h;
  const g = c.getContext("2d");
  rows.forEach((row, y) => {
    for (let x = 0; x < row.length; x++) {
      const col = palette[row[x]];
      if (!col) continue;
      g.fillStyle = col;
      g.fillRect(x, y, 1, 1);
    }
  });
  c.className = "px";
  return c;
}

/** Place a pixel canvas at scale s (CSS px per cell). */
export function sized(canvas, s) {
  canvas.style.width = `${canvas.width * s}px`;
  canvas.style.height = `${canvas.height * s}px`;
  canvas.style.position = "absolute";
  return canvas;
}

// 12x12 tab/utility icons in the app's pixel-icon style (1 = ink, 2 = accent).
export const ICONS = {
  today: [
    ".....11.....", ".1...11...1.", "..1......1..", "....2222....", "...222222...", "11.222222.11",
    "11.222222.11", "...222222...", "....2222....", "..1......1..", ".1...11...1.", ".....11.....",
  ],
  schedule: [
    "..1......1..", "111111111111", "1..........1", "111111111111", "1.22.22.22.1", "1.22.22.22.1",
    "1..........1", "1.22.22.22.1", "1.22.22.22.1", "1..........1", "111111111111", "............",
  ],
  grades: [
    "....1111....", "..11111111..", "1111111111..", "..11111111.2", "..1......1.2", "..1......1.2",
    "...111111..2", "..........22", "..........22", "............", "............", "............",
  ],
  study: [
    "...11111111.", "...1......1.", ".11111111.1.", ".1......1.1.", "11111111.1.1", "1......1.1.1",
    "1.2222.1.111", "1......1.1..", "1.2222.1.1..", "1......111..", "11111111....", "............",
  ],
  you: [
    "....1111....", "...111111...", "...111111...", "...111111...", "....1111....", "............",
    "..11111111..", ".1111111111.", ".1111221111.", ".1111111111.", ".1111111111.", "............",
  ],
  lock: [
    "....1111....", "...1....1...", "...1....1...", "...1....1...", "..11111111..", "..12222221..",
    "..12211221..", "..12211221..", "..12222221..", "..11111111..", "............", "............",
  ],
  spark: [
    ".....2......", ".....2......", "....222.....", "22222222222.", "....222.....", ".....2......",
    ".....2...2..", ".........2..", "........222.", ".........2..", ".........2..", "............",
  ],
};

export function icon(name, ink, accent, s = 3) {
  return sized(pixelCanvas(ICONS[name], { 1: ink, 2: accent }), s);
}
