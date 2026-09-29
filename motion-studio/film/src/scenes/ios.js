// iOS (beats 36–100): four clean chapters of 16 beats. A numbered label and
// one plain sentence on the left, the phone big on the right, Isko between
// them drawing a light-thread to the thing that matters. Real momentum
// scroll (closed-form springs with overscroll), Island morphs, and the notes
// chapter shatters a note into pixel chunks that magnet-snap into a card.
import { BEAT, clamp, css, ease, el, hash, lerp, pb, pulse, springB } from "../lib/core.js";
import { renderCampus } from "../art/campus.js";
import { blinkAt, makeIsko } from "../art/isko.js";
import { makePhone } from "../ui/phone.js";
import { pixText } from "../ui/pixtype.js";
import { makeThread } from "../ui/thread.js";

const CH = [
  { at: 36, n: "01", title: "Today", desc: "Your next class and free time,<br>the second you open it.", hue: "245,178,39", tab: "today", view: "today" },
  { at: 52, n: "02", title: "Schedule", desc: "Your whole week in one scroll.<br>Classes, rooms and gaps.", hue: "126,163,224", tab: "schedule", view: "schedule" },
  { at: 68, n: "03", title: "Grades", desc: "Grades as they post, your GPA,<br>and what you need for your goal.", hue: "88,199,146", tab: "grades", view: "grades" },
  { at: 84, n: "04", title: "Notes → cards", desc: "Your notes become flashcards.<br>Study what's due, nothing more.", hue: "181,138,208", tab: "study", view: "notes" },
];
const chAt = (b) => CH.reduce((a, c) => (b >= c.at ? c : a), CH[0]);
// camera keyframes: [beat, focusX, focusY (phone px), screenX, screenY, scale, rotY, rotX]
const KF = [
  [36, 230, 480, 1330, 540, 0.98, -14, 4], [38.5, 230, 440, 1330, 540, 1.1, -10, 3], [43.5, 230, 300, 1290, 500, 1.5, -8, 3], [48, 230, 480, 1330, 540, 1.02, -12, 4],
  [52, 230, 480, 590, 540, 1.0, 16, 4], [54.5, 230, 420, 620, 540, 1.35, 10, 3], [59.5, 230, 500, 590, 540, 1.1, 14, 4],
  [68, 230, 250, 1300, 480, 1.5, -10, 4], [71.5, 230, 600, 1290, 540, 1.3, -8, 3], [76.5, 230, 360, 1290, 520, 1.55, -8, 3], [81, 230, 480, 1330, 540, 1.02, -14, 4],
  [84, 230, 430, 590, 540, 1.15, 12, 3], [88, 230, 480, 590, 540, 1.05, 12, 4], [91, 230, 500, 620, 540, 1.28, 10, 3], [97.5, 230, 480, 590, 540, 1.05, 10, 3],
  [99.2, 230, 481, 960, 560, 0.9, 0, 0],
];
const CX = 5, CY = 8; // note chunks

export function stageBackdrop(layer) {
  const bg = el("div", "abs", layer);
  css(bg, { inset: "0", background: "#0d0c10" });
  const glow = el("div", "abs", layer);
  css(glow, { width: "1800px", height: "1800px", borderRadius: "50%" });
  const floor = el("div", "abs", layer);
  css(floor, { left: "-1200px", right: "-1200px", top: "640px", height: "1400px", transformOrigin: "50% 0%", transform: "perspective(900px) rotateX(72deg)",
    backgroundImage: "radial-gradient(rgba(245,178,39,.3) 2px, transparent 2.6px)", backgroundSize: "46px 46px",
    WebkitMaskImage: "linear-gradient(to bottom, transparent, #000 25%, #000 60%, transparent)", maskImage: "linear-gradient(to bottom, transparent, #000 25%, #000 60%, transparent)" });
  return { bg, glow, floor };
}

