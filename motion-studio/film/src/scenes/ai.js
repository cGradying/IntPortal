// BOMB → the AI, on-device (beats 164–200). Colour explodes back in with an
// "Offline" chip pinned to the frame, and the film explains how IntAssis
// answers, as the app actually does it (RAGQuery / NoteRetrieval):
//   1 your notes are sliced into paragraph chunks
//   2 each chunk becomes a point in a meaning map (local embeddings)
//   3 your question lands in the map and the nearest chunks light up
//   4 a small model on the phone writes the answer, citing your notes.
// Then "made for you", one build per spoken word: summaries, study plans,
// flashcards, quizzes, a grade target. Everything assembles from fragments.
import { clamp, css, ease, el, hash, lerp, pb, pulse, springB } from "../lib/core.js";
import { blinkAt, makeIsko } from "../art/isko.js";
import { makePhone, NOTE } from "../ui/phone.js";
import { pixText } from "../ui/pixtype.js";
import { makeThread } from "../ui/thread.js";

const MAP = { cx: 1430, cy: 560, f: 1300 };
const TOPIC = ["#f5b227", "#7ea3e0", "#e0697e", "#58c792"];
const PAGES = [
  { t: "Trees & graphs", s: "COMP 20073 · wk 5", topic: 0 },
  { t: "OOP: classes", s: "COMP 20083 · wk 4", topic: 1 },
  { t: "Philippine history", s: "GEED 10103 · wk 3", topic: 2 },
];
const HITS = [0, 1, 3]; // chunk ids nearest the question (all from "Trees & graphs")
const MADE = [
  { at: 186, lab: "SUMMARY", title: "Trees & graphs, in 3 lines", body: ["BSTs keep keys ordered left → right", "Balanced: subtree heights differ ≤ 1", "BFS uses a queue, DFS a stack"] },
  { at: 187.5, lab: "STUDY PLAN", title: "From your syllabus", body: ["Wk 5 · Trees — review Tue", "Wk 6 · Graphs — quiz Fri", "Wk 7 · Midterm prep"] },
  { at: 189, lab: "FLASHCARDS", title: "12 cards from one note", body: ["What is a balanced BST?", "BFS uses which structure?", "Heap height with n nodes?"] },
  { at: 190.5, lab: "QUIZ", title: "Dijkstra fails on…", body: ["A · cycles", "B · negative edges ✓", "Why? It assumes a settled node never gets cheaper."] },
  { at: 192, lab: "GRADE TARGET", title: "For a 1.50 this term", body: ["Aim for 1.69 or better", "on the 2 subjects left", "From your posted grades"] },
];

