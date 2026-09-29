// Cold open (beats 0–16). "Class / in / nine / minutes." resolve out of
// colour pixels on 8ths while the clock flips. Then the old portal swings in:
// type the ID, the password and a CAPTCHA, Sign in, spinner, and SESSION
// EXPIRED thunks. Retry montage, then the edit stutters: a scrub bar jumps the
// stamp back three times. On beat 15 the page cracks along a grid and gold
// light leaks through; the shards drift loose for the magnet scene to catch.
import { BEAT, clamp, css, ease, el, hash, noise1, pb, pulse } from "../lib/core.js";
import { pixText } from "../ui/pixtype.js";
import { drawLogin, PH, PW } from "../ui/oldportal.js";

const GX = 8, GY = 6; // crack grid
const NUM = "2024-00123-MN-0";
const WORDS = [
  ["Class", 0, 0, "#f7ecec"], ["in", 0.5, 0, "#f7ecec"], ["nine", 1.0, 1, "#f5b227"], ["minutes.", 1.5, 1, "#f7ecec"],
];
const LEFT = [
  ["Sign in", 8.5, 10.6, "#f7ecec"], ["again.", 9.0, 10.6, "#f5b227"],
  ["Wrong", 10.75, 13.3, "#ff6b6b"], ["captcha.", 11.25, 13.3, "#f7ecec"],
];
const STUTTER = [13.5, 13.75, 14.0, 14.25, 14.5];

function stampScale(d) {
  if (d < 0) return 0;
  return d < 0.12 ? 1.9 - 0.98 * ease.outCubic(d / 0.12) : 0.92 + 0.08 * ease.outCubic(clamp((d - 0.12) / 0.2));
}

