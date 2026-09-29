// A 3D iPhone running IntPortal. The app UI is rebuilt from the real
// Svelte screens (intportal-app/src/lib) and restyled for the film: same
// grammar (Island glance, notched cards, stamps, dither free-time, pixel tab
// icons), refreshed layout, every colour from the room variables.
import { el, refs } from "../lib/core.js";
import { icon, pixelCanvas, sized } from "../art/pixel.js";
import { applyRoom, ROOM } from "./rooms.js";

const CSS = `
.phone { position:absolute; width:460px; height:962px; border-radius:72px; padding:14px;
  background:linear-gradient(145deg,#6b6b72,#2a2a2f 30%,#1a1a1e 70%,#55555c); box-shadow: 0 60px 120px -30px rgba(0,0,0,.65), inset 0 0 0 2px rgba(255,255,255,.08); }
.phone .scr { position:relative; width:432px; height:934px; border-radius:58px; overflow:hidden; background:var(--ground); color:var(--ink); font-family:var(--ui);
  background-image: radial-gradient(var(--dot) 1.4px, transparent 1.6px); background-size: 22px 22px; }
.phone .di { position:absolute; left:50%; top:12px; width:124px; height:36px; margin-left:-62px; border-radius:20px; background:#000; z-index:9; }
.phone .sb { position:absolute; left:0; right:0; top:0; height:54px; display:flex; justify-content:space-between; align-items:center; padding:6px 38px 0 44px; font:600 17px var(--ui); z-index:8; }
.phone .sb i { display:inline-block; width:26px; height:12px; border-radius:4px; border:1.5px solid var(--ink); margin-left:6px; position:relative; }
.phone .sb i::after { content:""; position:absolute; inset:1.5px; right:5px; background:var(--ink); border-radius:2px; }
.phone .island { position:absolute; left:50%; top:64px; transform:translateX(-50%); height:46px; padding:0 18px 0 12px; border-radius:24px; background:var(--island);
  display:flex; align-items:center; gap:10px; white-space:nowrap; font:600 17px var(--ui); color:#f1f1f3; z-index:7; box-shadow:0 8px 24px rgba(0,0,0,.25); }
.phone .island .gl { width:22px; height:22px; }
.phone .island b { color:var(--gold); font-weight:700; }
.phone .view { position:absolute; left:0; right:0; top:0; bottom:0; }
.phone .pad { padding: 128px 22px 120px; }
.phone .lab { font:600 13px var(--ui); letter-spacing:.12em; text-transform:uppercase; color:var(--ink3); }
.phone .h1 { font:800 40px var(--display); letter-spacing:-.03em; margin:6px 0 16px; color:var(--ink); }
.phone .card { background:var(--card); border:1px solid var(--edge); position:relative; }
.phone .code { font:800 22px var(--display); letter-spacing:-.01em; }
.phone .row { display:flex; align-items:center; gap:14px; padding:14px 16px; border-radius:18px; background:var(--card); border:1px solid var(--edge); margin-bottom:10px; }
.phone .bar { width:4px; align-self:stretch; border-radius:2px; }
.phone .t { font:600 16px var(--ui); font-variant-numeric:tabular-nums; width:70px; color:var(--ink); }
.phone .t small { display:block; color:var(--ink3); font-weight:500; }
.phone .ti { font:400 16px var(--ui); color:var(--ink2); }
.phone .free { height:44px; border-radius:14px; display:flex; align-items:center; padding-left:84px; color:var(--gold); font:700 16px var(--display); margin-bottom:10px;
  background-image: radial-gradient(var(--gold) 1.2px, transparent 1.5px); background-size:7px 7px; background-color:transparent; opacity:.95; }
.phone .free span { background:var(--ground); padding:2px 8px; }
.phone .tabs { position:absolute; left:0; right:0; bottom:0; height:96px; background:var(--ground2); border-top:1px solid var(--edge); display:flex; justify-content:space-around; padding-top:12px; z-index:6; }
.phone .tab { display:flex; flex-direction:column; align-items:center; gap:6px; font:600 13px var(--display); color:var(--ink3); width:80px; }
.phone .tab.on { color:var(--gold); }
.phone .tab canvas { position:relative !important; }
.phone .stamp { font:800 24px var(--display); letter-spacing:.01em; border:3px solid currentColor; padding:4px 10px; transform:rotate(-3deg); color:var(--good); }
.phone .pend { font:600 15px var(--ui); color:var(--ink2); background:var(--sunk); padding:8px 12px; border-radius:12px; }
.phone .grid { position:relative; height:520px; margin-top:6px; }
.phone .blk { position:absolute; border-radius:8px; padding:6px 7px; font:800 12px var(--display); overflow:hidden; }
.phone .blk small { display:block; font:500 11px var(--ui); opacity:.85; margin-top:2px; }
.phone .btn4 { flex:1; text-align:center; padding:12px 0; border-radius:14px; font:700 15px var(--display); background:var(--card2); color:var(--ink2); border:1px solid var(--edge2); }
.phone .bub { max-width:320px; padding:12px 14px; border-radius:18px; font:400 16px/1.35 var(--ui); margin-bottom:10px; }
.phone .chip { display:inline-block; font:600 13px var(--ui); padding:5px 10px; border-radius:10px; background:var(--gold); color:var(--on-gold); }
`;