export default {
  id: "ai", from: 164, to: 200,
  init(layer) {
    css(layer, { background: "#0c0a14" });
    this.floor = el("div", "abs", layer);
    css(this.floor, { left: "-1200px", right: "-1200px", top: "660px", height: "1400px", transformOrigin: "50% 0%", transform: "perspective(900px) rotateX(72deg)",
      backgroundImage: "radial-gradient(rgba(134,99,168,.45) 2px, transparent 2.6px)", backgroundSize: "46px 46px",
      maskImage: "linear-gradient(to bottom, transparent, #000 25%, #000 60%, transparent)", WebkitMaskImage: "linear-gradient(to bottom, transparent, #000 25%, #000 60%, transparent)" });
    // colour burst bands (164 → 164.7)
    this.bands = ["#f5b227", "#e0697e", "#7ea3e0", "#58c792", "#b58ad0", "#7a1128", "#fff1c4", "#10b981"].map((c) => {
      const d = el("div", "abs", layer);
      css(d, { left: "0", width: "1920px", height: `${1080 / 8 + 2}px`, background: c });
      return d;
    });
    this.still = pixText(layer, { text: "Still works.", size: 230, x: 960, y: 360, anchor: "c", ink: "#f7ecec", shadow: "#2a0a14" });
    // phone
    this.P = makePhone(layer);
    this.P.setRoom("Night");
    this.P.setTab("study");
    this.P.setAirplane(true);
    for (const k of ["today", "schedule", "grades", "study"]) this.P.views[k].node.style.display = "none";
    const A = this.P.views.assis.r;
    A.q.textContent = "What's a balanced BST?";
    A.cite.innerHTML = ["Trees & graphs", "BST lecture", "Lab 3"].map((s) => `<span class="chip" style="background:rgba(245,178,39,.18);color:var(--gold);margin:0 6px 6px 0">From your notes · ${s}</span>`).join("");
    this.chips = [...A.cite.children];
    // on-device die
    this.die = el("div", "abs notch", layer, `<div style="display:grid;grid-template-columns:repeat(4,14px);gap:5px">${Array.from({ length: 16 }, (_, i) => `<i data-i="${i}" style="width:14px;height:14px;background:#3a2f44;display:block"></i>`).join("")}</div>
      <div style="font:700 20px var(--pixel);color:#f5b227;margin-top:12px;letter-spacing:.06em">ON-DEVICE<br>MODEL</div>`);
    css(this.die, { left: "80px", top: "600px", padding: "18px", background: "#1a1424", border: "3px solid #5d3f78" });
    this.dieCells = [...this.die.querySelectorAll("i")];
    // offline chip pinned all scene
    this.offline = el("div", "abs", layer, "✈ OFFLINE");
    css(this.offline, { right: "60px", top: "46px", font: "700 34px var(--pixel)", color: "#1b1406", background: "#f5b227", padding: "10px 18px", letterSpacing: ".08em" });
    // pages → chunks
    this.pages = PAGES.map((p, pi) => {
      const chunks = [0, 1, 2, 3].map((ci) => {
        const d = el("div", "abs", layer);
        const lines = ci === 0 ? `<div style="font:800 26px var(--display);color:#f7ecec">${p.t}</div><div style="font:600 15px var(--ui);color:${TOPIC[p.topic]}">${p.s}</div>`
          : `<div style="font:400 17px/1.35 var(--ui);color:#cdbbd8">${pi === 0 ? NOTE[ci + 1][1] : ["Encapsulation keeps state behind methods.", "Inheritance shares behaviour between classes.", "Interfaces describe what, not how.", "Cavite Mutiny, 1872: the Gomburza.", "The Propaganda Movement wrote from Spain.", "The Katipunan, founded 1892."][(pi - 1) * 3 + ci - 1]}</div>`;
        d.innerHTML = lines;
        css(d, { width: "330px", height: "92px", padding: "14px 18px", background: "#231c2e", borderLeft: `6px solid ${TOPIC[p.topic]}`, overflow: "hidden" });
        return { d, ci, id: pi * 4 + ci };
      });
      return { p, pi, chunks };
    });
    // meaning map points: 12 chunk points + 70 background points
    this.pts = [];
    for (let i = 0; i < 82; i++) {
      const topic = i < 12 ? PAGES[Math.floor(i / 4)].topic : Math.floor(hash(i, 1) * 4);
      const c = [[-220, -120, 60], [180, -60, -120], [60, 170, 140], [-140, 150, -200]][topic];
      const p = [c[0] + (hash(i, 2) - 0.5) * 260, c[1] + (hash(i, 3) - 0.5) * 200, c[2] + (hash(i, 4) - 0.5) * 260];
      if (i === 0 || i === 1 || i === 3) { p[0] = -200 + i * 30; p[1] = -110 + i * 12; p[2] = 40 + i * 10; }
      const d = el("div", "abs", layer);
      css(d, { width: "16px", height: "16px", background: TOPIC[topic] });
      this.pts.push({ d, p, topic, chunk: i < 12 });
    }
    this.qpt = el("div", "abs", layer);
    css(this.qpt, { width: "26px", height: "26px", background: "#fff", outline: "4px solid #f5b227" });
    this.svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
    this.svg.setAttribute("width", "1920"); this.svg.setAttribute("height", "1080");
    css(this.svg, { position: "absolute", left: "0", top: "0" });
    layer.appendChild(this.svg);
    this.lines = HITS.map(() => {
      const l = document.createElementNS("http://www.w3.org/2000/svg", "line");
      l.setAttribute("stroke", "#f5b227"); l.setAttribute("stroke-width", "5"); l.setAttribute("stroke-dasharray", "10 7");
      this.svg.appendChild(l);
      return l;
    });
    this.beam = makeThread(layer, { width: 8, color: "#fff1c4", z: 5 });
    // step labels
    this.steps = [
      [168, "1", "Your notes → chunks"], [171, "2", "A meaning map, on the phone"], [175, "3", "Finds what matters"], [179, "4", "Answers, citing your notes"],
    ].map(([at, n, t]) => ({ at, n: pixText(layer, { text: n, size: 100, font: "pixel", x: 900, y: 130, ink: "#f5b227", shadow: "#2a0a14" }), t: pixText(layer, { text: t, size: 60, x: 990, y: 156, ink: "#f7ecec", shadow: "#000" }) }));
    // made-for-you cards
    this.made = MADE.map((m, i) => {
      const d = el("div", "abs notch", layer, `<div style="font:700 20px var(--pixel);letter-spacing:.1em;color:${TOPIC[i % 4]}">${m.lab}</div>
        <div style="font:800 32px/1.1 var(--display);color:#f7ecec;margin:8px 0 12px;letter-spacing:-.02em">${m.title}</div>
        ${m.body.map((l) => `<div style="font:400 20px/1.35 var(--ui);color:#cdbbd8;margin-bottom:4px">${l}</div>`).join("")}`);
      css(d, { left: "0", top: "0", width: "420px", height: "250px", padding: "20px 24px", background: "#231c2e", borderTop: `6px solid ${TOPIC[i % 4]}` });
      const frags = Array.from({ length: 12 }, (_, k) => {
        const f = el("div", "abs", layer);
        css(f, { width: "105px", height: "84px", background: TOPIC[i % 4] });
        return { f, k, r: hash(i, k, 9) };
      });
      const word = pixText(layer, { text: ["Summaries", "Study plans", "Flashcards", "Quizzes", "Grade targets"][i], size: 120, x: 110, y: 110, ink: i % 2 ? "#f5b227" : "#f7ecec", shadow: "#000" });
      return { m, d, frags, word, i };
    });
    this.madeFor = pixText(layer, { text: "Made for you.", size: 150, x: 110, y: 110, ink: "#f7ecec", shadow: "#000" });
    this.offLine = pixText(layer, { text: "Offline.", size: 150, font: "pixel", x: 1180, y: 110, ink: "#f5b227", shadow: "#000" });
    this.isko = makeIsko(layer, 6);
  },
  proj(p, ang) {
    const c = Math.cos(ang), s = Math.sin(ang);
    const x = p[0] * c + p[2] * s, z = -p[0] * s + p[2] * c;
    const k = MAP.f / (MAP.f + z);
    return [MAP.cx + x * k, MAP.cy + p[1] * k, k];
  },
  render(b, t) {
    const P = this.P, A = P.views.assis.r;
    // ---- burst
    this.bands.forEach((d, i) => {
      const k = pb(b, 164 + i * 0.03, 164.55 + i * 0.03, ease.inCubic);
      d.style.display = k < 1 ? "" : "none";
      d.style.top = `${i * 135}px`;
      d.style.transform = `translateX(${(i % 2 ? 1 : -1) * k * 2000}px)`;
    });
    this.floor.style.backgroundPosition = `0px ${b * 60}px`;
    this.still.render(b, { at: 164.5, dur: 1, out: 167.4, outDur: 0.5, glitchAt: [166] });
    const oc = springB(b, 164.3, 2.4, 0.5);
    this.offline.style.transform = `scale(${clamp(oc, 0, 1.2) * (1 + pulse(b, 194, 0.8) * 0.2)})`;

    // ---- phone: rises at 167.5, IntAssis from 175
    const pIn = springB(b, 167.3, 1.5, 0.75);
    const pOut = pb(b, 185.1, 186, ease.inCubic);
    const ph = b >= 167.2 && b < 186;
    P.root.style.display = ph ? "" : "none";
    if (ph) {
      P.root.style.transformOrigin = "230px 481px";
      P.root.style.transform = `perspective(2400px) translate3d(${480 - 230 - pOut * 900}px, ${560 - 481 + (1 - pIn) * 900}px, 0) rotateY(10deg) scale(0.86)`;
    }
    const notesOn = b < 175;
    P.views.notes.node.style.display = notesOn ? "" : "none";
    P.views.assis.node.style.display = notesOn ? "none" : "";
    if (!notesOn) {
      const up = springB(b, 175, 1.8, 0.8);
      A.sheet.style.transform = `translateY(${(1 - up) * 640}px)`;
      A.q.style.transform = `scale(${clamp(springB(b, 175.6, 2.4, 0.6), 0, 1.1)})`;
      A.q.style.transformOrigin = "100% 100%";
      const ans = "A BST where the two subtrees of every node differ in height by at most 1, so search stays O(log n).";
      const s = ans.slice(0, Math.floor(ans.length * pb(b, 180.2, 182.6)));
      if (A.aT.textContent !== s) A.aT.textContent = s;
      A.a.style.display = b >= 180 ? "" : "none";
      this.chips.forEach((c, i) => {
        const k = springB(b, 179.5 + i * 0.5 + 0.9, 2.6, 0.5);
        c.style.display = b >= 179.5 + i * 0.5 + 0.9 ? "inline-block" : "none";
        c.style.transform = `scale(${clamp(k, 0, 1.1)})`;
      });
    }
    const dieOn = b >= 172 && b < 185.6;
    this.die.style.display = dieOn ? "" : "none";
    this.dieCells.forEach((c, i) => (c.style.background = hash(i, Math.floor(b * 4)) < 0.25 + (b >= 179 && b < 183 ? 0.45 : 0) ? "#f5b227" : "#3a2f44"));
    this.die.style.transform = `translateX(${pb(b, 184.9, 185.5, ease.inCubic) * -500}px)`;

    // ---- steps
    this.steps.forEach((s, i) => {
      const next = [171, 175, 179, 185.2][i];
      s.n.render(b, { at: s.at, dur: 0.6, out: next - 0.35, outDur: 0.35 });
      s.t.render(b, { at: s.at + 0.2, dur: 0.8, out: next - 0.3, outDur: 0.35 });
    });

    // ---- 1: pages fan out (168) and slice into chunks (169.5); 2: chunks fly to the map (171 →)
    const ang = (b - 170) * 0.12;
    this.pages.forEach(({ pi, chunks }) => {
      const fan = springB(b, 168 + pi * 0.25, 1.8, 0.7);
      const px = 900 + pi * 360, py = 330;
      chunks.forEach((c) => {
        const slice = pb(b, 169.5 + pi * 0.15, 170.1 + pi * 0.15, ease.outBack);
        const fly = pb(b, 171 + c.id * 0.08, 172.2 + c.id * 0.08, ease.inOutCubic);
        const on = b >= 168 && fly < 1 && b < 175;
        c.d.style.display = on ? "" : "none";
        if (!on) return;
        const [tx, ty] = this.proj(this.pts[c.id].p, ang);
        const x0 = lerp(480, px, fan), y0 = lerp(560, py + c.ci * (92 + slice * 26), fan);
        const x = lerp(x0, tx - 165, fly), y = lerp(y0, ty - 46, fly);
        c.d.style.transform = `translate(${x}px, ${y}px) scale(${lerp(clamp(fan, 0, 1.05), 0.05, fly)}) rotate(${(1 - fan) * 20 + (c.ci - 1.5) * slice * 2}deg)`;
      });
    });
    // knife sweep
    // ---- the map (171 → 183.4): rotating, question lands 176, hits light up 177
    const mapOn = b >= 171 && b < 185.5;
    const mk = pb(b, 171, 172.2, ease.outCubic) * (1 - pb(b, 184.7, 185.5, ease.inCubic));
    const hitK = pb(b, 177, 177.6, ease.outCubic);
    const qk = pb(b, 175.8, 176.8, ease.inOutCubic);
    const back = (id) => pb(b, 179.4 + HITS.indexOf(id) * 0.5, 180.3 + HITS.indexOf(id) * 0.5, ease.inCubic);
    const qp = this.proj([-160, -80, 60], ang);
    this.pts.forEach((pt, i) => {
      const hit = HITS.includes(i);
      const on = mapOn && (pt.chunk ? b >= 172 + i * 0.08 : true) && !(hit && back(i) >= 1);
      pt.d.style.display = on ? "" : "none";
      if (!on) return;
      let [x, y, k] = this.proj(pt.p, ang);
      if (hit && b >= 179.4) {
        const bk = back(i);
        const tr = this.chips[HITS.indexOf(i)]?.getBoundingClientRect();
        if (tr && tr.width) { x = lerp(x, tr.left + 20, bk); y = lerp(y, tr.top + 12, bk); }
        else { x = lerp(x, 520, bk); y = lerp(y, 640, bk); }
      }
      const sz = (hit ? 16 + hitK * 16 : 16) * k * mk;
      const dim = b >= 177 && !hit ? 0.3 : 1;
      css(pt.d, { width: `${sz}px`, height: `${sz}px`, opacity: String(dim), background: hit && b >= 177 ? "#fff1c4" : TOPIC[pt.topic], outline: hit && b >= 177 ? "4px solid #f5b227" : "" });
      pt.d.style.transform = `translate(${x - sz / 2}px, ${y - sz / 2}px)`;
    });
    // question point + beam from the phone
    const qOn = b >= 175.8 && b < 185;
    this.qpt.style.display = qOn && qk >= 1 ? "" : "none";
    this.qpt.style.transform = `translate(${qp[0] - 13}px, ${qp[1] - 13}px) scale(${1 + pulse(b, 176.8, 0.6) * 0.8})`;
    const qa = A.q.getBoundingClientRect();
    this.beam.render(qOn && b < 179.4, [qa.left, qa.top + qa.height / 2], [qp[0], qp[1]], qk, qk >= 1 ? (b - 176) * 0.7 : null, -200);
    this.lines.forEach((l, j) => {
      const id = HITS[j];
      const [x, y] = this.proj(this.pts[id].p, ang);
      const on = b >= 177 && b < 179.4;
      l.style.display = on ? "" : "none";
      const k = pb(b, 177 + j * 0.15, 177.5 + j * 0.15, ease.outCubic);
      l.setAttribute("x1", qp[0]); l.setAttribute("y1", qp[1]);
      l.setAttribute("x2", lerp(qp[0], x, k)); l.setAttribute("y2", lerp(qp[1], y, k));
    });

    // ---- Isko pushes the question in (175 → 177)
    const iOn = b >= 172 && b < 185.6;
    this.isko.root.style.display = iOn ? "" : "none";
    if (iOn) {
      const ix = 830 + Math.sin(t) * 10, iy = 900 + (1 - springB(b, 172, 1.6, 0.6)) * 300 + pb(b, 184.9, 185.6, ease.inCubic) * 400;
      this.isko.pose({ x: ix, y: iy, t, expr: b >= 177 && b < 178.5 ? "wow" : b >= 181 ? "happy" : blinkAt(t, 11), gesture: b >= 175.6 && b < 177 ? "reach" : b >= 181 && b < 182.5 ? "thumbs" : "idle", gk: 1, look: 1 });
    }

    // ---- made for you (186 → 200)
    this.made.forEach(({ m, d, frags, word, i }) => {
      const at = m.at;
      // settled grid position after 193.5
      const gx = 100 + (i % 3) * 600 + Math.floor(i / 3) * 300, gy = 380 + Math.floor(i / 3) * 330;
      const hx = 820, hy = 330;
      const settle = pb(b, 193.2 + i * 0.1, 194 + i * 0.1, ease.inOutCubic);
      const x = lerp(hx, gx, settle), y = lerp(hy, gy, settle), s = lerp(2.2, 1.18, settle);
      const built = pb(b, at, at + 0.35, ease.inCubic);
      const on = b >= at && b < 199.6;
      d.style.display = on && built >= 1 ? "" : "none";
      const next = MADE[i + 1]?.at ?? 999;
      const pushBack = b >= next && b < 193.2 ? 1 : 0;
      d.style.transform = `translate(${x}px, ${y}px) scale(${s * (1 - pushBack * 0.08) * (1 + pulse(b, at + 0.55, 0.4) * 0.05)})`;
      d.style.transformOrigin = "0 0";
      d.style.zIndex = 10 + i;
      d.style.opacity = pushBack && b < 193.2 ? 0 : 1;
      frags.forEach(({ f, k, r }) => {
        const fk = pb(b, at + r * 0.1, at + 0.3 + r * 0.05, ease.inCubic);
        const fo = b >= at && fk < 1;
        f.style.display = fo && b < at + 0.4 ? "" : "none";
        if (!fo) return;
        const tx = x + (k % 4) * 105 * s, ty = y + Math.floor(k / 4) * 84 * s;
        const sx = tx + (r - 0.5) * 700, sy = ty + (hash(k, i, 3) - 0.5) * 500;
        f.style.transform = `translate(${lerp(sx, tx, fk)}px, ${lerp(sy, ty, fk)}px) scale(${s}) rotate(${(1 - fk) * 120 * (r - 0.5)}deg)`;
      });
      word.render(b, { at: at + 0.05, dur: 0.5, out: (MADE[i + 1]?.at ?? 193.3) - 0.25, outDur: 0.25 });
    });
    this.madeFor.render(b, { at: 193.4, dur: 0.9, out: 199.2, outDur: 0.5, glitchAt: [196] });
    this.offLine.render(b, { at: 194, dur: 0.9, out: 199.3, outDur: 0.5 });
  },
};
