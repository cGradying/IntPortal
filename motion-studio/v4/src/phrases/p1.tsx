// Phrase 1 · Hook (b0-27). Sign in -> spinner -> "Session expired" (x3) ->
// the card is dragged into a phone -> splash -> Island chip -> Today builds.
import React from "react";
import { B, SNAP, STD, clamp, spring, track } from "../lib/motion";
import { C, PH } from "../theme";
import { Swap, T, Rule, Roll, abs } from "../ui/kit";
import { Icon } from "../ui/Icon";
import type { Box, Phrase } from "../types";

// Session card geometry (centered at 960,540)
const CARD = { w: 620, h: 300 };
const CX0 = 960 - CARD.w / 2, CY0 = 540 - CARD.h / 2;
const BTN = { x: 40, y: 206, w: 168, h: 58 }; // local to the card

/** Spinner arc: three stepped turns on beats, plus a slow drift. */
const Spinner: React.FC<{ t: number; at: number; steps: number[]; out: number; c?: string; size?: number }> = ({ t, at, steps, out, c = C.paper, size = 34 }) => {
  let a = (t - B(at)) * 40;
  for (const b of steps) a += 120 * spring(t - B(b), SNAP);
  return (
    <Swap t={t} inB={at} outB={out} delay={0.08} style={{ left: "50%", top: "50%" }}>
      <svg width={size} height={size} viewBox="0 0 24 24" style={{ display: "block", transform: `translate(-50%,-50%) rotate(${a.toFixed(2)}deg)` }}>
        <circle cx={12} cy={12} r={9} stroke={c} strokeOpacity={0.22} strokeWidth={1.75} fill="none" />
        <path d="M12 3a9 9 0 0 1 9 9" stroke={c} strokeWidth={1.75} strokeLinecap="round" fill="none" />
      </svg>
    </Swap>
  );
};

/** Content laid out on a fixed-size frame centered inside the morphing box. */
export const Center: React.FC<{ box: Box; w: number; h: number; children: React.ReactNode }> = ({ box, w, h, children }) => (
  <div style={{ ...abs, left: box.w / 2 - w / 2, top: box.h / 2 - h / 2, width: w, height: h }}>{children}</div>
);

const Inside: React.FC<{ t: number; box: Box }> = ({ t, box }) => {
  if (t > B(21)) return null;
  return (
    <>
      {/* b0-3: the pill */}
      <Swap t={t} inB={-9} outB={4} style={{ inset: 0, display: "flex", alignItems: "center", justifyContent: "center" }}>
        <T size={30} w={560} c={C.paper} ls={-0.4}>Sign in</T>
      </Swap>
      {/* b4-6 and b9: spinner */}
      <Spinner t={t} at={4} steps={[5, 6]} out={7} />
      <Spinner t={t} at={9} steps={[9.5]} out={10} />
      {/* b7-15: session expired card */}
      <Center box={box} w={CARD.w} h={CARD.h}>
        {[[7, 9], [10, 13]].map(([a, o]) => (
          <React.Fragment key={a}>
            <Swap t={t} inB={a} outB={o} x={40} y={38}><Icon name="alert" size={30} c={C.ink} /></Swap>
            <Swap t={t} inB={a} outB={o} x={40} y={86} delay={0.1}><T size={36} w={600}>Session expired</T></Swap>
            <Swap t={t} inB={a} outB={o} x={40} y={136} delay={0.14}><T size={20} c={C.mute}>Sign in again to see today’s classes.</T></Swap>
            <Swap t={t} inB={a} outB={o} x={BTN.x} y={BTN.y} delay={0.18}>
              <div style={{ width: BTN.w, height: BTN.h, borderRadius: 29, background: C.ink, display: "flex", alignItems: "center", justifyContent: "center", transform: `scale(${1 - 0.04 * clamp(spring(t - B(8) + 0.06, SNAP) - spring(t - B(8) - 0.1, SNAP))})` }}>
                <T size={19} w={560} c={C.paper}>Try again</T>
              </div>
            </Swap>
          </React.Fragment>
        ))}
        {/* attempt counter: x2 then x3 */}
        <Swap t={t} inB={10} outB={13} x={CARD.w - 116} y={36} delay={0.12}>
          <div style={{ height: 40, padding: "0 14px", borderRadius: 20, background: C.wash, display: "flex", alignItems: "center", gap: 6 }}>
            <T size={17} c={C.mute}>Attempt</T>
            <Roll t={t} keys={[[10, "2"], [11, "3"]]} size={17} w={600} />
          </div>
        </Swap>
      </Center>
    </>
  );
};

