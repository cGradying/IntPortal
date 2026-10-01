// Phone chrome: status bar, the Island (a living chip), the tab bar, and
// the theme palette (light until the cursor re-themes it in phrase 5).
import React from "react";
import { Img, staticFile } from "remotion";
import { B, SNAP, STD, Key, clamp, indicator, keysFrom, spring, swapAlpha, track, trackColor } from "../lib/motion";
import { C, MONO } from "../theme";
import { Swap, T, abs } from "../ui/kit";
import { Icon } from "../ui/Icon";

// ---------------------------------------------------------------- theme
export const THEMES = {
  light: { bg: "#FFFFFF", fg: "#0B0B0C", card: "#0B0B0C", cardFg: "#FFFFFF", wash: "#F3F1EE", mute: "#6E6B66" },
  dark: { bg: "#0B0B0C", fg: "#F5F4F2", card: "#1D1D1F", cardFg: "#FFFFFF", wash: "#18181A", mute: "#8F8C87" },
  paper: { bg: "#F4EFE6", fg: "#1A1714", card: "#1A1714", cardFg: "#F4EFE6", wash: "#EAE2D5", mute: "#7A7266" },
  contrast: { bg: "#000000", fg: "#FFFFFF", card: "#FFFFFF", cardFg: "#000000", wash: "#141414", mute: "#9A9A9A" },
};
type Th = typeof THEMES.light;
export const THEME_KEYS: [number, keyof typeof THEMES][] = [[0, "light"], [128, "dark"], [129, "paper"], [130, "contrast"], [131, "light"]];
export function theme(t: number): Th {
  const out = {} as Th;
  for (const k of Object.keys(THEMES.light) as (keyof Th)[])
    out[k] = trackColor(t, THEME_KEYS.map(([b, n]) => [b, THEMES[n][k]] as [number, string]), SNAP);
  return out;
}

// ---------------------------------------------------------------- windows
/** Beats where the phone chrome is on screen. */
export const PHONE_ON: [number, number][] = [[14.6, 111], [127.4, 132], [137, 152]];
export const phoneOn = (t: number) => PHONE_ON.some(([a, b]) => t > B(a) - 0.2 && t < B(b) + 0.4);

// ---------------------------------------------------------------- status bar
export const StatusBar: React.FC<{ t: number; th: Th }> = ({ t, th }) => (
  <>
    {PHONE_ON.map(([a, b]) => (
      <React.Fragment key={a}>
        <Swap t={t} inB={a + 0.4} outB={b} x={28} y={20}><T size={15} w={600} c={th.fg} tab>7:21</T></Swap>
        <Swap t={t} inB={a + 0.4} outB={b} x={344} y={18} style={{ display: "flex", gap: 6, color: th.fg }}>
          <Icon name={t > B(97) && t < B(112) ? "wifiOff" : "wifi"} size={18} />
          <div style={{ width: 26, height: 13, borderRadius: 4, border: `1.75px solid ${th.fg}`, marginTop: 2, position: "relative" }}>
            <div style={{ ...abs, left: 1.5, top: 1.5, width: 15, height: 6.5, borderRadius: 1.5, background: th.fg }} />
          </div>
        </Swap>
      </React.Fragment>
    ))}
  </>
);

// ---------------------------------------------------------------- island
// Center-x 210, top edge fixed at y 11.
const IS = keysFrom({ w: 0, h: 0, r: 17 }, [
  [14.8, { w: 112, h: 34 }],
  [21, { w: 262, h: 44, r: 22 }], // grows into a chip
  [52, { w: 380, h: 124, r: 34 }], // Isko notification (form 2)
  [54, { w: 262, h: 44, r: 22 }],
  [110.6, { w: 0, h: 0 }],
  [127.6, { w: 262, h: 44 }],
  [131.8, { w: 0, h: 0 }],
  [137.2, { w: 262, h: 44 }],
  [151.4, { w: 0, h: 0 }],
]);

/** Line-art Isko (form 2): one stroke weight, drawn on. */
export const IskoLine: React.FC<{ t: number; at: number; size?: number; c?: string }> = ({ t, at, size = 64, c = "#fff" }) => {
  const d = clamp(spring(t - B(at), { k: 60, d: 15 }));
  const p = { stroke: c, strokeWidth: 1.75 * (64 / size), fill: "none", strokeLinecap: "round" as const, strokeLinejoin: "round" as const, pathLength: 1, strokeDasharray: `${d} 1` };
  return (
    <svg width={size} height={size} viewBox="0 0 64 64" style={{ display: "block", overflow: "visible" }}>
      <path {...p} d="M14 30c0-11 8-18 18-18s18 7 18 18v8c0 9-7 15-18 15s-18-6-18-15z" />
      <path {...p} d="M17 18v-7h7v4M47 18v-7h-7v4" />
      <path {...p} d="M21 27h22a3 3 0 0 1 3 3v4a3 3 0 0 1-3 3H21a3 3 0 0 1-3-3v-4a3 3 0 0 1 3-3z" />
      <path {...p} d="M27 31v2M37 31v2" strokeWidth={3 * (64 / size)} />
      <path {...p} d="M32 12V6" />
      <circle cx={32} cy={4.5} r={2} fill="#F5B227" stroke="none" opacity={d} />
      <path {...p} d="M8 40a3 3 0 1 0 0 .1M56 40a3 3 0 1 0 0 .1" />
      <path {...p} d="M28 45c2 1.6 6 1.6 8 0" />
    </svg>
  );
};

