// The crystal (spec 046 C1b to C1d2): LAR's button, a 3x3x3 cube of glass where each cube is data.
// A fragment shader ray traces 27 boxes in a true isometric view. At rest it is flat, in the room's
// own tokens, and draws nothing. Ported from the picks page (reference/prototypes/study-you.src.html).
import { rgbOf } from "../dive";

const FS = `#version 300 es
precision highp float;
uniform vec2 uRes; uniform mat3 uRot; uniform vec3 uC[27]; uniform vec3 uH[27]; uniform float uLit[27]; uniform float uF[27];
uniform vec3 uRamp[5]; uniform vec3 uAccent, uGround; uniform vec3 uFace[3]; uniform vec3 uHair;
uniform float uZoom, uT, uCell, uSheen, uDay, uCalm, uStone, uPx;
out vec4 o;
const float B[16] = float[16](0., 8., 2., 10., 12., 4., 14., 6., 3., 11., 1., 9., 15., 7., 13., 5.);
// The 4x4 Bayer matrix the dive's arrival uses, on the art's own grid.
float bayer(vec2 f) { ivec2 c = ivec2(mod(floor(f), 4.)); return (B[c.y * 4 + c.x] + .5) / 16.; }
bool hitAll(vec3 ro, vec3 rd, float th, out float best, out vec3 n, out int id) {
  best = 1e9; id = -1;
  for (int i = 0; i < 27; i++) {
    if (uH[i].x < .004 || uF[i] < th) continue;
    vec3 a = (uC[i] - uH[i] - ro) / rd, b = (uC[i] + uH[i] - ro) / rd;
    vec3 lo = min(a, b), hi = max(a, b);
    float tn = max(lo.x, max(lo.y, lo.z)), tf = min(hi.x, min(hi.y, hi.z));
    if (tf > tn && tn > .001 && tn < best) { best = tn; id = i; n = -sign(rd) * step(lo.yzx, lo.xyz) * step(lo.zxy, lo.xyz); }
  }
  return id >= 0;
}
// What the glass reflects is the app itself: the room's ground, its dot grid, a soft key from above.
vec3 env(vec3 dir) {
  vec3 d = uRot * dir;
  vec3 g = min(uGround, vec3(.07, .06, .09)) * .6;  // obsidian stays dark in every room
  vec3 c = mix(g * .7, g + vec3(.03, .022, .05), smoothstep(-.6, 1., d.y));
  float key = dot(d, normalize(vec3(-.52, .74, -.42)));
  c += vec3(.72, .62, .92) * .09 * pow(max(key, 0.), 5.);
  c += vec3(1., .96, .9) * 1.9 * smoothstep(.885, .9, key);
  c += uAccent * .75 * smoothstep(.955, .985, dot(d, normalize(vec3(.86, .08, -.5))));
  if (d.y < -.05) {
    vec2 uv = d.xz / (-d.y + .25) * 3.4; vec2 f = abs(fract(uv) - .5);
    c += uAccent * .5 * step(max(f.x, f.y), .13) * smoothstep(-.05, -.5, d.y);
  }
  return c;
}
// The portal's tunnel, in the cube's space, quantised to the school's five tones through the dither.
vec3 portal(vec3 q, float th) {
  float r = length(q.xy) + .001, a = atan(q.y, q.x), z = 1.9 / (r + .55);
  float arms = .5 + .5 * cos(a * 5. + z * 4.6 - uT * .9 + q.z * .9);
  float rings = .5 + .5 * cos(z * 9. - uT * 1.3);
  float v = mix(arms, rings, .5 + .5 * sin(uT * .23));
  v = v * .82 + .24 * smoothstep(1.7, 0., r) - .05;
  v = mix(v, .7 + .12 * sin(a * 2. + uT * .8), uCalm);  // the + stays clean and legible
  return uRamp[int(clamp(floor(v * 5. + (th - .5) * .9), 0., 4.))];
}
void main() {
  vec2 p = (gl_FragCoord.xy - .5 * uRes) / uRes.y * 2.;
  float th = bayer(gl_FragCoord.xy / uCell);
  // Parallel rays: a true isometric view, drawn like an icon, not a lens.
  vec3 ro = vec3(p * uZoom, -9.), rd = vec3(0., 0., 1.);
  ro = ro * uRot; rd = rd * uRot;
  float t; vec3 n; int id;
  if (!hitAll(ro, rd, th, t, n, id)) { o = vec4(0.); return; }
  vec3 col = vec3(0.), thr = vec3(1.);
  vec3 firstQ = ro + rd * t, firstN = n; int firstId = id;
  for (int b = 0; b < 3; b++) {
    if (b > 0 && !hitAll(ro, rd, 0.02, t, n, id)) break;
    vec3 q = ro + rd * t, c = uC[id], h = uH[id], l = (q - c) / h;
    vec3 fromEdge = (h - abs(q - c)) * (1. - abs(n));
    vec3 bev = (1. - smoothstep(0., .05, fromEdge)) * sign(l) * (1. - abs(n));
    float edge = max(max(abs(bev.x), abs(bev.y)), abs(bev.z));
    vec3 ns = normalize(n + bev * .9);
    float cs = clamp(dot(-rd, ns), 0., 1.), F = .05 + .95 * pow(1. - cs, 5.);
    col += thr * F * env(reflect(rd, ns)) * 1.25;
    if (b == 0) {
      vec3 w = uRot * n, we = uRot * bev;
      float lit = max(dot(normalize(w + we), normalize(vec3(-.52, .74, -.42))), 0.);
      // The obsidian bevel: a lit violet top edge, an accent rim where it turns away.
      col += mix(vec3(.2, .13, .3), mix(uAccent, vec3(1.), .4), lit) * edge * (.08 + 1.1 * lit);
      col += vec3(.1, .07, .15) * (.02 + .16 * max(dot(w, normalize(vec3(-.45, .8, -.4))), 0.));
    }
    vec3 r = refract(rd, ns, 1. / 1.5);
    if (dot(r, r) < .01) r = rd;
    vec3 a2 = (c - h - q) / r, b2 = (c + h - q) / r, hi = max(a2, b2);
    float d = max(min(hi.x, min(hi.y, hi.z)), .001);
    vec3 pe = q + r * d;
    vec3 ne = sign(r) * step(hi.xyz, hi.yzx) * step(hi.xyz, hi.zxy);
    // Lit cubes are data: a soft square window onto the portal, seen through the glass.
    float m = max(min(h.x, min(h.y, h.z)), .05), glow = 0.; vec3 tone = vec3(0.);
    for (int k = 1; k <= 3; k++) {
      vec3 sp = q + r * d * float(k) * .25;
      vec3 g = max(abs(sp - c) - (h - m), vec3(0.)) / m;
      float w = 1. - smoothstep(.2, .78, max(g.x, max(g.y, g.z)));
      glow += w; tone += portal(sp, th) * w;
    }
    tone /= max(glow, .001); glow /= 3.;
    float lit = uLit[id];
    thr *= (1. - F) * exp(-d * vec3(1.05, 1.3, .95));
    col += thr * (vec3(.028, .016, .042) + tone * glow * (.04 + 2.7 * lit));
    vec3 r2 = refract(r, -ne, 1.5);
    if (dot(r2, r2) < .01) r2 = reflect(r, -ne);
    ro = pe + r2 * .004; rd = r2;
  }
  col += thr * env(rd);
  // LAR's sheen: every few seconds a dithered band crosses the body, lifting a step.
  float band = 1. - smoothstep(0., .34, abs(dot(firstQ, normalize(vec3(.7, .7, 0.))) * .24 - uSheen));
  if (band > th) col += mix(uAccent, vec3(1.), .4) * .1;
  col = clamp(col * (2.51 * col + .03) / (col * (2.43 * col + .59) + .14), 0., 1.);
  col = pow(col, vec3(.4545));
  // At rest it is made of the app's own surfaces, in exact token colours: flat tones,
  // card hairlines, a dot where data is. The + is the same gold as every primary action.
  if (uStone > .001) {
    vec3 c0 = uC[firstId], h0 = uH[firstId], w0 = uRot * firstN, side = 1. - abs(firstN);
    vec3 fe = (h0 - abs(firstQ - c0)) * side + (1. - side) * 9.;
    float edgeDist = min(fe.x, min(fe.y, fe.z));
    float m0 = min(side.x > .5 ? h0.x : 9., min(side.y > .5 ? h0.y : 9., side.z > .5 ? h0.z : 9.));
    vec3 st;
    if (uCalm > .5) {
      st = abs(w0.z) > .6 ? uAccent : uAccent * .68;
    } else {
      st = w0.y > .5 ? uFace[0] : (w0.x < 0. ? uFace[1] : uFace[2]);
      st = mix(uHair, st, smoothstep(uPx * .5, uPx * 1.1, edgeDist));
      float dotted = step(m0 * .74, edgeDist) * step(.3, uLit[firstId]);
      st = mix(st, uAccent, dotted);
    }
    float hh = clamp((uRot * firstQ).y * .2 + .5, 0., 1.);
    col = mix(col, st, step(hh * .72 + th * .28, uStone * 1.02));
  }
  o = vec4(col, 1.);
}`;
const VS = `#version 300 es
void main() { vec2 v = vec2((gl_VertexID << 1) & 2, gl_VertexID & 2); gl_Position = vec4(v * 2. - 1., 0., 1.); }`;

