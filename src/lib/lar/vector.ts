// LAR as smooth vector art: the same character as the pixel sprite (an
// obsidian pebble with block ears, a dark visor with gold eyes, a belly
// window onto the portal, a gold spark antenna, floating mitts and an
// orbiting cube), drawn as shapes instead of pixels and with no outline.
// One pure list of shapes feeds both renderers: SVG markup for crisp use,
// and a canvas painter so a host can draw him at a lower resolution and let
// him resolve (the landing's depth effect).

export type Mood = "open" | "blink" | "happy" | "wow" | "wink" | "focus";
export type Gesture = "idle" | "wave" | "point" | "reach" | "thumbs";

export const MOODS: Mood[] = ["open", "blink", "happy", "wow", "wink", "focus"];
export const GESTURES: Gesture[] = ["idle", "wave", "point", "reach", "thumbs"];

/** The drawing box, in head units: body about 100 wide, centred on x = 70, room for the mitts. */
export const VIEW = { x: -26, y: -8, w: 192, h: 142 } as const;

export const PAL = {
  shade: "#2c1c3a",
  deep: "#43295a",
  body: "#5f3f7e",
  lit: "#8663a8",
  high: "#b996d8",
  visor: "#140b1b",
  rim: "#2d1d3c",
  gold: "#f5b227",
  goldShade: "#b87a10",
  white: "#fff6dc",
  blush: "#ff7a9c",
  mouth: "#7a1128",
  frame: "#24162e",
  glow: "#e27bd0",
  core: "#c2403a",
} as const;

/** The SIS swirl, the belly's default when no portal theme is given. */
export const SIS_RAMP = ["#3b1220", "#7a1c2c", "#b5412a", "#e08a35", "#f3cf6a"];

type Stop = [number, string];
export type Paint =
  | string
  | { kind: "radial"; cx: number; cy: number; r: number; stops: Stop[] }
  | { kind: "linear"; x1: number; y1: number; x2: number; y2: number; stops: Stop[] };

export interface Shape {
  d: string;
  fill?: Paint;
  stroke?: string;
  width?: number;
  opacity?: number;
  /** Clip to this path (the belly window). */
  clip?: string;
}

export interface Pose {
  mood?: Mood;
  gesture?: Gesture;
  /** Seconds on his idle clock; 0 holds him still. */
  t?: number;
  cube?: boolean;
  /** The belly window's five tones, darkest first. */
  ramp?: string[];
  /** Which way he faces: -1 left, 0 front, 1 right (a three-quarter turn). */
  turn?: number;
}

const f = (n: number) => +n.toFixed(2);

/** A rounded rectangle as a path. */
export function rr(x: number, y: number, w: number, h: number, r: number): string {
  r = Math.min(r, w / 2, h / 2);
  return `M${f(x + r)} ${f(y)}H${f(x + w - r)}A${r} ${r} 0 0 1 ${f(x + w)} ${f(y + r)}V${f(y + h - r)}A${r} ${r} 0 0 1 ${f(x + w - r)} ${f(y + h)}H${f(x + r)}A${r} ${r} 0 0 1 ${f(x)} ${f(y + h - r)}V${f(y + r)}A${r} ${r} 0 0 1 ${f(x + r)} ${f(y)}Z`;
}

const ellipse = (cx: number, cy: number, rx: number, ry: number) =>
  `M${f(cx - rx)} ${f(cy)}A${f(rx)} ${f(ry)} 0 1 0 ${f(cx + rx)} ${f(cy)}A${f(rx)} ${f(ry)} 0 1 0 ${f(cx - rx)} ${f(cy)}Z`;
const circle = (cx: number, cy: number, r: number) => ellipse(cx, cy, r, r);

/** The pebble: a superellipse, slightly fuller below the middle. */
function pebble(cx: number, cy: number, rx: number, ry: number, dx = 0): string {
  const pts: string[] = [];
  for (let k = 0; k < 72; k++) {
    const a = (k / 72) * Math.PI * 2;
    const c = Math.cos(a);
    const s = Math.sin(a);
    const x = cx + dx + rx * Math.sign(c) * Math.abs(c) ** (2 / 2.4);
    const y = cy + (s > 0 ? ry * 0.94 : ry) * Math.sign(s) * Math.abs(s) ** (2 / 2.2);
    pts.push(`${k ? "L" : "M"}${f(x)} ${f(y)}`);
  }
  return pts.join("") + "Z";
}

/** A four-point spark, the antenna's tip and the eyes' glint family. */
function spark(cx: number, cy: number, r: number): string {
  const q = r * 0.28;
  return `M${f(cx)} ${f(cy - r)}Q${f(cx + q)} ${f(cy - q)} ${f(cx + r)} ${f(cy)}Q${f(cx + q)} ${f(cy + q)} ${f(cx)} ${f(cy + r)}Q${f(cx - q)} ${f(cy + q)} ${f(cx - r)} ${f(cy)}Q${f(cx - q)} ${f(cy - q)} ${f(cx)} ${f(cy - r)}Z`;
}

