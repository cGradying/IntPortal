// Hook (beats 0–7.6): "Class in nine minutes." slams in word by word on 8ths,
// then the old portal: a dated SIS page in 3D, a cursor hammering Sign in, a
// spinner, and the SESSION EXPIRED stamp on "expired". The page shatters into
// tiles and falls away into the void where the new portal is forming.
import { BEAT, clamp, css, ease, el, hash, noise1, pb, pulse, springB } from "../lib/core.js";

const WORDS = [
  { w: "Class", at: 0.0, x: 90, y: 200, size: 470, col: "#f7ecec" },
  { w: "in", at: 0.5, x: 900, y: 250, size: 560, col: "#f7ecec" },
  { w: "nine", at: 1.0, x: 120, y: 180, size: 600, col: "#f5b227" },
  { w: "minutes.", at: 1.5, x: 70, y: 290, size: 400, col: "#f7ecec" },
];
const SAYS = ["And", "the portal", "says…"];
const SAYS_AT = [2.6, 3.1, 4.2];

function oldPage() {
  const rows = [
    ["COMP 20073", "Data Structures and Algorithms", "M/Th 7:30AM-9:00AM", "S512"],
    ["GEED 10053", "Purposive Communication", "M/Th 10:30AM-12:00PM", "N301"],
    ["MATH 20013", "Discrete Structures", "T/F 1:00PM-2:30PM", "S208"],
    ["COMP 20083", "Object-Oriented Programming", "W 7:30AM-10:30AM", "LAB 3"],
    ["PATHFIT 2", "Physical Activity Towards Health", "S 8:00AM-10:00AM", "GYM"],
    ["GEED 10103", "Readings in Philippine History", "T/F 3:00PM-4:30PM", "N210"],
  ];
  return `
  <div style="height:44px;background:linear-gradient(#e9e9e9,#cfcfcf);border-bottom:1px solid #999;display:flex;align-items:center;gap:10px;padding:0 14px">
    <i style="width:12px;height:12px;border-radius:50%;background:#e0625a"></i><i style="width:12px;height:12px;border-radius:50%;background:#e5bf3c"></i><i style="width:12px;height:12px;border-radius:50%;background:#62c254"></i>
    <div style="margin-left:18px;flex:1;height:26px;background:#fff;border:1px solid #aaa;border-radius:4px;font:14px Arial;color:#555;padding:4px 10px">https://sis.example.edu.ph/student/schedule.php?sid=…</div>
  </div>
  <div style="height:70px;background:linear-gradient(#5d6b7d,#3f4a58);color:#fff;font:bold 24px 'Times New Roman';padding:20px 24px">Student Information System <span style="font:13px Arial;opacity:.8">Student Module (Beta)</span></div>
  <div style="display:flex;height:calc(100% - 114px);background:#fff">
    <div style="width:210px;background:#eef0f3;border-right:1px solid #c7ccd3;padding:16px;font:15px Arial;line-height:2;color:#1a4fb5;text-decoration:underline">Home<br>Enrollment<br>Class Schedule<br>Grades<br>Account<br>Logout</div>
    <div style="flex:1;padding:20px 24px;font:14px Arial;color:#222">
      <div style="font:bold 18px Arial;margin-bottom:10px">Class Schedule — 1st Semester</div>
      <table style="border-collapse:collapse;width:100%">
        <tr>${["Code", "Description", "Schedule", "Room"].map((h) => `<th style="border:1px solid #999;background:#d7dbe0;padding:6px;text-align:left">${h}</th>`).join("")}</tr>
        ${rows.map((r) => `<tr>${r.map((c) => `<td style="border:1px solid #bbb;padding:6px">${c}</td>`).join("")}</tr>`).join("")}
      </table>
      <div data-r="btn" style="margin-top:22px;display:inline-block;padding:8px 22px;background:linear-gradient(#f6f6f6,#d9d9d9);border:1px solid #888;border-radius:3px;font:15px Arial">Sign in again</div>
    </div>
  </div>`;
}

