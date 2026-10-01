// Today (b24-31) -> day timeline (b32-55): cards grow out of each other's
// edges, the next class opens into a hero, the list is dragged, the free
// block opens into a sheet, the week strip is scrubbed, a class opens.
import React from "react";
import { B, SNAP, SOFT, STD, clamp, indicator, spring, track, trackS } from "../lib/motion";
import { C } from "../theme";
import { Roll, Rule, Swap, T, abs } from "../ui/kit";
import { El, rectKeys } from "../ui/el";
import { Icon } from "../ui/Icon";

const OUT = 55.2;
// scrolling content is clipped below this phone-local y (the week strip);
// before the timeline exists nothing sits above it but the greeting
const CLIP = 140; // the whole Today tab leaves when Grades opens

// scroll of the day timeline (dragged b32-35, momentum on release)
export const SCROLL: [number, number, typeof SOFT?][] = [[0, 0], [33, -60], [34, -150], [35, -200, SOFT]];
const scroll = (t: number) => trackS(t, SCROLL);

// ---------------------------------------------------------------- rects
const card1 = rectKeys({ x: 20, y: 150, w: 380, h: 0, r: 28 }, [
  [24, { h: 150 }],
  [28, { h: 330 }], // hero
  [32, { x: 76, w: 324, h: 120, r: 20 }], // becomes the first timeline block
]);
const card2 = rectKeys({ x: 20, y: 300, w: 380, h: 0, r: 24 }, [
  [25, { y: 314, h: 92 }],
  [28, { y: 494 }],
  [32, { x: 76, y: 410, w: 324, h: 120, r: 20 }], // the free block
]);
const card3 = rectKeys({ x: 20, y: 406, w: 185, h: 0, r: 24 }, [[26, { y: 420, h: 150 }], [28, { y: 600 }]]);
const card4 = rectKeys({ x: 205, y: 420, w: 0, h: 150, r: 24 }, [[27, { x: 215, w: 185 }], [28, { y: 600 }]]);

// timeline rows (besides card1 / card2), y in scroll space
const ROWS = [
  { t: "7:30", y: 150 }, { t: "9:00", y: 280 }, { t: "10:30", y: 410 }, { t: "12:00", y: 540 },
  { t: "13:00", y: 630 }, { t: "14:30", y: 760 }, { t: "16:00", y: 890 },
];
const BLOCKS = [
  { y: 280, h: 120, i: 1 }, { y: 540, h: 80, i: 3 }, { y: 630, h: 120, i: 4 }, { y: 760, h: 120, i: 5 }, { y: 890, h: 120, i: 6 },
];
// day content for the scrubbed week strip: [Tue, Wed, Thu, Fri]
const DAY_INDEX: [number, number][] = [[0, 0], [44, 1], [45, 2], [46, 3], [47, 0]];
const DAYS = [
  ["Data Structures", "Discrete Math", "Free", "Lunch", "GEED 10053", "MATH 20023", "PATHFIT 2"],
  ["Web Dev", "Free", "Statistics", "Lunch", "Org Meeting", "Free", "NSTP"],
  ["Data Structures", "Discrete Math", "Lab · S510", "Lunch", "Free", "MATH 20023", "Free"],
  ["Free", "Physics", "Physics Lab", "Lunch", "GEED 10053", "Free", "Free"],
];
const ROOMS = ["S512", "S308", "", "", "N307", "S204", "Gym"];
const dayAt = (t: number) => { let d = 0; for (const [b, v] of DAY_INDEX) if (t >= B(b) - 0.05) d = v; return d; };

// the free block opens into a sheet and is dragged back down
const SHEET = rectKeys({ x: 76, y: 210, w: 324, h: 120, r: 20 }, [
  [37, { x: 8, y: 420, w: 404, h: 452, r: 36 }],
  [41, { y: 600, h: 272 }],
  [42, { x: 76, y: 210, w: 324, h: 120, r: 20 }],
]);
// a class block opens into a detail view
const DETAIL = rectKeys({ x: 76, y: 430, w: 324, h: 120, r: 20 }, [
  [49, { x: 8, y: 56, w: 404, h: 744, r: 40 }],
  [51, { x: 76, y: 430, w: 324, h: 120, r: 20 }],
]);

// week strip: Tue Wed Thu Fri (+ Mon at the left)
const WD = ["Mon", "Tue", "Wed", "Thu", "Fri"];
const cell = (i: number): [number, number] => [20 + i * 76 + 4, 20 + i * 76 + 72];
const WEEK: [number, number, number][] = [[0, ...cell(1)], [44, ...cell(2)], [45, ...cell(3)], [46, ...cell(4)], [47, ...cell(1)]];

