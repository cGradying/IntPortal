// Notes + on-device AI (b71-111). One note, one black pill that becomes the
// command bar, the answer, a flashcard, a quiz and a plan.
import React from "react";
import { B, SNAP, STD, clamp, hash, lerp, spring, track } from "../lib/motion";
import { C } from "../theme";
import { Swap, T, abs, typed } from "../ui/kit";
import { El, rectAt, rectKeys } from "../ui/el";
import { Icon } from "../ui/Icon";

export const N_IN = 71.3, N_OUT = 111;

// ---------------------------------------------------------------- note
export const NOTE = rectKeys({ x: 20, y: 132, w: 380, h: 0, r: 24 }, [
  [72, { h: 520 }],
  [92, { h: 150 }], // shrinks into a sources strip above the answer
]);
export const LINES = [
  "A BST keeps left < node < right.",
  "Balanced: subtree heights differ by ≤ 1.",
  "AVL trees rotate to stay balanced.",
  "Search stays O(log n).",
  "Rotations: LL, RR, LR, RL.",
  "Insert first, then rebalance.",
];
export const LINE_Y = (i: number) => 96 + i * 48; // note-local, text top
// approximate rendered widths (16px Geist), used for selection ends
export const LINE_W = [252, 318, 270, 176];

// ---------------------------------------------------------------- the pill
export const PILL = rectKeys({ x: 40, y: 182, w: 0, h: 38, r: 19 }, [
  [76, { w: 132 }],
  [78, { x: 16, y: 742, w: 388, h: 58, r: 29 }], // command bar
  [92, { x: 20, y: 296, w: 380, h: 430, r: 28 }], // answer
  [101, { x: 70, y: 330, w: 280, h: 300, r: 26 }], // flashcard
  [105, { x: 20, y: 296, w: 380, h: 430, r: 28 }], // quiz
  [109, { x: 20, y: 296, w: 380, h: 330, r: 28 }], // plan
]);
const PILL_FILL: [number, string][] = [[0, C.ink], [101, C.paper], [109, C.ink]];

/** Flashcard turn: over at b103, back to the front at b104.4 before the quiz. */
export const flipAt = (t: number) => spring(t - B(103), STD) - spring(t - B(104.4), STD);

// scatter positions (note-local) for the meaning map
const CHUNK_PT: [number, number][] = [[118, 190], [214, 262], [262, 206], [92, 408]];
const Q_PT: [number, number] = [238, 238];
const OTHER: [number, number][] = Array.from({ length: 18 }, (_, i) => [40 + hash(i + 3) * 300, 70 + hash(i + 40) * 410]);

const ANSWER =
  "A balanced BST keeps each node’s subtrees within one level of each other, so search, insert and delete stay O(log n). AVL trees restore balance with rotations.".split(" ");

export const ACTIONS = [
  { n: "cards", l: "Cards", x: 20, at: 100 },
  { n: "quiz", l: "Quiz", x: 148, at: 104 },
  { n: "plan", l: "Plan", x: 276, at: 108 },
];
export const ACT_Y = 744;

