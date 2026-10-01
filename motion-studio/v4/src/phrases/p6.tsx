// Phrase 6 · PUP SIS + campuses (b140-167). The phone connects, then shrinks
// into the PUP tile; a stack of school tiles builds behind it, deals into a
// page, pages turn, and the camera dives back into the PUP tile.
import React from "react";
import { B, SNAP, STD, clamp, lerp, spring } from "../lib/motion";
import { C, P } from "../theme";
import { Roll, Swap, T, abs } from "../ui/kit";
import type { Box, Phrase } from "../types";
import { MAJORS, SCHOOLS } from "../data/schools";

// grid: 8 x 4 tiles per page
export const TW = 196, TH = 108, GAP = 14, COLS = 8, ROWS = 4;
const GW = COLS * TW + (COLS - 1) * GAP, GH = ROWS * TH + (ROWS - 1) * GAP;
const GX = 960 - GW / 2, GY = 560 - GH / 2;
export const cellC = (c: number, r: number): [number, number] => [GX + c * (TW + GAP) + TW / 2, GY + r * (TH + GAP) + TH / 2];
const [PUPX, PUPY] = cellC(0, 0);

const NAMES = [
  ...MAJORS.map((m) => ({ a: m.name, b: m.sub })),
  ...SCHOOLS.map((s) => ({ a: s.name, b: s.pub ? "Public" : "Private" })),
];
const FLIPS = [160, 162, 164]; // page turns
const school = (page: number, i: number) => NAMES[(page * 31 + i) % NAMES.length];

const StackAndTiles: React.FC<{ t: number; box: Box }> = ({ t }) => {
  if (t < B(151.6) || t > B(168.6)) return null;
  const count = (b: number, n: number) => spring(t - B(b), STD) * n;
  const layers = 3 + count(153, 3) + count(154, 4) + count(155, 4); // drawn layers, not schools
  const dealt = spring(t - B(156), SNAP);
  const out = 1 - clamp(spring(t - B(168), SNAP));
  const out2 = (1 - clamp(spring(t - B(156.3), SNAP))) * clamp(spring(t - B(152), STD));
  return (
    <>
      {/* the stack behind the PUP tile */}
      {out2 > 0.01 && Array.from({ length: 14 }, (_, k) => {
        const vis = clamp(layers - k);
        if (vis <= 0) return null;
        const i = 14 - k; // draw back to front
        return (
          <div key={k} style={{
            ...abs, left: 960 - 130 + i * 3, top: 540 - 75 - i * 9, width: 260 - i * 6, height: 150, borderRadius: 22,
            background: C.paper, outline: `1px solid ${C.line2}`, outlineOffset: -1, opacity: out2 * clamp(layers - i),
          }} />
        );
      })}
      {/* dealt tiles: row r leaves the stack on beat 156 + r */}
      {dealt > 0.001 && Array.from({ length: COLS * ROWS }, (_, i) => {
        if (i === 0) return null; // the PUP tile is the Shape
        const c = i % COLS, r = Math.floor(i / COLS);
        const k = spring(t - B(156 + r) - c * 0.025, STD);
        if (k <= 0.001) return null;
        const [x, y] = cellC(c, r);
        const cx = lerp(960, x, k), cy = lerp(540, y, k);
        // page turns: each tile flips, column by column
        let ang = 0;
        for (const f of FLIPS) ang += 180 * spring(t - B(f) - c * 0.03, STD);
        const page = Math.floor((ang + 90) / 180);
        const s = school(page, i);
        return (
          <div key={i} style={{
            ...abs, left: cx - TW / 2, top: cy - TH / 2, width: TW, height: TH, borderRadius: 16, background: C.paper,
            outline: `1px solid ${C.line}`, outlineOffset: -1, opacity: clamp(k * 3) * out,
            transform: `perspective(900px) rotateY(${ang.toFixed(2)}deg) scale(${lerp(0.82, 1, k).toFixed(3)})`,
          }}>
            <div style={{ ...abs, inset: 0, padding: "16px 16px", transform: page % 2 ? "scaleX(-1)" : undefined }}>
              <T size={15} w={600} style={{ overflow: "hidden", textOverflow: "ellipsis", width: TW - 32 }}>{s.a}</T>
              <T size={12} c={C.mute} style={{ marginTop: 6, overflow: "hidden", textOverflow: "ellipsis", width: TW - 32, whiteSpace: "nowrap" }}>{s.b}</T>
              <div style={{ ...abs, left: 16, bottom: 14, height: 22, padding: "0 9px", borderRadius: 11, border: `1.25px solid ${C.line2}`, display: "flex", alignItems: "center" }}>
                <T size={11} w={560} c={C.mute}>Soon</T>
              </div>
            </div>
          </div>
        );
      })}
    </>
  );
};