export default {
  id: "open", from: 0, to: 16,
  init(layer) {
    this.bg = el("div", "abs", layer);
    css(this.bg, { inset: "0", background: "#0a080c" });
    this.floor = el("div", "abs", layer);
    css(this.floor, { left: "-1200px", right: "-1200px", top: "600px", height: "1500px", transformOrigin: "50% 0%", transform: "perspective(800px) rotateX(74deg)",
      backgroundImage: "radial-gradient(rgba(245,178,39,.42) 2.4px, transparent 3px)", backgroundSize: "52px 52px",
      maskImage: "linear-gradient(to bottom, transparent, #000 20%, #000 55%, transparent)", WebkitMaskImage: "linear-gradient(to bottom, transparent, #000 20%, #000 55%, transparent)" });
    // hook words: two lines, each word its own pixel-resolve block
    const size = 250, gap = 64;
    let x = [110, 110];
    this.words = WORDS.map(([w, at, line, ink], i) => {
      const T = pixText(layer, { text: w, size, x: x[line], y: line ? 420 : 150, ink, shadow: "#3a0a18", ramp: i % 2 ? ["#f5b227", "#c2403a", "#8663a8", "#fff1c4"] : ["#8663a8", "#f5b227", "#c2403a", "#fff1c4"] });
      x[line] += T.w + gap;
      return { T, at };
    });
    this.clocks = ["7:21", "7:22", "7:23", "7:24"].map((s, i) =>
      pixText(layer, { text: s, size: 150, font: "pixel", x: 1860, y: 40, anchor: "r", ink: i < 2 ? "#e0697e" : "#ff5a5a", ramp: ["#7a1128", "#f5b227", "#fff1c4"] }));
    this.left = LEFT.map(([w, at, out, ink], i) => ({ T: pixText(layer, { text: w, size: 120, x: 80, y: 330 + (i % 2) * 130, ink, shadow: "#2a0a14" }), at, out }));

    // the page, in 3D, drawn from state every frame
    this.stage = el("div", "abs", layer);
    css(this.stage, { left: "600px", top: "175px", width: `${PW}px`, height: `${PH}px`, perspective: "1700px" });
    this.root = el("div", "abs p3d", this.stage);
    css(this.root, { inset: "0", transformOrigin: "50% 50%" });
    this.leak = el("div", "abs", this.root);
    css(this.leak, { inset: "-40px", background: "radial-gradient(circle at 50% 50%, #fff1c4 0%, #f5b227 18%, #c2403a 38%, #7a1128 58%, #1a0f20 80%)", transform: "translateZ(-60px)" });
    this.page = el("canvas", "abs", this.root);
    this.page.width = PW; this.page.height = PH;
    css(this.page, { left: "0", top: "0", boxShadow: "0 40px 120px -20px rgba(0,0,0,.7)" });
    this.g = this.page.getContext("2d");
    this.tiles = [];
    for (let j = 0; j < GY; j++) for (let i = 0; i < GX; i++) {
      const w = PW / GX, h = PH / GY;
      const c = el("canvas", "abs", this.root);
      c.width = Math.ceil(w); c.height = Math.ceil(h);
      css(c, { left: `${i * w}px`, top: `${j * h}px`, width: `${Math.ceil(w)}px`, height: `${Math.ceil(h)}px`, backfaceVisibility: "hidden" });
      this.tiles.push({ c, i, j, w, h });
    }
    this.stamp = el("div", "abs", this.root, "SESSION<br>EXPIRED");
    css(this.stamp, { left: "170px", top: "180px", width: "760px", padding: "26px 0", border: "14px solid #e5484d", color: "#e5484d", fontFamily: "var(--pixel)", fontWeight: 700, fontSize: "150px", lineHeight: "0.92", letterSpacing: "0.06em", textAlign: "center", background: "rgba(20,8,12,.35)" });
    this.loading = pixText(layer, { text: "Loading…\n99%", size: 170, font: "pixel", x: 90, y: 300, ink: "#f7ecec", lh: 1.05, shadow: "#2a0a14" });
    this.cursor = el("div", "abs", this.root,
      `<svg width="34" height="46" viewBox="0 0 17 23"><path d="M1 1 L1 18 L5.5 13.8 L8.6 21 L11.4 19.8 L8.4 12.8 L14.5 12.8 Z" fill="#fff" stroke="#000" stroke-width="1.3"/></svg>`);
    // edit scrub bar for the stutter
    this.scrub = el("div", "abs", layer);
    css(this.scrub, { left: "90px", right: "90px", bottom: "70px", height: "34px" });
    this.scrub.innerHTML = `<div style="position:absolute;left:0;right:0;top:15px;height:4px;background:#3a2f44"></div>
      ${Array.from({ length: 33 }, (_, i) => `<i style="position:absolute;left:${(i / 32) * 100}%;top:${i % 4 ? 12 : 6}px;width:3px;height:${i % 4 ? 10 : 22}px;background:${i % 4 ? "#5d3f78" : "#8663a8"}"></i>`).join("")}
      <div data-r="ph" style="position:absolute;top:-6px;width:6px;height:46px;background:#f5b227"></div>`;
    this.ph = this.scrub.querySelector("[data-r=ph]");
  },
  state(b, t) {
    // page state at beat b
    const s = { t, num: "", pw: 0, cap: "", focus: -1 };
    const type = (a, z, n) => Math.floor(n * clamp((b - a) / (z - a)));
    if (b >= 2.75) { s.focus = 0; s.num = NUM.slice(0, type(2.75, 3.9, NUM.length)); }
    if (b >= 3.9) { s.focus = 1; s.pw = type(3.9, 4.4, 10); }
    if (b >= 4.4) { s.focus = 2; s.cap = "x7Kq9".slice(0, type(4.4, 4.9, 5)); }
    const click = (at) => pulse(b, at, 0.3);
    s.press = Math.max(click(5.0), click(8.5), click(11.5));
    if (b >= 5.0 && b < 6.5) { s.focus = -1; s.dim = 0.55; s.spin = (b - 5) * BEAT * 9; s.progress = 0.99 * ease.outExpo(clamp((b - 5) / 1.2)); }
    if (b >= 6.5) { s.dim = 0.5; s.focus = -1; }
    if (b >= 8.5) { s.stamp = false; s.dim = 0; s.btn = "Sign in again"; s.num = ""; s.pw = 0; s.cap = ""; }
    if (b >= 9.0) { s.focus = 0; s.num = NUM.slice(0, type(9.0, 9.75, NUM.length)); }
    if (b >= 9.75) { s.focus = 1; s.num = NUM; s.pw = type(9.75, 10.1, 10); }
    if (b >= 10.1) { s.focus = 2; s.pw = 10; s.cap = "x7kq9".slice(0, type(10.1, 10.5, 5)); }
    if (b >= 10.75) { s.err = "Incorrect characters. Please try again."; }
    if (b >= 11.5) { s.focus = -1; s.dim = 0.55; s.spin = (b - 11.5) * BEAT * 9; s.progress = 0.99 * ease.outExpo(clamp((b - 11.5) / 1.0)); }
    if (b >= 13.5) { s.spin = null; s.dim = 0.5; }
    if (b >= 15) s.stamp = true;
    return s;
  },
  render(b, t) {
    // floor + hook words (0 – 2.6)
    const hookOn = b < 2.6;
    this.floor.style.display = hookOn || b >= 8.3 ? "" : "none";
    this.floor.style.backgroundPosition = `0px ${b * 140}px`;
    this.words.forEach(({ T, at }) => T.render(b, { at, dur: 0.45, out: 2.35, outDur: 0.4, bandAt: at + 0.5 }));
    const ci = b < 1.25 ? 0 : b < 9 ? 1 : b < 12 ? 2 : 3;
    const clockVis = b < 2.6 || b >= 8.3;
    const starts = [0, 1.25, 9, 12];
    this.clocks.forEach((T, i) => {
      if (!clockVis || i !== ci) return T.render(-1);
      const at = b >= 8.3 ? Math.max(starts[i], 8.3) : starts[i];
      T.render(b, { at, dur: 0.35, out: b < 2.6 ? 2.35 : 99, outDur: 0.4 });
    });
    this.left.forEach(({ T, at, out }) => T.render(b, { at, dur: 0.5, out, outDur: 0.35 }));

    // page
    const on = b >= 2.55;
    this.stage.style.display = on ? "" : "none";
    this.scrub.style.display = b >= 13.25 && b < 15 ? "" : "none";
    if (!on) return;
    const s = this.state(b, t);
    drawLogin(this.g, s);
    const enter = pb(b, 2.55, 3.2, ease.outExpo);
    const thunk = Math.max(pulse(b, 6.5, 0.8), ...STUTTER.map((a) => pulse(b, a, 0.5) * 0.7));
    const shake = thunk * 16;
    const crack = pb(b, 15, 16, ease.outCubic);
    this.root.style.transform = `translate3d(${(1 - enter) * 900 + noise1(b * 9, 3) * shake}px, ${noise1(b * 9, 7) * shake}px, ${-pb(b, 2.6, 15) * 180}px) rotateY(${-20 + enter * 6 + crack * 8}deg) rotateX(${5 - crack * 2}deg) scale(${1.12 + pb(b, 15, 16, ease.outCubic) * 0.08})`;
    // stamp thunk rendered as a scale on the whole page under the stamp
    const st = [6.5, ...STUTTER].filter((a) => b >= a).pop();
    const sc = st != null && b < 8.5 || b >= 13.5 ? stampScale((b - st) * BEAT) : 1;
    this.page.style.transform = `scale(${1 + (sc - 1) * 0.02})`;
    const stampOn = st != null && ((b >= 6.5 && b < 8.5) || (b >= 13.5 && b < 15));
    this.stamp.style.display = stampOn ? "" : "none";
    if (stampOn) {
      const d = (b - st) * BEAT;
      this.stamp.style.transform = `translateZ(60px) rotate(-4deg) scale(${sc})`;
      this.stamp.style.filter = `blur(${clamp(1 - d / 0.12) * 3}px)`;
    }
    this.loading.render(b, { at: 5.6, dur: 0.5, out: 6.45, outDur: 0.3 });
    // stutter: the edit jumps back — scrub playhead and chromatic offset
    const stut = STUTTER.reduce((a, s0) => (b >= s0 && b < s0 + 0.25 ? s0 : a), null);
    const jitter = stut != null ? (hash(Math.floor(stut * 4), 9) - 0.5) * 40 : 0;
    this.page.style.filter = stut != null ? `drop-shadow(${6 + jitter * 0.2}px 0 0 rgba(0,229,255,.55)) drop-shadow(${-6}px 0 0 rgba(255,0,170,.55))` : "";
    this.page.style.translate = stut != null ? `${jitter}px 0` : "";
    const scrubX = stut != null ? 0.62 - 0.06 * (STUTTER.indexOf(stut) % 2) : 0.62 + pb(b, 14.75, 15) * 0.1;
    this.ph.style.left = `${scrubX * 100}%`;
    // cursor
    const cx = b < 8.5 ? 400 : 400, cy = 590;
    this.cursor.style.display = (b >= 4.6 && b < 6.4) || (b >= 8.0 && b < 12) ? "" : "none";
    this.cursor.style.transform = `translate(${cx + Math.sin(b * 3) * 5}px, ${cy}px) scale(${1 - s.press * 0.18})`;
    // crack at 15: the page becomes tiles, gaps open, gold light leaks
    const cracked = b >= 15;
    this.page.style.display = cracked ? "none" : "";
    this.leak.style.display = cracked ? "" : "none";
    this.leak.style.opacity = clamp(crack * 3);
    this.tiles.forEach((T) => {
      T.c.style.display = cracked ? "" : "none";
      if (!cracked) return;
      const x = T.c.getContext("2d");
      x.clearRect(0, 0, T.c.width, T.c.height);
      x.drawImage(this.page, T.i * T.w, T.j * T.h, T.w, T.h, 0, 0, T.w, T.h);
      const r1 = hash(T.i, T.j, 1), r2 = hash(T.i, T.j, 2), r3 = hash(T.i, T.j, 3);
      const k = crack;
      const dx = (T.i - GX / 2 + 0.5) * 22 * k + (r1 - 0.5) * 30 * k;
      const dy = (T.j - GY / 2 + 0.5) * 22 * k + (r2 - 0.5) * 30 * k;
      T.c.style.transform = `translate3d(${dx}px, ${dy}px, ${(r3 - 0.3) * 160 * k}px) rotateX(${(r1 - 0.5) * 40 * k}deg) rotateY(${(r2 - 0.5) * 50 * k}deg) rotateZ(${(r3 - 0.5) * 14 * k}deg)`;
    });
  },
};
