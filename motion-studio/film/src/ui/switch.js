// Pixel toggle switch (the stephanlivera-style reference): a stepped-corner
// track, a square knob that snaps across with a 1-frame squash, gold when on.
// Every flip in the film has a click SFX on the same beat (audio/mix.py).
import { clamp, css, el } from "../lib/core.js";

const STEP = "polygon(0 6px,3px 6px,3px 3px,6px 3px,6px 0,calc(100% - 6px) 0,calc(100% - 6px) 3px,calc(100% - 3px) 3px,calc(100% - 3px) 6px,100% 6px,100% calc(100% - 6px),calc(100% - 3px) calc(100% - 6px),calc(100% - 3px) calc(100% - 3px),calc(100% - 6px) calc(100% - 3px),calc(100% - 6px) 100%,6px 100%,6px calc(100% - 3px),3px calc(100% - 3px),3px calc(100% - 6px),0 calc(100% - 6px))";

export function pixSwitch(parent, { label = "", s = 1, x = 0, y = 0, on = "#f5b227", off = "#3a2f44", ink = "#f7ecec", labelSize = 28 } = {}) {
  const root = el("div", "abs", parent);
  css(root, { left: `${x}px`, top: `${y}px`, display: "flex", alignItems: "center", width: "max-content", whiteSpace: "nowrap", gap: `${18 * s}px`, transformOrigin: "0 50%" });
  const track = el("div", "", root);
  css(track, { position: "relative", width: `${76 * s}px`, height: `${40 * s}px`, background: off, clipPath: STEP, flex: "none" });
  const knob = el("div", "", track);
  css(knob, { position: "absolute", top: `${6 * s}px`, left: `${6 * s}px`, width: `${28 * s}px`, height: `${28 * s}px`, background: "#d8cce2", clipPath: STEP });
  const hi = el("div", "", knob);
  css(hi, { position: "absolute", left: `${5 * s}px`, top: `${5 * s}px`, width: `${6 * s}px`, height: `${6 * s}px`, background: "#fff" });
  const lab = el("div", "", root, label);
  css(lab, { font: `700 ${labelSize * s}px var(--pixel)`, color: ink, letterSpacing: "0.04em", whiteSpace: "nowrap" });
  return {
    root, lab,
    /** k: 0 off → 1 on (knob travel), press: 0..1 squash */
    render(k, press = 0) {
      k = clamp(k);
      const snap = k < 0.5 ? 0 : 1;
      knob.style.left = `${(6 + k * 36) * s}px`;
      knob.style.transform = `scale(${1 + press * 0.25}, ${1 - press * 0.2})`;
      knob.style.background = snap ? "#fff6dc" : "#d8cce2";
      track.style.background = snap ? on : off;
    },
  };
}
