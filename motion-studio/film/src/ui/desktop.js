// Desktop surfaces: macOS Registrar (SwiftUI app), Windows (WinUI port) and
// the web app (React). Markup mirrors each codebase's layout: the Mac's maroon
// menu field + sheets + pixel titles, WinUI's NavigationView, the web's top nav.
import { el } from "../lib/core.js";
import { WEEK } from "./phone.js";

const SUB = { COMP: ["#7a1128", "#3f517a"], GEED: ["#b13e34", "#5c315f"], MATH: ["#8f6410"], PATHFIT: ["#2e5a4f"] };
const subj = (c) => {
  const [p, n] = c.split(" ");
  const arr = SUB[p] || ["#3f517a"];
  return arr[(parseInt(n || "0", 10) >> 4) % arr.length];
};

function weekGrid({ x0 = 60, colW = 150, hPx = 52, h0 = 7, font = "var(--pixel)", days = 6, notch = true, now = true } = {}) {
  const D = ["MON 28", "TUE 29", "WED 30", "THU 1", "FRI 2", "SAT 3"].slice(0, days);
  return `<div style="position:relative;height:${hPx * 10 + 40}px">
    <div style="display:flex;margin-left:${x0}px;height:34px">${D.map((d, i) => `<div style="width:${colW}px;font:600 13px var(--ui);letter-spacing:.08em;color:${i === 0 ? "#765806" : "#766c6f"};${i === 0 ? "background:rgba(201,162,39,.14)" : ""};padding:8px">${d}</div>`).join("")}</div>
    ${Array.from({ length: 10 }, (_, i) => `<div style="position:absolute;left:0;right:0;top:${34 + i * hPx}px;border-top:1px solid #e2ddd6;font:500 12px var(--ui);color:#766c6f;padding:3px 8px">${((h0 + i - 1) % 12) + 1} ${h0 + i < 12 ? "AM" : "PM"}</div>`).join("")}
    ${WEEK.filter((w) => w[0] < days).map(([d, s, l, c, r], i) => {
      const col = subj(c);
      return `<div data-r="w${i}" class="${notch ? "notch" : ""}" style="position:absolute;left:${x0 + d * colW + 3}px;top:${34 + (s - h0) * hPx + 2}px;width:${colW - 6}px;height:${l * hPx - 4}px;background:color-mix(in srgb, ${col} 13%, #fff);border:2px solid color-mix(in srgb, ${col} 45%, transparent);${notch ? "" : "border-radius:6px;"}padding:6px 8px;overflow:hidden">
        <div style="font:${font === "var(--pixel)" ? "500 16px" : "700 14px"} ${font};color:${col}">${c}</div><div style="font:500 12px var(--ui);color:#554c4f">${r}</div></div>`;
    }).join("")}
    ${now ? `<div style="position:absolute;left:${x0}px;right:0;top:${34 + 0.35 * hPx}px;height:2px;background:#c9a227"></div>` : ""}
  </div>`;
}

export function macApp(parent) {
  const n = el("div", "abs", parent);
  const menu = (t, on) => `<div style="padding:8px 14px;margin:1px 8px;font:600 15px var(--ui);color:${on ? "#fff" : "#ddb9be"};${on ? "background:#560a19;" : ""}display:flex;gap:10px;align-items:center" class="${on ? "notch" : ""}"><i style="width:14px;height:14px;background:${on ? "#c9a227" : "#ddb9be55"}"></i>${t}</div>`;
  n.innerHTML = `<div style="position:absolute;inset:0;display:flex;background:#f4f2ef;font-family:var(--ui);color:#1c1517">
    <div style="width:236px;background:#6d0e1f;color:#f7ecec;display:flex;flex-direction:column;padding-top:16px">
      <div style="display:flex;gap:7px;padding:0 16px 18px"><i style="width:12px;height:12px;border-radius:50%;background:#ff5f57"></i><i style="width:12px;height:12px;border-radius:50%;background:#febc2e"></i><i style="width:12px;height:12px;border-radius:50%;background:#28c840"></i></div>
      <div style="display:flex;align-items:center;gap:10px;padding:0 16px 20px;font:700 22px var(--pixel)"><i style="width:16px;height:22px;background:linear-gradient(#faebb3,#cca128 40%,#941c30);outline:3px solid #34203f"></i>IntPortal</div>
      <div style="font:700 11px var(--pixel);letter-spacing:.12em;color:#ddb9be;padding:4px 18px">MAIN</div>${menu("Today")}${menu("Schedule", true)}${menu("Grades")}
      <div style="font:700 11px var(--pixel);letter-spacing:.12em;color:#ddb9be;padding:14px 18px 4px">STUDY</div>${menu("Notebook")}${menu("Quizzes")}${menu("Syllabus")}
      <div style="font:700 11px var(--pixel);letter-spacing:.12em;color:#ddb9be;padding:14px 18px 4px">SYSTEM</div>${menu("Settings")}
      <div style="margin-top:auto;padding:16px;border-top:1px solid #ffffff22;font:600 14px var(--ui)">Iskolar (sample)<div style="margin-top:6px;display:inline-block;padding:3px 8px;background:#560a19;font:700 12px var(--pixel)">MN · Sta. Mesa</div></div>
    </div>
    <div style="flex:1;padding:22px 28px;min-width:0">
      <div style="font:500 13px var(--ui);color:#766c6f">Student Module › Schedule</div>
      <div style="display:flex;align-items:baseline;gap:16px"><div style="font:700 34px var(--pixel);margin:4px 0 2px">Schedule</div><div style="font:400 15px var(--ui);color:#554c4f">Week of Sep 28 · 6 classes</div>
      <div style="margin-left:auto;padding:8px 16px;background:#1b5db8;color:#fff;font:500 15px var(--pixel)" class="notch">Export</div></div>
      <div style="margin-top:14px;background:#fff;border:1px solid #e2ddd6;padding:0 0 10px" class="notch">
        <div style="display:flex;justify-content:space-between;padding:10px 14px;background:#f7f5f2;border-bottom:1px solid #e2ddd6;font:600 13px var(--pixel);letter-spacing:.06em">THIS WEEK<span style="color:#766c6f">SYNCED 7:21 AM</span></div>
        ${weekGrid({ colW: 142 })}
      </div>
    </div>
    <div style="position:absolute;left:250px;bottom:18px;width:48px;height:48px;background:#1c1517" class="notch"></div>
  </div>`;
  return n;
}

