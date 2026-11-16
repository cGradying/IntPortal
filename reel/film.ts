// The reel (spec 054) as a pure function of time: window.seek(t) paints frame t.
// The footage is the real app on demo data (capture.mjs); LAR and the campus are
// drawn by the app's own renderers. Laid out from the viewport, so 9:16 and 16:9
// come from one timeline.
import "../src/lib/app.css";
import { build } from "../src/lib/campus/paint";
import { startStrip } from "../src/lib/campus/render";
import { loadScene } from "../src/lib/campus/scenes";
import { litWindow } from "../src/lib/campus/sky";
import { BOX, SIS, drawLar, hands, rig, type Gesture, type State } from "../src/lib/lar/sprite";
import { ACTS, DUR, FPS, LINES, SHOTS, type Line } from "./timeline";

declare global {
  interface Window {
    seek(t: number): Promise<void>;
    DUR: number;
  }
}

const W = innerWidth;
const H = innerHeight;
const tall = H > W;
const U = Math.min(W, H) / 1080; // one unit is a pixel at 1080 short side

const clamp = (x: number, a = 0, b = 1) => Math.min(b, Math.max(a, x));
const outExpo = (x: number) => (x >= 1 ? 1 : 1 - Math.pow(2, -10 * x));
const outBack = (x: number) => 1 + 2.2 * Math.pow(x - 1, 3) + 1.2 * Math.pow(x - 1, 2);
const inQuad = (x: number) => x * x;
/** 0 to 1 over `d` seconds from `start`. */
const prog = (t: number, start: number, d: number) => clamp((t - start) / d);

const stage = document.getElementById("stage")!;
stage.innerHTML = `
  <div class="ground"></div>
  <canvas class="campus" width="192" height="80"></canvas>
  <div class="phone"><img class="screen" alt="" /></div>
  <canvas class="lar"></canvas>
  <div class="lines"></div>
`;
const css = document.createElement("style");
css.textContent = `
  #stage { position: fixed; inset: 0; overflow: hidden; background: #0b0710; font-family: "Montserrat Variable", system-ui, sans-serif; }
  .ground { position: absolute; inset: 0;
    background: radial-gradient(circle at 1px 1px, rgba(245, 178, 39, 0.09) 1.2px, transparent 1.6px) 0 0 / ${14 * U * 1.6}px ${14 * U * 1.6}px,
      radial-gradient(ellipse 60% 45% at 22% 18%, rgba(122, 17, 40, 0.35), transparent 70%),
      radial-gradient(ellipse 55% 40% at 80% 85%, rgba(245, 178, 39, 0.10), transparent 70%), #0b0710; }
  .campus { position: absolute; left: 0; bottom: 0; width: 100%; image-rendering: pixelated; opacity: 0;
    -webkit-mask-image: linear-gradient(to bottom, transparent, #000 30%); mask-image: linear-gradient(to bottom, transparent, #000 30%); }
  .phone { position: absolute; background: #050307; box-shadow: 0 0 0 ${2 * U}px #1d1622, 0 ${60 * U}px ${120 * U}px -${40 * U}px rgba(0,0,0,.95); overflow: hidden; }
  .screen { display: block; width: 100%; height: 100%; object-fit: cover; }
  .lar { position: absolute; image-rendering: pixelated; }
  .lines { position: absolute; display: grid; gap: ${18 * U}px; }
  .line { color: #f4ecd8; font-weight: 800; letter-spacing: -0.03em; line-height: 1.02; white-space: pre-wrap; }
  .line.small { font-family: "Source Sans 3 Variable", system-ui, sans-serif; font-weight: 600; letter-spacing: 0; color: rgba(244,236,216,.72); }
  .line .gold { color: #f5b227; }
`;
document.head.append(css);

const phone = stage.querySelector<HTMLDivElement>(".phone")!;
const screen = stage.querySelector<HTMLImageElement>(".screen")!;
const larCv = stage.querySelector<HTMLCanvasElement>(".lar")!;
const campusCv = stage.querySelector<HTMLCanvasElement>(".campus")!;
const linesBox = stage.querySelector<HTMLDivElement>(".lines")!;