let styled = false;
function style() {
  if (styled) return;
  styled = true;
  const s = document.createElement("style");
  s.textContent = CSS;
  document.head.appendChild(s);
}

export const SUBJ = { COMP20073: 6, GEED10053: 1, MATH20013: 3, COMP20083: 5, PATHFIT2: 2, GEED10103: 4 };
const sv = (code) => `var(--s${SUBJ[code.replace(/\s/g, "")] || 1})`;

const glyph = () => sized(pixelCanvas(["oooooo", "o3443o", "o4234o", "o3243o", "o4324o", "oooooo"], { o: "#4a3160", 2: "#faebb3", 3: "#941c30", 4: "#cca128" }), 3.6);

function todayView(v) {
  v.innerHTML = `<div class="pad" data-r="scroll">
    <div class="lab">Monday, September 28</div>
    <div class="h1" data-r="hello">Good morning</div>
    <div class="card notch" data-r="hero" style="overflow:hidden">
      <div data-r="campus" style="height:176px;background:#0e1030;position:relative"></div>
      <div style="padding:16px 18px 18px;display:flex;justify-content:space-between;align-items:flex-end">
        <div><div class="lab">Up next</div>
          <div class="code" style="color:${sv("COMP 20073")};font-size:30px;margin-top:6px">COMP 20073</div>
          <div class="ti" style="color:var(--ink);font-size:17px">Data Structures and Algorithms</div>
          <div class="ti" style="font-size:14px;margin-top:4px">7:30–9:00AM · S512</div></div>
        <div style="text-align:right"><div style="font:800 44px var(--display);letter-spacing:-.04em" data-r="big">7:30</div>
          <div class="ti" style="font-size:15px" data-r="inm">in 9m</div></div>
      </div>
    </div>
    <div style="display:flex;justify-content:space-between;margin:22px 2px 12px"><div class="lab">Today</div><div style="font:700 15px var(--display);color:var(--gold)">4h free ahead</div></div>
    <div data-r="rows">
      <div class="row"><div class="t">7:30<small>9:00</small></div><div class="bar" style="background:${sv("COMP 20073")}"></div><div><div class="code" style="font-size:18px">COMP 20073</div><div class="ti">Data Structures and Algorithms</div></div></div>
      <div class="free"><span>1h 30m free</span></div>
      <div class="row"><div class="t">10:30<small>12:00</small></div><div class="bar" style="background:${sv("GEED 10053")}"></div><div><div class="code" style="font-size:18px">GEED 10053</div><div class="ti">Purposive Communication</div></div></div>
      <div class="row"><div class="t">1:00<small>2:30</small></div><div class="bar" style="background:${sv("MATH 20013")}"></div><div><div class="code" style="font-size:18px">MATH 20013</div><div class="ti">Discrete Structures</div></div></div>
      <div class="free"><span>2h 30m free</span></div>
    </div>
  </div>`;
}

const WEEK = [
  // day, start hour, length, code, room
  [0, 7.5, 1.5, "COMP 20073", "S512"], [0, 10.5, 1.5, "GEED 10053", "N301"], [1, 13, 1.5, "MATH 20013", "S208"], [2, 7.5, 3, "COMP 20083", "LAB 3"],
  [3, 7.5, 1.5, "COMP 20073", "S512"], [3, 10.5, 1.5, "GEED 10053", "N301"], [4, 13, 1.5, "MATH 20013", "S208"], [1, 15, 1.5, "GEED 10103", "N210"],
  [4, 15, 1.5, "GEED 10103", "N210"], [5, 8, 2, "PATHFIT 2", "GYM"],
];
export { WEEK };

