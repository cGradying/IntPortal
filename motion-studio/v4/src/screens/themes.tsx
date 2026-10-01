// b127.4-139.6: the home screen, re-themed by the cursor, then reflowed as
// the Shape is dragged out to tablet, Mac and PC and back to the phone.
import React from "react";
import { B, SNAP, STD, clamp, spring, track } from "../lib/motion";
import { PH } from "../theme";
import type { Box } from "../types";
import { Swap, T, abs } from "../ui/kit";
import { Icon } from "../ui/Icon";
import { THEMES, theme } from "./chrome";
import { DEV, LAYOUT } from "../phrases/p5";

const IN = 127.4, OUT = 139.6;
const keysOf = (f: (l: (typeof LAYOUT)["phone"]) => number) => DEV.map(([b, d]) => [b, f(LAYOUT[d])] as [number, number]);
const CARD_K = [0, 1, 2, 3, 4, 5].map((i) => [0, 1, 2, 3].map((j) => keysOf((l) => l.cards[i][j])));
const SIDE_K = keysOf((l) => l.side), TITLE_K = keysOf((l) => l.title);
const GX_K = keysOf((l) => l.g[0]), GY_K = keysOf((l) => l.g[1]);
const devOn = (t: number, a: number, b: number) => clamp(spring(t - B(a), SNAP)) * (1 - clamp(spring(t - B(b), SNAP)));

export const SWATCH: (keyof typeof THEMES)[] = ["dark", "paper", "contrast", "light"];
export const SW_Y = 742; // phone-local center y of the swatch row

