// Isko 3.0: a pocket-size portal spirit, IntPortal's helper AI.
// Not a person: an obsidian pebble (the portal frame's own stone) with stepped
// block "ears", a dark visor face with big gold eyes, a round window in his
// belly that shows the live portal swirl, a gold spark-key antenna, two
// floating mitts and a tiny orbiting portal cube. Hi-bit: outlined, 4-tone
// shading with ordered dither between tones, drawn procedurally at init.
// Every part is its own layer so motion is sub-pixel smooth; pose() is
// stateless and sets every part on every call.
import { clamp, el, lerp } from "../lib/core.js";

export const ISKO_PAL = {
  o: "#1a0f20", // outline
  d: "#2c1c3a", k: "#43295a", b: "#5f3f7e", B: "#8663a8", L: "#b996d8", // body ramp
  v: "#140b1b", V: "#2d1d3c", g: "#f5b227", G: "#b87a10", w: "#fff6dc", p: "#ff7a9c",
  r: "#7a1128", s: "#24162e", e: "#5d3f78", m: "#e27bd0", c: "#c2403a",
};
const BAYER = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]];
const W = 26, H = 23;

// ------------------------------------------------------------ sprite build
function grid(w, h) {
  return Array.from({ length: h }, () => Array(w).fill(null));
}
function toCanvas(g, pal = ISKO_PAL) {
  const c = document.createElement("canvas");
  c.width = g[0].length;
  c.height = g.length;
  const x = c.getContext("2d");
  g.forEach((row, j) => row.forEach((k, i) => {
    if (!k) return;
    x.fillStyle = pal[k] || k;
    x.fillRect(i, j, 1, 1);
  }));
  c.className = "px";
  return c;
}
function outline(g) {
  const h = g.length, w = g[0].length, out = g.map((r) => r.slice());
  for (let j = 0; j < h; j++) for (let i = 0; i < w; i++) {
    if (g[j][i]) continue;
    const n = [[1, 0], [-1, 0], [0, 1], [0, -1]].some(([a, b]) => g[j + b]?.[i + a] && g[j + b][i + a] !== "o");
    if (n) out[j][i] = "o";
  }
  return out;
}
/** Pebble body: a squashed superellipse lit from the top-left, dithered. */
function bodyGrid() {
  const g = grid(W, H);
  const cx = W / 2 - 0.5, cy = 12.2, rx = 10.6, ry = 9.8;
  const tones = ["d", "k", "b", "B", "L"];
  for (let j = 0; j < H; j++) for (let i = 0; i < W; i++) {
    const nx = (i - cx) / rx, ny = (j - cy) / (j > cy ? ry * 0.92 : ry);
    const r = Math.abs(nx) ** 2.4 + Math.abs(ny) ** 2.2;
    if (r > 1) continue;
    const nz = Math.sqrt(Math.max(0, 1 - Math.min(1, nx * nx + ny * ny)));
    let l = clamp(0.5 + (-nx * 0.55 - ny * 0.65 + nz * 0.55) * 0.62);
    l = l * 4 + (BAYER[j % 4][i % 4] / 16 - 0.5) * 0.55;
    g[j][i] = tones[clamp(Math.round(l), 0, 4)];
  }
  // stepped block ears: the portal frame's corner blocks
  const ear = (x0, dir) => {
    for (let s = 0; s < 3; s++) for (let w = 0; w < 3 - s; w++) {
      const i = x0 + dir * w, j = 3 - s;
      g[j][i] = s === 2 ? "B" : "b";
    }
  };
  ear(5, 1); ear(W - 6, -1);
  g[1][5] = "g"; g[1][W - 6] = "g"; // gold rivets on the ear tips
  // visor: rounded dark screen
  for (let j = 6; j <= 13; j++) for (let i = 5; i <= W - 6; i++) {
    const corner = (j === 6 || j === 13) && (i === 5 || i === W - 6);
    if (corner) continue;
    const rim = j === 6 || j === 13 || i === 5 || i === W - 6;
    g[j][i] = rim ? "V" : "v";
  }
  g[7][7] = "V"; g[7][8] = "V"; // glass glint
  // belly window: a tiny square pixel portal (the app icon), swirl is live
  const bx0 = W / 2 - 4, by0 = 14;
  for (let j = 0; j < 7; j++) for (let i = 0; i < 8; i++) {
    const corner = (j === 0 || j === 6) && (i === 0 || i === 7);
    if (corner) continue;
    const edge = j === 0 || j === 6 || i === 0 || i === 7;
    g[by0 + j][bx0 + i] = edge ? "s" : "v";
  }
  g[by0][bx0 + 1] = "g"; g[by0][bx0 + 6] = "g"; g[by0 + 6][bx0 + 1] = "G"; g[by0 + 6][bx0 + 6] = "G";
  // magenta rim light on the right edge: reads on dark scenes
  for (let j = 0; j < H; j++) for (let i = W - 1; i > 0; i--) {
    if (g[j][i] && g[j][i] !== "o") { if (j > 4 && j < 19 && !"vVsgG".includes(g[j][i])) g[j][i] = "m"; break; }
  }
  return outline(g);
}
/** Eyes and blush for each expression, drawn over the visor. */
function faceGrid(expr) {
  const g = grid(W, H);
  const L = 9, R = W - 11, y = 8;
  const put = (i, j, k) => (g[j][i] = k);
  const eyeOpen = (x) => {
    for (let j = 0; j < 4; j++) for (let i = 0; i < 2; i++) put(x + i, y + j, "g");
    put(x, y, "w");
    put(x + 1, y + 3, "G");
  };
  const eyeClosed = (x) => { put(x - 1, y + 2, "g"); put(x, y + 2, "g"); put(x + 1, y + 2, "g"); put(x + 2, y + 2, "g"); };
  const eyeHappy = (x) => { put(x - 1, y + 2, "g"); put(x, y + 1, "g"); put(x + 1, y + 1, "g"); put(x + 2, y + 2, "g"); };
  const eyeWow = (x) => {
    for (let j = 0; j < 4; j++) for (let i = -1; i < 3; i++) {
      const edge = j === 0 || j === 3 || i === -1 || i === 2;
      const corner = (j === 0 || j === 3) && (i === -1 || i === 2);
      if (edge && !corner) put(x + i, y + j, "g");
    }
    put(x, y + 1, "w");
  };
  const eyeFocus = (x, s) => { put(x - 1, y + 1 + (s > 0 ? 0 : 0), "g"); for (let i = 0; i < 3; i++) put(x + i - (s < 0 ? 1 : 0), y + 2, "g"); put(x, y + 3, "G"); put(x + 1, y + 3, "G"); };
  const E = {
    open: [eyeOpen, eyeOpen], blink: [eyeClosed, eyeClosed], happy: [eyeHappy, eyeHappy],
    wow: [eyeWow, eyeWow], wink: [eyeOpen, eyeHappy], focus: [(x) => eyeFocus(x, 1), (x) => eyeFocus(x, -1)],
  }[expr] || [eyeOpen, eyeOpen];
  E[0](L); E[1](R);
  if (expr !== "focus") { put(L - 2, y + 4, "p"); put(L - 1, y + 4, "p"); put(R + 2, y + 4, "p"); put(R + 3, y + 4, "p"); }
  if (expr === "wow") { put(W / 2 - 1, y + 4, "g"); put(W / 2, y + 4, "g"); }
  else if (expr === "happy" || expr === "wink") { put(W / 2 - 2, y + 4, "g"); put(W / 2 + 1, y + 4, "g"); put(W / 2 - 1, y + 5, "g"); put(W / 2, y + 5, "g"); }
  return g;
}
const MITT = ["..ooo..", ".oBLBo.", "oBLBbbo", "obBbbko", "obbbkko", ".okkko.", "..ooo.."];
const THUMB = ["..oo...", ".oLBo..", ".oBbo..", "oBLBbbo", "obBbbko", "obbbkko", ".ooooo."];
const ANTENNA = ["...g...", "..gwg..", ".ggwgg.", "..gwg..", "...g...", "..oBo..", "..obo..", "..oko..", ".okkko."];
const CUBE = ["...o...", "..ogo..", ".ogwgo.", "ogwcgGo", ".ogcGo.", "..oGo..", "...o..."];
const rowsToGrid = (rows) => rows.map((r) => [...r].map((c) => (c === "." ? null : c)));