// Mitt offsets per gesture, [dx, dy] in head units from where each floats.
const GEST: Record<Gesture, [[number, number], [number, number]]> = {
  idle: [[0, 0], [0, 0]],
  wave: [[0, 0], [10, -46]],
  point: [[0, 0], [20, -22]],
  reach: [[-8, -36], [8, -36]],
  thumbs: [[0, 0], [8, -26]],
};

const EYE = { L: 50, R: 90, y: 50 } as const;

function eye(x: number, kind: "open" | "closed" | "happy" | "wow" | "focusL" | "focusR", y0: number): Shape[] {
  const y = EYE.y + y0;
  const g = PAL.gold;
  switch (kind) {
    case "open":
      return [
        { d: rr(x - 5, y - 9, 10, 18, 5), fill: { kind: "linear", x1: 0, y1: y - 9, x2: 0, y2: y + 9, stops: [[0, "#ffd36b"], [0.62, g], [1, PAL.goldShade]] } },
        { d: circle(x - 1.4, y - 4.6, 2), fill: PAL.white },
      ];
    case "closed":
      return [{ d: `M${x - 7} ${y + 2}H${x + 7}`, stroke: g, width: 4 }];
    case "happy":
      return [{ d: `M${x - 7} ${y + 4}Q${x} ${y - 7} ${x + 7} ${y + 4}`, stroke: g, width: 4 }];
    case "wow":
      return [
        { d: circle(x, y, 7.5), stroke: g, width: 3.6 },
        { d: circle(x - 2, y - 2, 1.8), fill: PAL.white },
      ];
    case "focusL":
    case "focusR": {
      const s = kind === "focusL" ? 1 : -1;
      return [
        { d: `M${x - 7} ${y - 2 - 3 * s}L${x + 7} ${y - 2 + 3 * s}L${x + 7} ${y + 6}Q${x} ${y + 9} ${x - 7} ${y + 6}Z`, fill: g },
      ];
    }
  }
}

function face(mood: Mood, y0: number, fx: number): Shape[] {
  const out: Shape[] = [];
  const pair: Record<Mood, [Parameters<typeof eye>[1], Parameters<typeof eye>[1]]> = {
    open: ["open", "open"],
    blink: ["closed", "closed"],
    happy: ["happy", "happy"],
    wow: ["wow", "wow"],
    wink: ["open", "happy"],
    focus: ["focusL", "focusR"],
  };
  out.push(...eye(EYE.L + fx, pair[mood][0], y0), ...eye(EYE.R + fx, pair[mood][1], y0));
  if (mood !== "focus") {
    out.push({ d: ellipse(36 + fx, 63 + y0, 6.5, 3), fill: PAL.blush, opacity: 0.8 }, { d: ellipse(104 + fx, 63 + y0, 6.5, 3), fill: PAL.blush, opacity: 0.8 });
  }
  if (mood === "wow") out.push({ d: ellipse(70 + fx, 64 + y0, 3.4, 4), fill: PAL.gold });
  if (mood === "happy" || mood === "wink") out.push({ d: `M${f(63 + fx)} ${f(61 + y0)}Q${f(70 + fx)} ${f(69 + y0)} ${f(77 + fx)} ${f(61 + y0)}`, stroke: PAL.gold, width: 3.4 });
  return out;
}

function mitt(x: number, y: number, thumb: boolean): Shape[] {
  const fill: Paint = { kind: "radial", cx: x - 3, cy: y - 4, r: 13, stops: [[0, PAL.high], [0.45, PAL.lit], [1, PAL.deep]] };
  const out: Shape[] = [{ d: circle(x, y, 9.5), fill }];
  if (thumb) out.push({ d: rr(x - 3, y - 19, 7, 12, 3.5), fill });
  return out;
}

function cubeShapes(x: number, y: number, s: number): Shape[] {
  const h = s * 0.58;
  return [
    { d: `M${f(x)} ${f(y - s)}L${f(x + s)} ${f(y - s + h)}L${f(x)} ${f(y - s + 2 * h)}L${f(x - s)} ${f(y - s + h)}Z`, fill: "#ffd36b" },
    { d: `M${f(x - s)} ${f(y - s + h)}L${f(x)} ${f(y - s + 2 * h)}L${f(x)} ${f(y + h)}L${f(x - s)} ${f(y)}Z`, fill: PAL.gold },
    { d: `M${f(x + s)} ${f(y - s + h)}L${f(x)} ${f(y - s + 2 * h)}L${f(x)} ${f(y + h)}L${f(x + s)} ${f(y)}Z`, fill: PAL.goldShade },
    { d: circle(x, y - s + h, s * 0.22), fill: PAL.core },
  ];
}