export const Notes: React.FC<{ t: number }> = ({ t }) => {
  if (t < B(N_IN) - 0.1 || t > B(N_OUT) + 0.4) return null;
  const note = rectAt(t, NOTE);
  return (
    <>
      <Swap t={t} inB={N_IN} outB={92} x={24} y={62}><T size={30} w={620}>Notes</T></Swap>
      <Swap t={t} inB={92} outB={N_OUT} x={24} y={62}><T size={30} w={620}>Ask Isko</T></Swap>
      {/* the note card */}
      <El t={t} k={NOTE} fill={[[0, C.wash]]}>
        {(r) => <NoteBody t={t} w={r.w} />}
      </El>
      {/* action chips (b95.5 -> 111) */}
      {ACTIONS.map((a, i) => {
        const on = clamp(spring(t - B(a.at)) - (i < 2 ? spring(t - B(ACTIONS[i + 1].at)) : 0));
        return (
          <Swap key={a.n} t={t} inB={95.4 + i * 0.25} outB={N_OUT} x={a.x} y={ACT_Y} w={124} h={46}
            style={{ borderRadius: 23, background: on > 0.5 ? C.ink : C.wash, display: "flex", alignItems: "center", justifyContent: "center", gap: 8, color: on > 0.5 ? C.paper : C.ink, transform: `scale(${1 - 0.05 * clamp(spring(t - B(a.at) + 0.06, SNAP) - spring(t - B(a.at) - 0.1, SNAP))})` }}>
            <Icon name={a.n} size={20} /><T size={16} w={560} c={on > 0.5 ? C.paper : C.ink}>{a.l}</T>
          </Swap>
        );
      })}
      {/* flashcard backs (fan) */}
      {t > B(100.8) && t < B(105.2) && [-1, 1].map((s) => {
        const k = spring(t - B(101)) * (1 - spring(t - B(104.9), SNAP));
        const fan = spring(t - B(102));
        return (
          <div key={s} style={{
            ...abs, left: 70, top: 330, width: 280, height: 300, borderRadius: 26, background: C.wash, border: `1px solid ${C.line}`,
            opacity: clamp(k), transform: `translate(${s * 46 * fan}px, ${8 * (1 - fan)}px) rotate(${s * 7 * fan}deg)`,
          }} />
        );
      })}
      {/* the pill and everything it becomes */}
      <El t={t} k={PILL} fill={PILL_FILL} lift={[[100.8, 0], [101, 1], [105, 0]]} hide={t < B(75.9)}
        style={{ transform: `perspective(1200px) rotateY(${(180 * flipAt(t)).toFixed(2)}deg)`, outline: t > B(100.8) && t < B(109) ? `1px solid ${C.line}` : undefined, outlineOffset: -1 }}>
        {(r) => <PillBody t={t} r={r} />}
      </El>
    </>
  );
};