export function winApp(parent) {
  const n = el("div", "abs", parent);
  const nav = (t, on) => `<div style="position:relative;padding:10px 14px 10px 18px;margin:2px 6px;border-radius:6px;font:400 15px var(--ui);${on ? "background:#e9e6e6;font-weight:600" : ""}">${on ? '<i style="position:absolute;left:4px;top:10px;width:3px;height:20px;border-radius:2px;background:#7a1128"></i>' : ""}${t}</div>`;
  n.innerHTML = `<div style="position:absolute;inset:0;background:#f3f1f1;font-family:var(--ui);color:#1b1b1b;display:flex;flex-direction:column">
    <div style="height:42px;display:flex;align-items:center;padding-left:14px;gap:10px;font:400 13px var(--ui)"><i style="width:16px;height:16px;background:linear-gradient(#faebb3,#cca128 40%,#941c30)"></i>IntPortal<span style="margin-left:auto;display:flex">${["—", "▢", "✕"].map((c) => `<span style="width:46px;text-align:center">${c}</span>`).join("")}</span></div>
    <div style="flex:1;display:flex">
      <div style="width:250px;padding-top:6px">${nav("Today", true)}${nav("Schedule")}${nav("Grades")}${nav("Notebook")}${nav("Quizzes")}${nav("Syllabus")}<div style="height:180px"></div>${nav("Settings")}</div>
      <div style="flex:1;background:#fbfbfb;border-top-left-radius:8px;border:1px solid #e5e5e5;padding:26px 32px">
        <div style="font:600 30px var(--ui)">Today</div><div style="font:400 15px var(--ui);color:#5f5f5f;margin-bottom:18px">Monday, September 28 · 4h free</div>
        ${[["7:30", "COMP 20073", "Data Structures and Algorithms", "#3f517a"], ["", "1h 30m free", "", ""], ["10:30", "GEED 10053", "Purposive Communication", "#b13e34"], ["1:00", "MATH 20013", "Discrete Structures", "#8f6410"]].map(([t, c, d, col], i) =>
          col ? `<div data-r="win${i}" style="display:flex;gap:16px;align-items:center;background:#fff;border:1px solid #e5e5e5;border-radius:8px;padding:14px 16px;margin-bottom:10px"><div style="width:56px;font:600 16px var(--ui)">${t}</div><i style="width:4px;height:40px;border-radius:2px;background:${col}"></i><div><div style="font:700 17px var(--ui)">${c}</div><div style="font:400 14px var(--ui);color:#5f5f5f">${d}</div></div></div>`
            : `<div style="margin:0 0 10px 72px;padding:8px 12px;border-radius:8px;background:repeating-linear-gradient(45deg,#f6e9c4 0 6px,#fbf4e2 6px 12px);font:600 14px var(--ui);color:#765806">${c}</div>`).join("")}
      </div>
    </div>
  </div>`;
  return n;
}