// ------------------------------------------------------------ belly swirl
const SW = ["#2a0a14", "#7a1128", "#c2403a", "#f5b227", "#fff1c4"];
export function drawSwirl(ctx, t, n = 7, m = n) {
  ctx.clearRect(0, 0, n, m);
  const c = (n - 1) / 2, cy = (m - 1) / 2;
  for (let j = 0; j < m; j++) for (let i = 0; i < n; i++) {
    const dx = i - c, dy = (j - cy) * 1.1, r = Math.hypot(dx, dy);
    const a = Math.atan2(dy, dx);
    let v = 0.5 + 0.5 * Math.sin(a * 2 - r * 1.6 + t * 5.5);
    v = v * (1 - r / (c + 1)) * 1.25 + (1 - r / (c + 0.5)) * 0.35;
    v += (BAYER[j % 4][i % 4] / 16 - 0.5) * 0.28;
    ctx.fillStyle = SW[clamp(Math.floor(v * 5), 0, 4)];
    ctx.fillRect(i, j, 1, 1);
  }
}

// ------------------------------------------------------------ rig
/**
 * Build Isko inside `parent`. `S` = CSS px per sprite pixel.
 * Returns { root, pose(p), size }.
 */
export function makeIsko(parent, S = 8) {
  const root = el("div", "abs isko", parent);
  Object.assign(root.style, { width: `${W * S}px`, height: `${H * S}px`, left: "0", top: "0", transformOrigin: "50% 100%" });
  const shadow = el("div", "abs", root);
  Object.assign(shadow.style, { left: `${5 * S}px`, top: `${(H + 5) * S}px`, width: `${(W - 10) * S}px`, height: `${2.2 * S}px`, borderRadius: "50%", background: "rgba(0,0,0,.35)" });
  const trail = el("div", "abs", root);
  const trailDots = Array.from({ length: 8 }, (_, i) => {
    const d = el("div", "abs", trail);
    Object.assign(d.style, { width: `${S * 2}px`, height: `${S * 2}px`, background: i % 3 === 0 ? ISKO_PAL.g : i % 3 === 1 ? ISKO_PAL.B : "#c2403a" });
    return d;
  });
  const cubeBack = el("div", "abs", root);
  const body = el("div", "abs", root);
  Object.assign(body.style, { left: "0", top: "0", width: `${W * S}px`, height: `${H * S}px`, transformOrigin: `50% 100%` });
  const place = (cv, wrap, x, y) => {
    cv.style.width = `${cv.width * S}px`;
    cv.style.height = `${cv.height * S}px`;
    cv.style.position = "absolute";
    wrap.appendChild(cv);
    Object.assign(wrap.style, { left: `${x * S}px`, top: `${y * S}px` });
    return wrap;
  };
  const antenna = place(toCanvas(rowsToGrid(ANTENNA)), el("div", "abs", body), W / 2 - 3.5, -7);
  antenna.style.transformOrigin = `${3.5 * S}px ${9 * S}px`;
  place(toCanvas(bodyGrid()), el("div", "abs", body), 0, 0);
  const faces = {};
  const faceWrap = el("div", "abs", body);
  for (const k of ["open", "blink", "happy", "wow", "wink", "focus"]) {
    faces[k] = toCanvas(faceGrid(k));
    place(faces[k], el("div", "abs", faceWrap), 0, 0);
  }
  const belly = document.createElement("canvas");
  belly.width = 6; belly.height = 5;
  belly.className = "px";
  place(belly, el("div", "abs", body), W / 2 - 3, 15);
  const bctx = belly.getContext("2d");
  const cubeFront = el("div", "abs", root);
  const cube = place(toCanvas(rowsToGrid(CUBE)), el("div", "abs", cubeFront), 0, 0);
  const mitt = (rows) => place(toCanvas(rowsToGrid(rows)), el("div", "abs", root), 0, 0);
  const hands = [0, 1].map(() => {
    const w = el("div", "abs", root);
    const a = mitt(MITT), b = mitt(THUMB);
    w.appendChild(a); w.appendChild(b);
    a.style.left = a.style.top = b.style.left = b.style.top = "0";
    w.style.transformOrigin = `${3.5 * S}px ${3.5 * S}px`;
    return { w, open: a, thumb: b };
  });

  const GEST = {
    // [dx, dy, rot] per hand, in sprite px from the body's side anchors
    idle: [[0, 0, 0], [0, 0, 0]],
    wave: [[0, 0, 0], [3, -12, -30]],
    point: [[0, 0, 0], [9, -6, -20]],
    carry: [[4, -2, 20], [-4, -2, -20]],
    cover: [[7, -9, 15], [-7, -9, -15]],
    thumbs: [[0, 0, 0], [3, -7, 0]],
    reach: [[-3, -10, -30], [3, -10, 30]],
  };

  /**
   * p: { x, y (bottom-centre, css px), scale, t (seconds, for idle life),
   *   squash (-1..1), tilt (deg), look (-1..1), expr, gesture, gk (0..1 blend),
   *   gesture2 / wavePhase, cube (bool), cubePhase, trail: [[dx,dy],...] (css px,
   *   relative to x,y), opacity, bob (0..1) }
   */
  function pose(p) {
    const t = p.t ?? 0;
    const sc = p.scale ?? 1;
    const sq = p.squash ?? 0;
    const bob = Math.sin(t * 3.1) * 1.4 * S * (p.bob ?? 1);
    const sx = sc * (1 + sq * 0.2);
    const sy = sc * (1 - sq * 0.2);
    root.style.transform = `translate(${p.x - (W * S) / 2}px, ${p.y - H * S}px) scale(${sx}, ${sy})`;
    root.style.opacity = p.opacity ?? 1;
    body.style.transform = `translateY(${bob}px) rotate(${p.tilt ?? 0}deg)`;
    const look = clamp(p.look ?? 0, -1, 1);
    faceWrap.style.transform = `translate(${Math.round(look * 1.5) * S}px, ${Math.round((p.lookY ?? 0) * 1) * S}px)`;
    const expr = p.expr ?? "open";
    for (const k in faces) faces[k].style.display = k === expr ? "" : "none";
    antenna.style.transform = `rotate(${Math.sin(t * 3.1 - 0.9) * 6 + (p.tilt ?? 0) * 0.6}deg)`;
    drawSwirl(bctx, t * (p.swirlSpeed ?? 1), 6, 5);
    // hands: float at the sides, follow the bob with a lag, blend to gesture
    const g = GEST[p.gesture ?? "idle"] || GEST.idle;
    const k = clamp(p.gk ?? 1);
    hands.forEach((h, i) => {
      const side = i === 0 ? -1 : 1;
      const lag = Math.sin(t * 3.1 - 0.7 - i * 0.3) * 1.2 * S;
      let [dx, dy, rot] = g[i];
      if (p.gesture === "wave" && i === 1) rot += Math.sin(p.wavePhase ?? t * 9) * 28;
      const hx = (W / 2 + side * 14.5 - 3.5 + dx * k) * S;
      const hy = (13 + dy * k) * S + lag;
      h.w.style.transform = `translate(${hx}px, ${hy}px) rotate(${rot * k * (i === 0 ? 1 : 1)}deg) scaleX(${side})`;
      const thumb = p.gesture === "thumbs" && i === 1 && k > 0.5;
      h.open.style.display = thumb ? "none" : "";
      h.thumb.style.display = thumb ? "" : "none";
    });
    // orbiting cube: passes behind and in front of the body
    const on = p.cube ?? true;
    const a = p.cubePhase ?? t * 2.2;
    const cx = (W / 2 - 3.5 + Math.cos(a) * 16) * S;
    const cy = (6 + Math.sin(a) * 3) * S + bob * 0.5;
    const front = Math.sin(a) > 0;
    cube.style.display = on ? "" : "none";
    (front ? cubeFront : cubeBack).appendChild(cube);
    cube.style.transform = `translate(${cx}px, ${cy}px) scale(${0.75 + 0.25 * Math.sin(a)}) rotate(${Math.round(a * 4) * 0}deg)`;
    // dithered trail (caller passes past offsets, oldest last)
    const tr = p.trail ?? [];
    trailDots.forEach((d, i) => {
      const q = tr[i];
      d.style.display = q ? "" : "none";
      if (!q) return;
      const f = 1 - i / trailDots.length;
      const sz = Math.max(1, Math.round(2 * f + 0.4));
      d.style.width = d.style.height = `${sz * S}px`;
      d.style.transform = `translate(${(W * S) / 2 + q[0] / sx - sz * S / 2}px, ${H * S * 0.55 + q[1] / sy}px)`;
      d.style.opacity = f > 0.35 ? 1 : 0.6;
    });
    shadow.style.transform = `scaleX(${1 - bob / (S * 16)})`;
    shadow.style.display = p.shadow === false ? "none" : "";
  }
  return { root, pose, W: W * S, H: H * S };
}

/** Blink schedule: closed for ~0.12s at seeded moments. */
export function blinkAt(t, seed = 3, base = "open") {
  const period = 2.9 + (seed % 3) * 0.4;
  const k = ((t + seed * 0.37) % period) / period;
  return k > 0.958 ? "blink" : base;
}

/** Offsets for the trail from a pure path function f(t) -> [x, y]. */
export function trailFrom(f, t, n = 8, dt = 0.035) {
  const [x0, y0] = f(t);
  const out = [];
  for (let i = 1; i <= n; i++) {
    const [x, y] = f(t - i * dt);
    const d = Math.hypot(x - x0, y - y0);
    if (d < 6 * i) break; // only when actually moving
    out.push([x - x0, y - y0]);
  }
  return out;
}

export const lerp2 = (a, b, k) => [lerp(a[0], b[0], k), lerp(a[1], b[1], k)];
