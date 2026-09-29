// Every platform (beats 84–108): one continuous dolly along a row of devices
// in 3D — iPhone, Android, the macOS Registrar, the Windows port, the web app
// — each landing on its beat. Then the camera pulls back wide and one change
// (COMP 20073 marked Online on the Mac) stamps onto every device at once.
import { css, ease, el, lerp, pb, pulse, springB } from "../lib/core.js";
import { renderCampus } from "../art/campus.js";
import { makePhone } from "../ui/phone.js";
import { macApp, webApp, winApp } from "../ui/desktop.js";
import { headline } from "../ui/type.js";
import { stageBackdrop } from "./ios.js";

const DEV = [
  { k: "ios", x: -2300, z: 0, at: 84, label: "iPhone" },
  { k: "android", x: -1500, z: -120, at: 86, label: "Android" },
  { k: "mac", x: -150, z: 0, at: 90, label: "macOS" },
  { k: "win", x: 1650, z: -80, at: 94, label: "Windows" },
  { k: "web", x: 3400, z: 0, at: 98, label: "Web" },
];

function stamp(parent, x, y, size = 30) {
  const s = el("div", "abs", parent, "ONLINE");
  css(s, { left: `${x}px`, top: `${y}px`, font: `700 ${size}px var(--pixel)`, letterSpacing: "0.12em", color: "#1b5db8", border: `${Math.round(size / 8)}px solid #1b5db8`, padding: "2px 10px", background: "rgba(255,255,255,.85)", zIndex: 20 });
  return s;
}