function scheduleView(v) {
  const days = ["MON", "TUE", "WED", "THU", "FRI", "SAT"];
  const colW = 58, x0 = 40, hPx = 50, h0 = 7;
  v.innerHTML = `<div class="pad">
    <div class="lab">Sep 28 – Oct 3</div>
    <div class="h1">Schedule</div>
    <div style="display:flex;margin-left:${x0}px">${days.map((d, i) => `<div style="width:${colW}px;text-align:center;font:700 12px var(--display);color:${i === 0 ? "var(--gold)" : "var(--ink3)"}">${d}<br><span style="font:700 18px var(--display);color:${i === 0 ? "var(--gold)" : "var(--ink)"}">${28 + i > 30 ? 28 + i - 30 : 28 + i}</span></div>`).join("")}</div>
    <div class="grid" data-r="grid" style="perspective:900px">
      <div data-r="face" class="p3d" style="position:absolute;inset:0;transform-origin:50% 50% -150px">
      ${Array.from({ length: 11 }, (_, i) => `<div style="position:absolute;left:0;right:0;top:${i * hPx}px;border-top:1px solid var(--edge);font:600 11px var(--ui);color:var(--ink3);padding-top:2px">${((h0 + i - 1) % 12) + 1}${h0 + i < 12 ? "a" : "p"}</div>`).join("")}
      ${WEEK.map(([d, s, l, c, r], i) => `<div class="blk notch" data-r="b${i}" style="left:${x0 + d * colW + 2}px;top:${(s - h0) * hPx}px;width:${colW - 4}px;height:${l * hPx - 3}px;background:color-mix(in srgb, ${sv(c)} 22%, var(--card));color:${sv(c)};border:2px solid color-mix(in srgb, ${sv(c)} 55%, transparent)">${c.split(" ")[0]}<small>${c.split(" ")[1] || ""}</small><small>${r}</small></div>`).join("")}
      <div data-r="now" style="position:absolute;left:${x0 - 4}px;right:0;top:${(7.35 - h0) * hPx}px;height:3px;background:var(--gold)"><i style="position:absolute;left:-6px;top:-5px;width:13px;height:13px;background:var(--gold)"></i></div>
      </div>
    </div>
  </div>`;
}

export const GRADES = [
  ["COMP 20073", "Data Structures and Algorithms", "3u", "1.25"],
  ["GEED 10053", "Purposive Communication", "3u", "1.50"],
  ["PATHFIT 2", "Physical Activity Towards Health", "2u", "1.00"],
  ["COMP 20083", "Object-Oriented Programming", "3u", "1.25"],
  ["MATH 20013", "Discrete Structures", "3u", null],
  ["GEED 10103", "Readings in Philippine History", "3u", null],
];

function gradesView(v) {
  v.innerHTML = `<div class="pad">
    <div class="lab">First semester · 2026–2027</div>
    <div class="h1">Grades</div>
    <div class="card notch" style="padding:20px 22px;display:flex;justify-content:space-between;align-items:flex-end;margin-bottom:12px">
      <div><div class="lab">GPA</div><div data-r="gpa" style="font:800 72px var(--display);letter-spacing:-.04em;color:var(--good);line-height:1">1.28</div>
      <div class="ti" style="font-size:15px;margin-top:6px">4 of 6 posted · 11 units</div></div>
      <svg width="130" height="70" viewBox="0 0 130 70" data-r="spark"><polyline points="6,56 64,30 124,18" fill="none" stroke="var(--good)" stroke-width="3" data-r="line" stroke-dasharray="140" stroke-dashoffset="140"/>
        <rect x="1" y="51" width="10" height="10" fill="none" stroke="var(--good)" stroke-width="2.5"/><rect x="59" y="25" width="10" height="10" fill="none" stroke="var(--good)" stroke-width="2.5"/><rect x="119" y="13" width="10" height="10" fill="var(--good)"/></svg>
    </div>
    <div data-r="coach" class="card notch" style="padding:14px 18px 14px 22px;margin-bottom:12px;border-left:5px solid var(--gold)">
      <div class="lab">Coach</div><div data-r="coachT" style="font:400 17px/1.35 var(--ui);color:var(--ink);margin-top:4px;min-height:46px"></div></div>
    ${GRADES.map(([c, t, u, g], i) => `<div class="row" data-r="g${i}"><div class="bar" style="background:${sv(c)}"></div><div style="flex:1;min-width:0"><div class="code" style="font-size:18px">${c}</div><div class="ti" style="white-space:nowrap;overflow:hidden;text-overflow:ellipsis">${t}</div></div><div class="ti" style="font-size:15px">${u}</div>${g ? `<div class="stamp" data-r="s${i}">${g}</div>` : `<div class="pend">Pending</div>`}</div>`).join("")}
  </div>`;
}