// The phone's status bar and Island are drawn by the phone module.
export const p1: Phrase = {
  name: "p1",
  from: 0,
  to: 28,
  shape: [
    [2, { w: 288, h: 86 }], // hover
    [3.2, { w: 280, h: 84 }],
    [4, { w: 84, h: 84, r: 42 }], // pill -> circle
    [7, { w: CARD.w, h: CARD.h, r: 28 }], // circle -> card
    [9, { w: 84, h: 84, r: 42 }], // retry -> spinner
    [10, { w: CARD.w, h: CARD.h, r: 28 }],
    // drag the bottom-right corner (top-left stays put)
    [13, { cx: CX0 + 260, cy: CY0 + 295, w: 520, h: 590 }],
    // snap into the phone: corner stays under the cursor at (1170, 980)
    [14, { cx: PH.cx, cy: PH.cy, w: PH.w, h: PH.h, r: PH.r }],
  ],
  fill: [[4, C.ink], [7, C.paper], [9, C.ink], [10, C.paper]],
  lift: [[7, 1], [9, 0], [10, 1]],
  cam: [
    [7, { z: 1.45 }],
    [9, { z: 1.7 }],
    [10, { z: 1.45 }],
    [13, { cy: 600, z: 1.08 }],
    [15, { cx: 960, cy: 540, z: 1.12 }],
    [16, { cy: 500, z: 1.5 }],
    [20, { cy: 330, z: 1.9 }],
    [24, { cy: 540, z: 1.14 }],
  ],
  cur: [
    [0, 1066, 562], // leave C0 -> onto the pill
    [4, 1046, 590], // drift off the shrinking circle
    [7, CX0 + BTN.x + 120, CY0 + BTN.y + 34], // to "Try again"
    [9, 1030, 600],
    [11, CX0 + CARD.w - 6, CY0 + CARD.h - 6], // to the corner
    [13, CX0 + 520 - 6, CY0 + 590 - 6], // drag (locked to the corner)
    [14, 1170 - 6, 980 - 6],
    [15.2, 1240, 860], // release, move aside
    [20, 1180, 300],
  ],
  clicks: [3, 8],
  holds: [[12, 14.4]],
  events: [
    [0, "cursor leaves C0"], [1, "cursor lands on pill"], [2, "hover grow"], [3, "click Sign in"],
    [4, "pill -> circle"], [5, "spinner step"], [6, "spinner step"], [7, "circle -> Session expired card"],
    [8, "click Try again"], [9, "card -> spinner"], [10, "card back, attempt 2"], [11, "attempt 3"],
    [12, "grab corner"], [13, "drag taller"], [14, "radius 56, snaps to phone"], [15, "status bar in"],
    [16, "Int"], [17, "Portal"], [18, "divider draws"], [19, "tagline"],
    [20, "camera zooms to top"], [21, "Island chip grows"], [22, "chip text"], [23, "Isko peeks"],
    [24, "card 1"], [25, "card 2"], [26, "card 3"], [27, "card 4"],
  ],
  Inside,
};

/** Splash wordmark inside the phone (b16-20). */
export const Splash: React.FC<{ t: number; box: Box }> = ({ t, box }) => {
  if (t < B(15.5) || t > B(21)) return null;
  const pw = 172 * spring(t - B(17), STD); // "Portal" opens from width 0
  return (
    <Center box={box} w={PH.w} h={PH.h}>
      <Swap t={t} inB={16} outB={20} x={0} y={380} w={PH.w} style={{ display: "flex", justifyContent: "center" }}>
        <div style={{ display: "flex", alignItems: "baseline" }}>
          <T size={64} w={640} ls={-2.6}>Int</T>
          <div style={{ width: pw, overflow: "hidden" }}>
            <div style={{ opacity: clamp(spring(t - B(17) - 0.05, STD) * 1.2), filter: `blur(${(6 * (1 - clamp(spring(t - B(17), STD)))).toFixed(2)}px)` }}>
              <T size={64} w={640} ls={-2.6}>Portal</T>
            </div>
          </div>
        </div>
      </Swap>
      <Rule t={t} at={18} out={20} x={PH.w / 2 - 70} y={470} w={140} />
      <Swap t={t} inB={19} outB={20} x={0} y={492} w={PH.w} style={{ textAlign: "center" }}>
        <T size={19} c={C.mute} style={{ textAlign: "center" }}>your campus, in one place</T>
      </Swap>
    </Center>
  );
};

export const _track = track;
