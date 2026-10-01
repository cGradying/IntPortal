// Small building blocks shared by every state.
import React from "react";
import { B, clamp, spring, swapAlpha, SNAP, STD, Spr } from "../lib/motion";
import { C, FONT } from "../theme";

export const abs: React.CSSProperties = { position: "absolute" };

/**
 * Content that swaps in at inB and out at outB with its own timing:
 * short blur, a few px of travel, no fade-from-nothing scale.
 */
export const Swap: React.FC<{
  t: number; inB: number; outB?: number; x?: number; y?: number; w?: number; h?: number;
  delay?: number; style?: React.CSSProperties; children?: React.ReactNode; dy?: number;
}> = ({ t, inB, outB, x = 0, y = 0, w, h, delay, style, children, dy = 1 }) => {
  const s = swapAlpha(t, inB, outB, { delay });
  if (!s.on) return null;
  return (
    <div style={{
      ...abs, left: x, top: y, width: w, height: h, opacity: s.o,
      filter: s.blur > 0.05 ? `blur(${s.blur.toFixed(2)}px)` : undefined,
      transform: `translateY(${(s.y * dy).toFixed(2)}px)`, ...style,
    }}>{children}</div>
  );
};

/** Text with Geist defaults. */
export const T: React.FC<{
  size?: number; w?: number; c?: string; ls?: number; lh?: number; tab?: boolean;
  style?: React.CSSProperties; children: React.ReactNode;
}> = ({ size = 16, w = 500, c = C.ink, ls, lh = 1.2, tab, style, children }) => (
  <div style={{
    fontFamily: FONT, fontSize: size, fontWeight: w, color: c, lineHeight: lh, whiteSpace: "pre",
    letterSpacing: ls ?? (size >= 28 ? -0.025 * size : size >= 18 ? -0.012 * size : 0),
    fontVariantNumeric: tab ? "tabular-nums" : undefined, ...style,
  }}>{children}</div>
);

/**
 * Rolling number: each key [beat, text] rolls its changed characters up
 * through a clipped line (an odometer), one spring per change.
 */
export const Roll: React.FC<{
  t: number; keys: [number, string][]; size: number; w?: number; c?: string; s?: Spr; style?: React.CSSProperties;
}> = ({ t, keys, size, w = 600, c = C.ink, s = STD, style }) => {
  // current = last key whose beat passed; previous = the one before
  let i = 0;
  while (i + 1 < keys.length && t >= B(keys[i + 1][0])) i++;
  const cur = keys[i][1];
  const prev = i > 0 ? keys[i - 1][1] : cur;
  const k = i > 0 ? spring(t - B(keys[i][0]), s) : 1;
  const n = Math.max(cur.length, prev.length);
  const lh = size * 1.15;
  const chars = [];
  for (let j = 0; j < n; j++) {
    const a = prev.padStart(n, " ")[j], b = cur.padStart(n, " ")[j];
    const moving = a !== b && k < 1;
    // new glyph rises from below while the old one leaves through the top
    chars.push(
      <span key={j} style={{ display: "inline-block", position: "relative", height: lh, overflow: "hidden", verticalAlign: "top" }}>
        <span style={{ display: "block", transform: `translateY(${(moving ? (1 - k) * lh : 0).toFixed(2)}px)` }}>{b === " " ? " " : b}</span>
        {moving && <span style={{ ...abs, left: 0, top: 0, display: "block", transform: `translateY(${(-k * lh).toFixed(2)}px)` }}>{a === " " ? " " : a}</span>}
      </span>,
    );
  }
  return (
    <div style={{ fontFamily: FONT, fontSize: size, fontWeight: w, color: c, lineHeight: `${lh}px`, letterSpacing: -0.03 * size, fontVariantNumeric: "tabular-nums", whiteSpace: "pre", ...style }}>
      {chars}
    </div>
  );
};

/** A line that draws from 0 to its full width on a spring. */
export const Rule: React.FC<{ t: number; at: number; x: number; y: number; w: number; c?: string; out?: number; vertical?: boolean }> = ({ t, at, x, y, w, c = C.ink, out, vertical }) => {
  let k = spring(t - B(at), STD);
  if (out !== undefined) k *= 1 - spring(t - B(out), SNAP);
  if (k < 0.002) return null;
  return <div style={{ ...abs, left: x, top: y, width: vertical ? 1.75 : w * k, height: vertical ? w * k : 1.75, background: c, borderRadius: 1 }} />;
};

/** Typed text: one chunk per beat. keys [beat, fullTextSoFar]. Caret blinks on the beat. */
export function typed(t: number, keys: [number, string][]) {
  let s = "";
  for (const [b, txt] of keys) if (t >= B(b) - 0.02) s = txt;
  return s;
}

export const clampN = clamp;
export { SNAP };
