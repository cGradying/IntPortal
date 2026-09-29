// PUPSIS integration (beats 108–140). A host plate in the SIS's own grammar
// signs in with your account; its schedule and grade rows lift off as
// light-lines and land in the phone as native cards (the SIS web UI is never
// shown to you — this is the one time you see it, from behind the glass).
// The sync ripple goes green. Then IntAssis answers a question grounded in
// the synced grades, and the build flashes the feature set word by word.
import { clamp, css, ease, el, lerp, pb, pulse, springB } from "../lib/core.js";
import { makePhone } from "../ui/phone.js";
import { renderCampus } from "../art/campus.js";
import { headline } from "../ui/type.js";
import { stageBackdrop } from "./ios.js";

const ROWS = [
  ["COMP 20073", "Data Structures and Algorithms", "M/Th 7:30–9:00AM"],
  ["GEED 10053", "Purposive Communication", "M/Th 10:30AM–12PM"],
  ["MATH 20013", "Discrete Structures", "T/F 1:00–2:30PM"],
  ["COMP 20083", "Object-Oriented Programming", "W 7:30–10:30AM"],
  ["PATHFIT 2", "Physical Activity", "S 8:00–10:00AM"],
  ["GEED 10103", "Readings in Phil. History", "T/F 3:00–4:30PM"],
];
const WORDS = ["Schedule", "Grades", "Notes", "Decks", "Reminders", "Calendar", "IntAssis", "Rooms"];

