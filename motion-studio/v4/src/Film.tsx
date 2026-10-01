// The film: a warm-gray canvas, one Shape that never cuts, a camera that
// frames each state, and a cursor that drives every change.
import React, { useEffect, useState } from "react";
import { AbsoluteFill, continueRender, delayRender, staticFile, useCurrentFrame } from "remotion";
import { CAM, FPS, Key, STD, clamp, keysFrom, loopT, press, track, trackColor } from "./lib/motion";
import { C, C0W, CAM0, FONT, LIFT } from "./theme";
import type { Box, Cam } from "./types";
import { PHRASES } from "./phrases";
import { Cursor } from "./ui/Cursor";

// ---------------------------------------------------------------- key tables
const START_BOX: Box = { cx: 960, cy: 540, w: 280, h: 84, r: 42 };
const START_CAM: Cam = CAM0;

const shapeStates = PHRASES.flatMap((p) => p.shape);
export const SHAPE_KEYS = keysFrom(START_BOX, shapeStates);
const FILL_KEYS: [number, string][] = [[0, C.ink], ...PHRASES.flatMap((p) => p.fill ?? [])];
const LIFT_KEYS: Key[] = [[0, 0], ...PHRASES.flatMap((p) => p.lift ?? [])];
const camStates = PHRASES.flatMap((p) => p.cam).map(([b, c]) => [b, c.z ? { ...c, z: Math.log(c.z) } : c] as [number, Partial<Cam>]);
export const CAM_KEYS = keysFrom({ ...START_CAM, z: Math.log(START_CAM.z) }, camStates);

export function camAt(t: number): Cam {
  return { cx: track(t, CAM_KEYS.cx, CAM), cy: track(t, CAM_KEYS.cy, CAM), z: Math.exp(track(t, CAM_KEYS.z, CAM)) };
}
export function boxAt(t: number): Box {
  return {
    cx: track(t, SHAPE_KEYS.cx), cy: track(t, SHAPE_KEYS.cy), w: track(t, SHAPE_KEYS.w),
    h: track(t, SHAPE_KEYS.h), r: track(t, SHAPE_KEYS.r),
  };
}

// Cursor keys are in world px; frame 0 and the last frame rest on C0 (screen).
const c0World = C0W;
const CUR = PHRASES.flatMap((p) => p.cur);
export const CUR_X: Key[] = [[0, c0World[0]], ...CUR.map(([b, x]) => [b, x] as Key)];
export const CUR_Y: Key[] = [[0, c0World[1]], ...CUR.map(([b, , y]) => [b, y] as Key)];
const CLICKS = PHRASES.flatMap((p) => p.clicks);
const HOLDS = PHRASES.flatMap((p) => p.holds ?? []);

export function cursorAt(t: number): [number, number] {
  return [track(t, CUR_X, STD), track(t, CUR_Y, STD)];
}

// ---------------------------------------------------------------- fonts
const useFonts = () => {
  const [handle] = useState(() => delayRender("fonts"));
  useEffect(() => {
    const faces = [
      new FontFace("Geist", `url(${staticFile("fonts/Geist-Variable.woff2")})`, { weight: "100 900" }),
      new FontFace("Geist Mono", `url(${staticFile("fonts/GeistMono-Variable.woff2")})`, { weight: "100 900" }),
    ];
    Promise.all(faces.map((f) => f.load())).then((fs) => {
      fs.forEach((f) => document.fonts.add(f));
      continueRender(handle);
    });
  }, [handle]);
};

// ---------------------------------------------------------------- film
export const Film: React.FC = () => {
  useFonts();
  const frame = loopT(useCurrentFrame());
  const t = frame / FPS;
  const cam = camAt(t);
  const box = boxAt(t);
  const fill = trackColor(t, FILL_KEYS);
  const lift = clamp(track(t, LIFT_KEYS));
  const [wx, wy] = cursorAt(t);
  const sx = 960 + (wx - cam.cx) * cam.z, sy = 540 + (wy - cam.cy) * cam.z;

  return (
    <AbsoluteFill style={{ background: C.canvas, fontFamily: FONT, overflow: "hidden" }}>
      <div style={{
        position: "absolute", left: 0, top: 0, width: 1920, height: 1080, transformOrigin: "0 0",
        transform: `translate(960px, 540px) scale(${cam.z.toFixed(5)}) translate(${(-cam.cx).toFixed(3)}px, ${(-cam.cy).toFixed(3)}px)`,
      }}>
        {PHRASES.map((p) => p.Under && <p.Under key={p.name} t={t} box={box} />)}
        {/* The Shape */}
        <div style={{
          position: "absolute", left: box.cx - box.w / 2, top: box.cy - box.h / 2, width: box.w, height: box.h,
          borderRadius: Math.min(box.r, box.w / 2, box.h / 2), background: fill, overflow: "hidden",
          boxShadow: lift > 0.01 ? LIFT.replace(/0\.(\d+)\)/g, (_, d) => `${(Number("0." + d) * lift).toFixed(3)})`) : undefined,
          outline: lift > 0.01 ? `1px solid rgba(11,11,12,${(0.06 * lift).toFixed(3)})` : undefined, outlineOffset: -1,
        }}>
          {PHRASES.map((p) => p.Inside && <p.Inside key={p.name} t={t} box={box} />)}
        </div>
        {PHRASES.map((p) => p.Over && <p.Over key={p.name} t={t} box={box} />)}
      </div>
      <Cursor x={sx} y={sy} press={press(t, CLICKS, HOLDS)} />
    </AbsoluteFill>
  );
};
