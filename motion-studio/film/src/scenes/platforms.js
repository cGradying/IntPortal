// iOS · Mac · PC (beats 116–132). One dolly along three devices. The phone's
// cards lift off as tiles and magnet-snap into the Mac on sixteenths, then on
// into the Windows PC. Wide shot, and one "In sync" stamp lands on all three.
import { clamp, css, ease, el, lerp, pb, pulse, springB } from "../lib/core.js";
import { renderCampus } from "../art/campus.js";
import { makePhone } from "../ui/phone.js";
import { macApp, winApp } from "../ui/desktop.js";
import { pixText } from "../ui/pixtype.js";
import { stageBackdrop } from "./ios.js";

const DEV = [
  { k: "ios", x: -1700, z: 0, at: 116, label: "iPhone" },
  { k: "mac", x: 0, z: -60, at: 117.5, label: "Mac" },
  { k: "win", x: 1750, z: -40, at: 120.5, label: "PC" },
];
const TILES = [
  ["UP NEXT", "COMP 20073 · 7:30", "#7ea3e0"], ["GRADE", "COMP 20083 · 1.25", "#58c792"],
  ["FREE", "1h 30m after class", "#f5b227"], ["STUDY", "12 cards due", "#b58ad0"],
];

function stamp(parent, x, y, size = 30) {
  const s = el("div", "abs", parent, "IN SYNC");
  css(s, { left: `${x}px`, top: `${y}px`, font: `700 ${size}px var(--pixel)`, letterSpacing: "0.12em", color: "#1e7249", border: `${Math.round(size / 8)}px solid #1e7249`, padding: "2px 12px", background: "rgba(255,255,255,.9)", zIndex: 20, whiteSpace: "nowrap" });
  return s;
}