export type CrystalMode = "cube" | "plus";

/** One floating button (046 C1b, C1c): the + on Study, the cube elsewhere once LAR's model is on the phone. */
/** The + on Study and in the note editor (046 C1b, C11); the cube elsewhere once a model is installed. */
export const crystalMode = (tab: string, hasModel: boolean, editing = false): CrystalMode | null => (editing || tab === "study" ? "plus" : hasModel ? "cube" : null);

/** Glass needs WebGL2, motion, and memory to spare: `smallRam` is the tier #188 and #189 stall on (C1d, C1d2). */
export const useGlass = (reduceMotion: boolean, smallRam: boolean, webgl2: boolean) => webgl2 && !reduceMotion && !smallRam;

/** It settles this long after the last movement (C1b2). */
export const REST_MS = 2200;
export const isResting = (now: number, moved: number, thinking: boolean, foldLeft: number) => !thinking && now - moved > REST_MS && foldLeft < 0.01;

interface Cell {
  p: [number, number, number];
  tc: [number, number, number];
  th: [number, number, number];
  delay: number;
  seed: number;
  lit: number;
  bar: boolean;
}

export const CELLS: Cell[] = [];
for (let k = -1; k <= 1; k++)
  for (let j = -1; j <= 1; j++)
    for (let i = -1; i <= 1; i++) {
      const hBar = i === 0 && j === 0 && k === -1;
      const vBar = i === 0 && j === 1 && k === -1;
      const onArm = k === -1 && (i === 0 || j === 0);
      // Back layers leave first, then corners, then the arms fold into the two bars.
      const delay = k === 1 ? 0 : k === 0 ? 0.1 : onArm ? (hBar || vBar ? 0.3 : 0.24) : 0.18;
      CELLS.push({
        p: [i, j, k],
        tc: hBar || vBar ? [0, 0, 0] : [i * 0.55, j * 0.55, 0],
        th: hBar ? [1.38, 0.42, 0.42] : vBar ? [0.42, 1.38, 0.42] : [0, 0, 0],
        delay,
        seed: (((i + 2) * 7 + (j + 2) * 13 + (k + 2) * 29) % 27) / 27,
        lit: 0,
        bar: hBar || vBar,
      });
    }

