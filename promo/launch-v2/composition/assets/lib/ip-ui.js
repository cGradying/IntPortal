/* Phone UI markup builders (Today / Schedule / Grades / Study / You + Island + tab bar).
   Copy and layout follow the iOS app's demo state. Pure string builders -> deterministic. */
(function () {
  const IP = window.IP;
  const UI = (IP.ui = {});

  UI.COLORS = { "COMP 20073": "var(--s6)", "GEED 10053": "var(--s1)", "MATH 20013": "var(--s2)", "COMP 20083": "var(--s1)", "PATHFIT 2": "var(--s3)", "GEED 10103": "var(--s5)" };
  UI.col = (code) => UI.COLORS[code] || "var(--s1)";

  const GLYPH = (churn) => `<svg class="glyph" viewBox="0 0 7 9" shape-rendering="crispEdges"><path d="M0 0h7v9H0z" fill="#34203f"/><path d="M1 1h5v7H1z" fill="#170b1a"/><path d="M2 2h3v1H2zM1 4h2v1H1zM4 5h2v1H4zM2 6h3v1H2z" fill="${churn ? "#faebb3" : "#941c30"}"/><path d="M3 3h2v1H3zM2 5h2v1H2zM4 2h1v2H4z" fill="#cca128"/></svg>`;
  UI.jeepLane = () => `<span class="jeep-lane">${IP.spriteSVG(IP.JEEP, IP.JEEP_COLORS)}</span>`;

  // Island: {label, short, open, line, synced, trip, live}. Always the full 368px capsule; `open` only changes the clip.
  UI.island = (o = {}) => `
    <div class="m-pill"></div>
    <div class="m-island" data-island style="clip-path:${o.open ? "inset(0px 0px 0px 0px round 36px)" : "inset(0px 111px 72px 111px round 22px)"}">
      <div class="rc" style="opacity:${o.open ? 0 : 1}"><span class="lead" data-lead>${o.trip ? UI.jeepLane() : GLYPH(o.live)}</span><span class="ln" data-ln>${o.label || "IntPortal"}</span><span class="tr" data-tr>${o.short || ""}</span></div>
      <div class="ro" style="opacity:${o.open ? 1 : 0}"><span class="lead" data-lead2>${o.trip ? UI.jeepLane() : GLYPH(o.live)}</span><span class="ln" data-ln2>${o.label || "IntPortal"}</span><span class="tr" data-tr2>${o.short || ""}</span></div>
      <div class="more" style="opacity:${o.open ? 1 : 0}"><div class="big" data-big>${o.line || ""}</div><div class="meta"><span data-meta>${o.synced || "Synced just now · sis8.pup.edu.ph"}</span><span class="sync">Sync now</span></div></div>
    </div>`;

  UI.tabs = (active) => {
    const T = [["today", "Today"], ["schedule", "Schedule"], ["grades", "Grades"], ["study", "Study"], ["you", "You"]];
    return `<nav class="m-tabs">${T.map(([id, l]) => `<div class="tab${id === active ? " on" : ""}" data-tab="${id}">${IP.iconSVG(id === "schedule" ? "schedule" : id, 26, "currentColor", "var(--gold)")}<span>${l}</span></div>`).join("")}</nav>`;
  };

  UI.status = (time) => `<div class="ph-status"><span>${time || "7:18"}</span><span class="ph-ind"><i class="ph-sig"></i><i class="ph-wifi"></i><i class="ph-batt"></i></span></div>`;

  // ---------- screens ----------
  UI.today = (o = {}) => {
    const cls = (code, time, end, desc, extra = "") => `<li class="m-class" style="--c:${UI.col(code)}"><span class="time m-num">${time}<small>${end}</small></span><span class="stripe"></span><span class="what"><strong>${code}</strong><span>${desc}</span></span>${extra}</li>`;
    return `<div class="m-content">
      <header><p class="m-label">${o.date || "Monday, September 28"}</p><h1 class="m-h1">${o.greeting || "Good morning"}</h1></header>
      <section class="m-coach m-card m-notch" data-layer="coach"><div class="line"><span class="m-label" style="display:block;margin-bottom:2px">Coach</span>${o.coach || "For a 1.50 this term, aim for 1.69 or better on what's left."}</div><span class="x">×</span></section>
      <section class="m-hero m-card m-notch" data-layer="hero"><canvas class="m-campus" width="192" height="80"></canvas>
        <div class="m-up"><div class="who"><p class="m-label">${o.upLabel || "Up next"}</p><h2>${o.code || "COMP 20073"}</h2><p class="desc">${o.desc || "Data Structures and Algorithms"}</p><p class="meta">${o.meta || "7:30AM–9AM · SANTOS, JUAN"}</p></div>
        <div class="m-count"><span class="big m-num" data-count>${o.big || "12"}</span><span class="unit" data-unit>${o.unit || "minutes"}</span></div></div></section>
      <section data-layer="day"><div class="m-head"><p class="m-label">Today</p><p class="m-free m-num">4h free ahead</p></div>
        <ol class="m-daylist" style="margin-top:10px">${cls("COMP 20073", "7:30AM", "9AM", "Data Structures and Algorithms", o.now ? '<span class="m-now">Now</span>' : "")}<li class="m-gap m-num">1h 30m free</li>${cls("GEED 10053", "10:30AM", "12PM", "Purposive Communication")}</ol></section>
    </div>`;
  };

  UI.grades = (o = {}) => {
    const row = (code, desc, u, g, pending) => `<li class="m-grade" style="--c:${UI.col(code)}" data-row="${code}"><span class="stripe"></span><span class="what"><strong>${code}</strong><span>${desc}</span></span><span class="units">${u}u</span>${g ? `<span class="m-stamp" data-stamp>${g}</span>` : `<span class="m-pending">Pending</span>`}</li>`;
    const rows = o.rows || [["COMP 20073", "Data Structures and Algorithms", 3, "1.25"], ["GEED 10053", "Purposive Communication", 3, "1.50"], ["MATH 20013", "Discrete Structures", 3, ""], ["COMP 20083", "Object-Oriented Programming", 3, ""], ["PATHFIT 2", "Physical Activity Towards Health and…", 2, "1.00"]];
    return `<div class="m-content" style="gap:14px">
      <header><p class="m-label">First Semester · 2026-2027</p><h1 class="m-h1">Grades</h1></header>
      <section class="m-gpa m-card m-notch" data-layer="gpa"><div><p class="m-label">GPA</p><p class="value m-num" data-gpa>${o.gpa || "1.28"}${o.best ? '<span class="m-best" data-best>Personal best</span>' : ""}</p><p class="sub">3 of 6 posted · 8 units</p></div>
        <svg class="trend" viewBox="0 0 100 40" preserveAspectRatio="none"><path d="M4 32 L50 20 L96 12" fill="none" stroke="var(--gold)" stroke-width="2" vector-effect="non-scaling-stroke"/><rect x="2" y="30" width="4" height="4" fill="var(--card)" stroke="var(--gold)" vector-effect="non-scaling-stroke"/><rect x="48" y="18" width="4" height="4" fill="var(--card)" stroke="var(--gold)" vector-effect="non-scaling-stroke"/><rect x="94" y="10" width="4" height="4" fill="var(--gold)" stroke="var(--gold)" vector-effect="non-scaling-stroke"/></svg></section>
      <p class="m-note">Lower is better on PUP's 1.00–5.00 scale. Weighted by units; INC and DRP don't count.</p>
      <ol class="m-daylist" data-layer="rows">${rows.map((r) => row(...r)).join("")}</ol></div>`;
  };

  UI.study = (o = {}) => `<div class="m-content" style="gap:14px">
    <header><p class="m-label">Spaced repetition</p><h1 class="m-h1">Study</h1></header>
    <section class="m-sum m-card m-notch" data-layer="sum"><div><p class="m-label">Due now</p><p class="big m-num">${o.due || 6}</p></div><div><p class="m-label">Streak</p><p class="big m-num">${o.streak || 5}<small> days</small></p></div><div><p class="m-label">Today</p><p class="big m-num">${o.today || 12}<small> cards</small></p></div></section>
    <div class="m-deck" data-layer="deck"><span class="what"><strong>DSA terms</strong><small>COMP 20073 · 18 cards</small></span><span class="due m-num">6 due</span></div>
    <section class="m-term m-card m-notch" data-layer="card"><p class="m-label">Term</p><p class="t">${o.term || "Queue"}</p><hr/><p class="d" data-answer style="opacity:${o.showAnswer ? 1 : 0}">first in first out</p></section>
    <div class="m-rate" data-layer="rate"><div class="again">Again</div><div>Hard</div><div class="${o.pick === "good" ? "pick" : ""}">Good</div><div>Easy</div></div></div>`;

  UI.schedule = (o = {}) => {
    const hrs = [7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17];
    const H = 40, top = 28, colW = 160;
    const y = (h) => top + (h - 7) * H;
    const blocks = [
      [0, 7.5, 9, "COMP", "20073", "var(--s6)"], [0, 10.5, 12, "GEED", "10053", "var(--s1)"], [0, 13, 15, "MATH", "20013", "var(--s2)"], [0, 16, 17.5, "COMP", "20083", "var(--s1)"],
      [1, 8, 10, "PATHFIT", "2", "var(--s5)"], [1, 13, 16, "GEED", "10103", "var(--s3)"],
    ];
    return `<div class="m-content" style="gap:12px">
      <header><p class="m-label">This week</p><h1 class="m-h1">Schedule</h1></header>
      <div class="m-seg"><div>Day</div><div class="on">Week</div></div>
      <div class="m-week" data-layer="week">
        <div class="dh on" style="left:34px;width:${colW}px">MON</div><div class="dh" style="left:${34 + colW + 6}px;width:${colW}px">TUE</div>
        ${hrs.map((h) => `<div class="hr" style="top:${y(h) - 6}px">${h <= 12 ? h : h - 12}${h < 12 ? "a" : "p"}</div><div class="ln" style="top:${y(h)}px"></div>`).join("")}
        ${blocks.map(([c, s, e, a, b, col], i) => `<div class="blk" data-blk="${i}" style="--c:${col};left:${34 + c * (colW + 6)}px;width:${colW}px;top:${y(s)}px;height:${(e - s) * H - 2}px">${a}<small>${b}</small></div>`).join("")}
        <div class="m-nowline" style="top:${y(15.5)}px"></div></div></div>`;
  };

  UI.rooms = () => {
    const ids = ["night", "day", "maroon", "pupMaroon", "astraMoon", "sakura", "matrix", "dracula", "nord"];
    return ids.map((id, i) => {
      const r = IP.room(id);
      return `<div class="m-room m-notch${i === 0 ? " on" : ""}" data-room-id="${id}"><span class="m-swatch"><i style="background:${r["--ground"]}"></i><i style="background:${r["--card"]}"></i><i style="background:${r["--gold"]}"></i></span><span>${r.name}</span></div>`;
    }).join("");
  };
  UI.you = () => `<div class="m-content" style="gap:14px">
    <header><p class="m-label">Account and look</p><h1 class="m-h1">You</h1></header>
    <section class="m-block m-card m-notch" data-layer="sync"><p class="m-label">Sync</p><div class="m-line"><span>Last synced</span><strong>Sep 28, 2026 at 7:18 AM</strong></div><div class="m-line"><span>Server</span><strong>sis8.pup.edu.ph</strong></div><div class="m-btn">Sync now</div></section>
    <section class="m-block m-card m-notch" data-layer="rooms"><p class="m-label">Room</p><div class="m-rooms">${UI.rooms()}</div></section></div>`;


  // ---------- Mac window (Registrar). o: {room, time} -> 1600x1000 markup ----------
  const SUN = `<svg viewBox="0 0 12 12" shape-rendering="crispEdges">${IP.ICONS.today.map((row, y) => [...row].map((c, x) => (c === "#" ? `<rect x="${x}" y="${y}" width="1" height="1" fill="currentColor"/>` : c === "+" ? `<rect x="${x}" y="${y}" width="1" height="1" fill="var(--gold)"/>` : "")).join("")).join("")}</svg>`;
  const SPARK = `<svg viewBox="0 0 9 9" shape-rendering="crispEdges"><path d="M4 0h1v3h1v1h3v1H6v1H5v3H4V6H3V5H0V4h3V3h1z" fill="var(--maroon)"/></svg>`;
  UI.SPARK = SPARK;
  UI.mac = function (o = {}) {
    const notes = [["Pointers and memory", 1], ["Arrays vs linked lists", 0], ["Big-O cheat sheet", 0], ["Recursion practice", 0]];
    return `<div class="mac" data-room="${o.room || "pupMaroon"}">
      <div class="mac-dither"></div>
      <div class="mac-pill"><span style="width:30px;height:30px;color:var(--ink)">${SUN}</span><b>Today</b><span>· MATH 20013 at 1PM</span></div>
      <div class="mac-main">
        <div class="mac-tabs"><span>Arrays vs linked lists</span><span class="on">Pointers and memory</span><span>Big-O cheat sheet</span></div>
        <h1 class="mac-title">Pointers and memory</h1>
        <div class="mac-tools"><i></i><i></i><i></i><i></i><i></i><i></i><i></i><i></i></div>
        <div class="mac-doc"><h4>Pointers 101</h4><p>- A pointer stores an address.</p><p>- Arrays decay to pointers.</p><p>- Every malloc needs a free.</p><p>- NULL means "points nowhere".</p><p>- Stack is fast, heap is yours.</p></div>
      </div>
      <aside class="mac-side">
        <h2>Monday</h2><p class="sub">September 28 &nbsp;·&nbsp; 1h free</p>
        <div class="mac-daynote"><span>Day note</span><span>Sep 28</span></div>
        <div class="mac-cls" data-cls="a" style="--c:var(--s2)"><b>MATH 20013 <em>at 1PM</em></b><span>Discrete Structures</span><span>1PM – 3PM</span><div class="stamp" data-stamp-online>Online</div></div>
        <div class="mac-gap">1h free</div>
        <div class="mac-cls" style="--c:var(--s1)"><b>COMP 20083 <em>at 4PM</em></b><span>Object-Oriented Programming</span></div>
        <div class="mac-vault">Vault</div>
        ${notes.map(([n, on]) => `<div class="mac-note${on ? " on" : ""}"><span>${n}</span><i></i></div>`).join("")}
      </aside>
      <div class="mac-orbbtn">${SPARK}</div>
    </div>`;
  };
  UI.macPanel = () => `<div class="mac-panel">
      <div class="ph"><b>Assistant</b><span class="tag">LOCAL</span><span class="auto">Act automatically</span></div>
      <div class="msgs"><div class="u" data-u>/rag summarize my C note</div><div class="a" data-a></div><div class="chips" data-chips><span>Pointers and memory</span><span>Arrays vs linked lists</span></div></div>
      <div class="inp"><span class="ph-txt" data-inp></span><span class="send">&#8593;</span></div>
    </div>`;

  // whole phone. o: {room, screen, time, island:{...}, explode, lite, tab}
  UI.phone = function (o = {}) {
    const screens = { today: UI.today, schedule: UI.schedule, grades: UI.grades, study: UI.study, you: UI.you };
    const body = (screens[o.screen || "today"])(o.data || {});
    return `<div class="phone${o.lite ? " lite" : ""}${o.flat ? " flat" : ""}" data-room="${o.room || "night"}">
      <div class="ph-slab">${o.flat ? "" : [-5, -3, -1, 1, 3, 5].map((z) => `<div class="ph-slice" style="transform:translateZ(${z}px)"></div>`).join("") + '<div class="ph-back"></div>'}
        <div class="ph-front"><div class="ph-screen${o.explode ? " explode" : ""}"><div class="ph-plate"></div>${UI.status(o.time)}${UI.island(o.island || {})}${body}${UI.tabs(o.tab || o.screen || "today")}<div class="ph-home"></div></div></div></div></div>`;
  };
  UI.mount = function (el, o) {
    el.innerHTML = UI.phone(o);
    const ph = el.querySelector(".phone");
    IP.applyRoom(ph, o.room || "night");
    return ph;
  };
  // paint every campus canvas inside el at `ms`/`hour`
  UI.paintCampus = function (el, ms, hour, litKey) {
    el.querySelectorAll("canvas.m-campus").forEach((cv) => IP.drawCampus(cv.getContext("2d"), 192, 80, ms, hour, { lit: IP.litIndexFor(litKey || "COMP 20073"), jeepCycle: false }));
  };
})();