// ---------------------------------------------------------------- note body
const NoteBody: React.FC<{ t: number; w: number }> = ({ t, w }) => {
  const sel = [73, 74, 75].map((b) => clamp(spring(t - B(b), STD))); // locked to the cursor keys
  const selOut = clamp(spring(t - B(84), SNAP));
  const map = spring(t - B(88), STD);
  const mapOut = clamp(spring(t - B(92), SNAP));
  return (
    <>
      <Swap t={t} inB={72} outB={88} x={22} y={22}><T size={24} w={620}>BST review</T></Swap>
      <Swap t={t} inB={72} outB={75.6} x={22} y={56} delay={0.08}><T size={13} c={C.mute}>Edited 2m ago · COMP 20073</T></Swap>
      {LINES.map((l, i) => (
        <Swap key={i} t={t} inB={72} outB={88} delay={0.1 + 0.03 * i} x={20} y={LINE_Y(i)}>
          <div style={{ position: "relative", display: "inline-block", padding: "4px 6px", margin: "-4px -6px", borderRadius: 8 }}>
            <T size={16} c={i > 3 ? C.faint : C.ink}>{l}</T>
            {i < 3 && sel[i] * (1 - selOut) > 0.002 && (
              <div style={{ ...abs, left: 0, top: 0, bottom: 0, width: `${(sel[i] * 100).toFixed(2)}%`, overflow: "hidden", borderRadius: 8, background: C.ink, opacity: 1 - selOut }}>
                <div style={{ padding: "4px 6px" }}><T size={16} c={C.paper}>{l}</T></div>
              </div>
            )}
          </div>
        </Swap>
      ))}
      {/* chunk dividers b84-86, dots b87 */}
      {[1, 2, 3].map((i) => {
        const k = clamp(spring(t - B(83 + i), STD)) * (1 - clamp(spring(t - B(88), SNAP)));
        return k > 0.002 && <div key={i} style={{ ...abs, left: 20, top: LINE_Y(i) - 15, width: (w - 40) * k, height: 1.5, background: C.ink, opacity: 0.5 }} />;
      })}
      {/* chunk dots travel into the meaning map */}
      {[0, 1, 2, 3].map((i) => {
        const k = clamp(spring(t - B(87) - i * 0.04, SNAP)) * (1 - mapOut);
        if (k < 0.002) return null;
        const x = lerp(w - 34, CHUNK_PT[i][0], map), y = lerp(LINE_Y(i) + 10, CHUNK_PT[i][1], map);
        const ring = clamp(spring(t - B(90), STD)) * (i < 3 ? 1 : 0);
        return (
          <React.Fragment key={i}>
            <div style={{ ...abs, left: x - 6, top: y - 6, width: 12, height: 12, borderRadius: 6, background: C.ink, transform: `scale(${k})` }} />
            {ring > 0.01 && <div style={{ ...abs, left: x - 16, top: y - 16, width: 32, height: 32, borderRadius: 16, border: `1.75px solid ${C.ink}`, transform: `scale(${0.6 + 0.4 * ring})`, opacity: ring }} />}
            <div style={{ ...abs, left: x + 12, top: y - 9, opacity: map * (1 - mapOut) }}><T size={12} w={600}>{`¶${i + 1}`}</T></div>
          </React.Fragment>
        );
      })}
      {/* other notes as quiet dots + the question */}
      {OTHER.map(([x, y], i) => {
        const k = clamp(spring(t - B(88) - i * 0.012, STD)) * (1 - mapOut);
        return k > 0.002 && <div key={i} style={{ ...abs, left: x - 4, top: y - 4, width: 8, height: 8, borderRadius: 4, background: C.faint, opacity: k }} />;
      })}
      {(() => {
        const k = spring(t - B(89), STD) * (1 - mapOut);
        if (k < 0.002) return null;
        const x = lerp(210, Q_PT[0], k), y = lerp(640, Q_PT[1], spring(t - B(89), STD));
        const line = clamp(spring(t - B(91), { k: 90, d: 19 }));
        return (
          <>
            <svg width={w} height={520} style={{ ...abs, left: 0, top: 0, overflow: "visible" }}>
              {[0, 1, 2].map((i) => (
                <line key={i} x1={Q_PT[0]} y1={Q_PT[1]} x2={lerp(Q_PT[0], CHUNK_PT[i][0], line)} y2={lerp(Q_PT[1], CHUNK_PT[i][1], line)} stroke={C.ink} strokeWidth={1.75} strokeLinecap="round" opacity={line > 0.01 ? 1 : 0} />
              ))}
            </svg>
            <div style={{ ...abs, left: x - 11, top: y - 11, width: 22, height: 22, borderRadius: 11, background: C.paper, border: `5px solid ${C.ink}` }} />
          </>
        );
      })()}
      <Swap t={t} inB={88} outB={92} x={22} y={22}><T size={13} w={600}>Meaning map</T></Swap>
      <Swap t={t} inB={88} outB={92} x={22} y={40} delay={0.06}><T size={13} c={C.mute}>On this phone · 4 chunks · 22 notes</T></Swap>
      {/* sources strip */}
      <Swap t={t} inB={92} outB={N_OUT} x={22} y={22} style={{ display: "flex", gap: 10, alignItems: "center" }}>
        <Icon name="layers" size={20} c={C.ink} /><T size={15} w={600}>3 passages from your notes</T>
      </Swap>
      <Swap t={t} inB={92} outB={N_OUT} x={22} y={58} delay={0.08}><T size={14} c={C.mute}>BST review · Lecture 6 · AVL drills</T></Swap>
      <Swap t={t} inB={92} outB={N_OUT} x={22} y={96} delay={0.12} style={{ display: "flex", gap: 6 }}>
        {[0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11].map((i) => (
          <div key={i} style={{ width: 22, height: 22, borderRadius: 11, background: i === 1 || i === 2 || i === 5 ? C.ink : C.line2 }} />
        ))}
      </Swap>
    </>
  );
};

