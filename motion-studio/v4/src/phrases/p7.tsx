// Phrase 7 · Beta waitlist and the loop (b168-195). The PUP tile becomes the
// Beta Pass, faces fill in, the cursor types an email and joins, the pass
// becomes the wordmark, the wordmark becomes the "Sign in" pill of frame 0.
import React, { useMemo } from "react";
import { Img, staticFile } from "remotion";
import { B, SNAP, STD, clamp, spring } from "../lib/motion";
import { C, C0W } from "../theme";
import { Rule, Swap, T, abs, typed } from "../ui/kit";
import { El, rectKeys } from "../ui/el";
import { Icon } from "../ui/Icon";
import { Center } from "./p1";
import type { Box, Phrase } from "../types";
import { PEOPLE, face } from "../art/faces";

const PASS = { w: 680, h: 420 };
const X0 = 960 - PASS.w / 2, Y0 = 540 - PASS.h / 2;
const FIELD = { x: 32, y: 300, w: 400, h: 64 };
const JOIN = rectKeys({ x: 448, y: 300, w: 200, h: 64, r: 32 }, [[181, { x: 516, w: 64 }], [182, { x: 448, w: 200 }]]);

/** A pixel face as crisp SVG rects (20 x 24 sprite px). */
const Face: React.FC<{ i: number; s: number }> = ({ i, s }) => {
  const g = useMemo(() => face(PEOPLE[i]), [i]);
  return (
    <svg width={20 * s} height={24 * s} viewBox="0 0 20 24" shapeRendering="crispEdges" style={{ display: "block" }}>
      {g.flatMap((row, y) => row.map((c, x) => (c ? <rect key={`${x}-${y}`} x={x} y={y} width={1.02} height={1.02} fill={c} /> : null)))}
    </svg>
  );
};

