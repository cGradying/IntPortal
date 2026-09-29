// Isko 2.0 — the Iskolar ng Bayan, redrawn hi-bit (outlined, 3-tone shading)
// and rigged into parts so he moves smoothly: head, torso, two arms, two legs
// and a swinging ID card. Same outfit DNA as the app's 14x20 sprite: white
// PUP polo, maroon collar, gold lanyard and ID, navy slacks.
import { clamp, el } from "../lib/core.js";
import { pixelCanvas, sized } from "./pixel.js";

const PAL = {
  o: "#120d12", h: "#1d1717", H: "#3a2f2c", f: "#e0a77c", F: "#c4865c", s: "#f0c09a",
  e: "#1d1717", E: "#ffffff", m: "#9b4a3c", b: "#e98f7a",
  w: "#f4f1ea", W: "#cfc8bb", V: "#a9a194", r: "#7a1128", R: "#560a19", g: "#f2c14e", G: "#b8860b",
  i: "#fff7e0", c: "#7a1128", p: "#2c3346", P: "#1f2433", q: "#3b4560", k: "#141414", K: "#3a3a3a",
};

const HEAD = [
  "...oooooooo...", "..oHHHhhhhhoo.", ".oHHhhhhhhhhho", "ohHhhhhhhhhhho", "ohhhhhhhhhhhho",
  "ohhhhhffhhhhho", "ohhfffffffhhho", "ohfffffffffhfo", "offEefffffEeFo", "offeefffffeeFo",
  "obbffffffffbbo", "offfffmmmfffFo", ".offffffffffo.", "..oFFffffFFo..", "....oFFFFo....",
];
const HEAD_BLINK = HEAD.map((r, i) => (i === 8 ? "offfffffffffFo" : i === 9 ? "ofeeeffffeeeFo" : r));
const HEAD_HAPPY = HEAD.map((r, i) => (i === 8 ? "offfffffffffFo" : i === 9 ? "ofefeffffefeFo" : i === 11 ? "offffmmmmmffFo" : r));

const TORSO = [
  "....orRRRRro....", "..oowrRggRrwoo..", ".owwwwwgwwgwwwwo", "owwwwwwgwwgwwwWo", "owWwwwwwgggwwwWo",
  "owWwwwwwwwwwwwWo", "owWwwwwwwwwwwwWo", "owWVwwwwwwwwwVWo", "oWWVwwwwwwwwwVWo", "oWVVwwwwwwwwVVWo",
  "ooPPPPPPPPPPPPoo", ".opppppppppppPo.", ".opppppPPpppppo.",
];
const ARM = ["owwWo", "owwWo", "owWVo", ".oVo.", ".ofo.", ".ofo.", ".ofo.", ".oFo.", "offFo", "offFo", ".oFo."];
const LEG = ["opppo.", "opppo.", "oqppo.", "opppo.", "opppo.", "oPppo.", "opppo.", "oPPPo.", "okkkko", "oKkkko", ".oooo."];
const CARD = ["oggo", "oiio", "occo", "oiio", "oooo"];

/**
 * Build a rigged Isko inside `parent`. Scale `S` = CSS px per sprite pixel.
 * Returns { root, pose(p) } — pose() is stateless: every call sets every part.
 */
