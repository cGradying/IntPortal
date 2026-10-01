// Phrase 5 · Sax solo (b112-139). The dot becomes Isko: the Shape itself
// (pebble + eyes), then a pixel sprite, ASCII, 3D obsidian (HyperFrames
// clips); then the phone is re-themed and dragged out to tablet, Mac, PC
// and back, and a halftone Isko peeks over its edge.
import React from "react";
import { OffthreadVideo, Sequence, staticFile } from "remotion";
import { B, FPS, SNAP, STD, clamp, spring } from "../lib/motion";
import { C, PH } from "../theme";
import { Swap, abs } from "../ui/kit";
import type { Box, Phrase } from "../types";
import clips from "../clips.json";
import { THEMES } from "../screens/chrome";

const CL = clips as unknown as Record<string, [number, number]>;

/** A HyperFrames alpha clip placed in world space at its beat window. */
export const Clip: React.FC<{ name: string; cx: number; cy: number; w: number; h: number; inB: number; outB: number; t: number }> = ({ name, cx, cy, w, h, inB, outB, t }) => {
  const [a, b] = CL[name];
  const from = Math.round(B(a) * FPS), dur = Math.round((B(b) - B(a)) * FPS);
  return (
    <Swap t={t} inB={inB} outB={outB} delay={0} x={cx - w / 2} y={cy - h / 2} w={w} h={h}>
      <Sequence from={from} durationInFrames={dur} layout="none">
        <OffthreadVideo src={staticFile(`clips/${name}.webm`)} transparent muted style={{ width: w, height: h, display: "block" }} />
      </Sequence>
    </Swap>
  );
};

// ---------------------------------------------------------------- pebble Isko (form 3)
const Pebble: React.FC<{ t: number; box: Box }> = ({ t, box }) => {
  if (t < B(111.8) || t > B(116.6)) return null;
  const open = spring(t - B(113), STD);
  const blink = clamp(spring(t - B(114), { k: 900, d: 60 }) - spring(t - B(114) - 0.09, { k: 600, d: 49 }));
  const eh = 46 * open * (1 - 0.9 * blink);
  return (
    <Swap t={t} inB={112} outB={116} x={0} y={0} w={box.w} h={box.h} delay={0}>
      {[-1, 1].map((s) => (
        <div key={s} style={{ ...abs, left: box.w / 2 + s * 42 - 14, top: box.h / 2 - 8 - eh / 2, width: 28, height: Math.max(eh, 0.01), borderRadius: 14, background: C.paper }} />
      ))}
    </Swap>
  );
};
const PebbleOver: React.FC<{ t: number; box: Box }> = ({ t, box }) => {
  if (t < B(112.8) || t > B(116.6)) return null;
  const m = spring(t - B(115), STD);
  const ant = spring(t - B(113.5), STD);
  const out = 1 - spring(t - B(116), SNAP);
  return (
    <>
      {[-1, 1].map((s) => (
        <div key={s} style={{
          ...abs, left: box.cx + s * (box.w / 2 + 34 * m) - 26, top: box.cy + 10 - 26, width: 52, height: 52, borderRadius: 26,
          background: C.ink, transform: `scale(${(m * out).toFixed(3)})`,
        }} />
      ))}
      {/* antenna: one stroke and Isko's gold spark (the only colour) */}
      <div style={{ ...abs, left: box.cx - 0.875, top: box.cy - box.h / 2 - 34 * ant, width: 1.75, height: 34 * ant * out, background: C.ink }} />
      <div style={{ ...abs, left: box.cx - 8, top: box.cy - box.h / 2 - 34 * ant - 14, width: 16, height: 16, background: "#F5B227", transform: `rotate(45deg) scale(${(ant * out).toFixed(3)})` }} />
    </>
  );
};

// ---------------------------------------------------------------- device reflow
type R = [number, number, number, number];
type Layout = { w: number; h: number; side: number; title: number; g: [number, number]; cards: R[] };
// card order: next class, free time, GWA, notes, Isko, week (PC only)
export const LAYOUT: Record<string, Layout> = {
  phone: { w: 420, h: 880, side: 0, title: 0, g: [24, 74], cards: [[20, 150, 380, 150], [20, 314, 380, 92], [20, 420, 185, 150], [215, 420, 185, 150], [20, 584, 380, 112], [400, 150, 0, 600]] },
  tablet: { w: 780, h: 580, side: 0, title: 0, g: [28, 48], cards: [[24, 120, 360, 200], [24, 332, 360, 100], [396, 120, 174, 160], [582, 120, 174, 160], [396, 292, 360, 264], [780, 120, 0, 400]] },
  mac: { w: 1200, h: 740, side: 220, title: 44, g: [252, 70], cards: [[248, 136, 440, 230], [248, 378, 440, 110], [700, 136, 220, 170], [932, 136, 244, 170], [700, 318, 476, 398], [1200, 136, 0, 500]] },
  pc: { w: 1560, h: 860, side: 240, title: 40, g: [272, 66], cards: [[264, 128, 520, 260], [264, 400, 520, 120], [796, 128, 240, 190], [1048, 128, 248, 190], [796, 330, 500, 506], [1308, 128, 228, 708]] },
};
export const DEV: [number, keyof typeof LAYOUT][] = [[0, "phone"], [132, "tablet"], [133, "mac"], [134, "pc"], [136, "tablet"], [137, "phone"]];