function studyView(v) {
  v.innerHTML = `<div class="pad">
    <div class="lab">Study</div>
    <div class="h1">Decks</div>
    <div data-r="deckrow" style="display:flex;justify-content:space-between;align-items:center;margin-bottom:8px">
      <div><div class="code" style="font-size:20px;color:${sv("COMP 20073")}">COMP 20073</div><div class="ti">Trees & graphs</div></div>
      <div style="text-align:right"><div data-r="due" style="font:800 34px var(--display);color:var(--gold)">12</div><div class="ti" style="font-size:13px">due</div></div>
    </div>
    <div data-r="stage" class="p3d" style="position:relative;height:430px;perspective:1100px;margin-top:12px">
      ${Array.from({ length: 7 }, (_, i) => `<div data-r="c${i}" class="card notch p3d" style="position:absolute;left:36px;top:30px;width:316px;height:380px;transform-origin:50% 100%;backface-visibility:hidden">
        <div style="position:absolute;inset:0;padding:26px;display:flex;flex-direction:column;justify-content:space-between;backface-visibility:hidden" data-r="f${i}">
          <div class="lab">Question ${i + 1} of 12</div>
          <div style="font:800 30px/1.1 var(--display);letter-spacing:-.02em">${["Time complexity of binary search?", "What is a balanced BST?", "BFS uses which structure?", "Height of a heap with n nodes?", "Dijkstra fails on…?", "In-order traversal of a BST gives…?", "What does DFS use?"][i]}</div>
          <div class="ti" style="font-size:14px">Tap to flip</div></div>
        <div style="position:absolute;inset:0;padding:26px;display:flex;flex-direction:column;justify-content:center;transform:rotateY(180deg);backface-visibility:hidden;background:var(--card2)" data-r="k${i}">
          <div class="lab">Answer</div><div style="font:800 64px var(--display);color:var(--gold);letter-spacing:-.03em;margin:10px 0">O(log n)</div><div class="ti">Halve the range each step.</div></div>
      </div>`).join("")}
    </div>
    <div data-r="rate" style="display:flex;gap:8px;margin-top:10px"><div class="btn4">Again</div><div class="btn4">Hard</div><div class="btn4" data-r="good">Good</div><div class="btn4">Easy</div></div>
  </div>`;
}

export const NOTE = [
  ["h", "Trees & graphs"], ["m", "COMP 20073 · Week 5 · lecture"],
  ["p", "A binary search tree keeps smaller keys on the left, larger on the right."],
  ["p", "Balanced BST: heights of the two subtrees differ by at most 1, so search stays O(log n)."],
  ["b", "Rotations fix balance after an insert"], ["b", "In-order traversal gives sorted keys"],
  ["p", "BFS explores level by level with a queue. DFS goes deep first with a stack."],
  ["b", "Dijkstra fails on negative edges"], ["b", "Heap height is ⌊log n⌋"],
];
function notesView(v) {
  v.innerHTML = `<div class="pad" data-r="body">
    <div class="lab">Notebook</div>
    <div class="h1">Notes</div>
    <div data-r="sheet" class="card notch" style="padding:20px 22px;min-height:560px">
      ${NOTE.map(([k, t]) => k === "h" ? `<div style="font:800 30px var(--display);letter-spacing:-.02em;color:var(--ink);margin-bottom:4px">${t}</div>`
        : k === "m" ? `<div class="ti" style="font-size:14px;margin-bottom:14px;color:var(--gold)">${t}</div>`
        : k === "p" ? `<div style="font:400 17px/1.4 var(--ui);color:var(--ink);margin-bottom:12px">${t}</div>`
        : `<div style="font:400 17px/1.4 var(--ui);color:var(--ink2);margin:0 0 8px 6px">▪ ${t}</div>`).join("")}
    </div>
  </div>`;
}