/** How many of the 27 cubes show a data dot, as on the picks page. */
export const FILL = 0.3;
const HALF = 0.445;

export interface Box {
  c: number[];
  h: number[];
  /** Depth for the signal to travel by. */
  d: number;
}

/** A random branching neuron, or roots when `down`. Always 27 boxes. */
export function neuronForm(down = false, R: () => number = Math.random): Box[] {
  const start = [0, down ? 1.5 : 0, 0];
  const out: Box[] = [{ c: start, h: [0.28, 0.28, 0.28], d: 0 }];
  const tips = [{ p: start, a: -1, d: 0 }];
  let guard = 0;
  while (out.length < 27 && guard++ < 400) {
    const tip = tips[Math.floor(R() * tips.length)];
    const a = Math.floor(R() * 3);
    if (a === tip.a) continue;
    const dir = down && a === 1 ? -1 : R() < 0.5 ? -1 : 1;
    const len = 0.5 + R() * 0.75;
    const e = [...tip.p];
    e[a] += dir * len;
    if (Math.max(...e.map(Math.abs)) > 2.15) continue;
    const h = [0.065, 0.065, 0.065];
    h[a] = len / 2 + 0.03;
    out.push({ c: tip.p.map((v, i) => (v + e[i]) / 2), h, d: tip.d + 1 });
    tips.push({ p: e, a, d: tip.d + 1 });
    if (R() < 0.3 && out.length < 27) out.push({ c: e, h: [0.13, 0.13, 0.13], d: tip.d + 1.5 });
  }
  while (out.length < 27) out.push({ c: [0, 0, 0], h: [0, 0, 0], d: 0 });
  return out;
}

