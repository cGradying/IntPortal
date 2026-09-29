// PUP SIS, clean (beats 132–148). Three steps, left to right, each numbered:
// ① sign in with your own account on your own device, ② your schedule and
// grades travel over one cable as pixel packets, ③ they land as native
// cards and the sync ripples green. Mabini flips on beside PUP SIS for one
// beat ("soon"). A snare build pushes the camera in, then the tape stops.
import { clamp, css, ease, el, lerp, pb, pulse, springB } from "../lib/core.js";
import { makePhone } from "../ui/phone.js";
import { renderCampus } from "../art/campus.js";
import { pixText } from "../ui/pixtype.js";
import { makeThread } from "../ui/thread.js";
import { stageBackdrop } from "./ios.js";

const ROWS = [
  ["COMP 20073", "Data Structures and Algorithms", "M/Th 7:30–9:00AM"],
  ["GEED 10053", "Purposive Communication", "M/Th 10:30AM–12PM"],
  ["MATH 20013", "Discrete Structures", "T/F 1:00–2:30PM"],
  ["COMP 20083", "Object-Oriented Programming", "W 7:30–10:30AM"],
  ["PATHFIT 2", "Physical Activity", "S 8:00–10:00AM"],
  ["GEED 10103", "Readings in Phil. History", "T/F 3:00–4:30PM"],
];
const STEPS = [
  { at: 132.5, n: "1", t: "Sign in", c: "Your account, on your device", x: 120 },
  { at: 136, n: "2", t: "It comes over", c: "Schedule and grades", x: 760 },
  { at: 139, n: "3", t: "In the app", c: "Native, and it stays synced", x: 1340 },
];
/** Tape stop: time slows to a halt across beat 147 → 148. */
const slow = (b) => (b < 147 ? b : 147 + 0.55 * (1 - (1 - clamp(b - 147)) ** 2));