const PassBody: React.FC<{ t: number; box: Box }> = ({ t, box }) => {
  if (t < B(167.6) || t > B(184.6)) return null;
  const shrink = t > B(182.8) ? Math.min(box.w / PASS.w, box.h / PASS.h) : 1;
  const email = typed(t, [[177, "you@"], [178, "you@school"], [179, "you@school.edu.ph"]]);
  const caret = t > B(176) && t < B(180) && ((t - B(176)) % (B(177) - B(176))) < 0.25;
  const stamp = spring(t - B(175), { k: 260, d: 32 });
  return (
    <Center box={box} w={PASS.w} h={PASS.h}>
      <div style={{ ...abs, inset: 0, transform: `scale(${shrink.toFixed(4)})`, transformOrigin: "50% 50%" }}>
        <Swap t={t} inB={168} outB={184} x={32} y={26}><T size={24} w={650} c={C.paper} ls={-0.8}>IntPortal</T></Swap>
        <Swap t={t} inB={168} outB={184} x={PASS.w - 210} y={32} w={178} style={{ textAlign: "right" }}>
          <T size={13} w={600} c={C.inkMute} ls={2} style={{ textAlign: "right" }}>BETA PASS · 2026</T>
        </Swap>
        <Rule t={t} at={168} out={184} x={32} y={72} w={PASS.w - 64} c={C.inkLine} />
        {PEOPLE.slice(0, 6).map((p, i) => {
          const k = spring(t - B(169 + i), STD);
          return (
            <Swap key={i} t={t} inB={169 + i} outB={184} delay={0} x={32 + i * 104} y={92}>
              <div style={{ width: 92, height: 108, borderRadius: 16, background: "#1D1D1F", display: "flex", alignItems: "flex-end", justifyContent: "center", overflow: "hidden", transform: `scale(${(0.9 + 0.1 * k).toFixed(3)})` }}>
                <Face i={i} s={4} />
              </div>
              <T size={13} c={C.inkMute} style={{ marginTop: 8, textAlign: "center", width: 92 }}>{p.name}</T>
            </Swap>
          );
        })}
        {/* the stamp: lands at scale 1 on a critically damped spring */}
        {stamp > 0.002 && t < B(184) && (
          <div style={{
            ...abs, left: 410, top: 112, padding: "8px 16px", border: `2.5px solid ${C.paper}`, borderRadius: 10, background: C.ink,
            opacity: clamp(stamp * 1.4) * (1 - clamp(spring(t - B(183.8), SNAP))), transform: `rotate(-8deg) scale(${(1.35 - 0.35 * stamp).toFixed(3)})`,
          }}>
            <T size={22} w={700} c={C.paper} ls={3}>EARLY ACCESS</T>
          </div>
        )}
        <Swap t={t} inB={168.6} outB={184} x={FIELD.x} y={FIELD.y} w={FIELD.w} h={FIELD.h} delay={0.1}
          style={{ borderRadius: 18, background: C.paper, boxShadow: t > B(176) && t < B(180.5) ? `0 0 0 3px ${C.inkLine}` : undefined }}>
          <div style={{ ...abs, left: 20, top: 20, color: C.mute }}><Icon name="mail" size={24} /></div>
          <div style={{ ...abs, left: 58, top: 20, display: "flex", alignItems: "center" }}>
            <T size={20} w={500} c={email ? C.ink : C.faint}>{email || "Your school email"}</T>
            <div style={{ width: 1.75, height: 24, background: C.ink, marginLeft: 2, opacity: caret ? 1 : 0 }} />
          </div>
        </Swap>
        <El t={t} k={JOIN} fill={[[0, C.paper]]} hide={t < B(168.6)}
          style={{ opacity: clamp(spring(t - B(168.6) - 0.12, { k: 260, d: 32 })) * (1 - clamp((t - B(184)) / 0.11)), transform: `scale(${1 - 0.05 * clamp(spring(t - B(180) + 0.06, SNAP) - spring(t - B(180) - 0.1, SNAP))})` }}>
          {(r) => (
            <>
              <Swap t={t} inB={168.6} outB={181} x={0} y={0} w={r.w} h={r.h} style={{ display: "flex", alignItems: "center", justifyContent: "center" }}>
                <T size={17} w={600}>Join the waitlist</T>
              </Swap>
              <Swap t={t} inB={181} outB={182} x={r.w / 2 - 12} y={r.h / 2 - 12}>
                <svg width={24} height={24} viewBox="0 0 24 24" style={{ transform: `rotate(${((t - B(181)) * 400).toFixed(1)}deg)` }}>
                  <circle cx={12} cy={12} r={9} stroke={C.ink} strokeOpacity={0.2} strokeWidth={1.75} fill="none" />
                  <path d="M12 3a9 9 0 0 1 9 9" stroke={C.ink} strokeWidth={1.75} strokeLinecap="round" fill="none" />
                </svg>
              </Swap>
              <Swap t={t} inB={182} outB={184} x={0} y={0} w={r.w} h={r.h} style={{ display: "flex", alignItems: "center", justifyContent: "center", gap: 8, color: C.ink }}>
                <Icon name="check" size={20} /><T size={17} w={600}>You’re in</T>
              </Swap>
            </>
          )}
        </El>
      </div>
    </Center>
  );
};

const Wordmark: React.FC<{ t: number; box: Box }> = ({ t, box }) => {
  if (t < B(183.6) || t > B(188.6)) return null;
  return (
    <Center box={box} w={760} h={280}>
      <Swap t={t} inB={184} outB={188} x={0} y={50} w={760} style={{ textAlign: "center" }}>
        <T size={96} w={650} ls={-4.2} style={{ textAlign: "center" }}>IntPortal</T>
      </Swap>
      <Rule t={t} at={186} out={188} x={380 - 60} y={176} w={120} />
      <Swap t={t} inB={185} outB={188} x={0} y={194} w={760} style={{ textAlign: "center" }}>
        <T size={30} w={500} c={C.mute} style={{ textAlign: "center" }}>Step through.</T>
      </Swap>
    </Center>
  );
};