/** What the 27 boxes map while LAR thinks (C1b3): a neuron, roots, a helix, a lattice. */
export const FORMS: ((R?: () => number) => Box[])[] = [
  (R) => neuronForm(false, R),
  (R) => neuronForm(true, R),
  () =>
    Array.from({ length: 27 }, (_, i) => {
      const a = i * 0.72;
      return { c: [Math.cos(a) * 1.35, -2 + (4 * i) / 26, Math.sin(a) * 1.35], h: [0.15, 0.15, 0.15], d: i * 0.5 };
    }),
  (R = Math.random) =>
    CELLS.map((c) => {
      const j = () => (R() - 0.5) * 0.5;
      return { c: [c.p[0] * 1.5 + j(), c.p[1] * 1.5 + j(), c.p[2] * 1.5 + j()], h: [0.11, 0.11, 0.11], d: Math.hypot(...c.p) * 2 };
    }),
];

const YAW = Math.PI / 4;
const PITCH = 0.6155;

/** View from object: roll, then pitch, then yaw, column order for GL. */
export function viewMatrix(yaw: number, pitch: number, roll: number): number[] {
  const [cy, sy, cp, sp, cr, sr] = [Math.cos(yaw), Math.sin(yaw), Math.cos(pitch), Math.sin(pitch), Math.cos(roll), Math.sin(roll)];
  const mul = (a: number[], b: number[]) => {
    const r = new Array<number>(9);
    for (let c = 0; c < 3; c++) for (let w = 0; w < 3; w++) r[c * 3 + w] = a[w] * b[c * 3] + a[3 + w] * b[c * 3 + 1] + a[6 + w] * b[c * 3 + 2];
    return r;
  };
  return mul([cr, sr, 0, -sr, cr, 0, 0, 0, 1], mul([1, 0, 0, 0, cp, -sp, 0, sp, cp], [cy, 0, -sy, 0, 1, 0, sy, 0, cy]));
}

export interface RestTones {
  faces: [string, string, string];
  hair: string;
  gold: string;
  goldDark: string;
}