export default {
  id: "sync", from: 132, to: 148,
  init(layer) {
    this.root = el("div", "abs", layer);
    css(this.root, { inset: "0", transformOrigin: "50% 55%" });
    const R = this.root;
    this.bd = stageBackdrop(R);
    // host plate
    this.host = el("div", "abs", R);
    css(this.host, { left: "100px", top: "360px", width: "620px", height: "470px", perspective: "1600px" });
    this.plate = el("div", "abs p3d notch", this.host);
    css(this.plate, { inset: "0", background: "#f4f2ef", color: "#1c1517", boxShadow: "0 60px 120px -30px rgba(0,0,0,.7)", fontFamily: "var(--ui)" });
    this.plate.innerHTML = `
      <div style="height:60px;background:#6d0e1f;color:#f7ecec;display:flex;align-items:center;gap:12px;padding:0 20px">
        <div style="font:700 24px var(--pixel)">PUP SIS</div>
        <div style="margin-left:auto;font:600 15px var(--ui);background:#560a19;padding:6px 12px">sis8.pup.edu.ph</div></div>
      <div style="padding:16px 20px">
        <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:10px"><div style="font:700 20px var(--pixel)">Class schedule</div>
          <div data-r="auth" style="font:700 15px var(--ui);padding:6px 12px">Signing in…</div></div>
        ${ROWS.map((r, i) => `<div data-r="r${i}" style="display:flex;gap:12px;padding:10px 12px;border:1px solid #e2ddd6;border-top:${i ? "0" : "1px solid #e2ddd6"};background:#fff;font:500 15px var(--ui)"><b style="width:110px;font:700 15px var(--display)">${r[0]}</b><span style="flex:1;color:#554c4f;white-space:nowrap;overflow:hidden">${r[1]}</span></div>`).join("")}
      </div>`;
    this.r = {};
    this.plate.querySelectorAll("[data-r]").forEach((n) => (this.r[n.dataset.r] = n));
    // Mabini, beside it, for one beat
    this.mab = el("div", "abs notch", R, `<div style="font:700 26px var(--pixel);color:#6fd6c0">Mabini</div><div style="font:600 18px var(--ui);color:#cdbbd8;margin-top:6px">PUP online · soon</div>`);
    css(this.mab, { left: "400px", top: "250px", width: "320px", padding: "18px 22px", background: "#142a2a", border: "3px solid #6fd6c0" });
    // phone
    this.P = makePhone(R);
    this.P.setRoom("Night");
    this.P.setTab("today");
    for (const k of ["schedule", "grades", "study", "notes", "assis"]) this.P.views[k].node.style.display = "none";
    this.rowsEls = [...this.P.views.today.r.rows.querySelectorAll(".row")];
    this.cv = el("canvas", "", this.P.views.today.r.campus);
    this.cv.width = 776; this.cv.height = 352;
    css(this.cv, { width: "388px", height: "176px", display: "block" });
    // cable + packets
    this.cable = makeThread(R, { width: 10, color: "#f5b227", z: 10 });
    this.packets = ROWS.map(([c], i) => {
      const d = el("div", "abs", R, c);
      css(d, { font: "700 22px var(--pixel)", color: "#1b1406", background: i % 2 ? "#f5b227" : "#fff1c4", padding: "6px 12px", whiteSpace: "nowrap", zIndex: 12 });
      return d;
    });
    this.ripple = el("div", "abs notch", R);
    css(this.ripple, { border: "10px solid #58c792" });
    // step labels
    this.steps = STEPS.map((s) => ({
      s,
      n: pixText(R, { text: s.n, size: 110, font: "pixel", x: s.x, y: 60, ink: "#f5b227", shadow: "#2a0a14" }),
      t: pixText(R, { text: s.t, size: 64, x: s.x + 90, y: 90, ink: "#f7ecec", shadow: "#000" }),
      c: (() => { const d = el("div", "abs", R, s.c); css(d, { left: `${s.x + 94}px`, top: "178px", font: "400 28px var(--ui)", color: "#cdbbd8" }); return d; })(),
    }));
    this.lock = el("div", "abs notch", R, "🔒&nbsp; Your account · your device · nothing else");
    css(this.lock, { left: "100px", top: "870px", padding: "14px 22px", font: "700 26px var(--ui)", background: "#f5b227", color: "#1b1406" });
  },
  render(b0, t) {
    const b = slow(b0);
    const P = this.P;
    // build: push in with the snare roll; tape stop dims to black
    const push = pb(b0, 140, 147, ease.inCubic);
    const jit = b0 >= 144 && b0 < 147 ? Math.sin(b0 * 50) * (b0 - 144) * 1.2 : 0;
    const dark = pb(b0, 147, 148, ease.inQuad);
    this.root.style.transform = `translate(${jit}px, ${-jit * 0.6}px) scale(${1 + push * 0.1 - dark * 0.04})`;
    this.root.style.filter = dark > 0 ? `brightness(${1 - dark * 0.92}) saturate(${1 - dark})` : "";

    const inK = springB(b, 131.9, 1.6, 0.75);
    this.plate.style.transform = `translateX(${(1 - inK) * -900}px) rotateY(${14 * (1 - inK) + 10}deg) rotateX(4deg)`;
    const authed = b >= 134.5;
    const auth = authed ? "Signed in ✓" : "Signing in…";
    if (this.r.auth.textContent !== auth) this.r.auth.textContent = auth;
    css(this.r.auth, { background: authed ? "#e3f3ea" : "#e3ecf9", color: authed ? "#1e7249" : "#1b4f99", transform: `scale(${1 + pulse(b, 134.5, 0.5) * 0.15})` });
    const lk = springB(b, 135, 2.2, 0.6);
    this.lock.style.display = b >= 135 ? "" : "none";
    this.lock.style.transform = `translateY(${(1 - lk) * 60}px) scale(${clamp(lk, 0, 1.1)})`;
    // Mabini flip: 144 → 145.5
    const mOn = b >= 143.9 && b < 145.7;
    this.mab.style.display = mOn ? "" : "none";
    if (mOn) this.mab.style.transform = `perspective(900px) rotateX(${(1 - pb(b, 143.9, 144.25, ease.outBack)) * -90 + pb(b, 145.3, 145.7, ease.inCubic) * 90}deg)`;

    // phone
    const pIn = springB(b, 131.95, 1.4, 0.78);
    const px = lerp(2300, 1500, pIn), py = 580;
    P.root.style.transformOrigin = "230px 481px";
    P.root.style.transform = `perspective(2400px) translate3d(${px - 230}px, ${py - 481}px, 0) rotateY(-12deg) rotateX(4deg) scale(0.9)`;
    const cv = renderCampus(t, { hour: 7.5, net: 0.4 + 0.6 * pb(b, 137, 142), w: 776, h: 352, aspect: 776 / 352, next: 101 });
    this.cv.getContext("2d").drawImage(cv, 0, 0);
    const isl = b < 134.5 ? "Signing in to <b>PUP SIS</b>" : b < 142 ? "Syncing <b>schedule</b>…" : "Synced · <b>just now</b>";
    if (P.islandT.innerHTML !== isl) P.islandT.innerHTML = isl;

    // cable from the plate to the phone, packets on sixteenths from 137
    const a = this.plate.getBoundingClientRect(), p = P.root.getBoundingClientRect();
    const A0 = [a.right - 10, a.top + a.height * 0.5], C0 = [p.left + 40, p.top + p.height * 0.62];
    const ck = pb(b, 136, 136.9, ease.outCubic);
    this.cable.render(b >= 136, A0, C0, ck, null, -160);
    const mx = (A0[0] + C0[0]) / 2, my = (A0[1] + C0[1]) / 2 - 160;
    const pt = (u) => [(1 - u) ** 2 * A0[0] + 2 * (1 - u) * u * mx + u * u * C0[0], (1 - u) ** 2 * A0[1] + 2 * (1 - u) * u * my + u * u * C0[1]];
    this.packets.forEach((d, i) => {
      const at = 137 + i * 0.5;
      const k = pb(b, at, at + 1.4, ease.inOutCubic);
      const on = b >= at && k < 1;
      d.style.display = on ? "" : "none";
      this.r[`r${i}`].style.background = b >= at - 0.25 && b < at + 0.5 ? "#fff3cf" : "#fff";
      if (!on) return;
      const [x, y] = pt(k);
      d.style.transform = `translate(${x - 70}px, ${y - 20}px) scale(${1 + Math.sin(k * Math.PI) * 0.15})`;
    });
    this.rowsEls.forEach((row, i) => {
      const at = 137 + i * 0.5 + 1.4;
      const k = springB(b, at, 2.4, 0.5);
      row.style.transform = b < at ? "scale(0.9)" : `scale(${0.9 + 0.1 * clamp(k, 0, 1.15)})`;
      row.style.opacity = b < at ? 0.2 : 1;
    });
    // ripple at 142
    const rk = pb(b, 142, 143.6, ease.outCubic);
    this.ripple.style.display = b >= 142 && b < 143.6 ? "" : "none";
    const gl = P.island.getBoundingClientRect();
    const size = 40 + rk * 2400;
    css(this.ripple, { left: `${gl.left + 22 - size / 2}px`, top: `${gl.top + 23 - size / 2}px`, width: `${size}px`, height: `${size}px`, opacity: String(1 - rk) });
    // steps
    this.steps.forEach(({ s, n, t: tt, c }) => {
      n.render(b, { at: s.at, dur: 0.6, out: 146.4, outDur: 0.5 });
      tt.render(b, { at: s.at + 0.25, dur: 0.9, out: 146.5, outDur: 0.5 });
      c.style.display = b >= s.at + 0.8 && b < 146.6 ? "" : "none";
      c.style.transform = `translateY(${(1 - pb(b, s.at + 0.8, s.at + 1.3, ease.outExpo)) * 30}px)`;
    });
    this.bd.glow.style.transform = `translate(${px - 900}px, -300px)`;
    this.bd.glow.style.background = `radial-gradient(circle, rgba(88,199,146,${0.18 + pulse(b, 142, 2) * 0.3}) 0%, transparent 60%)`;
  },
};