export const p5: Phrase = {
  name: "p5",
  from: 112,
  to: 140,
  shape: [
    [112, { w: 250, h: 214, r: 107 }], // dot -> pebble
    [116, { w: 560, h: 420, r: 44 }], // pixel frame (paper)
    [120, { w: 520, h: 520, r: 30 }], // ascii frame (ink)
    [124, { w: 600, h: 600, r: 300 }], // 3D stage (paper circle)
    [127.4, { w: PH.w, h: PH.h, r: PH.r }], // back to the phone
    // drag the corner: the shape grows about its center, the corner stays under the cursor
    [132, { w: LAYOUT.tablet.w, h: LAYOUT.tablet.h, r: 30 }],
    [133, { w: LAYOUT.mac.w, h: LAYOUT.mac.h, r: 16 }],
    [134, { w: LAYOUT.pc.w, h: LAYOUT.pc.h, r: 10 }],
    [136, { w: LAYOUT.tablet.w, h: LAYOUT.tablet.h, r: 30 }],
    [137, { w: PH.w, h: PH.h, r: PH.r }],
  ],
  // the phone background follows the theme the cursor picks
  fill: [[116, C.paper], [120, C.ink], [124, C.paper], [128, THEMES.dark.bg], [129, THEMES.paper.bg], [130, THEMES.contrast.bg], [131, THEMES.light.bg]],
  lift: [[116, 1], [120, 0], [124, 1]],
  cam: [
    [112, { z: 2.3 }],
    [116, { z: 1.7 }],
    [120, { z: 1.62 }],
    [124, { z: 1.45 }],
    [127.4, { z: 1.12 }],
    [132, { z: 1.2 }],
    [133, { z: 1.1 }],
    [134, { z: 0.96 }],
    [136, { z: 1.2 }],
    [137, { z: 1.12 }],
  ],
  cur: [
    [112, 1240, 700],
    // theme swatches (phone-local y 800 row): Dark, Paper, Contrast, Light
    ...[0, 1, 2, 3].map((i) => [127.1 + i, 960 - 96 + i * 64, 100 + 742] as [number, number, number]),
    [131.1, 960 + PH.w / 2 - 4, 540 + PH.h / 2 - 4], // to the corner
    [132, 960 + LAYOUT.tablet.w / 2 - 4, 540 + LAYOUT.tablet.h / 2 - 4],
    [133, 960 + LAYOUT.mac.w / 2 - 4, 540 + LAYOUT.mac.h / 2 - 4],
    [134, 960 + LAYOUT.pc.w / 2 - 4, 540 + LAYOUT.pc.h / 2 - 4],
    [136, 960 + LAYOUT.tablet.w / 2 - 4, 540 + LAYOUT.tablet.h / 2 - 4],
    [137, 960 + PH.w / 2 - 4, 540 + PH.h / 2 - 4],
    [137.6, 1260, 760],
  ],
  clicks: [128, 129, 130, 131],
  holds: [[131.8, 137.4]],
  events: [
    [112, "dot -> pebble"], [113, "eyes open"], [114, "blink"], [115, "mitts"],
    [116, "pixel Isko: happy"], [117, "wow"], [118, "wink"], [119, "focus"],
    [120, "ASCII Isko"], [121, "glyphs: binary"], [122, "glyphs: ISKO"], [123, "resolve to colour"],
    [124, "3D turn 90"], [125, "180"], [126, "270"], [127, "front"],
    [128, "theme: dark"], [129, "paper"], [130, "contrast"], [131, "light"],
    [132, "drag -> tablet"], [133, "-> Mac"], [134, "-> PC"], [135, "title draws"],
    [136, "back -> tablet"], [137, "-> phone"], [138, "halftone Isko"], [139, "solo ends"],
  ],
  Inside: ({ t, box }) => (
    <>
      <Pebble t={t} box={box} />
      {t > B(115.4) && t < B(120.6) && <Clip name="pixel" t={t} inB={115.9} outB={120} cx={box.w / 2} cy={box.h / 2} w={560} h={420} />}
      {t > B(119.4) && t < B(124.6) && <Clip name="ascii" t={t} inB={119.9} outB={124} cx={box.w / 2} cy={box.h / 2} w={520} h={520} />}
    </>
  ),
  Over: ({ t, box }) => (
    <>
      <PebbleOver t={t} box={box} />
      {t > B(123.4) && t < B(128.2) && <Clip name="obsidian" t={t} inB={123.8} outB={127.5} cx={960} cy={540} w={640} h={640} />}
      {t > B(137.4) && t < B(140.4) && <Clip name="halftone" t={t} inB={137.6} outB={140.2} cx={960 + PH.w / 2 + 30} cy={470} w={420} h={420} />}
    </>
  ),
};

export const _p5 = { clamp };