export default {
  id: "platforms", from: 84, to: 108,
  init(layer) {
    this.bd = stageBackdrop(layer);
    this.world = el("div", "abs p3d", layer);
    css(this.world, { left: "960px", top: "540px", width: "0", height: "0" });
    this.dev = {};
    this.stamps = [];
    // phones
    for (const k of ["ios", "android"]) {
      const holder = el("div", "abs p3d", this.world);
      const P = makePhone(holder);
      P.setRoom(k === "ios" ? "Night" : "Astra Moon");
      P.root.style.left = "-230px";
      P.root.style.top = "-481px";
      if (k === "android") {
        css(P.ph, { borderRadius: "46px", background: "linear-gradient(145deg,#3a3d44,#15161a 40%,#2c2f36)" });
        css(P.scr, { borderRadius: "34px" });
        css(P.scr.querySelector(".di"), { width: "26px", height: "26px", marginLeft: "-13px", borderRadius: "50%", top: "16px" });
        P.setTab("grades");
        for (const v of ["today", "schedule", "study", "assis"]) P.views[v].node.style.display = "none";
        P.views.grades.r.coachT.textContent = "For a 1.50 this term, aim for 1.69 or better on the 2 left.";
        for (let i = 0; i < 4; i++) P.views.grades.r[`s${i}`].style.opacity = 1;
        P.views.grades.r.line.setAttribute("stroke-dashoffset", "0");
        this.stamps.push(stamp(P.scr, 250, 470, 22));
      } else {
        P.setTab("today");
        for (const v of ["schedule", "grades", "study", "assis"]) P.views[v].node.style.display = "none";
        this.cv = el("canvas", "", P.views.today.r.campus);
        this.cv.width = 776; this.cv.height = 352;
        css(this.cv, { width: "388px", height: "176px", display: "block" });
        this.stamps.push(stamp(P.scr, 240, 610, 22));
      }
      this.dev[k] = { holder, P };
    }
    // laptop (mac), monitor (win), browser window (web)
    const frame = (w, h, kind) => {
      const holder = el("div", "abs p3d", this.world);
      const bez = el("div", "abs", holder);
      const scr = el("div", "abs", bez);
      if (kind === "mac") {
        css(bez, { left: `${-w / 2 - 18}px`, top: `${-h / 2 - 18}px`, width: `${w + 36}px`, height: `${h + 36}px`, borderRadius: "26px", background: "#0c0c0e", boxShadow: "0 0 0 3px #3a3a40, 0 70px 120px -40px rgba(0,0,0,.7)" });
        css(scr, { left: "18px", top: "18px", width: `${w}px`, height: `${h}px`, borderRadius: "10px", overflow: "hidden" });
        const base = el("div", "abs", holder);
        css(base, { left: `${-w / 2 - 110}px`, top: `${h / 2 + 18}px`, width: `${w + 220}px`, height: "26px", borderRadius: "0 0 30px 30px", background: "linear-gradient(#c9c9ce,#8e8e94)" });
      } else if (kind === "win") {
        css(bez, { left: `${-w / 2 - 16}px`, top: `${-h / 2 - 16}px`, width: `${w + 32}px`, height: `${h + 32}px`, borderRadius: "14px", background: "#111", boxShadow: "0 70px 120px -40px rgba(0,0,0,.7)" });
        css(scr, { left: "16px", top: "16px", width: `${w}px`, height: `${h}px`, overflow: "hidden", background: "linear-gradient(135deg,#1d3a6e,#5b2a6e)" });
        const stand = el("div", "abs", holder);
        css(stand, { left: "-60px", top: `${h / 2 + 16}px`, width: "120px", height: "110px", background: "linear-gradient(#2a2a2e,#18181b)" });
        const foot = el("div", "abs", holder);
        css(foot, { left: "-200px", top: `${h / 2 + 120}px`, width: "400px", height: "18px", borderRadius: "8px", background: "#202024" });
      } else {
        css(bez, { left: `${-w / 2}px`, top: `${-h / 2}px`, width: `${w}px`, height: `${h}px`, borderRadius: "14px", overflow: "hidden", boxShadow: "0 70px 120px -40px rgba(0,0,0,.7), 0 0 0 1px #0003" });
        css(scr, { left: "0", top: "0", width: `${w}px`, height: `${h}px` });
      }
      return { holder, scr };
    };
    this.dev.mac = frame(1440, 900, "mac");
    const m = macApp(this.dev.mac.scr); css(m, { inset: "0" });
    this.stamps.push(stamp(this.dev.mac.scr, 360, 250, 26));
    this.dev.win = frame(1400, 860, "win");
    const winWin = el("div", "abs", this.dev.win.scr);
    css(winWin, { left: "70px", top: "50px", width: "1260px", height: "740px", borderRadius: "8px", overflow: "hidden", boxShadow: "0 30px 60px rgba(0,0,0,.4)" });
    const w = winApp(winWin); css(w, { inset: "0" });
    this.stamps.push(stamp(winWin, 720, 150, 24));
    this.dev.web = frame(1440, 880, "web");
    const wb = webApp(this.dev.web.scr); css(wb, { inset: "0" });
    this.stamps.push(stamp(this.dev.web.scr, 1100, 280, 24));
    // labels under each device
    this.labels = DEV.map((d) => {
      const l = el("div", "abs mask display", this.world, `<span>${d.label}</span>`);
      css(l, { fontSize: "64px", color: "#f5b227", whiteSpace: "nowrap" });
      return l;
    });
    this.head = headline(layer, [{ text: "Same you,", at: 102 }, { text: "everywhere.", at: 102.5, gold: true }], { x: 110, y: 90, size: 120, out: 107.3 });
    this.tapMac = el("div", "abs", this.dev.mac.scr);
    css(this.tapMac, { left: "380px", top: "270px", width: "40px", height: "40px", borderRadius: "50%", border: "4px solid #1b5db8" });
  },
  render(b, t) {
    // camera path along the row, then wide
    const stops = [[84, -1950, 0.62], [88.5, -1950, 0.62], [90, -150, 0.62], [93.5, -150, 0.62], [94.5, 1650, 0.6], [97.5, 1650, 0.6], [98.5, 3400, 0.6], [100.5, 3400, 0.6], [101.5, 550, 0.26]];
    let s0 = stops[0], s1 = stops[0];
    for (const s of stops) if (b >= s[0]) { s0 = s1; s1 = s; }
    const k = s0 === s1 ? 1 : springB(b, s1[0], 0.95, 0.85);
    const cx = lerp(s0[1], s1[1], k), sc = lerp(s0[2], s1[2], k);
    const yaw = Math.sin(t * 0.4) * 3 - (cx - 550) / 260;
    this.world.style.transform = `perspective(3000px) scale(${sc}) rotateY(${yaw}deg) translate3d(${-cx}px, 40px, 0)`;
    this.bd.floor.style.backgroundPosition = `${cx * 0.2}px 0px`;
    this.bd.glow.style.transform = "translate(160px, -260px)";
    this.bd.glow.style.background = "radial-gradient(circle, rgba(245,178,39,.22) 0%, rgba(245,178,39,.06) 40%, transparent 62%)";
    // devices land on their beat
    DEV.forEach((d, i) => {
      const land = springB(b, d.at - 0.2, 1.6, 0.6);
      const node = this.dev[d.k].holder;
      const sway = (i % 2 ? 1 : -1) * 6;
      node.style.transform = `translate3d(${d.x}px, ${(1 - land) * -900}px, ${d.z}px) rotateY(${sway * (1 - land) + (d.k === "ios" ? 8 : d.k === "android" ? -6 : 0)}deg)`;
      node.style.display = b >= d.at - 0.2 ? "" : "none";
      const L = this.labels[i];
      const lk = pb(b, d.at + 0.5, d.at + 1, ease.outExpo);
      const y = d.k === "ios" || d.k === "android" ? 530 : d.k === "win" ? 600 : 520;
      L.style.transform = `translate3d(${d.x - 140}px, ${y}px, 0)`;
      L.firstChild.style.transform = `translateY(${(1 - lk) * 105}%)`;
    });
    const cv = renderCampus(t, { hour: 7.4, net: 1, w: 776, h: 352, aspect: 776 / 352, next: 101 });
    this.cv.getContext("2d").drawImage(cv, 0, 0);
    // tap on the Mac at 103.6, then ONLINE stamps land everywhere at 104
    const tk = pb(b, 103.6, 104.3, ease.outCubic);
    this.tapMac.style.display = b >= 103.6 && b < 104.3 ? "" : "none";
    this.tapMac.style.transform = `scale(${1 + tk * 4})`;
    this.tapMac.style.opacity = 1 - tk;
    this.stamps.forEach((s, i) => {
      const at = 104 + i * 0.12;
      const d = b - at;
      s.style.display = d >= 0 ? "" : "none";
      if (d < 0) return;
      const sc2 = d < 0.25 ? 1.9 - 0.98 * ease.outCubic(d / 0.25) : 0.92 + 0.08 * ease.outCubic(Math.min(1, (d - 0.25) / 0.35));
      s.style.transform = `rotate(-3deg) scale(${sc2})`;
      s.style.filter = `blur(${Math.max(0, 1 - d / 0.25) * 2}px)`;
    });
    void pulse;
    this.head(b);
  },
};