function assisView(v) {
  v.innerHTML = `<div data-r="sheet" class="card" style="position:absolute;left:10px;right:10px;bottom:106px;height:560px;border-radius:30px;padding:18px 18px;box-shadow:0 -20px 60px rgba(0,0,0,.35);z-index:5">
    <div style="display:flex;align-items:center;gap:10px;margin-bottom:14px"><div data-r="orb" style="width:40px;height:40px;background:var(--island);display:flex;align-items:center;justify-content:center" class="notch"></div><div style="font:800 22px var(--display)">IntAssis</div><div style="margin-left:auto" class="chip">On this phone</div></div>
    <div data-r="q" class="bub" style="margin-left:auto;background:#1b5db8;color:#fff">What do I need for a 1.50?</div>
    <div data-r="a" class="bub" style="background:var(--sunk);color:var(--ink)"><span data-r="aT"></span></div>
    <div data-r="cite" style="margin-bottom:10px"><span class="chip" style="background:var(--gold-soft,rgba(245,178,39,.18));color:var(--gold)">From your grades</span></div>
    <div style="position:absolute;left:18px;right:18px;bottom:16px"><div style="font:400 13px var(--ui);color:var(--ink3);margin-bottom:8px">Runs locally and can be wrong. Check anything that matters.</div>
    <div style="height:48px;border-radius:14px;border:2px solid var(--edge2);padding:12px 14px;color:var(--ink3);font:400 16px var(--ui)">Ask IntAssis… or /command</div></div>
  </div>`;
}

export function makePhone(parent) {
  style();
  const root = el("div", "abs p3d", parent);
  const back = el("div", "phone", root);
  back.style.transform = "rotateY(180deg)";
  back.style.backfaceVisibility = "hidden";
  back.innerHTML = `<div style="position:absolute;inset:14px;border-radius:58px;background:linear-gradient(150deg,#3a2a33,#1d1418 60%,#2a1d24)"></div>
    <div style="position:absolute;right:40px;top:40px;width:170px;height:170px;border-radius:44px;background:#15101a;box-shadow:inset 0 0 0 3px #ffffff18">
      ${[[26, 26], [96, 26], [26, 96]].map(([x, y]) => `<i style="position:absolute;left:${x}px;top:${y}px;width:52px;height:52px;border-radius:50%;background:radial-gradient(circle,#2c3a55 20%,#05060a 60%);box-shadow:0 0 0 4px #2a2a30"></i>`).join("")}</div>
    <div style="position:absolute;left:0;right:0;top:440px;text-align:center;font:800 40px var(--display);color:#f5b227;letter-spacing:-.02em">IntPortal</div>`;
  const ph = el("div", "phone", root);
  ph.style.backfaceVisibility = "hidden";
  const scr = el("div", "scr", ph);
  el("div", "di", scr);
  el("div", "sb", scr, `<span data-r="clock">7:21</span><span style="display:flex;align-items:center;gap:6px"><b data-r="plane" style="display:none;font:700 16px var(--ui)">✈</b><svg data-r="bars" width="18" height="12"><rect x="0" y="8" width="3" height="4" fill="currentColor"/><rect x="5" y="5" width="3" height="7" fill="currentColor"/><rect x="10" y="2" width="3" height="10" fill="currentColor"/><rect x="15" y="0" width="3" height="12" fill="currentColor"/></svg><i></i></span>`);
  const sbr = refs(scr);
  const island = el("div", "island", scr);
  island.appendChild(glyph()).style.position = "relative";
  const islandT = el("span", "", island, "COMP 20073 · <b>in 9m</b>");
  const views = {};
  for (const [k, fn] of Object.entries({ today: todayView, schedule: scheduleView, grades: gradesView, study: studyView, notes: notesView })) {
    const v = el("div", "view", scr);
    fn(v);
    views[k] = { node: v, r: refs(v) };
  }
  const av = el("div", "view", scr);
  assisView(av);
  views.assis = { node: av, r: refs(av) };
  views.assis.r.orb.appendChild(icon("spark", "#f5b227", "#f5b227", 2.4)).style.position = "relative";
  const tabs = el("div", "tabs", scr);
  const tabEls = {};
  for (const [k, ic] of [["today", "today"], ["schedule", "schedule"], ["grades", "grades"], ["study", "study"], ["you", "you"]]) {
    const t = el("div", "tab", tabs);
    t.appendChild(icon(ic, "#8c8c96", "#f5b227", 2.6));
    el("div", "", t, k[0].toUpperCase() + k.slice(1));
    tabEls[k] = t;
  }
  let room = null;
  return {
    root, ph, scr, views, island, islandT, tabs, tabEls,
    setRoom(r) {
      if (room === r) return;
      room = r;
      applyRoom(scr, typeof r === "string" ? ROOM[r] : r);
    },
    setAirplane(on) {
      sbr.plane.style.display = on ? "" : "none";
      sbr.bars.style.display = on ? "none" : "";
    },
    setTab(k) {
      for (const t in tabEls) tabEls[t].classList.toggle("on", t === k);
    },
  };
}
