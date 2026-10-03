// Finds a tiling of the portal frame (a two-cell ring) with pentominoes and
// prints it as the FRAME and PIECES constants for src/lib/pentomino.ts.
// Exact cover by Algorithm X over the ring's cells. No two-cell ring of 60
// cells takes all twelve pentominoes once (exhaustive search), so a shape may
// repeat up to MAX_USES times and the search wants at least MIN_KINDS shapes.
// Usage: node scripts/pentomino-solve.mjs [cols] [rows] [minKinds]
const cols = Number(process.argv[2] ?? 8);
const rows = Number(process.argv[3] ?? 11);
const MIN_KINDS = Number(process.argv[4] ?? 10);
const MAX_USES = 2;
const SHAPES = {
  F: [[1, 0], [2, 0], [0, 1], [1, 1], [1, 2]],
  I: [[0, 0], [0, 1], [0, 2], [0, 3], [0, 4]],
  L: [[0, 0], [0, 1], [0, 2], [0, 3], [1, 3]],
  N: [[1, 0], [1, 1], [0, 2], [1, 2], [0, 3]],
  P: [[0, 0], [1, 0], [0, 1], [1, 1], [0, 2]],
  T: [[0, 0], [1, 0], [2, 0], [1, 1], [1, 2]],
  U: [[0, 0], [2, 0], [0, 1], [1, 1], [2, 1]],
  V: [[0, 0], [0, 1], [0, 2], [1, 2], [2, 2]],
  W: [[0, 0], [0, 1], [1, 1], [1, 2], [2, 2]],
  X: [[1, 0], [0, 1], [1, 1], [2, 1], [1, 2]],
  Y: [[1, 0], [0, 1], [1, 1], [1, 2], [1, 3]],
  Z: [[0, 0], [1, 0], [1, 1], [1, 2], [2, 2]],
};
const norm = (cells) => {
  const mx = Math.min(...cells.map((c) => c[0])), my = Math.min(...cells.map((c) => c[1]));
  return cells.map(([x, y]) => [x - mx, y - my]).sort((a, b) => a[1] - b[1] || a[0] - b[0]);
};
const variants = (cells) => {
  const out = new Map();
  let cur = cells;
  for (let f = 0; f < 2; f++) {
    for (let r = 0; r < 4; r++) {
      const n = norm(cur);
      out.set(JSON.stringify(n), n);
      cur = cur.map(([x, y]) => [y, -x]);
    }
    cur = cur.map(([x, y]) => [-x, y]);
  }
  return [...out.values()];
};
const inRing = (c, r) => c >= 0 && r >= 0 && c < cols && r < rows && (c < 2 || r < 2 || c >= cols - 2 || r >= rows - 2);
const cells = [];
for (let r = 0; r < rows; r++) for (let c = 0; c < cols; c++) if (inRing(c, r)) cells.push(`${c},${r}`);
if (cells.length !== 60) throw new Error(`${cols}×${rows} ring has ${cells.length} cells, not 60`);

// Columns: 12 shapes + every cell. Rows: each placement of each shape.
const options = [];
for (const [name, base] of Object.entries(SHAPES))
  for (const v of variants(base))
    for (let r = 0; r < rows; r++) for (let c = 0; c < cols; c++) {
      const placed = v.map(([x, y]) => [x + c, y + r]);
      if (placed.every(([x, y]) => inRing(x, y))) options.push({ name, cells: placed, cover: placed.map(([x, y]) => `${x},${y}`) });
    }

const columns = cells;
const kinds = (chosen) => new Set(chosen.map((o) => o.name)).size;
function solve(open, chosen, live) {
  if (open.size === 0) return kinds(chosen) >= MIN_KINDS ? chosen : null;
  // Even if every remaining piece were a new shape, could we still reach MIN_KINDS?
  if (kinds(chosen) + open.size / 5 < MIN_KINDS) return null;
  let best = null, bestN = Infinity;
  for (const col of open) {
    let n = 0;
    for (const o of live) if (o.cover.includes(col)) n++;
    if (n < bestN) [best, bestN] = [col, n];
    if (n === 0) return null;
  }
  for (const o of live) {
    if (!o.cover.includes(best)) continue;
    const nextOpen = new Set(open);
    o.cover.forEach((c) => nextOpen.delete(c));
    const uses = chosen.filter((p) => p.name === o.name).length + 1;
    const nextLive = live.filter((p) => !p.cover.some((c) => o.cover.includes(c)) && !(uses >= MAX_USES && p.name === o.name));
    const found = solve(nextOpen, [...chosen, o], nextLive);
    if (found) return found;
  }
  return null;
}
const found = solve(new Set(columns), [], options);
if (!found) throw new Error(`no tiling of the ${cols}×${rows} ring with ${MIN_KINDS}+ different pentominoes`);
const lowest = (p) => Math.max(...p.cells.map(([, y]) => y));
const meanX = (p) => p.cells.reduce((a, [x]) => a + x, 0) / 5;
found.sort((a, b) => lowest(b) - lowest(a) || meanX(a) - meanX(b));
console.log(`export const FRAME = { cols: ${cols}, rows: ${rows}, thick: 2 } as const;\n`);
console.log("export const PIECES: readonly Piece[] = [");
for (const p of found) console.log(`  { shape: "${p.name}", cells: [${p.cells.map(([x, y]) => `[${x}, ${y}]`).join(", ")}] },`);
console.log("];");