/** PUP tile content inside the Shape (b152-168). */
const Tile: React.FC<{ t: number; box: Box }> = ({ t, box }) => {
  if (t < B(151.6) || t > B(168.6)) return null;
  return (
    <>
      <Swap t={t} inB={152} outB={168} x={18} y={16}><T size={17} w={650} c={C.paper}>PUP</T></Swap>
      <Swap t={t} inB={152} outB={168} x={18} y={40} delay={0.06}><T size={12} c={C.inkMute} style={{ width: box.w - 36, overflow: "hidden" }}>Polytechnic University</T></Swap>
      <Swap t={t} inB={152} outB={168} x={18} y={box.h - 36} delay={0.1} style={{ display: "flex", gap: 6, alignItems: "center" }}>
        <div style={{ width: 8, height: 8, borderRadius: 4, background: C.paper }} />
        <T size={12} w={560} c={C.paper}>Live now</T>
      </Swap>
    </>
  );
};

/** The counter chip: stack height, then schools shown, then 100+. */
const Counter: React.FC<{ t: number; box: Box }> = ({ t }) => {
  if (t < B(152.6) || t > B(168.6)) return null;
  const toGrid = spring(t - B(156), STD);
  const y = lerp(330, GY - 64, toGrid);
  return (
    <>
      <Swap t={t} inB={153} outB={168} x={960 - 120} y={y - 26} w={240} h={52} style={{ display: "flex", justifyContent: "center" }}>
        <div style={{ height: 52, padding: "0 22px 0 20px", borderRadius: 26, background: C.ink, display: "flex", alignItems: "center", gap: 10 }}>
          <Roll t={t} keys={[[153, " 8"], [154, "16"], [155, "32"], [161, "64"], [163, "96"], [165, "100+"]]} size={24} w={620} c={C.paper} />
          <T size={16} c={C.inkMute}>campuses</T>
        </div>
      </Swap>
      <Swap t={t} inB={166} outB={168} x={0} y={GY + GH + 30} w={1920} style={{ textAlign: "center" }}>
        <T size={40} w={620} style={{ textAlign: "center" }}>Universities and colleges, public and private.</T>
        <T size={24} c={C.mute} style={{ textAlign: "center", marginTop: 8 }}>Not connected yet — PUP SIS is first.</T>
      </Swap>
    </>
  );
};

export const p6: Phrase = {
  name: "p6",
  from: 140,
  to: 168,
  shape: [
    [152, { w: 260, h: 150, r: 22 }], // phone -> PUP tile
    [156, { cx: PUPX, cy: PUPY, w: TW, h: TH, r: 16 }], // dealt into the page's first cell
    [168, { cx: 960, cy: 540, w: 680, h: 420, r: 32 }], // -> Beta pass
  ],
  fill: [[152, C.ink]],
  lift: [[151.6, 0]],
  cam: [
    [139.2, { cy: 470, z: 1.5 }],
    [144, { cy: 600, z: 1.45 }],
    [148, { cy: 500, z: 1.65 }],
    [151, { cy: 540, z: 1.05 }],
    [152, { cy: 480, z: 1.6 }],
    [156, { cy: 560, z: 1.0 }],
    [167, { cx: PUPX, cy: PUPY, z: 2.6 }],
  ],
  cur: [
    [138.8, ...P(260, 382)] as [number, number, number], // Connect button
    [141, ...P(330, 520)] as [number, number, number],
    [151.3, 1240, 800],
    [155.4, 1500, 900],
  ],
  clicks: [140],
  events: [
    [140, "click Connect PUP SIS"], [141, "33%"], [142, "66%"], [143, "Signed in"],
    [144, "Schedule synced"], [145, "Grades synced"], [146, "Rooms synced"], [147, "synced just now"],
    [148, "more campuses chip grows"], [149, "chip flips"], [150, "chip folds"], [151, "camera pulls out"],
    [152, "phone -> PUP tile, stack"], [153, "8"], [154, "16"], [155, "32"],
    [156, "deal row 1"], [157, "row 2"], [158, "row 3"], [159, "row 4"],
    [160, "page 2"], [161, "64"], [162, "page 3"], [163, "96"],
    [164, "page 4"], [165, "100+"], [166, "not connected yet"], [167, "dive into PUP tile"],
  ],
  Inside: Tile,
  Under: StackAndTiles,
  Over: Counter,
};