// Phone: 9 by 19.5, the screen inset by a bezel.
const phoneH = tall ? H * 0.66 : H * 0.86;
const phoneW = phoneH * (1170 / 2532) + 2 * 12 * U;
const phoneX = tall ? (W - phoneW) / 2 : W * 0.66 - phoneW / 2;
const phoneY = tall ? H - phoneH - H * 0.05 : (H - phoneH) / 2;
Object.assign(phone.style, { width: `${phoneW}px`, height: `${phoneH}px`, left: `${phoneX}px`, top: `${phoneY}px`, borderRadius: `${64 * U}px`, padding: `${12 * U}px` });
screen.style.borderRadius = `${52 * U}px`;

// Lines sit above the phone on a tall frame, beside it on a wide one.
const textX = tall ? W * 0.08 : W * 0.08;
const textW = tall ? W * 0.84 : W * 0.46;
Object.assign(linesBox.style, { left: `${textX}px`, width: `${textW}px` });
const big = (tall ? 92 : 104) * U;
const small = (tall ? 46 : 50) * U;

const els = LINES.map((l) => {
  const d = document.createElement("div");
  d.className = "line" + (l.small ? " small" : "");
  d.style.fontSize = `${l.small ? small : l.text === "IntPortal" ? big * 1.7 : big}px`;
  d.innerHTML = l.text === "IntPortal" ? "Int<span class=gold>Portal</span>" : l.text;
  linesBox.append(d);
  return d;
});

/** Where the lines block sits in each act. */
function linesTop(t: number): { top: number; centered: boolean } {
  if (t < ACTS.questions[1]) return { top: tall ? H * 0.3 : H * 0.3, centered: false };
  if (t < ACTS.app[1]) return { top: tall ? H * 0.06 : H * 0.36, centered: false };
  if (t < ACTS.promise[1]) return { top: tall ? H * 0.16 : H * 0.08, centered: false };
  return { top: tall ? H * 0.5 : H * 0.54, centered: true };
}

function paintLines(t: number) {
  const { top, centered } = linesTop(t);
  linesBox.style.top = `${top}px`;
  linesBox.style.textAlign = centered ? "center" : "left";
  if (centered) Object.assign(linesBox.style, { left: `${W * 0.06}px`, width: `${W * 0.88}px` });
  else Object.assign(linesBox.style, { left: `${textX}px`, width: `${textW}px` });
  LINES.forEach((l: Line, i) => {
    const el = els[i];
    const shown = t >= l.at - 0.001 && t < l.end + 0.35;
    el.style.display = shown ? "block" : "none";
    if (!shown) return;
    const enter = outExpo(prog(t, l.at, 0.55));
    const leave = inQuad(prog(t, l.end, 0.3));
    // In act one each new question takes the light; the earlier ones step back.
    const later = t < ACTS.questions[1] ? LINES.filter((m) => m.at > l.at && m.at <= t && m.at < ACTS.questions[1]).length : 0;
    const dim = later ? 0.38 : 1;
    el.style.opacity = String(enter * (1 - leave) * dim);
    el.style.transform = `translateY(${(1 - enter) * 34 * U - leave * 14 * U}px)`;
    el.style.clipPath = `inset(0 0 ${(1 - enter) * 40}% 0)`;
  });
}

const frames = new Map<string, HTMLImageElement>();
async function frame(clip: string, n: number): Promise<HTMLImageElement> {
  const key = `${clip}/${String(n).padStart(4, "0")}`;
  let img = frames.get(key);
  if (!img) {
    img = new Image();
    img.src = `./footage/${key}.jpg`;
    await img.decode();
    frames.set(key, img);
    if (frames.size > 90) frames.delete(frames.keys().next().value!);
  }
  return img;
}