const Label: React.FC<{ a: string; b?: string; c?: string; m?: string; size?: number }> = ({ a, b, c = C.ink, m = C.mute, size = 17 }) => (
  <div>
    <T size={size} w={600} c={c}>{a}</T>
    {b && <T size={14} c={m} style={{ marginTop: 4 }}>{b}</T>}
  </div>
);

export const Today: React.FC<{ t: number }> = ({ t }) => {
  if (t < B(23.5) || t > B(OUT) + 0.4) return null;
  const sc = scroll(t);
  const day = dayAt(t);
  // swap windows for day-dependent text: one per scrub segment
  const SEG = DAY_INDEX.map(([b, d], i) => ({ d, a: i === 0 ? 32 : b, o: DAY_INDEX[i + 1]?.[0] ?? OUT }));
  const sheetOpen = t > B(36.6) && t < B(42.7);
  const scrim = clamp(spring(t - B(37)) - spring(t - B(42))) * 0.16 + clamp(spring(t - B(49)) - spring(t - B(51))) * 0.16;
  return (
    <>
      {/* greeting (Today) */}
      <Swap t={t} inB={24} outB={32} x={24} y={70}><T size={14} c={C.mute}>Tuesday, 12 August</T></Swap>
      <Swap t={t} inB={24} outB={32} x={24} y={92} delay={0.1}><T size={30} w={620}>Good morning, Aya</T></Swap>

      {/* ---- scrolling content, clipped under the week strip ---- */}
      <div style={{ ...abs, left: 0, top: CLIP, width: 420, height: 880 - CLIP, overflow: "hidden" }}>
      <div style={{ ...abs, left: 0, top: -CLIP, width: 420, height: 880 }}>
      {ROWS.map((r, i) => (
        <Swap key={i} t={t} inB={32} outB={OUT} delay={0.04 * i} x={22} y={r.y + sc + 4}><T size={14} c={C.mute} tab>{r.t}</T></Swap>
      ))}
      {BLOCKS.map((b, j) => (
        <Swap key={j} t={t} inB={32} outB={OUT} delay={0.05 + 0.04 * j} x={76} y={b.y + sc} w={324} h={b.h}
          style={{ borderRadius: 20, background: DAYS[day][b.i] === "Free" ? undefined : C.wash, border: DAYS[day][b.i] === "Free" ? `1.5px dashed ${C.line2}` : undefined }}>
          {SEG.map(({ d, a, o }) => (
            <Swap key={a} t={t} inB={a} outB={o} x={18} y={16}>
              <Label a={DAYS[d][b.i]} b={DAYS[d][b.i] === "Free" ? "Open time" : ROOMS[b.i] ? `Room ${ROOMS[b.i]}` : undefined} />
            </Swap>
          ))}
        </Swap>
      ))}

      {/* card 1: next class -> hero -> first block */}
      <El t={t} k={card1} fill={[[0, C.ink]]} dy={t > B(31.5) ? sc : 0}>
        {(r) => (
          <>
            <Swap t={t} inB={24} outB={28} x={22} y={20}><T size={14} c={C.inkMute}>Next class</T></Swap>
            <Swap t={t} inB={28} outB={32} x={22} y={20}><T size={14} c={C.inkMute}>Now · Data Structures</T></Swap>
            <Swap t={t} inB={24} outB={28} x={22} y={44} delay={0.1}><T size={26} w={600} c={C.paper}>Data Structures</T></Swap>
            <Swap t={t} inB={24} outB={28} x={22} y={82} delay={0.14}><T size={15} c={C.inkMute} tab>COMP 20073 · S512 · 7:30</T></Swap>
            <Swap t={t} inB={24} outB={28} x={r.w - 92} y={20} delay={0.18}>
              <div style={{ width: 72, height: 72, borderRadius: 36, border: `1.75px solid ${C.inkLine}`, display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center" }}>
                <T size={26} w={600} c={C.paper} tab>9</T><T size={11} c={C.inkMute}>min</T>
              </div>
            </Swap>
            {/* hero */}
            <Swap t={t} inB={28} outB={32} x={22} y={52}><T size={30} w={600} c={C.paper}>Data Structures</T></Swap>
            <Swap t={t} inB={28.6} outB={32} x={20} y={98}>
              <Roll t={t} keys={[[28, "0:00"], [29, "7:30"]]} size={88} w={620} c={C.paper} />
            </Swap>
            <Swap t={t} inB={30} outB={32} x={24} y={204}>
              <div style={{ height: 34, padding: "0 14px", borderRadius: 17, background: C.paper, display: "inline-flex", alignItems: "center" }}>
                <T size={15} w={600}>in 9 min · S512, 5F</T>
              </div>
            </Swap>
            <Swap t={t} inB={30.6} outB={32} x={24} y={262} w={332} h={44}>
              <div style={{ ...abs, left: 0, top: 22, width: 332, height: 6, borderRadius: 3, background: C.inkLine }} />
              <div style={{ ...abs, left: 0, top: 22, width: 332 * 0.62 * spring(t - B(31), STD), height: 6, borderRadius: 3, background: C.paper }} />
              <T size={13} c={C.inkMute} style={{ ...abs, left: 0, top: 0 }}>7:30</T>
              <T size={13} c={C.inkMute} style={{ ...abs, right: 0, top: 0 }}>Free at 10:30</T>
            </Swap>
            {/* as a timeline block */}
            <Swap t={t} inB={32} outB={OUT} x={18} y={16}><Label a="Data Structures" b="Room S512 · now" c={C.paper} m={C.inkMute} /></Swap>
          </>
        )}
      </El>

      {/* card 2: free time -> free block */}
      <El t={t} k={card2} fill={[[0, C.wash], [32, "#FFFFFF"]]} dy={t > B(31.5) ? sc : 0}
        style={{ border: t > B(32) ? `1.5px dashed ${C.line2}` : undefined }}>
        {() => (
          <>
            <Swap t={t} inB={25} outB={32} x={20} y={22} style={{ display: "flex", gap: 14 }}>
              <Icon name="clock" size={26} c={C.ink} style={{ marginTop: 6 }} />
              <Label a="1h 30m free" b="10:30 – 12:00 · Library is 3 min away" />
            </Swap>
            <Swap t={t} inB={32} outB={OUT} x={18} y={16}><Label a="Free · 1h 30m" b="Tap to plan it" /></Swap>
          </>
        )}
      </El>
      {/* cards 3 + 4 */}
      <El t={t} k={card3} fill={[[0, C.wash]]} hide={t > B(32.5)} style={{ opacity: 1 - clamp(spring(t - B(32), SNAP)) }}>
        {() => (
          <>
            <Swap t={t} inB={26} outB={32} x={20} y={20}><T size={14} c={C.mute}>GWA</T></Swap>
            <Swap t={t} inB={26} outB={32} x={20} y={44} delay={0.1}><T size={44} w={620} tab>1.28</T></Swap>
            <Swap t={t} inB={26} outB={32} x={20} y={110} delay={0.14}><T size={13} c={C.mute}>Dean’s list pace</T></Swap>
          </>
        )}
      </El>
      <El t={t} k={card4} fill={[[0, C.wash]]} hide={t > B(32.5)} style={{ opacity: 1 - clamp(spring(t - B(32), SNAP)) }}>
        {() => (
          <>
            <Swap t={t} inB={27} outB={32} x={20} y={20}><Icon name="note" size={24} c={C.ink} /></Swap>
            <Swap t={t} inB={27} outB={32} x={20} y={62} delay={0.1}><Label a="BST review" b="12 cards due" /></Swap>
          </>
        )}
      </El>

      </div>
      </div>

      {/* week strip header */}
      <Swap t={t} inB={32} outB={OUT} x={0} y={56} w={420} h={84} style={{ background: C.paper }}>
        <WeekStrip t={t} />
      </Swap>
      <Swap t={t} inB={32} outB={OUT} x={20} y={139} w={380} h={1} style={{ background: C.line }} />

      {/* scrim for sheet and detail (flat, no gradient) */}
      {scrim > 0.002 && <div style={{ ...abs, inset: 0, background: `rgba(11,11,12,${scrim.toFixed(3)})` }} />}

      {/* the sheet */}
      {sheetOpen && (
        <El t={t} k={SHEET} fill={[[0, "#FFFFFF"]]} lift={[[36.6, 0], [37, 1], [42, 0]]}>
          {(r) => (
            <>
              <div style={{ ...abs, left: r.w / 2 - 20, top: 10, width: 40, height: 5, borderRadius: 3, background: C.line2 }} />
              <Swap t={t} inB={38} outB={42} x={24} y={34}><T size={32} w={620}>1h 30m free</T></Swap>
              <Swap t={t} inB={38} outB={42} x={24} y={76} delay={0.1}><T size={15} c={C.mute} tab>10:30 – 12:00 · before GEED 10053</T></Swap>
              {[["book", "Library · 3 min", "Quiet floor, 42 seats open"], ["cards", "Review BST · 20 min", "12 cards due today"]].map(([ic, a, b], i) => (
                <Swap key={i} t={t} inB={39} outB={41} delay={0.12 * i} x={16} y={124 + i * 88} w={372} h={76} style={{ borderRadius: 20, background: C.wash }}>
                  <div style={{ ...abs, left: 16, top: 16, width: 44, height: 44, borderRadius: 22, background: C.paper, display: "flex", alignItems: "center", justifyContent: "center" }}><Icon name={ic} size={22} c={C.ink} /></div>
                  <div style={{ ...abs, left: 74, top: 16 }}><Label a={a} b={b} /></div>
                </Swap>
              ))}
            </>
          )}
        </El>
      )}

      {/* the class detail */}
      {t > B(48.6) && t < B(51.8) && (
        <El t={t} k={DETAIL} fill={[[0, C.wash], [49, C.ink], [51, C.wash]]} lift={[[48.6, 0], [49, 1], [51, 0]]}>
          {(r) => (
            <>
              <Swap t={t} inB={49} outB={51} x={28} y={30}><T size={14} c={C.inkMute}>13:00 – 14:30 · in 4h</T></Swap>
              <Swap t={t} inB={49} outB={51} x={28} y={54} delay={0.08}><T size={34} w={620} c={C.paper}>GEED 10053</T></Swap>
              <Swap t={t} inB={50} outB={51} x={28} y={104}><T size={22} w={560} c={C.paper}>Room N307 · 3F</T></Swap>
              <Swap t={t} inB={50} outB={51} x={28} y={136} delay={0.08}><T size={15} c={C.inkMute}>North Wing · 6 min walk</T></Swap>
              {/* floor map: one stroke weight, drawn on */}
              <Swap t={t} inB={50} outB={51} x={28} y={196} w={r.w - 56} h={360} delay={0.04}>
                <FloorMap t={t} at={50} />
              </Swap>
            </>
          )}
        </El>
      )}

    </>
  );
};

const WeekStrip: React.FC<{ t: number }> = ({ t }) => {
  const [l, r] = indicator(t, WEEK);
  return (
    <div style={{ ...abs, left: 0, top: 12, width: 420, height: 56 }}>
      <div style={{ ...abs, left: l, top: 0, width: r - l, height: 56, borderRadius: 18, background: C.ink }} />
      {WD.map((d, i) => {
        const [a, b] = cell(i);
        const cover = clamp((Math.min(r, b) - Math.max(l, a)) / (b - a));
        const date = String(11 + i);
        return (
          <div key={d} style={{ ...abs, left: a, top: 8, width: b - a, textAlign: "center" }}>
            {[0, 1].map((k) => (
              <div key={k} style={{ ...abs, left: 0, top: 0, width: b - a, opacity: k ? cover : 1 - cover }}>
                <T size={12} w={500} c={k ? C.inkMute : C.mute} style={{ textAlign: "center" }}>{d}</T>
                <T size={18} w={600} c={k ? C.paper : C.ink} tab style={{ textAlign: "center", marginTop: 2 }}>{date}</T>
              </div>
            ))}
          </div>
        );
      })}
    </div>
  );
};

const FloorMap: React.FC<{ t: number; at: number }> = ({ t, at }) => {
  const d = clamp(spring(t - B(at), { k: 50, d: 14 }));
  const p = { stroke: C.paper, strokeOpacity: 0.9, strokeWidth: 1.75, fill: "none", pathLength: 1, strokeDasharray: `${d} 1`, strokeLinecap: "round" as const, strokeLinejoin: "round" as const };
  const pin = spring(t - B(at) - 0.25, STD);
  return (
    <svg width={348} height={360} viewBox="0 0 348 360" style={{ display: "block", overflow: "visible" }}>
      <path {...p} d="M8 8h332v344H8z" />
      <path {...p} d="M8 150h120M220 150h120M128 8v142M220 8v142M8 250h332M174 250v102" />
      <path {...p} d="M128 110h-20M220 110h20" strokeOpacity={0.5} />
      <path {...p} d="M60 352V300M300 300v52" strokeOpacity={0.5} />
      <g transform={`translate(270 76) scale(${pin.toFixed(3)})`}>
        <circle r={20} fill={C.paper} />
        <circle r={6} fill={C.ink} />
      </g>
      <path {...p} d="M174 330V200h96v-100" strokeDasharray={`${d * 0.05} 0.04`} strokeOpacity={0.7} />
      <text x={150} y={204} fill={C.paper} fillOpacity={0.6 * d} fontSize={13} fontFamily="Geist">You</text>
      <text x={244} y={44} fill={C.paper} fillOpacity={d} fontSize={13} fontWeight={600} fontFamily="Geist">N307</text>
    </svg>
  );
};

export const _today = { track, Rule };