// ---------------------------------------------------------------- pill body
const PillBody: React.FC<{ t: number; r: { w: number; h: number } }> = ({ t, r }) => {
  const caret = (t - B(79)) % (B(80) - B(79)) < 0.23 || t > B(80) - 0.02;
  const q = typed(t, [[80, "What’s a"], [81, "What’s a balanced"], [82, "What’s a balanced BST?"]]);
  const flip = flipAt(t);
  const wifiOff = spring(t - B(97), SNAP);
  // streamed words: b93 -> b94.6
  const words = Math.floor(clamp((t - B(93)) / (B(94.6) - B(93))) * ANSWER.length + 0.0001);
  return (
    <>
      {/* Ask Isko pill */}
      <Swap t={t} inB={76} outB={78} x={14} y={9} style={{ display: "flex", gap: 7, alignItems: "center", color: C.paper }}>
        <Icon name="spark" size={18} /><T size={15} w={600} c={C.paper}>Ask Isko</T>
      </Swap>
      {/* command bar */}
      <Swap t={t} inB={78} outB={92} x={20} y={17} style={{ display: "flex", gap: 10, alignItems: "center", color: C.paper }}>
        <Icon name="spark" size={20} />
        <T size={17} w={500} c={q ? C.paper : C.inkMute}>{q || "Ask about your notes"}</T>
        <div style={{ width: 1.75, height: 22, background: C.paper, opacity: caret && t < B(83) ? 1 : 0, marginLeft: -6 }} />
      </Swap>
      <Swap t={t} inB={80} outB={92} x={r.w - 50} y={9}>
        <div style={{ width: 40, height: 40, borderRadius: 20, background: C.paper, display: "flex", alignItems: "center", justifyContent: "center", transform: `scale(${1 - 0.08 * clamp(spring(t - B(83) + 0.06, SNAP) - spring(t - B(83) - 0.1, SNAP))})` }}>
          <Icon name="arrowUp" size={20} c={C.ink} />
        </div>
      </Swap>
      {/* answer */}
      <Swap t={t} inB={92} outB={101} x={24} y={22} style={{ display: "flex", gap: 8, alignItems: "center", color: C.paper }}>
        <Icon name="spark" size={18} /><T size={14} c={C.inkMute}>Isko</T>
      </Swap>
      <Swap t={t} inB={92} outB={101} x={r.w - 134} y={16} style={{ display: "flex", gap: 10, alignItems: "center", color: C.paper }}>
        <Icon name={wifiOff > 0.5 ? "wifiOff" : "wifi"} size={20} />
        <div style={{ width: 54, height: 32, borderRadius: 16, background: wifiOff > 0.5 ? C.inkLine : C.paper, position: "relative", transform: `scale(${1 - 0.06 * clamp(spring(t - B(96) + 0.06, SNAP) - spring(t - B(96) - 0.1, SNAP))})` }}>
          <div style={{ ...abs, left: 4 + 22 * (1 - wifiOff), top: 4, width: 24, height: 24, borderRadius: 12, background: wifiOff > 0.5 ? C.paper : C.ink }} />
        </div>
      </Swap>
      <Swap t={t} inB={92.6} outB={101} x={24} y={64} w={r.w - 48}>
        <div style={{ fontFamily: "Geist", fontSize: 20, lineHeight: 1.42, color: C.paper, fontWeight: 500, letterSpacing: -0.2 }}>
          {ANSWER.map((wd, i) => <span key={i} style={{ opacity: i < words ? 1 : 0 }}>{wd} </span>)}
        </div>
      </Swap>
      {["BST review ¶2", "¶3", "Lecture 6"].map((c, i) => (
        <Swap key={c} t={t} inB={i === 0 ? 94 : 95} outB={101} delay={i === 2 ? 0.12 : 0} x={24 + [0, 136, 200][i]} y={292}>
          <div style={{ height: 32, padding: "0 12px", borderRadius: 16, border: `1.5px solid ${C.inkLine}`, display: "flex", alignItems: "center" }}>
            <T size={13} w={560} c={C.paper}>{c}</T>
          </div>
        </Swap>
      ))}
      <Swap t={t} inB={99} outB={101} x={24} y={370} style={{ display: "flex", gap: 8, alignItems: "center", color: C.paper }}>
        <Icon name="lock" size={18} /><T size={14} c={C.inkMute}>Answered on this phone · no internet</T>
      </Swap>
      {/* flashcard: front, then the back after the flip */}
      <Swap t={t} inB={101} outB={104.9} x={0} y={0} w={r.w} h={r.h} style={{ opacity: flip < 0.5 ? 1 : 0 }}>
        <T size={13} c={C.mute} style={{ ...abs, left: 24, top: 24 }}>Card 1 of 12</T>
        <T size={26} w={620} lh={1.18} style={{ ...abs, left: 24, top: 70, whiteSpace: "normal", width: r.w - 48 }}>What keeps a BST balanced?</T>
        <T size={13} c={C.faint} style={{ ...abs, left: 24, bottom: 24 }}>Tap to flip</T>
      </Swap>
      <Swap t={t} inB={103} outB={104.9} x={0} y={0} w={r.w} h={r.h} style={{ opacity: flip >= 0.5 ? 1 : 0, transform: "scaleX(-1)" }}>
        <T size={13} c={C.mute} style={{ ...abs, left: 24, top: 24 }}>Answer</T>
        <T size={22} w={600} lh={1.25} style={{ ...abs, left: 24, top: 70, whiteSpace: "normal", width: r.w - 48 }}>Every node’s subtree heights differ by at most 1.</T>
      </Swap>
      {/* quiz */}
      <Quiz t={t} w={r.w} />
      {/* plan */}
      <Swap t={t} inB={109} outB={N_OUT} x={24} y={24} style={{ display: "flex", gap: 8, alignItems: "center", color: C.paper }}>
        <Icon name="plan" size={18} /><T size={14} c={C.inkMute}>This week · built from your notes</T>
      </Swap>
      {[["Wed", "BST cards", "15 min", 109], ["Thu", "Quiz rematch", "10 min", 109.2], ["Sat", "AVL rotations", "25 min", 110]].map(([d, a, m, b], i) => (
        <Swap key={i} t={t} inB={b as number} outB={N_OUT} x={20} y={70 + i * 80} w={r.w - 40} h={68}
          style={{ borderRadius: 18, background: "rgba(255,255,255,0.08)" }}>
          <T size={13} c={C.inkMute} style={{ ...abs, left: 18, top: 14 }}>{d as string}</T>
          <T size={18} w={600} c={C.paper} style={{ ...abs, left: 18, top: 32 }}>{a as string}</T>
          <T size={14} c={C.inkMute} tab style={{ ...abs, right: 18, top: 24 }}>{m as string}</T>
        </Swap>
      ))}
    </>
  );
};