/** Every shape of LAR in one pose, back to front. */
export function lar(p: Pose = {}): Shape[] {
  const mood = p.mood ?? "open";
  const gesture = p.gesture ?? "idle";
  const t = p.t ?? 0;
  const ramp = p.ramp ?? SIS_RAMP;
  const bob = Math.sin(t * 3.1) * 2.6;
  const sway = Math.sin(t * 3.1 - 0.9) * 0.16;
  const orbit = t * 2.2;
  const cubeOn = p.cube ?? true;
  const turn = Math.max(-1, Math.min(1, p.turn ?? 0));
  // Turning slides the face and belly toward the side he faces; the far ear tucks in.
  const fx = turn * 11;
  const vx = turn * 8;
  const cubeAt = { x: 70 + Math.cos(orbit) * 66, y: 66 + Math.sin(orbit) * 10 + bob, front: Math.sin(orbit) > 0 };
  const out: Shape[] = [];

  // A soft shadow under him.
  out.push({ d: ellipse(70, 124, 30 - bob * 0.8, 4.2), fill: "#000", opacity: 0.32 });
  if (cubeOn && !cubeAt.front) out.push(...cubeShapes(cubeAt.x, cubeAt.y, 6));

  const y0 = bob;
  // Antenna: a stem swaying from his crown, a gold spark on top.
  const ax = 70 + Math.sin(sway) * 12;
  const ay = 2 + y0 + Math.abs(Math.sin(sway)) * 2;
  out.push({ d: `M70 ${f(26 + y0)}Q${f(70 + Math.sin(sway) * 3)} ${f(16 + y0)} ${f(ax)} ${f(ay + 6)}`, stroke: PAL.deep, width: 4.5 });
  const pulse = 1 + Math.sin(t * 4.2) * 0.12;
  out.push({ d: spark(ax, ay, 8 * pulse), fill: PAL.gold }, { d: spark(ax, ay, 3.4 * pulse), fill: PAL.white });

  // Block ears: the frame's stepped corners, softened.
  for (const s of [-1, 1]) {
    const far = turn * s < 0 ? Math.abs(turn) : 0;
    const ex = 70 + s * 36 * (1 - far * 0.35) + vx * 0.5;
    out.push(
      { d: rr(ex - 9, 20 + y0, 18, 16, 4), fill: PAL.body },
      { d: rr(ex - 5 + s * 2, 12 + y0, 10, 12, 3.5), fill: PAL.lit },
      { d: rr(ex - 2.5 + s * 3, 8 + y0, 5, 5, 1.6), fill: PAL.gold },
    );
  }

  // The pebble, with a magenta rim light on his right so he reads on the void.
  const body = pebble(70, 64 + y0, 52, 47);
  out.push({ d: body, fill: PAL.glow });
  out.push({
    d: pebble(70, 64 + y0, 52, 47, -2.6),
    fill: { kind: "radial", cx: 52, cy: 40 + y0, r: 76, stops: [[0, PAL.high], [0.32, PAL.lit], [0.62, PAL.body], [0.86, PAL.deep], [1, PAL.shade]] },
  });

  // Visor, with a faint glass sheen.
  const vw = 92 - Math.abs(turn) * 10;
  out.push({ d: rr(70 - vw / 2 + vx, 32 + y0, vw, 40, 15), fill: PAL.rim });
  out.push({ d: rr(73 - vw / 2 + vx, 35 + y0, vw - 6, 34, 13), fill: PAL.visor });
  out.push({ d: `M${f(36 + vx)} ${f(39 + y0)}Q${f(54 + vx)} ${f(35 + y0)} ${f(74 + vx)} ${f(38 + y0)}L${f(72 + vx)} ${f(42 + y0)}Q${f(54 + vx)} ${f(40 + y0)} ${f(38 + vx)} ${f(44 + y0)}Z`, fill: "#ffffff", opacity: 0.07 });
  out.push(...face(mood, y0, fx));

  // Belly window onto the portal: the theme's ramp, turning.
  const bx = 70 + vx;
  const win = rr(bx - 16, 83 + y0, 32, 22, 6);
  out.push({ d: rr(bx - 19, 80 + y0, 38, 28, 8), fill: PAL.frame });
  out.push({ d: win, fill: { kind: "radial", cx: bx, cy: 94 + y0, r: 19, stops: [[0, ramp[4]], [0.3, ramp[3]], [0.58, ramp[2]], [0.82, ramp[1]], [1, ramp[0]]] } });
  for (let k = 0; k < 2; k++) {
    const a = t * 1.6 + k * Math.PI;
    const c = Math.cos(a);
    const s = Math.sin(a);
    const arm = `M${f(bx)} ${f(94 + y0)}Q${f(bx + c * 14 - s * 6)} ${f(94 + y0 + s * 9 + c * 4)} ${f(bx + c * 20)} ${f(94 + y0 + s * 13)}`;
    out.push({ d: arm, stroke: ramp[1], width: 3.2, opacity: 0.75, clip: win });
  }
  out.push({ d: circle(bx - 13.5, 82 + y0, 1.6), fill: PAL.gold }, { d: circle(bx + 13.5, 82 + y0, 1.6), fill: PAL.gold });

  // Mitts float beside him and lag his bob a little.
  GEST[gesture].forEach(([dx, dy], i) => {
    const side = i === 0 ? -1 : 1;
    const lag = Math.sin(t * 3.1 - 0.7 - i * 0.3) * 3;
    let wx = 0;
    if (gesture === "wave" && i === 1) wx = Math.sin(t * 9) * 6;
    out.push(...mitt(70 + side * 64 + dx + wx, 74 + dy + lag + y0, gesture === "thumbs" && i === 1));
  });

  if (cubeOn && cubeAt.front) out.push(...cubeShapes(cubeAt.x, cubeAt.y, 6));
  return out;
}

