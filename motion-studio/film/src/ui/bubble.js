// Isko's comment bubbles: a pixel speech card that pops next to him with a
// line about what you are doing, types itself in and pops away.
import { clamp, css, ease, el, pb, springB } from "../lib/core.js";

export function makeBubble(parent, { z = 40 } = {}) {
  const root = el("div", "abs notch", parent);
  css(root, { left: "0", top: "0", padding: "14px 20px 16px", background: "#1d1424", border: "4px solid #f5b227", maxWidth: "420px", zIndex: z, transformOrigin: "0% 100%" });
  const who = el("div", "", root, "ISKO");
  css(who, { font: "700 18px var(--pixel)", color: "#f5b227", letterSpacing: ".14em", marginBottom: "4px" });
  const txt = el("div", "", root);
  css(txt, { font: "600 28px/1.25 var(--ui)", color: "#f7ecec", whiteSpace: "nowrap" });
  const tail = el("div", "abs", root);
  css(tail, { left: "18px", bottom: "-20px", width: "16px", height: "16px", background: "#f5b227", boxShadow: "-12px 10px 0 -2px #f5b227" });
  return {
    /** list: [[at, dur, text]]; (x, y) = anchor point (Isko's head). */
    render(b, list, x, y, left = false) {
      const c = list.find(([at, dur]) => b >= at && b < at + dur);
      root.style.display = c ? "" : "none";
      if (!c) return;
      const [at, dur, text] = c;
      const k = clamp(springB(b, at, 2.6, 0.55), 0, 1.15) * (1 - pb(b, at + dur - 0.3, at + dur, ease.inCubic));
      const s = text.slice(0, Math.ceil(text.length * pb(b, at + 0.1, at + 0.1 + Math.min(1.2, text.length * 0.04))));
      if (txt.textContent !== s) txt.textContent = s;
      root.style.transformOrigin = left ? "100% 100%" : "0% 100%";
      tail.style.left = left ? "auto" : "18px"; tail.style.right = left ? "18px" : "auto";
      root.style.transform = left ? `translate(${x - 40}px, ${y - 150}px) translateX(-100%) scale(${k})` : `translate(${x + 40}px, ${y - 150}px) scale(${k})`;
    },
  };
}
