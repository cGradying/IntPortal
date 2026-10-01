// Morphing elements inside the phone: every rect is a set of spring tracks,
// so a card can grow out of another card's edge, become a sheet, fold back.
import React from "react";
import { Key, SNAP, Spr, STD, keysFrom, track, trackColor, clamp } from "../lib/motion";
import { LIFT_SM } from "../theme";

export type Rect = { x: number; y: number; w: number; h: number; r: number };
export type RectKeys = Record<keyof Rect, Key[]>;

export const rectKeys = (init: Rect, states: [number, Partial<Rect>][]) => keysFrom(init, states) as RectKeys;
export const rectAt = (t: number, k: RectKeys, s: Spr = STD): Rect => ({
  x: track(t, k.x, s), y: track(t, k.y, s), w: track(t, k.w, s), h: track(t, k.h, s), r: track(t, k.r, s),
});

export const El: React.FC<{
  t: number; k: RectKeys; fill?: [number, string][]; lift?: Key[]; s?: Spr; dy?: number;
  style?: React.CSSProperties; hide?: boolean; children?: (r: Rect) => React.ReactNode;
}> = ({ t, k, fill, lift, s, dy = 0, style, hide, children }) => {
  const r = rectAt(t, k, s);
  if (hide || r.w < 0.5 || r.h < 0.5) return null;
  const l = lift ? clamp(track(t, lift)) : 0;
  return (
    <div style={{
      position: "absolute", left: r.x, top: r.y + dy, width: r.w, height: r.h,
      borderRadius: Math.min(r.r, r.w / 2, r.h / 2), overflow: "hidden",
      background: fill ? trackColor(t, fill, SNAP) : undefined,
      boxShadow: l > 0.01 ? LIFT_SM.replace(/0\.(\d+)\)/g, (_, d) => `${(Number("0." + d) * l).toFixed(3)})`) : undefined,
      ...style,
    }}>
      {children?.(r)}
    </div>
  );
};