export default {
  id: "sync", from: 108, to: 139.8,
  init(layer) {
    this.bd = stageBackdrop(layer);
    // host plate
    this.host = el("div", "abs", layer);
    css(this.host, { left: "110px", top: "300px", width: "700px", height: "520px", perspective: "1600px" });
    this.plate = el("div", "abs p3d", this.host);
    css(this.plate, { inset: "0", background: "#f4f2ef", color: "#1c1517", boxShadow: "0 60px 120px -30px rgba(0,0,0,.7)", fontFamily: "var(--ui)" });
    this.plate.classList.add("notch");
    this.plate.innerHTML = `
      <div style="height:64px;background:#6d0e1f;color:#f7ecec;display:flex;align-items:center;gap:14px;padding:0 22px">
        <div style="font:700 26px var(--pixel)">PUP SIS</div><div style="font:500 16px var(--ui);opacity:.8">Student Module</div>
        <div data-r="host" style="margin-left:auto;font:600 16px var(--ui);background:#560a19;padding:6px 12px">sis8.pup.edu.ph</div></div>
      <div style="padding:18px 22px">
        <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:12px"><div style="font:700 22px var(--pixel)">Class schedule</div>
          <div data-r="auth" style="font:700 15px var(--ui);padding:6px 12px;background:#e3ecf9;color:#1b4f99">Signing in…</div></div>
        ${ROWS.map((r, i) => `<div data-r="r${i}" style="display:flex;gap:14px;padding:11px 12px;border:1px solid #e2ddd6;border-top:${i ? "0" : "1px solid #e2ddd6"};background:#fff;font:500 16px var(--ui)"><b style="width:120px;font:700 16px var(--display)">${r[0]}</b><span style="flex:1;color:#554c4f">${r[1]}</span><span style="color:#766c6f">${r[2]}</span></div>`).join("")}
        <div style="margin-top:16px;display:flex;gap:10px"><div class="notch" style="padding:8px 14px;background:#1b5db8;color:#fff;font:500 16px var(--pixel)">Grades</div><div class="notch" style="padding:8px 14px;border:2px solid #cbc3b9;font:500 16px var(--pixel)">COR</div></div>
      </div>`;
    this.r = {};
    this.plate.querySelectorAll("[data-r]").forEach((n) => (this.r[n.dataset.r] = n));
    // lock chips under the plate
    this.chips = ["Your account", "Your device", "Nothing else"].map((t, i) => {
      const c = el("div", "abs notch display", layer, t);
      css(c, { left: `${110 + i * 250}px`, top: "872px", padding: "14px 20px", fontSize: "26px", background: i === 2 ? "transparent" : "#f5b227", color: i === 2 ? "#f5b227" : "#1b1406", border: i === 2 ? "3px solid #f5b227" : "none" });
      return c;
    });
    // phone
    this.P = makePhone(layer);
    this.P.setRoom("Night");
    this.P.setTab("today");
    for (const k of ["schedule", "grades", "study"]) this.P.views[k].node.style.display = "none";
    this.rowsEls = [...this.P.views.today.r.rows.querySelectorAll(".row")];
    this.cv = el("canvas", "", this.P.views.today.r.campus);
    this.cv.width = 776; this.cv.height = 352;
    css(this.cv, { width: "388px", height: "176px", display: "block" });
    // light-lines
    this.svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
    this.svg.setAttribute("width", "1920");
    this.svg.setAttribute("height", "1080");
    css(this.svg, { position: "absolute", left: "0", top: "0", overflow: "visible" });
    layer.appendChild(this.svg);
    this.paths = ROWS.map(() => {
      const p = document.createElementNS("http://www.w3.org/2000/svg", "path");
      p.setAttribute("fill", "none");
      p.setAttribute("stroke", "#f5b227");
      p.setAttribute("stroke-width", "3");
      this.svg.appendChild(p);
      const dot = document.createElementNS("http://www.w3.org/2000/svg", "rect");
      dot.setAttribute("width", "16"); dot.setAttribute("height", "16"); dot.setAttribute("fill", "#ffe7a8");
      this.svg.appendChild(dot);
      return { p, dot };
    });
    // sync ripple: a pixel ring
    this.ripple = el("div", "abs", layer);
    css(this.ripple, { width: "40px", height: "40px", border: "10px solid #58c792", borderRadius: "0" });
    this.ripple.classList.add("notch");
    this.head1 = headline(layer, [{ text: "Works with", at: 110 }, { text: "PUP SIS.", at: 110.6, gold: true }], { x: 110, y: 48, size: 96, out: 123.2 });
    this.head2 = headline(layer, [{ text: "Ask it", at: 126 }, { text: "anything.", at: 126.6, gold: true }], { x: 110, y: 340, size: 150, out: 131.6 });
    this.words = WORDS.map((w, i) => {
      const d = el("div", "abs display", layer, w);
      css(d, { fontSize: `${[190, 210, 230, 200, 170, 190, 210, 240][i]}px`, color: i % 2 ? "#f5b227" : "#f7ecec", whiteSpace: "nowrap", left: `${[110, 150, 90, 130, 100, 140, 110, 120][i]}px`, top: `${[330, 300, 360, 320, 360, 300, 340, 300][i]}px` });
      return d;
    });
  },
  render(b, t) {
    const P = this.P;
    // plate swings in, leaves at 123.5
    const inK = springB(b, 107.55, 1.5, 0.75);
    const outK = pb(b, 123.2, 124.4, ease.inCubic);
    this.host.style.display = b < 124.5 ? "" : "none";
    this.plate.style.transform = `translateX(${(1 - inK) * -900 - outK * 1100}px) rotateY(${14 * (1 - inK) + 10}deg) rotateX(4deg)`;
    const authed = b >= 111.5;
    this.r.auth.textContent = authed ? "Signed in ✓" : "Signing in…";
    this.r.auth.style.background = authed ? "#e3f3ea" : "#e3ecf9";
    this.r.auth.style.color = authed ? "#1e7249" : "#1b4f99";
    this.chips.forEach((c, i) => {
      const k = springB(b, 112 + i * 0.5, 2.2, 0.6);
      c.style.display = b >= 112 + i * 0.5 && b < 124 ? "" : "none";
      c.style.transform = `translateY(${(1 - k) * 60 - outK * 300}px) scale(${clamp(k, 0, 1.1)})`;
    });
    // phone
    const pIn = springB(b, 107.6, 1.4, 0.78);
    const center = pb(b, 122.8, 124.2, ease.inOutCubic);
    const exitK = pb(b, 131.5, 139.6, ease.inCubic);
    const px = lerp(lerp(2200, 1390, pIn), 1300, center), py = lerp(560, 500, center);
    const sc = lerp(1.08, 1.85, center) * (1 - exitK * 0.6);
    const oy = lerp(480, 560, center);
    P.root.style.transformOrigin = `230px ${oy}px`;
    P.root.style.transform = `perspective(2400px) translate3d(${px - 230 + exitK * 260}px, ${py - oy}px, 0) rotateY(${-14 + center * 4 - exitK * 30}deg) rotateX(4deg) scale(${sc})`;
    if (b < 124.8) {
      const cv = renderCampus(t, { hour: 7.5, net: 0.4 + 0.6 * pb(b, 113, 121), w: 776, h: 352, aspect: 776 / 352, next: 101 });
      this.cv.getContext("2d").drawImage(cv, 0, 0);
    }
    // rows land on beats 113..118: highlight in SIS, travel, pop in phone
    const rowsOn = b < 124;
    const phoneRows = this.rowsEls;
    this.paths.forEach(({ p, dot }, i) => {
      const at = 113 + i * 0.75;
      const src = this.r[`r${i}`];
      src.style.background = b >= at && b < at + 0.8 ? "#fff3cf" : "#fff";
      const k = pb(b, at, at + 1.1, ease.inOutCubic);
      const show = rowsOn && b >= at && b < at + 1.6;
      p.style.display = dot.style.display = show ? "" : "none";
      if (!show) return;
      const a = src.getBoundingClientRect();
      const tgt = phoneRows[i % 2].getBoundingClientRect();
      const x0 = a.right, y0 = a.top + a.height / 2, x1 = tgt.left, y1 = tgt.top + tgt.height / 2;
      const c1 = x0 + 260, c2 = x1 - 260;
      p.setAttribute("d", `M${x0},${y0} C${c1},${y0 - 120} ${c2},${y1 + 120} ${x1},${y1}`);
      const len = p.getTotalLength();
      p.setAttribute("stroke-dasharray", `${len}`);
      p.setAttribute("stroke-dashoffset", `${len * (1 - k)}`);
      p.setAttribute("opacity", String(1 - pb(b, at + 1.1, at + 1.6)));
      const pt = p.getPointAtLength(len * k);
      dot.setAttribute("x", String(pt.x - 8));
      dot.setAttribute("y", String(pt.y - 8));
    });
    phoneRows.forEach((row, i) => {
      const at = 113 + i * 0.75 + 1.1 - (i >= 2 ? 1.5 : 0);
      const k = springB(b, at, 2.4, 0.5);
      row.style.transform = b < 112 ? "scale(0.9)" : `scale(${0.9 + 0.1 * clamp(k, 0, 1.15)})`;
      row.style.opacity = b < 112 ? 0.25 : b < at ? 0.25 : 1;
    });
    // ripple at 120 from the island glyph
    const rk = pb(b, 120, 121.6, ease.outCubic);
    this.ripple.style.display = b >= 120 && b < 121.6 ? "" : "none";
    const gl = P.island.getBoundingClientRect();
    const size = 40 + rk * 2600;
    css(this.ripple, { left: `${gl.left + 22 - size / 2}px`, top: `${gl.top + 23 - size / 2}px`, width: `${size}px`, height: `${size}px`, opacity: String(1 - rk) });
    const isl = b < 111.5 ? "Signing in to <b>PUP SIS</b>" : b < 120 ? "Syncing <b>schedule</b>…" : "Synced · <b>just now</b>";
    if (P.islandT.innerHTML !== isl) P.islandT.innerHTML = isl;
    // IntAssis from 124.5
    const A = P.views.assis;
    const aOn = b >= 124.3;
    A.node.style.display = aOn ? "" : "none";
    if (aOn) {
      const up = springB(b, 124.3, 1.6, 0.8);
      A.r.sheet.style.transform = `translateY(${(1 - up) * 640}px)`;
      const qk = springB(b, 125.2, 2.4, 0.6);
      A.r.q.style.transform = `scale(${clamp(qk, 0, 1.1)})`;
      A.r.q.style.transformOrigin = "100% 100%";
      const ans = "Average 1.69 or better on your last 2 subjects and you land a 1.50.";
      const n = Math.floor(ans.length * pb(b, 126.2, 128.6));
      const s = ans.slice(0, n);
      if (A.r.aT.textContent !== s) A.r.aT.textContent = s;
      const sweep = pb(b, 126.2, 128.8);
      A.r.a.style.display = b >= 126 ? "" : "none";
      A.r.a.style.backgroundImage = sweep < 1 ? `linear-gradient(90deg, transparent ${sweep * 100 - 12}%, rgba(245,178,39,.35) ${sweep * 100 - 4}%, transparent ${sweep * 100 + 4}%)` : "none";
      A.r.cite.style.display = b >= 129 ? "" : "none";
      A.r.cite.style.transform = `scale(${clamp(springB(b, 129, 2.6, 0.5), 0, 1.1)})`;
    }
    // feature words, one per beat, 132 → 139.5
    this.words.forEach((d, i) => {
      const at = 132 + i;
      const on = b >= at && b < at + 1 && b < 139.6;
      d.style.display = on ? "" : "none";
      if (!on) return;
      const k = pb(b, at, at + 0.3, ease.outExpo);
      d.style.transform = `translateX(${(1 - k) * -60 + (b - at) * 30}px) scale(${1.15 - 0.15 * k})`;
      d.style.filter = `blur(${(1 - k) * 6}px)`;
    });
    this.bd.glow.style.transform = `translate(${px - 800}px, -260px)`;
    this.bd.glow.style.background = `radial-gradient(circle, rgba(${b < 124 ? "88,199,146" : "245,178,39"},${0.22 + pulse(b, 120, 2) * 0.3}) 0%, transparent 60%)`;
    this.head1(b);
    this.head2(b);
    void t;
  },
};