export function webApp(parent) {
  const n = el("div", "abs", parent);
  n.innerHTML = `<div style="position:absolute;inset:0;background:#dee1e6;font-family:var(--ui);display:flex;flex-direction:column">
    <div style="height:40px;display:flex;align-items:flex-end;padding-left:80px;gap:4px"><div style="background:#fff;border-radius:10px 10px 0 0;padding:9px 16px;width:220px;font:500 13px var(--ui);display:flex;gap:8px;align-items:center"><i style="width:14px;height:14px;background:linear-gradient(#faebb3,#cca128 40%,#941c30)"></i>IntPortal</div></div>
    <div style="height:44px;background:#fff;display:flex;align-items:center;padding:0 14px;gap:14px;color:#5f6368"><span>←</span><span>→</span><span>↻</span><div style="flex:1;height:30px;border-radius:15px;background:#f1f3f4;display:flex;align-items:center;padding:0 14px;font:400 14px var(--ui);color:#3c4043">🔒&nbsp; IntPortal Web</div></div>
    <div style="flex:1;background:linear-gradient(#fcfbfa,#f2edec);padding:0 0 0;display:flex;flex-direction:column">
      <div style="height:58px;background:#140608;display:flex;align-items:center;gap:26px;padding:0 28px;color:#fcfbfa;font:600 15px var(--ui)"><b style="font:800 18px var(--display)">IntPortal</b><span style="opacity:.7">Schedule</span><span style="border-bottom:2px solid #c9a227;padding:6px 0">Grades</span><span style="opacity:.7">Notes</span><span style="opacity:.7">Quizzes</span><span style="opacity:.7">Syllabus</span></div>
      <div style="padding:26px 32px;display:flex;gap:22px">
        <div style="flex:1.5;background:#fff;border-radius:14px;padding:22px;box-shadow:0 1px 0 #0001">
          <div style="font:600 13px var(--ui);letter-spacing:.1em;color:#766c6f">GPA TREND</div>
          <div style="font:800 64px var(--display);color:#7a1128;letter-spacing:-.03em">1.28</div>
          <svg width="100%" height="200" viewBox="0 0 600 200" preserveAspectRatio="none"><polyline points="0,150 150,120 300,95 450,70 600,52" fill="none" stroke="#7a1128" stroke-width="4"/><polyline points="0,150 150,120 300,95 450,70 600,52 600,200 0,200" fill="#7a112814"/></svg>
        </div>
        <div style="flex:1;display:flex;flex-direction:column;gap:12px">
          ${[["COMP 20073", "1.25"], ["GEED 10053", "1.50"], ["PATHFIT 2", "1.00"], ["COMP 20083", "1.25"]].map(([c, g]) => `<div style="background:#fff;border-radius:12px;padding:14px 18px;display:flex;justify-content:space-between;font:700 17px var(--display)">${c}<span style="color:#1e7249">${g}</span></div>`).join("")}
        </div>
      </div>
    </div>
  </div>`;
  return n;
}