const hexOf = (rgb: number) => `#${(rgb & 0xffffff).toString(16).padStart(6, "0")}`;
const parts = (rgb: number) => [(rgb >> 16) & 255, (rgb >> 8) & 255, rgb & 255];
const mixed = (a: number, b: number, k: number) => {
  const [x, y] = [parts(a), parts(b)];
  return (Math.round(x[0] + (y[0] - x[0]) * k) << 16) | (Math.round(x[1] + (y[1] - x[1]) * k) << 8) | Math.round(x[2] + (y[2] - x[2]) * k);
};
const luma = (rgb: number) => {
  const [r, g, b] = parts(rgb);
  return (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255;
};

/** The rest state's colours, from the room's tokens (C1b2). The glass and the still image share them. */
export function restTones(card: number, ink: number, gold: number): RestTones {
  const day = luma(card) > 0.3;
  const k = day ? [0, 0.07, 0.15] : [0.2, 0.1, 0.035];
  const faces = k.map((v) => hexOf(mixed(card, ink, v))) as [string, string, string];
  return { faces, hair: hexOf(mixed(card, ink, day ? 0.24 : 0.3)), gold: hexOf(gold), goldDark: hexOf(mixed(0, gold, 0.68)) };
}

export const readTones = (el: Element = document.documentElement) => {
  const vars = getComputedStyle(el);
  const v = (name: string, fallback: number) => rgbOf(vars.getPropertyValue(name), fallback);
  return restTones(v("--card", 0x170b1a), v("--ink", 0xf4ecd8), v("--gold", 0xf5b227));
};

export interface RestFace {
  points: string;
  fill: string;
  dot: string | null;
}

/** The rest state as flat polygons in a viewBox of -3.25..3.25, projected with the glass's own matrix. */
export function restCube(t: RestTones): RestFace[] {
  const m = viewMatrix(YAW, PITCH, 0);
  const view = (v: number[]) => [m[0] * v[0] + m[3] * v[1] + m[6] * v[2], m[1] * v[0] + m[4] * v[1] + m[7] * v[2], m[2] * v[0] + m[5] * v[1] + m[8] * v[2]];
  const out: RestFace[] = [];
  const toPoints = (ps: number[][]) => ps.map((p) => { const q = view(p); return `${q[0].toFixed(3)},${(-q[1]).toFixed(3)}`; }).join(" ");
  for (const cell of CELLS)
    for (let axis = 0; axis < 3; axis++)
      for (const sign of [-1, 1]) {
        if (cell.p[axis] !== sign) continue;
        const n = [0, 0, 0];
        n[axis] = sign;
        const w = view(n);
        if (w[2] >= -0.01) continue; // faces the camera only
        const [u, v] = [(axis + 1) % 3, (axis + 2) % 3];
        const c = cell.p.map((x, i) => x + (i === axis ? sign * HALF : 0));
        const corner = (a: number, b: number, s = HALF) => c.map((x, i) => (i === u ? x + a * s : i === v ? x + b * s : x));
        out.push({
          points: toPoints([corner(-1, -1), corner(1, -1), corner(1, 1), corner(-1, 1)]),
          fill: w[1] > 0.5 ? t.faces[0] : w[0] < 0 ? t.faces[1] : t.faces[2],
          dot: cell.seed < FILL ? toPoints([corner(-1, -1, 0.26 * HALF), corner(1, -1, 0.26 * HALF), corner(1, 1, 0.26 * HALF), corner(-1, 1, 0.26 * HALF)]) : null,
        });
      }
  return out;
}

export interface Crystal {
  set(mode: CrystalMode): void;
  think(on: boolean): void;
  pulse(): void;
  wake(): void;
  menu(open: boolean): void;
  /** Turns the cube to face the student (spec 048 C1), the first beat of opening LAR's window; false turns it back. */
  face(on: boolean): void;
  hide(hidden: boolean): void;
  look(ramp: string[]): void;
  dispose(): void;
}

const hex = (css: string) => parts(rgbOf(css));
const linear = (css: string) => hex(css).map((v) => (v / 255) ** 2.2);
const clamp = (v: number) => Math.min(1, Math.max(0, v));
const smooth = (k: number) => k * k * (3 - 2 * k);

/** The glass, in one canvas. Null when it can't start, and the still image stays. Draws nothing at rest. */
export function mountCrystal(cv: HTMLCanvasElement, opts: { mode: CrystalMode; size: number; ramp: string[]; onlost?: () => void }): Crystal | null {
  const { size } = opts;
  const res = Math.round(size * Math.min(Math.min(devicePixelRatio || 1, 3) * 1.34, 4));
  cv.width = cv.height = res;
  const ctx = cv.getContext("webgl2", { alpha: true, antialias: false, premultipliedAlpha: true, powerPreference: "low-power" });
  if (!ctx) return null;
  const gl = ctx;
  const shader = (type: number, src: string) => {
    const x = gl.createShader(type)!;
    gl.shaderSource(x, src);
    gl.compileShader(x);
    return x;
  };
  const pr = gl.createProgram()!;
  gl.attachShader(pr, shader(gl.VERTEX_SHADER, VS));
  gl.attachShader(pr, shader(gl.FRAGMENT_SHADER, FS));
  gl.linkProgram(pr);
  if (!gl.getProgramParameter(pr, gl.LINK_STATUS)) return null;
  gl.useProgram(pr);
  const u = (name: string) => gl.getUniformLocation(pr, name);
  const U = { uRes: u("uRes"), uRot: u("uRot"), uC: u("uC"), uH: u("uH"), uLit: u("uLit"), uF: u("uF"), uRamp: u("uRamp"), uAccent: u("uAccent"), uGround: u("uGround"), uZoom: u("uZoom"), uT: u("uT"), uCell: u("uCell"), uSheen: u("uSheen"), uDay: u("uDay"), uCalm: u("uCalm"), uStone: u("uStone"), uFace: u("uFace"), uHair: u("uHair"), uPx: u("uPx") };
  gl.bindVertexArray(gl.createVertexArray());
  gl.viewport(0, 0, res, res);
  gl.uniform2f(U.uRes, res, res);
  gl.uniform1f(U.uCell, (res / size) * 1.5);
  gl.uniform1f(U.uPx, (6.4 / size) * 0.36);

  const s = { mode: opts.mode, m: opts.mode === "plus" ? 1 : 0, v: 0, yaw: YAW, pitch: PITCH, roll: 0, rollT: 0, think: false, th: 0, spread: 0, sv: 0, stone: 0, moved: performance.now(), hidden: false, lastYaw: YAW, face: false };
  let gold = { lin: [1, 1, 1], srgb: [1, 1, 1] };
  const applyTones = () => {
    const vars = getComputedStyle(document.documentElement);
    const t = readTones();
    gl.uniform3fv(U.uFace, t.faces.flatMap((f) => hex(f).map((v) => v / 255)));
    gl.uniform3fv(U.uHair, hex(t.hair).map((v) => v / 255));
    gl.uniform3fv(U.uGround, linear(vars.getPropertyValue("--ground").trim() || "#0b0710"));
    gl.uniform1f(U.uDay, luma(rgbOf(t.faces[0])) > 0.3 ? 1 : 0);
    gold = { lin: linear(t.gold), srgb: hex(t.gold).map((v) => v / 255) };
  };
  const look = (ramp: string[]) => gl.uniform3fv(U.uRamp, ramp.flatMap(linear));
  look(opts.ramp);
  applyTones();

  const [C, H, L, FD, fc, fh] = [new Float32Array(81), new Float32Array(81), new Float32Array(27), new Float32Array(27), new Float32Array(81), new Float32Array(81)];
  const lit = new Float32Array(27);
  let form: Box[] | null = null;
  let lastForm = -1;
  let nextForm = 0;
  const newForm = () => {
    let i;
    do i = Math.floor(Math.random() * FORMS.length);
    while (i === lastForm);
    lastForm = i;
    form = FORMS[i]();
    for (let k = form.length - 1; k > 0; k--) {
      const j = Math.floor(Math.random() * (k + 1));
      [form[k], form[j]] = [form[j], form[k]];
    }
  };
  const foldLeft = () => Math.abs((s.mode === "plus" ? 1 : 0) - s.m);
  const moving = () => s.face || Math.abs(s.v) > 0.01 || foldLeft() > 0.004 || Math.abs(s.spread) > 0.003 || Math.abs(s.roll - s.rollT) > 0.004;

  let raf = 0;
  let last = 0;
  let drawn = 0;
  let asleep = false;

  function frame(dt: number, now: number) {
    const clock = performance.now();
    const resting = isResting(clock, s.moved, s.think, foldLeft());
    s.stone += ((resting ? 1 : 0) - s.stone) * (1 - Math.exp(-dt * (resting ? 3.2 : 16)));
    if (s.stone > 0.998) s.stone = 1;
    // The fold runs on a spring, so the plus lands with a little weight.
    s.v += (((s.mode === "plus" ? 1 : 0) - s.m) * 62 - s.v * 11.5) * dt;
    s.m += s.v * dt;
    s.sv += (-s.spread * 180 - s.sv * 15) * dt;
    s.spread += s.sv * dt;
    const m = s.m;
    const plus = clamp(m);
    s.th += ((s.think ? 1 : 0) - s.th) * (1 - Math.exp(-dt * 5));
    if (s.think && clock > nextForm) {
      newForm();
      nextForm = clock + 1500 + Math.random() * 500;
    }
    const sp = 1 + s.spread;
    CELLS.forEach((c, i) => {
      const mi = smooth(clamp((plus * 1.42 - c.delay) / 1));
      const over = c.bar ? 1 + (m - plus) * 0.6 : 1;
      const tw = Math.sin(mi * Math.PI) * 0.9 * (c.bar ? 0.3 : 1);
      const [cs, sn] = [Math.cos(tw), Math.sin(tw)];
      const [x, y, z] = [c.p[0] * sp, c.p[1] * sp, c.p[2] * sp];
      const [rx, ry] = [x * cs - y * sn, x * sn + y * cs];
      C[i * 3] = rx + (c.tc[0] - rx) * mi;
      C[i * 3 + 1] = ry + (c.tc[1] - ry) * mi;
      C[i * 3 + 2] = z + (c.tc[2] - z) * mi;
      for (let a = 0; a < 3; a++) H[i * 3 + a] = c.bar ? (HALF + (c.th[a] - HALF) * mi) * over : HALF * (1 - 0.45 * mi);
      // Cubes that leave dissolve in the dive's dither instead of fading.
      FD[i] = c.bar ? 1 : 1 - smooth(clamp((mi - 0.12) / 0.78));
      if (s.th > 0.002 && form) {
        const f = form[i];
        const k = 1 - Math.exp(-dt * (3.4 + c.seed * 3));
        for (let a = 0; a < 3; a++) {
          fc[i * 3 + a] += (f.c[a] - fc[i * 3 + a]) * k;
          fh[i * 3 + a] += (f.h[a] - fh[i * 3 + a]) * k;
          C[i * 3 + a] += (fc[i * 3 + a] - C[i * 3 + a]) * s.th;
          H[i * 3 + a] += (fh[i * 3 + a] - H[i * 3 + a]) * s.th;
        }
        FD[i] += (1 - FD[i]) * s.th;
      } else if (!s.think) {
        for (let a = 0; a < 3; a++) {
          fc[i * 3 + a] = C[i * 3 + a];
          fh[i * 3 + a] = H[i * 3 + a];
        }
      }
      // Some cubes hold a datum, one is read now and then, and a signal runs while thinking.
      let lt = c.seed < FILL ? 0.46 + 0.14 * Math.sin(now * 0.7 + c.seed * 40) : 0;
      if (resting) lt = c.seed < FILL ? 0.5 : 0;
      else if (Math.sin(now * 0.31 + c.seed * 91) > 0.985) lt = 1.2;
      if (s.think && form) lt = 0.14 + Math.max(0, Math.sin(now * 3.6 - form[i].d * 1.25)) ** 4 * 1.9;
      lt += Math.sin(mi * Math.PI) * 1.1;
      if (c.bar) lt = lt * (1 - mi) + mi * (s.think ? 0.8 + 0.5 * Math.sin(now * 5.2) : 0.62 + 0.08 * Math.sin(now * 1.3));
      lit[i] += (lt - lit[i]) * (1 - Math.exp(-dt * 9));
      L[i] = lit[i];
    });
    if (s.face) {
      // Facing the student: the nearest flat face, square on, in about 150 ms (spec 048 C1).
      const f = 1 - Math.exp(-dt * 24);
      const q = Math.PI / 2;
      s.yaw += (Math.round(s.yaw / q) * q - s.yaw) * f;
      s.pitch += (0 - s.pitch) * f;
      s.roll += (0 - s.roll) * f;
    } else if (s.mode === "plus") {
      if (s.think) {
        s.yaw += dt * 0.42;
        s.pitch += (0.5 - s.pitch) * (1 - Math.exp(-dt * 5));
      }
      const near = s.think ? s.yaw : Math.round(s.yaw / (Math.PI * 2)) * Math.PI * 2;
      const f = 1 - Math.exp(-dt * 8);
      s.yaw += (near + (resting ? 0 : Math.sin(now * 0.7) * 0.16) - s.yaw) * f;
      if (!s.think) s.pitch += ((resting ? 0 : Math.sin(now * 0.53) * 0.1 + 0.08) - s.pitch) * f;
    } else if (resting) {
      // At rest it turns to its nearest three-quarter view and stays.
      const q = Math.PI / 2;
      const near = Math.round((s.yaw - q / 2) / q) * q + q / 2;
      s.yaw += (near - s.yaw) * (1 - Math.exp(-dt * 4));
      s.pitch += (PITCH - s.pitch) * (1 - Math.exp(-dt * 4));
    } else {
      s.yaw += dt * 0.42;
      s.pitch += (PITCH + Math.sin(now * 0.4) * 0.05 - s.pitch) * (1 - Math.exp(-dt * 5));
    }
    s.roll += (s.rollT - s.roll) * (1 - Math.exp(-dt * 13));
    gl.uniformMatrix3fv(U.uRot, false, viewMatrix(s.yaw, s.pitch, s.roll));
    gl.uniform1f(U.uZoom, 3.25 - 0.85 * plus * (1 - s.th));
    gl.uniform1f(U.uCalm, plus * 0.82 * (1 - s.th));
    gl.uniform1f(U.uStone, s.stone);
    gl.uniform3fv(U.uC, C);
    gl.uniform3fv(U.uH, H);
    gl.uniform1fv(U.uLit, L);
    gl.uniform1fv(U.uF, FD);
    gl.uniform1f(U.uT, now);
    gl.uniform1f(U.uSheen, ((now % 5.5) / 0.9) * 1.7 - 0.85);
    gl.uniform3fv(U.uAccent, s.stone > 0.5 ? gold.srgb : gold.lin);
    gl.drawArrays(gl.TRIANGLES, 0, 3);
    // Fully settled: nothing more to draw until something moves.
    if (resting && s.stone === 1 && Math.abs(s.yaw - s.lastYaw) < 0.0004 && foldLeft() < 0.002) asleep = true;
    s.lastYaw = s.yaw;
  }

  function loop(ts: number) {
    raf = 0;
    if (asleep || s.hidden) return;
    raf = requestAnimationFrame(loop);
    // 30 frames a second, and every frame while it folds, so the fold stays smooth (C1d).
    if (!moving() && ts - drawn < 32) return;
    const dt = Math.min(0.05, (ts - last) / 1000 || 0.016);
    last = drawn = ts;
    frame(dt, ts / 1000);
  }
  const run = () => {
    if (!raf && !s.hidden) {
      last = performance.now();
      raf = requestAnimationFrame(loop);
    }
  };
  const wake = () => {
    if (asleep) applyTones();
    s.moved = performance.now();
    asleep = false;
    run();
  };
  cv.addEventListener("webglcontextlost", (e) => {
    e.preventDefault();
    cancelAnimationFrame(raf);
    raf = 0;
    s.hidden = true;
    opts.onlost?.();
  });
  frame(0.016, performance.now() / 1000);
  run();
  return {
    set(mode) {
      s.mode = mode;
      s.rollT = 0;
      wake();
    },
    think(on) {
      s.think = on;
      wake();
    },
    pulse() {
      s.sv += 3.4;
      wake();
    },
    wake,
    menu(open) {
      s.rollT = open ? Math.PI / 4 : 0;
      wake();
    },
    face(on) {
      s.face = on;
      if (on) s.rollT = 0;
      wake();
    },
    hide(hidden) {
      s.hidden = hidden;
      if (!hidden) wake();
    },
    look(ramp) {
      look(ramp);
      wake();
    },
    dispose() {
      cancelAnimationFrame(raf);
      raf = 0;
      s.hidden = true;
      gl.getExtension("WEBGL_lose_context")?.loseContext();
    },
  };
}
