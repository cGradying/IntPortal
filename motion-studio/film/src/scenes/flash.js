// Global light flashes over everything: the warp's gold-white burst, the
// bomb after the drop, and the hard cuts into the hub and the ending. Each
// rises fast and decays on the beat grid.
import { css, el, pb } from "../lib/core.js";

const FLASHES = [
  { at: 35.4, peak: 35.95, end: 36.6, color: "255,244,214" },
  { at: 163.98, peak: 164.0, end: 164.35, color: "255,255,255" },
  { at: 199.7, peak: 199.98, end: 200.5, color: "255,244,214" },
  { at: 223.75, peak: 223.98, end: 224.45, color: "255,236,190" },
];

export default {
  id: "flash", from: 0, to: 400, top: true,
  init(layer) {
    this.d = el("div", "abs", layer);
    css(this.d, { inset: "0" });
  },
  render(b) {
    let a = 0, col = "255,255,255";
    for (const f of FLASHES) {
      if (b < f.at || b > f.end) continue;
      const k = b < f.peak ? pb(b, f.at, f.peak) ** 1.5 : 1 - pb(b, f.peak, f.end, (x) => 1 - (1 - x) ** 3);
      if (k > a) { a = k; col = f.color; }
    }
    this.d.style.display = a > 0.001 ? "" : "none";
    this.d.style.background = `rgba(${col},${a})`;
  },
};