async function paintPhone(t: number) {
  const [a, b] = ACTS.app;
  const show = t >= a && t < b + 0.6;
  phone.style.display = show ? "block" : "none";
  if (!show) return;
  const enter = outBack(prog(t, a, 0.9));
  const leave = inQuad(prog(t, b, 0.55));
  const lift = (1 - enter) * (H - phoneY + 40) + leave * (H - phoneY + 40);
  const shot = SHOTS.findLast((s) => t >= s.at) ?? SHOTS[0];
  const local = t - shot.at;
  const scale = 1 + 0.025 * clamp(local / shot.len);
  phone.style.transform = `translateY(${lift}px) scale(${scale})`;
  const n = Math.min(shot.frames, 1 + Math.round((shot.from + local) * FPS));
  const img = await frame(shot.clip, n);
  if (screen.src !== img.src) screen.src = img.src;
}

const r = rig();
const mitts = hands();
const BW = BOX.x1 - BOX.x0;
const BH = BOX.y1 - BOX.y0;

function paintLar(t: number) {
  // LAR asks with the student in act one, and waves at the end.
  const asking = t < ACTS.questions[1] + 0.4;
  const ending = t >= ACTS.end[0];
  const show = asking || ending;
  larCv.style.display = show ? "block" : "none";
  if (!show) return;
  const larSize = Math.round((asking ? 8 : tall ? 11 : 9) * U);
  if (larCv.width !== BW * larSize) {
    larCv.width = BW * larSize;
    larCv.height = BH * larSize;
    larCv.style.width = `${BW * larSize}px`;
    larCv.style.height = `${BH * larSize}px`;
  }
  const mode: State = asking ? "think" : "idle";
  const gesture: Gesture = ending ? "wave" : "idle";
  const enter = outBack(prog(t, asking ? 0 : ACTS.end[0], 0.8));
  const leave = asking ? inQuad(prog(t, ACTS.questions[1] - 0.2, 0.5)) : 0;
  const x = asking ? W - BW * larSize - (tall ? 20 : 120) * U : (W - BW * larSize) / 2;
  const y = asking ? (tall ? H * 0.6 : H * 0.42) : tall ? H * 0.14 : H * 0.02;
  larCv.style.left = `${x}px`;
  larCv.style.top = `${y + (1 - enter) * 60 * U}px`;
  larCv.style.opacity = String(clamp(enter) * (1 - leave));
  r.set(mode, t, {});
  const p = r.at(t, {}, false);
  mitts.at(gesture, t, false).forEach((g, i) => {
    const m = p.mitts[i];
    m.x += g.dx;
    m.y += g.dy;
    m.rot += g.rot;
    if (g.thumb) m.kind = "thumb";
  });
  const ctx = larCv.getContext("2d")!;
  ctx.setTransform(1, 0, 0, 1, 0, 0);
  ctx.clearRect(0, 0, larCv.width, larCv.height);
  ctx.setTransform(larSize, 0, 0, larSize, -BOX.x0 * larSize, -BOX.y0 * larSize);
  drawLar(ctx, p, SIS, t, { cube: true, shadow: true });
}

const built = build(await loadScene("Sta. Mesa"));
const strip = startStrip(campusCv, built, { lit: litWindow("COMP 20073", built.windows), hour: () => 20.4, keep: true });
strip.stop();

function paintCampus(t: number) {
  const [a, b] = ACTS.promise;
  const on = t >= a - 0.2 && t < ACTS.end[1];
  campusCv.style.display = on ? "block" : "none";
  if (!on) return;
  const enter = outExpo(prog(t, a, 1.0));
  campusCv.style.opacity = String(enter * (t >= b ? (tall ? 0.55 : 0.3) : 1));
  campusCv.style.height = "auto";
  campusCv.style.transform = `translateY(${(1 - enter) * 80 * U + (tall ? 0 : H * 0.24)}px)`;
  if (!tall) campusCv.style.width = "100%";
  else Object.assign(campusCv.style, { width: `${H * 0.42 * 2.4}px`, left: `${(W - H * 0.42 * 2.4) / 2}px` });
  strip.draw(t * 1000);
}

window.DUR = DUR;
window.seek = async (t: number) => {
  paintLines(t);
  paintLar(t);
  paintCampus(t);
  await paintPhone(t);
  await new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r)));
};
await document.fonts.ready;
await window.seek(0);
