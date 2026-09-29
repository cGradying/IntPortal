// iOS round trip (beats 19.6–68): the phone lands out of the warp flash and
// the camera travels through the app — Today (new campus card, Island glance
// morphs), Schedule (blocks pop, week cube-turn), Grades (GPA count, stamps
// thunk on beats, Coach types), Study (deck fan-out, flip, rate), then Isko
// hops up inside the app as your helper.
import { BEAT, clamp, css, ease, el, lerp, noise1, pb, pulse, springB, tb } from "../lib/core.js";
import { renderCampus } from "../art/campus.js";
import { blinkAt, makeIsko } from "../art/isko.js";
import { makePhone } from "../ui/phone.js";
import { headline } from "../ui/type.js";

const SECTIONS = [
  { k: "today", from: 19.6, hue: "245,178,39" },
  { k: "schedule", from: 28, hue: "126,163,224" },
  { k: "grades", from: 36, hue: "88,199,146" },
  { k: "study", from: 48, hue: "181,138,208" },
  { k: "today2", from: 60, hue: "245,178,39" },
];
const sectionAt = (b) => SECTIONS.reduce((a, s) => (b >= s.from ? s : a), SECTIONS[0]);

export function stageBackdrop(layer) {
  const bg = el("div", "abs", layer);
  css(bg, { inset: "0", background: "#0d0c10" });
  const glow = el("div", "abs", layer);
  css(glow, { width: "1600px", height: "1600px", borderRadius: "50%" });
  const floor = el("div", "abs", layer);
  css(floor, { left: "-1200px", right: "-1200px", top: "640px", height: "1400px", transformOrigin: "50% 0%", transform: "perspective(900px) rotateX(72deg)",
    backgroundImage: "radial-gradient(rgba(245,178,39,.32) 2px, transparent 2.6px)", backgroundSize: "46px 46px",
    WebkitMaskImage: "linear-gradient(to bottom, transparent, #000 25%, #000 60%, transparent)", maskImage: "linear-gradient(to bottom, transparent, #000 25%, #000 60%, transparent)" });
  return { bg, glow, floor };
}