export const Themes: React.FC<{ t: number; box: Box }> = ({ t, box }) => {
  if (t < B(IN) - 0.1 || t > B(OUT) + 0.4) return null;
  const th = theme(t);
  const side = track(t, SIDE_K), title = track(t, TITLE_K);
  const card = (i: number) => CARD_K[i].map((k) => track(t, k));
  // content is laid out from the box's top-left (Center puts us at the PH frame)
  const ox = -(box.w / 2 - PH.w / 2), oy = -(box.h / 2 - PH.h / 2);
  const mac = devOn(t, 133, 134), pc = devOn(t, 134, 136);
  const ttl = clamp(spring(t - B(135), { k: 60, d: 15 })) * (1 - clamp(spring(t - B(136), SNAP)));
  const greet = (
    <div style={{ ...abs, left: track(t, GX_K), top: track(t, GY_K) }}>
      <T size={14} c={th.mute}>Tuesday, 12 August</T>
      <T size={30} w={620} c={th.fg} style={{ marginTop: 4 }}>Good morning, Aya</T>
    </div>
  );
  return (
    <Swap t={t} inB={IN} outB={OUT} x={ox} y={oy} w={box.w} h={box.h}>
      {/* window chrome: title bar + sidebar grow out of nothing */}
      {title > 0.5 && (
        <div style={{ ...abs, left: 0, top: 0, width: box.w, height: title, borderBottom: `1px solid ${th.mute}33` }}>
          <div style={{ ...abs, left: 18, top: title / 2 - 6, display: "flex", gap: 8, opacity: mac }}>
            {[0, 1, 2].map((i) => <div key={i} style={{ width: 12, height: 12, borderRadius: 6, border: `1.5px solid ${th.fg}` }} />)}
          </div>
          <div style={{ ...abs, right: 16, top: title / 2 - 8, display: "flex", gap: 18, opacity: pc, color: th.fg }}>
            <svg width={16} height={16} viewBox="0 0 16 16"><path d="M3 8h10" stroke="currentColor" strokeWidth={1.75} strokeLinecap="round" /></svg>
            <svg width={16} height={16} viewBox="0 0 16 16"><rect x={3} y={3} width={10} height={10} rx={1.5} stroke="currentColor" strokeWidth={1.75} fill="none" /></svg>
            <svg width={16} height={16} viewBox="0 0 16 16"><path d="M3.5 3.5l9 9M12.5 3.5l-9 9" stroke="currentColor" strokeWidth={1.75} strokeLinecap="round" /></svg>
          </div>
          <div style={{ ...abs, left: 0, width: box.w, top: title / 2 - 10, textAlign: "center" }}>
            <T size={15} w={560} c={th.mute} style={{ textAlign: "center", opacity: 1 - ttl }}>IntPortal — Today</T>
          </div>
          <div style={{ ...abs, left: box.w / 2 - 110, width: 220 * ttl, top: title / 2 - 11, overflow: "hidden" }}>
            <T size={16} w={620} c={th.fg}>Same you, everywhere.</T>
          </div>
        </div>
      )}
      {side > 1 && (
        <div style={{ ...abs, left: 0, top: title, width: side, height: box.h - title, borderRight: `1px solid ${th.mute}33`, overflow: "hidden" }}>
          {(["today", "grades", "note", "spark"] as const).map((n, i) => (
            <div key={n} style={{ ...abs, left: 14, top: 24 + i * 52, width: side - 28, height: 42, borderRadius: 12, background: i === 0 ? th.fg : undefined, display: "flex", alignItems: "center", gap: 12, paddingLeft: 12, color: i === 0 ? th.bg : th.fg, opacity: clamp((side - 120) / 80) }}>
              <Icon name={n} size={20} />
              <T size={15} w={560} c={i === 0 ? th.bg : th.fg}>{["Today", "Grades", "Notes", "Isko"][i]}</T>
            </div>
          ))}
        </div>
      )}
      {greet}
      <Card r={card(0)} bg={th.card}>
        <T size={14} c={th.card === THEMES.contrast.card ? "#00000099" : "#FFFFFF99"} style={{ ...abs, left: 22, top: 20 }}>Next class</T>
        <T size={26} w={600} c={th.cardFg} style={{ ...abs, left: 22, top: 44 }}>Data Structures</T>
        <T size={15} c={th.cardFg} style={{ ...abs, left: 22, top: 82, opacity: 0.62 }} tab>COMP 20073 · S512 · 7:30</T>
        <div style={{ ...abs, right: 20, top: 20, width: 64, height: 64, borderRadius: 32, border: `1.75px solid ${th.cardFg}44`, display: "flex", alignItems: "center", justifyContent: "center" }}>
          <T size={22} w={600} c={th.cardFg} tab>9′</T>
        </div>
      </Card>
      <Card r={card(1)} bg={th.wash}>
        <div style={{ ...abs, left: 20, top: 22, display: "flex", gap: 14, color: th.fg }}>
          <Icon name="clock" size={26} style={{ marginTop: 4 }} />
          <div><T size={17} w={600} c={th.fg}>1h 30m free</T><T size={14} c={th.mute} style={{ marginTop: 4 }}>10:30 – 12:00 · Library is 3 min away</T></div>
        </div>
      </Card>
      <Card r={card(2)} bg={th.wash}>
        <T size={14} c={th.mute} style={{ ...abs, left: 20, top: 20 }}>GWA</T>
        <T size={44} w={620} c={th.fg} tab style={{ ...abs, left: 20, top: 44 }}>1.28</T>
        <T size={13} c={th.mute} style={{ ...abs, left: 20, top: 110 }}>Dean’s list pace</T>
      </Card>
      <Card r={card(3)} bg={th.wash}>
        <div style={{ ...abs, left: 20, top: 20, color: th.fg }}><Icon name="note" size={24} /></div>
        <T size={17} w={600} c={th.fg} style={{ ...abs, left: 20, top: 62 }}>BST review</T>
        <T size={14} c={th.mute} style={{ ...abs, left: 20, top: 88 }}>12 cards due</T>
      </Card>
      <Card r={card(4)} bg={th.wash}>
        <div style={{ ...abs, left: 20, top: 20, display: "flex", gap: 8, alignItems: "center", color: th.fg }}>
          <Icon name="spark" size={18} /><T size={14} c={th.mute}>Isko · on this device</T>
        </div>
        <div style={{ ...abs, right: 20, top: 56, maxWidth: "70%", padding: "10px 14px", borderRadius: 16, background: th.fg }}>
          <T size={15} w={500} c={th.bg} style={{ whiteSpace: "normal" }}>What’s a balanced BST?</T>
        </div>
        <T size={16} c={th.fg} lh={1.4} style={{ ...abs, left: 20, top: 118, right: 20, whiteSpace: "normal" }}>
          Subtree heights within 1 of each other, so search stays O(log n).
        </T>
      </Card>
      <Card r={card(5)} bg={th.wash}>
        <T size={14} c={th.mute} style={{ ...abs, left: 20, top: 20 }}>This week</T>
        {["Mon", "Tue", "Wed", "Thu", "Fri"].map((d, i) => (
          <div key={d} style={{ ...abs, left: 20, right: 20, top: 56 + i * 124, height: 110, borderRadius: 16, background: i === 1 ? th.card : th.bg }}>
            <T size={13} c={i === 1 ? th.cardFg : th.mute} style={{ ...abs, left: 14, top: 12, opacity: i === 1 ? 0.7 : 1 }}>{d}</T>
            <T size={16} w={600} c={i === 1 ? th.cardFg : th.fg} style={{ ...abs, left: 14, top: 34 }}>{["Web Dev", "Data Structures", "Statistics", "Physics", "NSTP"][i]}</T>
          </div>
        ))}
      </Card>
      {/* theme swatches (phone only) */}
      <Swap t={t} inB={IN + 0.3} outB={131.8} x={PH.w / 2 - 136} y={SW_Y - 30} w={272} h={60}
        style={{ borderRadius: 30, background: th.bg, boxShadow: `0 0 0 1px ${th.mute}44` }}>
        {SWATCH.map((n, i) => {
          const sel = clamp(spring(t - B(128 + i), SNAP) - (i < 3 ? spring(t - B(129 + i), SNAP) : 0));
          return (
            <div key={n} style={{ ...abs, left: 136 - 96 + i * 64 - 18, top: 12, width: 36, height: 36, borderRadius: 18, background: THEMES[n].bg, border: `1.5px solid ${th.mute}66`, boxShadow: `0 0 0 ${(4 * sel).toFixed(2)}px ${th.bg}, 0 0 0 ${(5.75 * sel).toFixed(2)}px ${th.fg}`, overflow: "hidden" }}>
              <div style={{ ...abs, left: 18, top: 0, width: 18, height: 36, background: THEMES[n].card }} />
            </div>
          );
        })}
      </Swap>
    </Swap>
  );
};

const Card: React.FC<{ r: number[]; bg: string; children: React.ReactNode }> = ({ r: [x, y, w, h], bg, children }) =>
  w < 1 ? null : (
    <div style={{ ...abs, left: x, top: y, width: w, height: h, borderRadius: 24, background: bg, overflow: "hidden" }}>{children}</div>
  );

export const _th = STD;