export function makeIsko(parent, S = 8) {
  const root = el("div", "abs isko", parent);
  root.style.width = `${16 * S}px`;
  root.style.height = `${37 * S}px`;
  root.style.transformOrigin = "50% 100%";
  const shadow = el("div", "abs", root);
  Object.assign(shadow.style, { left: `${1 * S}px`, top: `${35.5 * S}px`, width: `${14 * S}px`, height: `${2.4 * S}px`, borderRadius: "50%", background: "rgba(0,0,0,.35)" });
  const body = el("div", "abs", root);
  body.style.inset = "0";
  body.style.transformOrigin = `${8 * S}px ${36 * S}px`;

  const part = (rows, x, y, px, py) => {
    const wrap = el("div", "abs", body);
    wrap.style.left = `${x * S}px`;
    wrap.style.top = `${y * S}px`;
    wrap.style.transformOrigin = `${px * S}px ${py * S}px`;
    wrap.appendChild(sized(pixelCanvas(rows, PAL), S)).style.position = "relative";
    return wrap;
  };
  const legL = part(LEG, 3, 25, 2.5, 0.5);
  const legR = part(LEG, 8, 25, 2.5, 0.5);
  const armBack = part(ARM, 13.6, 14.6, 2.5, 1);
  const torso = part(TORSO, 0, 14, 8, 13);
  const card = part(CARD, 6, 19.5, 2, 0);
  const head = el("div", "abs", body);
  head.style.left = `${1 * S}px`;
  head.style.top = "0px";
  head.style.transformOrigin = `${7 * S}px ${14 * S}px`;
  const faces = [HEAD, HEAD_BLINK, HEAD_HAPPY].map((rows) => {
    const c = sized(pixelCanvas(rows, PAL), S);
    head.appendChild(c).style.position = "absolute";
    return c;
  });
  const armFront = part(ARM, -2.6, 14.6, 2.5, 1);

  /**
   * p: { x, y (feet, px), scale, face (+1 right / -1 left), walk (cycle phase,
   * radians or null), wave (0..1), wavePhase, point (0..1), squash (-1..1),
   * tilt (deg), expr ("open"|"blink"|"happy"), opacity }
   */
  function pose(p) {
    const sc = p.scale ?? 1;
    const face = p.face ?? 1;
    const sq = p.squash ?? 0;
    const walking = p.walk != null;
    const ph = p.walk ?? 0;
    const bob = walking ? Math.abs(Math.sin(ph)) * -1.1 * S : 0;
    const sx = sc * (1 + sq * 0.18) * face;
    const sy = sc * (1 - sq * 0.18);
    root.style.transform = `translate(${p.x - 8 * S}px, ${p.y - 36 * S}px) scale(${sx}, ${sy})`;
    root.style.opacity = p.opacity ?? 1;
    body.style.transform = `translateY(${bob + (p.lift ?? 0)}px) rotate(${(p.lean ?? 0)}deg)`;
    const swing = walking ? Math.sin(ph) * 24 : 0;
    legL.style.transform = `rotate(${swing}deg)`;
    legR.style.transform = `rotate(${-swing}deg)`;
    const wave = clamp(p.wave ?? 0);
    const point = clamp(p.point ?? 0);
    const wv = Math.sin(p.wavePhase ?? 0) * 22;
    armFront.style.transform = `rotate(${walking ? -swing * 0.9 : 0 + point * -80}deg)`;
    armBack.style.transform = `rotate(${walking ? swing * 0.9 : 0 + wave * (-160 + wv)}deg)`;
    const breathe = Math.sin((p.t ?? 0) * 2.4) * 0.35;
    torso.style.transform = `scaleY(${1 + breathe * 0.012})`;
    head.style.transform = `translateY(${breathe * 0.5}px) rotate(${p.tilt ?? 0}deg)`;
    card.style.transform = `rotate(${(p.cardSwing ?? 0) + (walking ? Math.sin(ph * 2 + 0.6) * 10 : 0)}deg)`;
    const ex = p.expr === "blink" ? 1 : p.expr === "happy" ? 2 : 0;
    faces.forEach((c, i) => (c.style.display = i === ex ? "" : "none"));
    shadow.style.transform = `scaleX(${1 - bob / (S * 12)})`;
  }
  return { root, pose };
}

/** Blink schedule: closed for ~0.12s at seeded moments. */
export function blinkAt(t, seed = 3) {
  const period = 2.9 + (seed % 3) * 0.4;
  const k = ((t + seed * 0.37) % period) / period;
  return k > 0.955 ? "blink" : "open";
}