export const Island: React.FC<{ t: number }> = ({ t }) => {
  const w = track(t, IS.w), h = track(t, IS.h), r = track(t, IS.r);
  if (w < 1 || h < 1) return null;
  const peek = spring(t - B(23), STD) - spring(t - B(28), STD) + spring(t - B(128), STD) - spring(t - B(131.6), STD);
  return (
    <>
      {/* Isko form 1: tiny pixel Isko slides out from behind the chip */}
      {peek > 0.01 && (
        <div style={{ ...abs, left: 210 + w / 2 - 62, top: 11 + h - 6, width: 112, height: 80, overflow: "hidden" }}>
          <Img src={staticFile("isko/happy.png")} style={{ ...abs, left: 0, top: 0, width: 112, height: 73.5, imageRendering: "pixelated", transform: `translateY(${((1 - peek) * -76).toFixed(2)}px)` }} />
        </div>
      )}
      <div style={{ ...abs, left: 210 - w / 2, top: 11, width: w, height: h, borderRadius: r, background: C.ink, overflow: "hidden" }}>
        <Swap t={t} inB={22} outB={43} x={18} y={12} style={{ display: "flex", gap: 8, alignItems: "center", color: C.paper }}>
          <Icon name="clock" size={18} />
          <T size={15} w={560} c={C.paper} tab>COMP 20073 · 9 min</T>
        </Swap>
        <Swap t={t} inB={43} outB={52} x={18} y={12} style={{ display: "flex", gap: 8, alignItems: "center", color: C.paper }}>
          <Icon name="arrowR" size={18} />
          <T size={15} w={560} c={C.paper} tab>Next · GEED 10053</T>
        </Swap>
        {/* b52-54 notification with line-art Isko */}
        <Swap t={t} inB={52} outB={54} x={18} y={28}><IskoLine t={t} at={52} size={68} /></Swap>
        <Swap t={t} inB={53} outB={54} x={104} y={36}><T size={22} w={600} c={C.paper}>Leave at 12:50.</T></Swap>
        <Swap t={t} inB={53} outB={54} x={104} y={68} delay={0.12}><T size={15} c={C.inkMute}>N307 is a 6-min walk.</T></Swap>
        <Swap t={t} inB={54} outB={98} x={18} y={12} style={{ display: "flex", gap: 8, alignItems: "center", color: C.paper }}>
          <Icon name="arrowR" size={18} />
          <T size={15} w={560} c={C.paper} tab>Next · GEED 10053</T>
        </Swap>
        <Swap t={t} inB={98} outB={112} x={18} y={12} style={{ display: "flex", gap: 8, alignItems: "center", color: C.paper }}>
          <Icon name="wifiOff" size={18} />
          <T size={15} w={560} c={C.paper}>Offline · Isko still works</T>
        </Swap>
        <Swap t={t} inB={127.8} outB={132} x={18} y={12} style={{ display: "flex", gap: 8, alignItems: "center", color: C.paper }}>
          <Icon name="sun" size={18} />
          <T size={15} w={560} c={C.paper}>Theme</T>
        </Swap>
        <Swap t={t} inB={137.4} outB={152} x={18} y={12} style={{ display: "flex", gap: 8, alignItems: "center", color: C.paper }}>
          <Icon name="link" size={18} />
          <T size={15} w={560} c={C.paper}>PUP SIS</T>
        </Swap>
      </div>
    </>
  );
};

// ---------------------------------------------------------------- tab bar
const TABS = ["today", "grades", "note", "spark"] as const;
const TAB_W = 95, TAB_X0 = 20;
const tabL = (i: number): [number, number] => [TAB_X0 + i * TAB_W + 15, TAB_X0 + i * TAB_W + TAB_W - 15];
const TAB_KEYS: [number, number, number][] = [[0, ...tabL(0)], [55, ...tabL(1)], [71, ...tabL(2)], [128, ...tabL(0)]];

export const TabBar: React.FC<{ t: number; th: Th; on: [number, number][] }> = ({ t, th, on }) => {
  const [l, r] = indicator(t, TAB_KEYS);
  return (
    <>
      {on.map(([a, b]) => {
        const s = swapAlpha(t, a, b);
        if (!s.on) return null;
        return (
          <div key={a} style={{ ...abs, left: 0, top: 808, width: 420, height: 56, opacity: s.o, filter: s.blur > 0.05 ? `blur(${s.blur}px)` : undefined }}>
            <div style={{ ...abs, left: l, top: 6, width: r - l, height: 44, borderRadius: 22, background: th.fg }} />
            {TABS.map((n, i) => {
              const cx = TAB_X0 + i * TAB_W + TAB_W / 2;
              const cover = clamp((Math.min(r, cx + 12) - Math.max(l, cx - 12)) / 24);
              return (
                <div key={n} style={{ ...abs, left: cx - 12, top: 16 }}>
                  <Icon name={n} size={24} c={th.fg} style={{ ...abs, opacity: 1 - cover }} />
                  <Icon name={n} size={24} c={th.bg} style={{ opacity: cover }} />
                </div>
              );
            })}
          </div>
        );
      })}
    </>
  );
};

export const _unused = { MONO, Key: 0 as unknown as Key };