export default {
  id: "hook", from: 0, to: 7.7,
  init(layer) {
    css(layer, { background: "transparent" });
    this.bg = el("div", "abs", layer);
    css(this.bg, { inset: "0", background: "#0a080c" });
    this.floor = el("div", "abs", layer);
    css(this.floor, { left: "-1200px", right: "-1200px", top: "560px", height: "1500px", transformOrigin: "50% 0%", transform: "perspective(800px) rotateX(74deg)",
      backgroundImage: "radial-gradient(rgba(245,178,39,.45) 2.4px, transparent 3px)", backgroundSize: "52px 52px",
      maskImage: "linear-gradient(to bottom, transparent, #000 20%, #000 55%, transparent)", WebkitMaskImage: "linear-gradient(to bottom, transparent, #000 20%, #000 55%, transparent)" });
    this.clock = el("div", "abs display", layer, "7:21");
    css(this.clock, { right: "60px", top: "40px", fontSize: "200px", color: "#7a1128", letterSpacing: "-0.04em" });
    // gold seed pixel
    this.pix = el("div", "abs", layer);
    css(this.pix, { width: "22px", height: "22px", background: "#f5b227" });
    // kinetic words
    this.words = WORDS.map((w) => {
      const d = el("div", "abs display", layer, w.w);
      css(d, { left: `${w.x}px`, top: `${w.y}px`, fontSize: `${w.size}px`, color: w.col, transformOrigin: "0% 60%", whiteSpace: "nowrap" });
      return d;
    });
    // old page in 3D, split into tiles for the shatter
    this.stage = el("div", "abs", layer);
    css(this.stage, { left: "640px", top: "150px", width: "1180px", height: "760px", perspective: "1600px" });
    this.pageRoot = el("div", "abs p3d", this.stage);
    css(this.pageRoot, { inset: "0", transformOrigin: "50% 50%" });
    this.whole = el("div", "abs", this.pageRoot, oldPage());
    css(this.whole, { inset: "0", background: "#fff", borderRadius: "10px", overflow: "hidden" });
    this.wdim = el("div", "abs", this.whole); css(this.wdim, { inset: "0", background: "rgba(30,30,34,.55)" });
    this.wspin = el("div", "abs", this.whole);
    css(this.wspin, { left: "600px", top: "360px", width: "64px", height: "64px", borderRadius: "50%", border: "8px solid rgba(255,255,255,.25)", borderTopColor: "#fff" });
    this.wbtn = this.whole.querySelector("[data-r=btn]");
    this.tiles = [];
    const TX = 8, TY = 6;
    for (let y = 0; y < TY; y++) {
      for (let x = 0; x < TX; x++) {
        const tile = el("div", "abs", this.pageRoot);
        const w = 1180 / TX, h = 760 / TY;
        css(tile, { left: `${x * w}px`, top: `${y * h}px`, width: `${w + 0.5}px`, height: `${h + 0.5}px`, overflow: "hidden", backfaceVisibility: "hidden" });
        const page = el("div", "abs", tile, oldPage());
        css(page, { left: `${-x * w}px`, top: `${-y * h}px`, width: "1180px", height: "760px", background: "#fff", borderRadius: "10px", overflow: "hidden" });
        const dim = el("div", "abs", page);
        css(dim, { inset: "0", background: "rgba(30,30,34,.55)" });
        const spin = el("div", "abs", page);
        css(spin, { left: "600px", top: "360px", width: "64px", height: "64px", borderRadius: "50%", border: "8px solid rgba(255,255,255,.25)", borderTopColor: "#fff" });
        this.tiles.push({ tile, x, y, page, dim, spin, btn: page.querySelector("[data-r=btn]") });
      }
    }
    // cursor
    this.cursor = el("div", "abs", this.pageRoot,
      `<svg width="34" height="46" viewBox="0 0 17 23"><path d="M1 1 L1 18 L5.5 13.8 L8.6 21 L11.4 19.8 L8.4 12.8 L14.5 12.8 Z" fill="#fff" stroke="#000" stroke-width="1.3"/></svg>`);
    // stamp (app's stamp grammar: pixel face, 2pt border, -3deg)
    this.stamp = el("div", "abs", this.stage, "SESSION<br>EXPIRED");
    css(this.stamp, { left: "220px", top: "200px", padding: "22px 40px", border: "10px solid #e5484d", color: "#e5484d", fontFamily: "var(--pixel)", fontWeight: 700, fontSize: "124px", lineHeight: "0.95", letterSpacing: "0.08em", textAlign: "center", background: "rgba(10,8,12,.12)" });
    // "And the portal says…"
    this.says = SAYS.map((s, i) => {
      const m = el("div", "abs mask display", layer, `<span>${s}</span>`);
      css(m, { left: "110px", top: `${300 + i * 118}px`, fontSize: "112px", color: i === 1 ? "#f5b227" : "#f7ecec" });
      return m;
    });
  },
  render(b) {
    const hookOn = b < 2.55;
    this.floor.style.display = this.clock.style.display = hookOn ? "" : "none";
    this.floor.style.backgroundPosition = `0px ${b * 140}px`;
    this.clock.style.transform = `translateY(${(1 - pb(b, 0, 0.3, ease.outExpo)) * -120}px) scale(${1 + pulse(b, 0, 0.5) * 0.1 + pulse(b, 1, 0.5) * 0.06})`;
    this.clock.textContent = b < 1.25 ? "7:21" : "7:22";
    // ---- kinetic words (0 – 2.5)
    let active = -1;
    WORDS.forEach((w, i) => { if (b >= w.at - 0.001 && b < 2.55) active = i; });
    this.words.forEach((d, i) => {
      const on = i === active;
      d.style.display = on ? "" : "none";
      if (!on) return;
      const w = WORDS[i];
      const k = w.at === 0 ? pb(b, -0.05, 0.25, ease.outExpo) : pb(b, w.at, w.at + 0.35, ease.outExpo);
      const drift = (b - w.at) * 18;
      d.style.transform = `translate(${drift}px, ${(1 - k) * 40}px) scale(${1.28 - 0.28 * k}) rotate(${(1 - k) * -3}deg)`;
      d.style.filter = `blur(${(1 - k) * 8}px)`;
    });
    // seed pixel: lands at beat 0, hops on each word
    const hop = WORDS.reduce((a, w) => a + pulse(b, w.at, 0.4), 0);
    const land = 1;
    css(this.pix, { left: "96px", top: `${130 - 520 * (1 - land) - hop * 26}px`, display: b < 2.55 ? "" : "none" });

    // ---- old page (2.5 – 7.6)
    const pageOn = b >= 2.5;
    this.stage.style.display = pageOn ? "" : "none";
    this.says.forEach((m, i) => {
      const on = b >= SAYS_AT[i] && b < 6.3;
      m.style.display = on ? "" : "none";
      const k = pb(b, SAYS_AT[i], SAYS_AT[i] + 0.4, ease.outExpo);
      m.firstChild.style.transform = `translateY(${(1 - k) * 110}%)`;
    });
    if (!pageOn) return;
    const enter = pb(b, 2.5, 3.1, ease.outExpo);
    const shake = pulse(b, 6.5, 0.8) * 14;
    const push = pb(b, 2.5, 7.6, ease.lin);
    this.pageRoot.style.transform =
      `translate3d(${(1 - enter) * 700 + noise1(b * 9, 3) * shake}px, ${noise1(b * 9, 7) * shake}px, ${-push * 160}px) rotateY(${-22 + enter * 6 + push * 4}deg) rotateX(${6 - push * 2}deg)`;

    // cursor clicks on 8ths: 3.0 3.5 4.0 4.5 5.0
    const clicks = [3.0, 3.5, 4.0, 4.5, 5.0];
    const press = clicks.reduce((a, c) => Math.max(a, pulse(b, c, 0.25)), 0);
    this.cursor.style.transform = `translate(${360 + Math.sin(b * 3) * 6}px, ${445 + (1 - enter) * 200}px) scale(${1 - press * 0.15})`;
    this.cursor.style.display = b < 6.2 ? "" : "none";
    const loading = b >= 3.0;
    const dimA = b < 3.0 ? 0 : b < 5.6 ? 0.25 + 0.2 * press : 0.62;
    const spinA = b * 540 * BEAT;

    // shatter from 6.9
    const sh = pb(b, 6.95, 7.7, ease.inCubic);
    const shattering = sh > 0;
    this.whole.style.display = shattering ? "none" : "";
    this.wdim.style.opacity = dimA;
    this.wspin.style.display = loading && b < 6.3 ? "" : "none";
    this.wspin.style.transform = `rotate(${spinA}deg)`;
    this.wbtn.style.filter = `brightness(${1 - press * 0.25})`;
    this.tiles.forEach((T) => {
      T.tile.style.display = shattering ? "" : "none";
      if (!shattering) return;
      T.dim.style.opacity = dimA;
      T.spin.style.display = loading && b < 6.3 ? "" : "none";
      T.spin.style.transform = `rotate(${spinA}deg)`;
      T.btn.style.filter = `brightness(${1 - press * 0.25})`;
      if (sh <= 0) { T.tile.style.transform = ""; T.tile.style.opacity = 1; return; }
      const r1 = hash(T.x, T.y, 11), r2 = hash(T.x, T.y, 12), r3 = hash(T.x, T.y, 13);
      const delay = (Math.abs(T.x - 3.5) / 4 + T.y / 6) * 0.25;
      const k = clamp((sh - delay) / (1 - delay));
      T.tile.style.transform = `translate3d(${(T.x - 3.5) * 40 * k}px, ${k * k * 500 + (r2 - 0.5) * 80 * k}px, ${-k * 900 * (0.6 + r1)}px) rotateX(${k * 160 * (r3 - 0.5)}deg) rotateY(${k * 140 * (r1 - 0.5)}deg)`;
      T.tile.style.opacity = 1 - k * 0.9;
    });
    this.bg.style.opacity = 1 - sh;

    // stamp thunk at 6.5: scale 1.9 → 0.92 → 1, blur 2 → 0
    const st = b - 6.5;
    this.stamp.style.display = st >= 0 && b < 7.3 ? "" : "none";
    if (st >= 0) {
      const s = st < 0.25 ? 1.9 - 0.98 * ease.outCubic(st / 0.25) : 0.92 + 0.08 * ease.outCubic(clamp((st - 0.25) / 0.35));
      this.stamp.style.transform = `translateZ(40px) rotate(-3deg) scale(${s})`;
      this.stamp.style.filter = `blur(${clamp(1 - st / 0.25) * 3}px)`;
      this.stamp.style.opacity = 1 - pb(b, 6.95, 7.3);
    }
  },
};
