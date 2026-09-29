// Global light flashes over everything: the warp's gold-white burst and the
// hard white cut frames. Each flash rises fast and decays on the beat grid.
import { css, el, pb } from "../lib/core.js";

const FLASHES = [
  { at: 19.55, peak: 19.95, end: 20.55, color: "255,244,214" },
  { at: 139.65, peak: 139.95, end: 140.55, color: "255,244,214" },
  { at: 171.7, peak: 171.98, end: 172.45, color: "255,236,190" },
];

export default {
  id: "flash", from: 0, to: 200, top: true,
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
    this.d.style.background = `radial-gradient(circle at 50% 50%, rgba(${col},${a}) 0%, rgba(${col},${a * 0.92}) 40%, rgba(${col},${a * 0.7}) 100%)`;
  },
};