export default {
  id: "ios", from: 35.9, to: 100,
  init(layer) {
    this.bd = stageBackdrop(layer);
    this.P = makePhone(layer);
    this.P.setRoom("Night");
    const campusHost = this.P.views.today.r.campus;
    this.campusImg = el("canvas", "", campusHost);
    this.campusImg.width = 776; this.campusImg.height = 352;
    css(this.campusImg, { width: "388px", height: "176px", display: "block" });
    // chapter labels
    this.labels = CH.map((c, i) => {
      const next = CH[i + 1]?.at ?? 99.2;
      const LX = i % 2 ? 1120 : 110;
      const num = pixText(layer, { text: c.n, size: 96, font: "pixel", x: LX + 2, y: 250, ink: "#f5b227", shadow: "#2a0a14" });
      const title = pixText(layer, { text: c.title, size: c.title.length > 8 ? 118 : 150, x: LX, y: 360, ink: "#f7ecec", shadow: "#2a0a14" });
      const desc = el("div", "abs", layer, `<span>${c.desc}</span>`);
      css(desc, { left: `${LX + 6}px`, top: "560px", width: "760px", font: "400 40px/1.3 var(--ui)", color: "#cdbbd8", overflow: "hidden" });
      return { c, num, title, desc, out: next - 0.9 };
    });
    // Isko + thread
    this.thread = makeThread(layer, { width: 6, z: 30 });
    this.isko = makeIsko(layer, 6);
    this.isko.root.style.zIndex = 31;
    // note chunks: clones of the note sheet, each clipped to one cell
    const sheet = this.P.views.notes.r.sheet;
    this.chunkHost = el("div", "abs", this.P.scr);
    css(this.chunkHost, { left: "0", top: "0", width: "432px", height: "934px", zIndex: 4, pointerEvents: "none" });
    this.chunks = [];
    for (let j = 0; j < CY; j++) for (let i = 0; i < CX; i++) {
      const c = sheet.cloneNode(true);
      c.removeAttribute("data-r");
      c.className = "card";
      css(c, { position: "absolute", left: "0", top: "0", width: "388px", height: "560px", margin: "0", clipPath: `inset(${(j * 560) / CY}px ${388 - ((i + 1) * 388) / CX}px ${560 - ((j + 1) * 560) / CY}px ${(i * 388) / CX}px)`, transformOrigin: `${((i + 0.5) * 388) / CX}px ${((j + 0.5) * 560) / CY}px` });
      this.chunkHost.appendChild(c);
      this.chunks.push({ c, i, j, r: hash(i, j, 41) });
    }
    this.sheetBox = { x: 22, y: 210 };
    this.cardBox = { x: 58, y: 306, w: 316, h: 380 };
  },
  render(b, t) {
    const P = this.P, V = P.views;
    const ch = chAt(b);
    const ci = CH.indexOf(ch);
    // ---- backdrop hue follows the chapter
    const hk = pb(b, ch.at, ch.at + 1.2, ease.outCubic);
    const prev = CH[Math.max(0, ci - 1)];
    const hue = prev.hue.split(",").map((v, i) => Math.round(lerp(+v, +ch.hue.split(",")[i], hk))).join(",");

    // ---- camera
    let k0 = KF[0], k1 = KF[0];
    for (const k of KF) if (b >= k[0]) { k0 = k1; k1 = k; }
    const mk = k0 === k1 ? 1 : springB(b, k1[0], 1.05, 0.82);
    const [, fxp, fyp, sx, sy, sc, ry, rx] = k1.map((v, i) => lerp(k0[i], v, mk));
    const arrive = springB(b, 35.95, 2.0, 0.7);
    const z = (1 - arrive) * -1400;
    const drift = Math.sin(t * 0.7) * 1.5 * (b < 98.5 ? 1 : 0);
    P.root.style.transformOrigin = `${fxp}px ${fyp}px`;
    P.root.style.transform = `perspective(2400px) translate3d(${sx - fxp}px, ${sy - fyp}px, ${z}px) rotateY(${ry + drift}deg) rotateX(${rx}deg) scale(${sc})`;
    this.bd.glow.style.transform = `translate(${sx - 900}px, ${sy - 900}px)`;
    this.bd.glow.style.background = `radial-gradient(circle, rgba(${hue},.28) 0%, rgba(${hue},.09) 35%, transparent 62%)`;
    this.bd.floor.style.backgroundPosition = `${-t * 30}px 0px`;
    P.root.style.filter = b < 36.3 ? `brightness(${1 + (1 - pb(b, 35.95, 36.3)) * 1.2})` : "";

    // ---- views: depth push between chapters; notes → study at 90.5
    const vk = ch.view === "notes" && b >= 90.5 ? "study" : ch.view;
    const pk = ci > 0 ? CH[ci - 1].view : vk;
    const push = pb(b, ch.at, ch.at + 0.7, ease.outExpo);
    for (const [k, v] of Object.entries({ today: V.today, schedule: V.schedule, grades: V.grades, study: V.study, notes: V.notes })) {
      const on = k === vk || (k === pk && push < 1 && k !== vk && b < 90);
      v.node.style.display = on ? "" : "none";
      if (!on) continue;
      if (k === vk && k !== pk && push < 1) v.node.style.transform = `translateX(${(1 - push) * 70}px) scale(${0.94 + 0.06 * push})`;
      else if (k === pk && k !== vk) v.node.style.transform = `translateX(${-push * 90}px) scale(${1 - 0.08 * push})`;
      else v.node.style.transform = "";
      v.node.style.opacity = k === pk && k !== vk ? 1 - push : 1;
      v.node.style.zIndex = k === vk ? 2 : 1;
    }
    V.assis.node.style.display = "none";
    P.setTab(ch.tab);
    const tabPop = pulse(b, ch.at, 0.5);
    P.tabEls[ch.tab].style.transform = `scale(${1 + tabPop * 0.2})`;

    // ---- Island morphs
    const isl = b < 44 ? "COMP 20073 · <b>in 9m</b>" : b < 52 ? "<b>1h 30m</b> free after class" : b < 68 ? "Next · <b>GEED 10053</b> 10:30" : b < 84 ? "Grades · <b>4 posted</b>" : b < 90.5 ? "Notes · <b>Trees & graphs</b>" : "<b>12 cards</b> due today";
    if (P.islandT.innerHTML !== isl) P.islandT.innerHTML = isl;
    const ib = Math.max(...[44, 52, 68, 84, 90.5].map((m) => pulse(b, m, 0.6)));
    P.island.style.transform = `translateX(-50%) scale(${1 + ib * 0.08}, ${1 - ib * 0.05})`;

    // ---- labels
    this.labels.forEach(({ c, num, title, desc, out }) => {
      num.render(b, { at: c.at + 0.25, dur: 0.75, out, outDur: 0.5 });
      title.render(b, { at: c.at + 0.5, dur: 1.25, out: out + 0.1, outDur: 0.6, glitchAt: [c.at + 8] });
      const on = b >= c.at + 1.5 && b < out + 0.6;
      desc.style.display = on ? "" : "none";
      if (on) {
        const k = pb(b, c.at + 1.5, c.at + 2.1, ease.outExpo), o = pb(b, out, out + 0.5, ease.inCubic);
        desc.firstChild.style.display = "inline-block";
        desc.firstChild.style.transform = `translateY(${(1 - k) * 110 - o * 110}%)`;
      }
    });

    // ---- Today: campus, momentum scroll with overscroll, countdown
    if (vk === "today") {
      const r = V.today.r;
      const cv = renderCampus(t, { hour: 7.0 + pb(b, 36, 52) * 0.5, net: 1, camX: Math.sin(t * 0.3) * 2, camZ: 30, w: 776, h: 352, aspect: 776 / 352, next: 101 });
      this.campusImg.getContext("2d").drawImage(cv, 0, 0, 776, 352);
      const scroll = 300 * springB(b, 38.5, 1.1, 0.8) - 300 * springB(b, 41.5, 1.5, 0.32);
      r.scroll.style.transform = `translateY(${-scroll}px)`;
      const mins = 9 - Math.floor(pb(b, 36, 52) * 1.99);
      if (r.inm.textContent !== `in ${mins}m`) r.inm.textContent = `in ${mins}m`;
    }
    // ---- Schedule: blocks pop on 16ths, now-line, week turn on 60
    if (vk === "schedule") {
      const r = V.schedule.r;
      for (let i = 0; i < 10; i++) r[`b${i}`].style.transform = `scale(${clamp(springB(b, 52.5 + i * 0.25, 3, 0.55), 0, 1.2)})`;
      const turn = pb(b, 60, 61.2, ease.inOutCubic);
      r.face.style.transform = `rotateY(${-Math.sin(turn * Math.PI) * 80}deg)`;
      r.now.style.transform = `scaleX(${pb(b, 55, 56, ease.outExpo)})`;
      r.now.style.transformOrigin = "0 50%";
    }
    // ---- Grades: GPA count, stamps on 72–75, Coach types 77–80
    if (vk === "grades") {
      const r = V.grades.r;
      const gs = lerp(3.0, 1.28, pb(b, 68.3, 70.4, ease.outCubic)).toFixed(2);
      if (r.gpa.textContent !== gs) r.gpa.textContent = gs;
      r.line.setAttribute("stroke-dashoffset", String(140 * (1 - pb(b, 69, 70.6, ease.outCubic))));
      for (let i = 0; i < 4; i++) {
        const at = 72 + i, st = r[`s${i}`], row = r[`g${i}`];
        const d = (b - at) * BEAT;
        if (d < 0) { st.style.opacity = 0; row.style.transform = ""; continue; }
        const s = d < 0.1 ? 1.9 - 0.98 * ease.outCubic(d / 0.1) : 0.92 + 0.08 * ease.outCubic(clamp((d - 0.1) / 0.2));
        st.style.opacity = 1;
        st.style.transform = `rotate(-3deg) scale(${s})`;
        st.style.filter = `blur(${clamp(1 - d / 0.1) * 2}px)`;
        row.style.transform = `translateX(${pulse(b, at, 0.6) * -10}px)`;
      }
      const full = "For a 1.50 this term, aim for 1.69 or better on the 2 left.";
      const txt = full.slice(0, Math.floor(full.length * pb(b, 77, 79.4)));
      if (r.coachT.textContent !== txt) r.coachT.textContent = txt;
    }
    // ---- Notes: shatter into chunks (88) that snap into a card (→ 90.4)
    const cOn = b >= 88 && b < 90.6;
    this.chunkHost.style.display = cOn ? "" : "none";
    V.notes.r.sheet.style.visibility = b >= 88 ? "hidden" : "";
    if (cOn) {
      const sb = this.sheetBox, cb = this.cardBox;
      for (const q of this.chunks) {
        q.c.style.display = q.j < 6 ? "" : "none";
        if (q.j >= 6) continue;
        const d0 = 88.1 + q.r * 0.9 + q.j * 0.05;
        const k = pb(b, d0, d0 + 0.9, ease.inOutCubic);
        const crack = pb(b, 88, 88.4, ease.outCubic);
        const w = 388 / CX, h = 560 / CY;
        const x0 = sb.x + (q.i - (CX - 1) / 2) * 8 * crack, y0 = sb.y + (q.j - (CY - 1) / 2) * 8 * crack;
        const tx = cb.x + q.i * (cb.w / CX) - q.i * w, ty = cb.y + 40 + q.j * (cb.h / CY) - q.j * h;
        const x = lerp(x0, tx, k) + Math.sin(k * Math.PI) * (q.r - 0.5) * 120;
        const y = lerp(y0, ty, k) - Math.sin(k * Math.PI) * 60;
        const sxk = lerp(1, cb.w / 388, k), syk = lerp(1, cb.h / 560, k);
        q.c.style.transform = `translate(${x}px, ${y}px) scale(${sxk}, ${syk}) rotateY(${Math.sin(k * Math.PI) * 60}deg)`;
        q.c.style.filter = k > 0.95 ? `brightness(${1 + pulse(b, d0 + 0.9, 0.3) * 0.6})` : "";
      }
    }
    // ---- Study: fan 91, flip 93, rate 95, flip 96.4, rate 97.4
    if (vk === "study") {
      const r = V.study.r;
      const fan = pb(b, 91, 91.9, ease.outBack) * (1 - pb(b, 92.4, 92.9, ease.inOutCubic));
      const flipA = pb(b, 93, 94, ease.inOutCubic);
      const off1 = pb(b, 95, 95.6, ease.inCubic);
      const flipB = pb(b, 96.4, 97.2, ease.inOutCubic);
      const off2 = pb(b, 97.4, 98, ease.inCubic);
      for (let i = 0; i < 7; i++) {
        const c = r[`c${i}`];
        let tr = `translate3d(${(i - 3) * 30 * fan}px, ${Math.abs(i - 3) * 10 * fan - i * 3 * (1 - fan)}px, ${-i * 14}px) rotateZ(${(i - 3) * 9 * fan}deg)`;
        if (i === 0) tr = `translate3d(${off1 * 520}px, ${-off1 * 60}px, 0) rotateZ(${off1 * 18}deg) rotateY(${flipA * 180}deg)`;
        if (i === 1) tr = `translate3d(${off2 * 520}px, ${-off2 * 60 - 3 * (1 - off1)}px, ${-14 * (1 - off1)}px) rotateZ(${off2 * 18}deg) rotateY(${flipB * 180}deg)`;
        c.style.transform = tr;
        c.style.zIndex = 10 - i;
      }
      const due = b < 95 ? 12 : b < 97.4 ? 11 : 10;
      if (r.due.textContent !== String(due)) r.due.textContent = String(due);
      r.due.style.transform = `scale(${1 + (pulse(b, 95, 0.5) + pulse(b, 97.4, 0.5)) * 0.25})`;
      const tap = Math.max(pulse(b, 94.9, 0.4), pulse(b, 97.3, 0.4));
      r.good.style.background = tap > 0.1 ? "var(--gold)" : "";
      r.good.style.color = tap > 0.1 ? "var(--on-gold)" : "";
    }

    // ---- Isko + thread to what matters
    const TARGETS = [
      [40, 47.5, () => V.today.r.hero], [55, 59.5, () => V.schedule.r.b0], [77, 81, () => V.grades.r.coach], [85, 88, () => V.notes.r.sheet],
    ];
    const tg = TARGETS.find(([a, z]) => b >= a - 0.5 && b < z + 0.5);
    const iOn = b >= 37.5 && b < 98.8;
    this.isko.root.style.display = iOn ? "" : "none";
    if (iOn) {
      const enter = springB(b, 37.5, 1.6, 0.6);
      const side = clamp((sx - 960) / 300, -1, 1);
      const ix = sx - side * (330 * sc + 120) + Math.sin(t * 0.9) * 12, iy = 830 + Math.sin(t * 1.3) * 10 + (1 - enter) * 400;
      const pointing = tg && b >= tg[0] && b < tg[1];
      this.isko.pose({ x: ix, y: iy, t, scale: 1, expr: pointing ? "focus" : b >= 95 && b < 96 ? "happy" : blinkAt(t, 6), gesture: pointing ? "point" : "idle", gk: 1, look: 1, flip: side < 0 });
      if (tg) {
        const r = tg[2]().getBoundingClientRect();
        const k = pb(b, tg[0], tg[0] + 0.6, ease.outCubic) * (1 - pb(b, tg[1], tg[1] + 0.4));
        this.thread.render(k > 0.01, [ix + side * 70, iy - 110], [side > 0 ? r.left + 8 : r.right - 8, r.top + r.height / 2], k, (b - tg[0]) * 0.5, -140);
      } else this.thread.render(false);
    } else this.thread.render(false);
  },
};
