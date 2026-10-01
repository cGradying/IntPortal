// b139.4-151.6: connect PUP SIS. One button: connect -> progress -> signed in;
// rows land; a "more campuses" chip grows from the button's edge and flips.
import React from "react";
import { B, SNAP, STD, clamp, spring, track } from "../lib/motion";
import { C } from "../theme";
import { Roll, Swap, T, abs } from "../ui/kit";
import { El, rectKeys } from "../ui/el";
import { Icon } from "../ui/Icon";

const IN = 139.4, OUT = 151.6;
export const BTN = rectKeys({ x: 20, y: 350, w: 380, h: 64, r: 32 }, [[143, { w: 210 }]]);
const CHIP = rectKeys({ x: 236, y: 350, w: 0, h: 64, r: 32 }, [[148, { w: 164 }], [150, { x: 400, w: 0 }]]);

export const Sis: React.FC<{ t: number }> = ({ t }) => {
  if (t < B(IN) - 0.1 || t > B(OUT) + 0.4) return null;
  const prog = track(t, [[0, 0], [140, 0.06], [141, 0.33], [142, 0.66], [143, 1]]);
  const flip = spring(t - B(149), STD);
  return (
    <>
      <Swap t={t} inB={IN} outB={OUT} x={24} y={68}><T size={14} c={C.mute}>Connect</T></Swap>
      <Swap t={t} inB={IN} outB={OUT} x={24} y={88} delay={0.06}><T size={30} w={620}>Your school</T></Swap>
      <Swap t={t} inB={IN} outB={OUT} x={20} y={150} w={380} h={180} delay={0.1} style={{ borderRadius: 24, background: C.wash }}>
        <div style={{ ...abs, left: 20, top: 20, width: 56, height: 56, borderRadius: 28, background: C.ink, display: "flex", alignItems: "center", justifyContent: "center" }}>
          <T size={15} w={700} c={C.paper} ls={0.4}>PUP</T>
        </div>
        <T size={19} w={600} lh={1.25} style={{ ...abs, left: 20, top: 92 }}>{"Polytechnic University\nof the Philippines"}</T>
        <T size={14} c={C.mute} style={{ ...abs, left: 92, top: 30 }}>Student Information System</T>
        <T size={14} c={C.mute} style={{ ...abs, left: 92, top: 50 }}>sis.pup.edu.ph</T>
      </Swap>
      {/* the button */}
      <El t={t} k={BTN} fill={[[0, C.ink]]} hide={t < B(IN)} style={{ opacity: clamp(spring(t - B(IN) - 0.08, { k: 260, d: 32 })) * (1 - clamp((t - B(OUT)) / 0.11)), transform: `scale(${1 - 0.04 * clamp(spring(t - B(140) + 0.06, SNAP) - spring(t - B(140) - 0.1, SNAP))})` }}>
        {(r) => (
          <>
            <Swap t={t} inB={IN} outB={140} x={0} y={0} w={r.w} h={r.h} style={{ display: "flex", alignItems: "center", justifyContent: "center", gap: 10, color: C.paper }}>
              <Icon name="link" size={20} /><T size={18} w={600} c={C.paper}>Connect PUP SIS</T>
            </Swap>
            <Swap t={t} inB={140} outB={143} x={0} y={0} w={r.w} h={r.h} style={{ display: "flex", alignItems: "center", justifyContent: "center", gap: 10 }}>
              <T size={18} w={600} c={C.paper}>Connecting</T>
              <Roll t={t} keys={[[140, "0%"], [141, "33%"], [142, "66%"]]} size={18} w={600} c={C.inkMute} />
            </Swap>
            <div style={{ ...abs, left: 0, bottom: 0, height: 3, width: r.w * prog, background: C.paper, opacity: 1 - clamp(spring(t - B(143.2), SNAP)) }} />
            <Swap t={t} inB={143} outB={OUT} x={0} y={0} w={r.w} h={r.h} style={{ display: "flex", alignItems: "center", justifyContent: "center", gap: 8, color: C.paper }}>
              <Icon name="check" size={20} /><T size={18} w={600} c={C.paper}>Signed in</T>
            </Swap>
          </>
        )}
      </El>
      {/* more campuses chip: grows from the button's edge, flips, folds away */}
      <El t={t} k={CHIP} fill={[[0, C.paper]]} style={{ outline: `1.5px dashed ${C.line2}`, outlineOffset: -1.5, transform: `perspective(600px) rotateX(${(180 * flip).toFixed(2)}deg)` }}>
        {(r) => (
          <div style={{ ...abs, left: 0, top: 0, width: r.w, height: r.h, transform: flip > 0.5 ? "scaleY(-1)" : undefined, display: "flex", flexDirection: "column", justifyContent: "center", paddingLeft: 20 }}>
            {flip < 0.5 ? (
              <><T size={15} w={600}>More campuses</T><T size={13} c={C.mute}>soon</T></>
            ) : (
              <><T size={15} w={600}>100+ schools</T><T size={13} c={C.mute}>on the way</T></>
            )}
          </div>
        )}
      </El>
      {/* synced rows */}
      {[["calendar", "Schedule", "7 classes"], ["grades", "Grades", "1st Sem · 1.28"], ["pin", "Rooms", "S512 · N307"]].map(([ic, a, v], i) => {
        const k = spring(t - B(144 + i), STD);
        return (
          <Swap key={a} t={t} inB={144 + i} outB={OUT} x={20 + 24 * (1 - k)} y={436 + i * 76} w={380} h={64} style={{ borderRadius: 18, background: C.wash }}>
            <div style={{ ...abs, left: 18, top: 20, color: C.ink }}><Icon name={ic} size={24} /></div>
            <T size={17} w={600} style={{ ...abs, left: 56, top: 21 }}>{a}</T>
            <T size={15} c={C.mute} tab style={{ ...abs, right: 18, top: 22 }}>{v}</T>
          </Swap>
        );
      })}
      <Swap t={t} inB={147} outB={OUT} x={24} y={672} style={{ display: "flex", gap: 8, alignItems: "center", color: C.mute }}>
        <div style={{ transform: `rotate(${(360 * spring(t - B(147), { k: 60, d: 15 })).toFixed(1)}deg)` }}><Icon name="refresh" size={18} /></div>
        <T size={14} c={C.mute}>Synced just now · works offline</T>
      </Swap>
    </>
  );
};
