// Kinetic headlines: display-face lines revealed through masks (slide up out
// of a baseline mask on a beat, exit upward). Never a fade.
import { css, ease, el, pb } from "../lib/core.js";

/**
 * lines: [{ text, at, gold? }]; out = beat the block exits.
 * Returns render(b).
 */
export function headline(parent, lines, { x = 120, y = 360, size = 118, lh = 1.0, out = 999, align = "left", width = 900 } = {}) {
  const box = el("div", "abs", parent);
  css(box, { left: `${x}px`, top: `${y}px`, width: `${width}px`, textAlign: align });
  const parts = lines.map((l, i) => {
    const m = el("div", "mask display", box, `<span>${l.html ?? l.text}</span>`);
    css(m, { display: "block", fontSize: `${size}px`, lineHeight: `${lh}`, color: l.gold ? "var(--gold)" : "#f7ecec", marginTop: i ? `${size * 0.02}px` : "0", whiteSpace: "nowrap" });
    return m;
  });
  return function render(b) {
    const vis = b >= lines[0].at - 0.01 && b < out + 0.6;
    box.style.display = vis ? "" : "none";
    if (!vis) return;
    parts.forEach((m, i) => {
      const k = pb(b, lines[i].at, lines[i].at + 0.45, ease.outExpo);
      const o = pb(b, out + i * 0.06, out + 0.4 + i * 0.06, ease.inCubic);
      m.firstChild.style.transform = `translateY(${(1 - k) * 105 - o * 105}%)`;
    });
  };
}
