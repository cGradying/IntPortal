// Grades (b55-71): the GWA rolls as grades land, rows land, the goal slider
// is dragged, and the slider becomes Isko's coach card.
import React from "react";
import { B, STD, clamp, spring, track } from "../lib/motion";
import { C } from "../theme";
import { Roll, Swap, T, abs } from "../ui/kit";
import { El, rectKeys } from "../ui/el";
import { Icon } from "../ui/Icon";

export const G_IN = 55.3, G_OUT = 71.2;

const ROWS = [
  ["COMP 20073", "Data Structures", "1.25"],
  ["MATH 20023", "Discrete Math", "1.50"],
  ["GEED 10053", "Art Appreciation", "1.00"],
  ["PATHFIT 2", "Fitness Exercises", "1.25"],
];
// slider: value -> x (2.00 at the left, 1.00 at the right)
export const SL = { x: 24, w: 332, y: 112 };
export const knobX = (v: number) => SL.x + ((2 - v) / 1) * SL.w;
export const GOAL: [number, number][] = [[0, 1.5], [65, 1.4], [66, 1.3], [67, 1.25]];
const card = rectKeys({ x: 20, y: 620, w: 380, h: 170, r: 28 }, [[68, { y: 600, h: 190 }]]);

export const Grades: React.FC<{ t: number }> = ({ t }) => {
  if (t < B(G_IN) - 0.1 || t > B(G_OUT) + 0.4) return null;
  const goal = track(t, GOAL.map(([b, v]) => [b, v]));
  const spark = clamp(spring(t - B(59), { k: 60, d: 15 }));
  return (
    <>
      <Swap t={t} inB={G_IN} outB={G_OUT} x={24} y={62}><T size={30} w={620}>Grades</T></Swap>
      <Swap t={t} inB={G_IN} outB={G_OUT} x={24} y={102} delay={0.08}><T size={14} c={C.mute}>1st Sem · 2025–26</T></Swap>
      {/* GWA card */}
      <Swap t={t} inB={G_IN} outB={G_OUT} x={20} y={136} w={380} h={200} style={{ borderRadius: 28, background: C.ink }}>
        <T size={14} c={C.inkMute} style={{ ...abs, left: 24, top: 22 }}>GWA so far</T>
        <div style={{ ...abs, left: 22, top: 44 }}>
          <Roll t={t} keys={[[G_IN, "3.00"], [56, "2.10"], [57, "1.60"], [58, "1.28"]]} size={76} w={620} c={C.paper} />
        </div>
        <Swap t={t} inB={58} outB={G_OUT} x={236} y={26}>
          <div style={{ height: 30, padding: "0 12px", borderRadius: 15, border: `1.5px solid ${C.inkLine}`, display: "flex", alignItems: "center", gap: 6, color: C.paper }}>
            <Icon name="arrowUp" size={14} /><T size={13} w={560} c={C.paper}>Dean’s list</T>
          </div>
        </Swap>
        <svg width={332} height={40} style={{ ...abs, left: 24, top: 146, overflow: "visible" }}>
          <path d="M0 6 L60 14 L120 22 L180 26 L240 30 L300 33 L332 34" stroke={C.paper} strokeWidth={1.75} fill="none" strokeLinecap="round" strokeLinejoin="round" pathLength={1} strokeDasharray={`${spark} 1`} />
          <circle cx={332} cy={34} r={4 * spark} fill={C.paper} />
        </svg>
      </Swap>
      {/* rows land one per beat */}
      {ROWS.map(([code, name, g], i) => {
        const k = spring(t - B(60 + i), STD);
        return (
          <Swap key={code} t={t} inB={60 + i} outB={G_OUT} x={20 + 24 * (1 - k)} y={350 + i * 64} w={380} h={56}>
            <T size={15} w={600} style={{ ...abs, left: 4, top: 8 }}>{code}</T>
            <T size={13} c={C.mute} style={{ ...abs, left: 4, top: 30 }}>{name}</T>
            <T size={22} w={600} tab style={{ ...abs, right: 4, top: 12 }}>{g}</T>
            <div style={{ ...abs, left: 4, right: 4, bottom: -4, height: 1, background: C.line }} />
          </Swap>
        );
      })}
      {/* goal slider -> coach card */}
      <El t={t} k={card} fill={[[0, C.wash], [68, C.ink]]} hide={t < B(63.4)} style={{ opacity: swapOpacity(t) }}>
        {() => (
          <>
            <Swap t={t} inB={63.4} outB={68} x={24} y={20}><T size={14} c={C.mute}>Goal GWA</T></Swap>
            <Swap t={t} inB={63.4} outB={68} x={24} y={42}><Roll t={t} keys={GOAL.map(([b, v]) => [b === 0 ? 63.4 : b, v.toFixed(2)])} size={30} w={620} /></Swap>
            <Swap t={t} inB={63.4} outB={68} x={210} y={20}><T size={14} c={C.mute}>Needed on 2 left</T></Swap>
            <Swap t={t} inB={63.4} outB={68} x={210} y={42}>
              <Roll t={t} keys={[[63.4, "1.94"], [65, "1.64"], [66, "1.34"], [67, "1.19"]]} size={30} w={620} />
            </Swap>
            <Swap t={t} inB={63.4} outB={68} x={0} y={0} w={380} h={170}>
              <div style={{ ...abs, left: SL.x, top: SL.y, width: SL.w, height: 1.75, background: C.line2 }} />
              <div style={{ ...abs, left: knobX(goal), top: SL.y, width: SL.x + SL.w - knobX(goal), height: 1.75, background: C.ink }} />
              <div style={{ ...abs, left: knobX(goal) - 14, top: SL.y - 13, width: 28, height: 28, borderRadius: 14, background: C.ink, border: `3px solid ${C.wash}` }} />
              <T size={12} c={C.faint} style={{ ...abs, left: SL.x, top: SL.y + 20 }}>2.00</T>
              <T size={12} c={C.faint} style={{ ...abs, right: 380 - SL.x - SL.w, top: SL.y + 20 }}>1.00</T>
            </Swap>
            {/* coach */}
            <Swap t={t} inB={68} outB={G_OUT} x={24} y={22} style={{ display: "flex", gap: 8, alignItems: "center", color: C.paper }}>
              <Icon name="spark" size={18} /><T size={14} c={C.inkMute}>Isko · coach</T>
            </Swap>
            <Swap t={t} inB={69} outB={G_OUT} x={24} y={56}><T size={40} w={620} c={C.paper}>Aim for 1.19</T></Swap>
            <Swap t={t} inB={70} outB={G_OUT} x={24} y={112}><T size={17} c={C.inkMute}>on the 2 subjects left.</T></Swap>
            <Swap t={t} inB={70} outB={G_OUT} x={24} y={142} delay={0.12}><T size={14} c={C.inkMute}>Start with MATH 20023 — 3 units.</T></Swap>
          </>
        )}
      </El>
    </>
  );
};

const swapOpacity = (t: number) => clamp(spring(t - B(63.4) - 0.05, { k: 260, d: 32 })) * (1 - clamp((t - B(G_OUT)) / 0.11));