const SignIn: React.FC<{ t: number; box: Box }> = ({ t }) => (
  t < B(188.6) ? null : (
    <Swap t={t} inB={189} style={{ inset: 0, display: "flex", alignItems: "center", justifyContent: "center" }}>
      <T size={30} w={560} c={C.paper} ls={-0.4}>Sign in</T>
    </Swap>
  )
);

/** Pixel Isko rises from behind the wordmark card, winks, sinks. */
const IskoWink: React.FC<{ t: number; box: Box }> = ({ t, box }) => {
  const up = spring(t - B(186.5), STD) - spring(t - B(188), SNAP);
  if (up < 0.002) return null;
  const wink = t > B(187) - 0.02 && t < B(187.55);
  return (
    <div style={{ ...abs, left: box.cx + box.w / 2 - 210, top: box.cy - box.h / 2 - 108 * up, width: 170, height: 112 }}>
      <Img src={staticFile(`isko/${wink ? "wink" : "open"}.png`)} style={{ width: 170, height: 112, imageRendering: "pixelated" }} />
    </div>
  );
};

const Caption: React.FC<{ t: number; box: Box }> = ({ t }) => (
  <Swap t={t} inB={192} outB={194} x={760} y={604} w={400} style={{ textAlign: "center" }}>
    <T size={17} c={C.mute} style={{ textAlign: "center" }}>Beta waitlist is open</T>
  </Swap>
);

export const p7: Phrase = {
  name: "p7",
  from: 168,
  to: 196,
  shape: [
    [183, { w: 600, h: 370, r: 30 }], // the pass shrinks
    [184, { w: 760, h: 280, r: 36 }], // -> wordmark card
    [188, { cx: 960, cy: 540, w: 280, h: 84, r: 42 }], // -> the pill of frame 0
    [191, { w: 288, h: 86 }], // hover
    [193, { w: 280, h: 84 }],
  ],
  fill: [[184, C.paper], [188, C.ink]],
  lift: [[184, 1], [188, 0]],
  cam: [
    [168, { cx: 960, cy: 540, z: 1.45 }],
    [175, { z: 1.55 }],
    [176, { cx: 960, cy: 600, z: 1.7 }],
    [183, { cx: 960, cy: 540, z: 1.55 }],
    [184, { z: 1.5 }],
    [188, { z: 1.8 }],
    [193, { z: 1.9 }],
  ],
  cur: [
    [168.4, 1380, 820],
    [175.2, X0 + FIELD.x + 230, Y0 + FIELD.y + 34], // email field
    [179.1, X0 + 448 + 120, Y0 + 300 + 36], // Join
    [182.6, 1360, 800],
    [189.4, 1066, 562], // hover the pill
    [193, C0W[0], C0W[1]], // home to C0 (rest)
  ],
  clicks: [176, 180],
  events: [
    [168, "tile -> Beta Pass"], [169, "face 1"], [170, "face 2"], [171, "face 3"],
    [172, "face 4"], [173, "face 5"], [174, "face 6"], [175, "EARLY ACCESS stamp"],
    [176, "click email"], [177, "you@"], [178, "school"], [179, ".edu.ph"],
    [180, "click Join"], [181, "spinner"], [182, "You're in"], [183, "pass shrinks"],
    [184, "wordmark"], [185, "Step through."], [186, "divider"], [187, "Isko winks"],
    [188, "card -> pill"], [189, "Sign in"], [190, "cursor glides to pill"], [191, "hover"],
    [192, "caption: waitlist open"], [193, "cursor heads home"], [194, "caption out"], [195, "rest at C0 (loop)"],
  ],
  Inside: ({ t, box }) => (
    <>
      <PassBody t={t} box={box} />
      <Wordmark t={t} box={box} />
      <SignIn t={t} box={box} />
    </>
  ),
  Under: IskoWink,
  Over: Caption,
};