export default {
  id: "platforms", from: 116, to: 132,
  init(layer) {
    this.bd = stageBackdrop(layer);
    this.world = el("div", "abs p3d", layer);
    css(this.world, { left: "960px", top: "540px", width: "0", height: "0" });
    this.dev = {};
    this.stamps = [];
    // phone
    const holder = el("div", "abs p3d", this.world);
    const P = makePhone(holder);
    P.setRoom("Night");
    P.root.style.left = "-230px";
    P.root.style.top = "-481px";
    P.setTab("today");
    for (const v of ["schedule", "grades", "study", "notes", "assis"]) P.views[v].node.style.display = "none";
    this.cv = el("canvas", "", P.views.today.r.campus);
    this.cv.width = 776; this.cv.height = 352;
    css(this.cv, { width: "388px", height: "176px", display: "block" });
    this.stamps.push(stamp(P.scr, 150, 420, 34));
    this.dev.ios = { holder, P };
    // laptop + PC monitor
    const frame = (w, h, kind) => {
      const holder = el("div", "abs p3d", this.world);
      const bez = el("div", "abs", holder);
      const scr = el("div", "abs", bez);
      if (kind === "mac") {
        css(bez, { left: `${-w / 2 - 18}px`, top: `${-h / 2 - 18}px`, width: `${w + 36}px`, height: `${h + 36}px`, borderRadius: "26px", background: "#0c0c0e", boxShadow: "0 0 0 3px #3a3a40, 0 70px 120px -40px rgba(0,0,0,.7)" });
        css(scr, { left: "18px", top: "18px", width: `${w}px`, height: `${h}px`, borderRadius: "10px", overflow: "hidden" });
        const base = el("div", "abs", holder);
        css(base, { left: `${-w / 2 - 110}px`, top: `${h / 2 + 18}px`, width: `${w + 220}px`, height: "26px", borderRadius: "0 0 30px 30px", background: "linear-gradient(#c9c9ce,#8e8e94)" });
      } else {
        css(bez, { left: `${-w / 2 - 16}px`, top: `${-h / 2 - 16}px`, width: `${w + 32}px`, height: `${h + 32}px`, borderRadius: "14px", background: "#111", boxShadow: "0 70px 120px -40px rgba(0,0,0,.7)" });
        css(scr, { left: "16px", top: "16px", width: `${w}px`, height: `${h}px`, overflow: "hidden", background: "linear-gradient(135deg,#1d3a6e,#5b2a6e)" });
        const stand = el("div", "abs", holder);
        css(stand, { left: "-60px", top: `${h / 2 + 16}px`, width: "120px", height: "110px", background: "linear-gradient(#2a2a2e,#18181b)" });
        const foot = el("div", "abs", holder);
        css(foot, { left: "-200px", top: `${h / 2 + 120}px`, width: "400px", height: "18px", borderRadius: "8px", background: "#202024" });
      }
      return { holder, scr };
    };
    this.dev.mac = frame(1440, 900, "mac");
    css(macApp(this.dev.mac.scr), { inset: "0" });
    this.stamps.push(stamp(this.dev.mac.scr, 560, 380, 48));
    this.dev.win = frame(1400, 860, "win");
    const winWin = el("div", "abs", this.dev.win.scr);
    css(winWin, { left: "70px", top: "50px", width: "1260px", height: "740px", borderRadius: "8px", overflow: "hidden", boxShadow: "0 30px 60px rgba(0,0,0,.4)" });
    css(winApp(winWin), { inset: "0" });
    this.stamps.push(stamp(winWin, 640, 300, 48));
    // travelling tiles (world space)
    this.tiles = TILES.map(([lab, txt, col]) => {
      const d = el("div", "abs notch", this.world, `<div style="font:700 18px var(--pixel);letter-spacing:.1em;color:${col}">${lab}</div><div style="font:800 30px var(--display);color:#f7ecec;letter-spacing:-.02em;margin-top:4px;white-space:nowrap">${txt}</div>`);
      css(d, { left: "-190px", top: "-60px", width: "380px", height: "120px", padding: "18px 22px", background: "#26262a", borderLeft: `8px solid ${col}`, boxShadow: "0 30px 60px -20px rgba(0,0,0,.6)" });
      return d;
    });
    this.labels = DEV.map((d) => pixText(layer, { text: d.label, size: 110, font: "pixel", x: 960, y: 950, anchor: "c", ink: "#f5b227", shadow: "#2a0a14" }));
    this.head1 = pixText(layer, { text: "Same you,", size: 130, x: 110, y: 90, ink: "#f7ecec", shadow: "#000" });
    this.head2 = pixText(layer, { text: "everywhere.", size: 130, x: 110, y: 230, ink: "#f5b227", shadow: "#000" });
  },
  render(b, t) {
    // camera stops: phone, Mac, PC, wide
    const stops = [[116, -1700, 0.78], [117.8, 0, 0.6], [120.6, 1750, 0.6], [123.4, 0, 0.36]];
    let s0 = stops[0], s1 = stops[0];
    for (const s of stops) if (b >= s[0]) { s0 = s1; s1 = s; }
    const k = s0 === s1 ? 1 : springB(b, s1[0], 0.95, 0.85);
    const cx = lerp(s0[1], s1[1], k), sc = lerp(s0[2], s1[2], k) * (1 + pb(b, 124, 132) * 0.08);
    const yaw = Math.sin(t * 0.4) * 3 - cx / 300;
    const W = (x, y, z) => `translate3d(${x}px, ${y}px, ${z}px)`;
    this.world.style.transform = `perspective(3000px) scale(${sc}) rotateY(${yaw}deg) translate3d(${-cx}px, 40px, 0)`;
    this.bd.floor.style.backgroundPosition = `${cx * 0.2}px 0px`;
    this.bd.glow.style.transform = "translate(60px, -360px)";
    this.bd.glow.style.background = "radial-gradient(circle, rgba(126,163,224,.22) 0%, rgba(126,163,224,.06) 40%, transparent 62%)";
    DEV.forEach((d, i) => {
      const land = d.k === "ios" ? 1 : springB(b, d.at - 0.2, 1.6, 0.6);
      const node = this.dev[d.k].holder;
      node.style.display = b >= d.at - 0.2 ? "" : "none";
      node.style.transform = `${W(d.x, (1 - land) * -900, d.z)} rotateY(${d.k === "ios" ? 8 : 0}deg) scale(${d.k === "ios" ? 1.25 : 1})`;
      const on = (i === 0 && b < 117.6) || (i === 1 && b >= 118 && b < 120.4) || (i === 2 && b >= 121 && b < 123.2);
      this.labels[i].render(on ? b : -1, { at: [116.2, 118, 121][i], dur: 0.6, out: [117.4, 120.2, 123][i], outDur: 0.35 });
    });
    const cv = renderCampus(t, { hour: 7.4, net: 1, w: 776, h: 352, aspect: 776 / 352, next: 101 });
    this.cv.getContext("2d").drawImage(cv, 0, 0);
    // tiles: phone → Mac (117 + i/4), Mac → PC (120 + i/4)
    this.tiles.forEach((d, i) => {
      const a1 = 117 + i * 0.25, a2 = 120 + i * 0.25;
      const src = [-1700, -260 + i * 150, 60];
      const mid = [-420 + (i % 2) * 460, -260 + Math.floor(i / 2) * 200, 40];
      const dst = [1750 - 420 + (i % 2) * 460, -240 + Math.floor(i / 2) * 200, 40];
      const k1 = pb(b, a1, a1 + 0.9, ease.inOutCubic), k2 = pb(b, a2, a2 + 0.9, ease.inOutCubic);
      let p = src;
      if (b >= a1) p = src.map((v, j) => lerp(v, mid[j], k1) + (j === 2 ? Math.sin(k1 * Math.PI) * 420 : 0));
      if (b >= a2) p = mid.map((v, j) => lerp(v, dst[j], k2) + (j === 2 ? Math.sin(k2 * Math.PI) * 420 : 0));
      const on = b >= a1 && b < a2 + 1.6;
      d.style.display = on ? "" : "none";
      if (!on) return;
      const weld = Math.max(pulse(b, a1 + 0.9, 0.4), pulse(b, a2 + 0.9, 0.4));
      d.style.transform = `${W(p[0], p[1], p[2])} rotateY(${-yaw}deg) scale(${1 + weld * 0.08})`;
      d.style.outline = weld > 0.1 ? `4px solid rgba(255,246,220,${weld})` : "";
      d.style.opacity = b > a2 + 1.1 ? 1 - pb(b, a2 + 1.1, a2 + 1.6) : 1;
    });
    // stamps on 124, 124.25, 124.5
    this.stamps.forEach((s, i) => {
      const at = 124 + i * 0.25, dd = b - at;
      s.style.display = dd >= 0 ? "" : "none";
      if (dd < 0) return;
      const sc2 = dd < 0.25 ? 1.9 - 0.98 * ease.outCubic(dd / 0.25) : 0.92 + 0.08 * ease.outCubic(clamp((dd - 0.25) / 0.35));
      s.style.transform = `rotate(-3deg) scale(${sc2})`;
      s.style.filter = `blur(${clamp(1 - dd / 0.25) * 2}px)`;
    });
    this.head1.render(b, { at: 124.8, dur: 1.2, out: 131.4, outDur: 0.5, glitchAt: [128] });
    this.head2.render(b, { at: 125.3, dur: 1.2, out: 131.5, outDur: 0.5 });
  },
};