export default {
  id: "ios", from: 19.6, to: 68.4,
  init(layer) {
    this.bd = stageBackdrop(layer);
    this.P = makePhone(layer);
    this.P.setRoom("Night");
    const campusHost = this.P.views.today.r.campus;
    this.campusImg = el("canvas", "", campusHost);
    this.campusImg.width = 776; this.campusImg.height = 352;
    css(this.campusImg, { width: "388px", height: "176px", display: "block" });
    // headlines
    this.heads = [
      headline(layer, [{ text: "Your whole", at: 22 }, { text: "day, before", at: 22.4 }, { text: "you ask.", at: 22.75, gold: true }], { x: 100, y: 300, size: 124, out: 27.3 }),
      headline(layer, [{ text: "Your week,", at: 29 }, { text: "one grid.", at: 29.6, gold: true }], { x: 1150, y: 400, size: 128, out: 35.4 }),
      headline(layer, [{ text: "Grades land.", at: 40 }, { text: "Your goal,", at: 44 }, { text: "mapped.", at: 44.5, gold: true }], { x: 1150, y: 300, size: 116, out: 47.4 }),
      headline(layer, [{ text: "Notes →", at: 53 }, { text: "cards.", at: 53.5 }, { text: "Study what's due.", at: 55, gold: true }], { x: 100, y: 330, size: 104, out: 59.4 }),
      headline(layer, [{ text: "Isko keeps", at: 61 }, { text: "an eye out.", at: 61.6, gold: true }], { x: 1150, y: 400, size: 118, out: 65.6 }),
    ];
    // Isko inside the phone screen
    this.isko = makeIsko(this.P.scr, 5);
    this.isko.root.style.zIndex = 5;
    this.bubble = el("div", "abs card notch", this.P.scr,
      `<div class="lab" style="color:var(--gold)">Isko</div><div style="font:600 19px/1.3 var(--ui);color:var(--ink);margin-top:4px">Next class in 9 min, room S512.<br>You're free 1h 30m after.</div>`);
    css(this.bubble, { left: "140px", top: "520px", width: "270px", padding: "14px 16px", zIndex: 6 });
  },
  render(b, t) {
    const P = this.P, V = P.views;
    const sec = sectionAt(b);
    // ---- backdrop colour field follows the section
    const hk = pb(b, sec.from, sec.from + 1.2, ease.outCubic);
    const prev = SECTIONS[Math.max(0, SECTIONS.indexOf(sec) - 1)];
    const mixHue = (a, c) => a.split(",").map((v, i) => Math.round(lerp(+v, +c.split(",")[i], hk))).join(",");
    const hue = mixHue(prev.hue, sec.hue);

    // ---- camera: focus-point keyframes. The focus (fx, fy in phone px) is
    // placed at screen (sx, sy); rotations and scale pivot on it.
    const KF = [
      [19.6, 230, 480, 1250, 560, 1.0, -16, 6], [23.2, 230, 330, 1250, 560, 1.5, -10, 4], [25.6, 230, 250, 1230, 520, 1.62, -8, 3],
      [28, 230, 470, 700, 560, 1.05, 18, 4], [30.4, 230, 560, 680, 560, 1.5, 12, 3],
      [36, 230, 260, 660, 470, 1.75, 14, 6], [39.4, 230, 700, 650, 520, 1.55, 10, 4], [43.6, 230, 420, 650, 520, 1.6, 8, 3],
      [48, 230, 520, 1240, 560, 1.2, -18, 5], [52.6, 230, 560, 1250, 580, 1.5, -12, 3],
      [60, 170, 720, 700, 560, 1.55, 14, 4], [64, 230, 520, 700, 560, 1.15, 16, 4],
    ];
    let k0 = KF[0], k1 = KF[0];
    for (const k of KF) if (b >= k[0]) { k0 = k1; k1 = k; }
    const mk = k0 === k1 ? 1 : springB(b, k1[0], 1.05, 0.82);
    const cam = k1.map((v, i) => lerp(k0[i], v, mk));
    const [, fxp, fyp, sx0, sy0, sc, ry, rx] = cam;
    const arrive = springB(b, 19.8, 2.0, 0.7);
    const z = (1 - arrive) * -1400;
    const drift = Math.sin(t * 0.7) * 1.5;
    const ex = pb(b, 67.1, 68.2, ease.inCubic);
    const spin = ex * 360;
    const sx = lerp(sx0, 960, ex), sy = lerp(sy0, 540, ex), scl = lerp(sc, 0.9, ex);
    P.root.style.transformOrigin = `${fxp}px ${fyp}px`;
    P.root.style.transform = `perspective(2400px) translate3d(${sx - fxp}px, ${sy - fyp}px, ${z}px) rotateY(${ry * (1 - ex) + drift + spin}deg) rotateX(${rx * (1 - ex)}deg) scale(${scl})`;
    const fx = sx - 230, fy = sy - 480;
    this.bd.glow.style.transform = `translate(${fx + 230 - 800}px, ${fy + 480 - 800}px)`;
    this.bd.glow.style.background = `radial-gradient(circle, rgba(${hue},.30) 0%, rgba(${hue},.10) 35%, transparent 62%)`;
    this.bd.floor.style.backgroundPosition = `${-t * 30}px 0px`;

    // ---- which view is on screen: depth push between views
    const views = { today: V.today, schedule: V.schedule, grades: V.grades, study: V.study };
    const vk = sec.k === "today2" ? "today" : sec.k;
    const pk = prev.k === "today2" ? "today" : prev.k;
    const push = pb(b, sec.from, sec.from + 0.7, ease.outExpo);
    for (const [k, v] of Object.entries(views)) {
      const on = k === vk || (k === pk && push < 1 && b >= 28);
      v.node.style.display = on ? "" : "none";
      if (!on) continue;
      if (k === vk && k !== pk) v.node.style.transform = `translateX(${(1 - push) * 70}px) scale(${0.94 + 0.06 * push})`;
      else if (k === pk && k !== vk) v.node.style.transform = `translateX(${-push * 90}px) scale(${1 - 0.08 * push})`;
      else v.node.style.transform = "";
      v.node.style.opacity = k === pk && k !== vk ? 1 - push : 1;
      v.node.style.zIndex = k === vk ? 2 : 1;
    }
    V.assis.node.style.display = "none";
    P.setTab(vk);

    // ---- Island glance morphs
    const isl = b < 24 ? "COMP 20073 · <b>in 9m</b>" : b < 26 ? "Next · <b>GEED 10053</b> 10:30" : b < 36 ? "<b>1h 30m</b> free after class" : b < 48 ? "Grades · <b>4 posted</b>" : b < 60 ? "<b>12 cards</b> due today" : "COMP 20073 · <b>in 9m</b>";
    if (P.islandT.innerHTML !== isl) P.islandT.innerHTML = isl;
    const ib = Math.max(...[24, 26, 36, 48, 60].map((m) => pulse(b, m, 0.6)));
    P.island.style.transform = `translateX(-50%) scale(${1 + ib * 0.08}, ${1 - ib * 0.05})`;
    P.views.today.r.scroll.style.transform = "";

    // ---- Today
    if (vk === "today") {
      const r = V.today.r;
      const hour = sec.k === "today" ? 7.0 + pb(b, 20, 28) * 0.5 : 7.35;
      const cv = renderCampus(t, { hour, net: 1, camX: Math.sin(t * 0.3) * 2, camZ: 30, w: 776, h: 352, aspect: 776 / 352, next: 101 });
      this.campusImg.getContext("2d").drawImage(cv, 0, 0, 776, 352);
      const sc = sec.k === "today" ? springB(b, 25, 1.4, 0.8) * 150 : 0;
      r.scroll.style.transform = `translateY(${-sc}px)`;
      const mins = 9 - Math.floor(pb(b, 20, 28) * 1.99);
      const s = `in ${mins}m`;
      if (r.inm.textContent !== s) r.inm.textContent = s;
    }
    // ---- Schedule: blocks pop on 16ths, now-line, week turn at 32
    if (vk === "schedule") {
      const r = V.schedule.r;
      for (let i = 0; i < 10; i++) {
        const k = springB(b, 28.4 + i * 0.25, 3, 0.55);
        r[`b${i}`].style.transform = `scale(${clamp(k, 0, 1.2)})`;
      }
      const turn = pb(b, 32, 33.2, ease.inOutCubic);
      r.face.style.transform = `rotateY(${-Math.sin(turn * Math.PI) * 80}deg)`;
      r.now.style.transform = `scaleX(${pb(b, 29, 30, ease.outExpo)})`;
      r.now.style.transformOrigin = "0 50%";
    }
    // ---- Grades
    if (vk === "grades") {
      const r = V.grades.r;
      const g = lerp(3.0, 1.28, pb(b, 36.2, 38.4, ease.outCubic));
      const gs = g.toFixed(2);
      if (r.gpa.textContent !== gs) r.gpa.textContent = gs;
      r.line.setAttribute("stroke-dashoffset", String(140 * (1 - pb(b, 37, 38.6, ease.outCubic))));
      for (let i = 0; i < 4; i++) {
        const at = 40 + i;
        const st = r[`s${i}`], row = r[`g${i}`];
        const d = (b - at) * BEAT;
        if (d < 0) { st.style.opacity = 0; row.style.transform = ""; continue; }
        const s = d < 0.1 ? 1.9 - 0.98 * ease.outCubic(d / 0.1) : 0.92 + 0.08 * ease.outCubic(clamp((d - 0.1) / 0.2));
        st.style.opacity = 1;
        st.style.transform = `rotate(-3deg) scale(${s})`;
        st.style.filter = `blur(${clamp(1 - d / 0.1) * 2}px)`;
        row.style.transform = `translateX(${pulse(b, at, 0.6) * -10}px)`;
      }
      const full = "For a 1.50 this term, aim for 1.69 or better on the 2 left.";
      const n = Math.floor(full.length * pb(b, 44, 46.2));
      const txt = full.slice(0, n);
      if (r.coachT.textContent !== txt) r.coachT.textContent = txt;
    }
    // ---- Study: fan-out 50, deal 52, flip 54, rate 56, flip 57.5, rate 58.5
    if (vk === "study") {
      const r = V.study.r;
      const fan = pb(b, 50, 50.9, ease.outBack) * (1 - pb(b, 51.8, 52.4, ease.inOutCubic));
      const flipA = pb(b, 54, 55.1, (k) => ease.inOutCubic(k));
      const off1 = pb(b, 56, 56.7, ease.inCubic);
      const flipB = pb(b, 57.4, 58.2, ease.inOutCubic);
      const off2 = pb(b, 58.6, 59.2, ease.inCubic);
      for (let i = 0; i < 7; i++) {
        const c = r[`c${i}`];
        const spread = (i - 3) * 9 * fan;
        let tr = `translate3d(${(i - 3) * 30 * fan}px, ${Math.abs(i - 3) * 10 * fan - i * 3 * (1 - fan)}px, ${-i * 14}px) rotateZ(${spread}deg)`;
        if (i === 0) tr = `translate3d(${off1 * 520}px, ${-off1 * 60}px, 0) rotateZ(${off1 * 18}deg) rotateY(${flipA * 180}deg)`;
        if (i === 1) tr = `translate3d(${off2 * 520 + (1 - off1) * 0}px, ${-off2 * 60 - 3 * (1 - off1)}px, ${-14 * (1 - off1)}px) rotateZ(${off2 * 18}deg) rotateY(${flipB * 180}deg)`;
        c.style.transform = tr;
        c.style.zIndex = 10 - i;
        c.style.display = i < 2 || b < 56 || i > 1 ? "" : "none";
      }
      const due = b < 56 ? 12 : b < 58.6 ? 11 : 10;
      if (r.due.textContent !== String(due)) r.due.textContent = String(due);
      r.due.style.transform = `scale(${1 + (pulse(b, 56, 0.5) + pulse(b, 58.6, 0.5)) * 0.25})`;
      const tap = Math.max(pulse(b, 55.9, 0.4), pulse(b, 58.5, 0.4));
      r.good.style.background = tap > 0.1 ? "var(--gold)" : "";
      r.good.style.color = tap > 0.1 ? "var(--on-gold)" : "";
    }
    // ---- Isko pops up in the app (60 → 66)
    const iskoOn = b >= 60 && b < 66.5;
    this.isko.root.style.display = this.bubble.style.display = iskoOn ? "" : "none";
    if (iskoOn) {
      const up = springB(b, 60, 2.2, 0.45);
      const hopK = pb(b, 60, 60.7);
      this.isko.pose({ x: 76, y: 830 + (1 - up) * 260, scale: 1, face: 1, t, squash: -Math.sin(hopK * Math.PI) * 0.4 + pulse(b, 60.7, 0.5) * 0.5,
        wave: pb(b, 61, 61.3) * (1 - pb(b, 63, 63.4)), wavePhase: (b - 61) * Math.PI * 2.2, expr: b > 61 && b < 63 ? "happy" : blinkAt(t, 5) });
      const bk = springB(b, 60.8, 2.4, 0.6);
      this.bubble.style.transform = `translateY(${(1 - bk) * 30}px) scale(${clamp(bk, 0, 1.1)})`;
      this.bubble.style.transformOrigin = "0% 100%";
    }
    this.heads.forEach((h) => h(b));
    if (b < 20.2) P.root.style.filter = `brightness(${1 + (1 - pb(b, 19.9, 20.2)) * 1.2})`;
    else P.root.style.filter = "";
    void tb; void noise1;
  },
};