const attr = (s: Shape, id: string) => {
  const p = s.fill;
  const fill = p === undefined ? "none" : typeof p === "string" ? p : `url(#${id})`;
  return `fill="${fill}"${s.stroke ? ` stroke="${s.stroke}" stroke-width="${s.width ?? 1}" stroke-linecap="round" stroke-linejoin="round"` : ""}${s.opacity !== undefined ? ` opacity="${s.opacity}"` : ""}`;
};

/** SVG markup for one pose. `uid` keeps gradient ids unique per instance. */
export function toSvg(shapes: Shape[], uid = "lar", label = "LAR, the Lakbay-Aral Robot"): string {
  let defs = "";
  let body = "";
  shapes.forEach((s, i) => {
    const id = `${uid}-${i}`;
    const p = s.fill;
    if (p && typeof p !== "string") {
      const stops = p.stops.map(([o, c]) => `<stop offset="${o}" stop-color="${c}"/>`).join("");
      defs += p.kind === "radial"
        ? `<radialGradient id="${id}" gradientUnits="userSpaceOnUse" cx="${f(p.cx)}" cy="${f(p.cy)}" r="${f(p.r)}">${stops}</radialGradient>`
        : `<linearGradient id="${id}" gradientUnits="userSpaceOnUse" x1="${f(p.x1)}" y1="${f(p.y1)}" x2="${f(p.x2)}" y2="${f(p.y2)}">${stops}</linearGradient>`;
    }
    if (s.clip) defs += `<clipPath id="${id}-c"><path d="${s.clip}"/></clipPath>`;
    body += `<path d="${s.d}" ${attr(s, id)}${s.clip ? ` clip-path="url(#${id}-c)"` : ""}/>`;
  });
  return `<svg viewBox="${VIEW.x} ${VIEW.y} ${VIEW.w} ${VIEW.h}" role="img" aria-label="${label}"><defs>${defs}</defs>${body}</svg>`;
}

/** Paint one pose into a 2D context at `scale` canvas pixels per head unit. */
export function paint(ctx: CanvasRenderingContext2D, shapes: Shape[], scale: number) {
  ctx.save();
  ctx.scale(scale, scale);
  ctx.translate(-VIEW.x, -VIEW.y);
  for (const s of shapes) {
    ctx.save();
    if (s.clip) ctx.clip(new Path2D(s.clip));
    ctx.globalAlpha = s.opacity ?? 1;
    const path = new Path2D(s.d);
    const p = s.fill;
    if (p !== undefined) {
      if (typeof p === "string") ctx.fillStyle = p;
      else {
        const g = p.kind === "radial" ? ctx.createRadialGradient(p.cx, p.cy, 0, p.cx, p.cy, p.r) : ctx.createLinearGradient(p.x1, p.y1, p.x2, p.y2);
        p.stops.forEach(([o, c]) => g.addColorStop(o, c));
        ctx.fillStyle = g;
      }
      ctx.fill(path);
    }
    if (s.stroke) {
      ctx.strokeStyle = s.stroke;
      ctx.lineWidth = s.width ?? 1;
      ctx.lineCap = "round";
      ctx.lineJoin = "round";
      ctx.stroke(path);
    }
    ctx.restore();
  }
  ctx.restore();
}

/** Closed for about a tenth of a second at seeded moments, open otherwise. */
export function blinkAt(t: number, seed = 3, base: Mood = "open"): Mood {
  const period = 2.9 + (seed % 3) * 0.4;
  const k = ((t + seed * 0.37) % period) / period;
  return k > 0.958 ? "blink" : base;
}