const QUIZ = [["A", "O(n)"], ["B", "O(n log n)"], ["C", "O(log n)"]];
const Quiz: React.FC<{ t: number; w: number }> = ({ t, w }) => {
  if (t < B(104.8) || t > B(109.5)) return null;
  const why = spring(t - B(107), STD);
  const wrong = spring(t - B(106), SNAP);
  return (
    <>
      <Swap t={t} inB={105} outB={109} x={24} y={24}><T size={13} c={C.mute}>Quiz · 1 of 5</T></Swap>
      <Swap t={t} inB={105} outB={109} x={24} y={48} w={w - 48}><T size={22} w={620} lh={1.2} style={{ whiteSpace: "normal" }}>Search in a balanced BST is…</T></Swap>
      {QUIZ.map(([l, a], i) => {
        const y = 124 + i * 72 + (i === 2 ? 96 * why : 0);
        const h = 60 + (i === 1 ? 96 * why : 0);
        const isB = i === 1, isC = i === 2;
        return (
          <Swap key={l} t={t} inB={105} outB={109} delay={0.06 * i} x={20} y={y} w={w - 40} h={h}
            style={{ borderRadius: 18, background: isB && wrong > 0.5 ? C.ink : C.wash, overflow: "hidden" }}>
            <div style={{ ...abs, left: 14, top: 14, width: 32, height: 32, borderRadius: 16, border: `1.75px solid ${isB && wrong > 0.5 ? C.paper : C.ink}`, display: "flex", alignItems: "center", justifyContent: "center" }}>
              {isC && why > 0.3 ? <Icon name="check" size={18} c={C.ink} /> : isB && wrong > 0.5 ? <Icon name="x" size={16} c={C.paper} /> : <T size={14} w={600}>{l}</T>}
            </div>
            <T size={18} w={560} c={isB && wrong > 0.5 ? C.paper : C.ink} tab style={{ ...abs, left: 60, top: 18 }}>{a}</T>
            {isB && (
              <Swap t={t} inB={107} outB={109} x={60} y={54} w={w - 140}>
                <T size={14} c={C.inkMute} style={{ marginBottom: 4 }}>Why not?</T>
                <T size={15} c={C.paper} lh={1.35} style={{ whiteSpace: "normal" }}>Each step halves what’s left, so it’s O(log n). n log n is sorting.</T>
              </Swap>
            )}
          </Swap>
        );
      })}
    </>
  );
};

export const _n = track;
