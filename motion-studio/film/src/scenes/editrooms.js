// Edit mid-animation / Rooms (beats 100–116). The camera pulls back out of the
// phone and the film turns out to be playing inside a pixel motion editor:
// layers, an inspector, a beat-marked timeline with the real playhead still
// moving. A cursor flips a room switch on every beat (a keyframe lands on the
// Room track each time) and the phone in the viewport re-rooms live. Isko
// hops out of the viewport and flips the last one himself. Then the camera
// pushes back into the viewport.
import { clamp, css, ease, el, hash, lerp, pb, pulse, springB } from "../lib/core.js";
import { renderCampus } from "../art/campus.js";
import { blinkAt, makeIsko } from "../art/isko.js";
import { makePhone } from "../ui/phone.js";
import { pixText } from "../ui/pixtype.js";
import { ROOM } from "../ui/rooms.js";
import { pixSwitch } from "../ui/switch.js";
import { makeBubble } from "../ui/bubble.js";

const LIST = ["Night", "Day", "Maroon Night", "Astra Moon", "Sakura", "Tokyo Night", "Dracula", "Matrix", "Nord", "Catppuccin", "Gruvbox", "PUP Maroon"];
const FLIPS = [[102, 1], [103, 2], [104, 3], [105, 4], [106, 5], [107, 6], [108, 7], [109, 8], [110, 9], [111, 10], [112, 11], [114, 0]];
const VP = { x: 300, y: 64, w: 1260, h: 696 }; // viewport rect in editor space
const FILL = 1920 / VP.w;
const T0 = 96, T1 = 124; // timeline window (beats)
const PIX = "font-family:var(--pixel);font-weight:700;letter-spacing:.04em";

const roomAt = (b) => FLIPS.reduce((a, [at, i]) => (b >= at ? i : a), 0);

export default {
  id: "editrooms", from: 100, to: 116,
  init(layer) {
    css(layer, { background: "#0b090e" });
    const E = (this.E = el("div", "abs", layer));
    css(E, { left: "0", top: "0", width: "1920px", height: "1080px", transformOrigin: "0 0", background: "#141019" });
    // top bar
    el("div", "abs", E, `<div style="position:absolute;left:0;right:0;top:0;height:64px;background:#1d1724;border-bottom:3px solid #2c2236"></div>
      <div style="position:absolute;left:24px;top:14px;${PIX};font-size:28px;color:#f5b227">▣ MOTION STUDIO</div>
      <div style="position:absolute;left:760px;top:18px;${PIX};font-size:24px;color:#cdbbd8;white-space:nowrap">intportal-launch.film</div>
      <div style="position:absolute;right:250px;top:14px;${PIX};font-size:28px;color:#f7ecec">▶ ■</div>`);
    this.tc = el("div", "abs", E);
    css(this.tc, { right: "30px", top: "16px", font: "700 26px var(--pixel)", color: "#58c792", letterSpacing: ".08em" });
    // layers panel
    const L = el("div", "abs", E);
    css(L, { left: "0", top: "64px", width: "300px", height: "696px", background: "#18131e", borderRight: "3px solid #2c2236", padding: "18px 0" });
    el("div", "", L, `<div style="${PIX};font-size:20px;color:#8a7a99;padding:0 22px 12px">LAYERS</div>`);
    this.layers = ["Isko", "Type", "Phone", "Room", "Portal", "Music"].map((n) => {
      const r = el("div", "", L, `<span style="color:#8a7a99">◉</span>&nbsp;&nbsp;${n}`);
      css(r, { font: "600 24px var(--ui)", color: "#e8dcef", padding: "12px 22px" });
      return r;
    });
    // viewport
    this.vp = el("div", "abs", E);
    css(this.vp, { left: `${VP.x}px`, top: `${VP.y}px`, width: `${VP.w}px`, height: `${VP.h}px`, overflow: "hidden" });
    this.vpDots = el("div", "abs", this.vp);
    css(this.vpDots, { inset: "0", backgroundSize: "30px 30px" });
    this.P = makePhone(this.vp);
    this.canvas = el("canvas", "", this.P.views.today.r.campus);
    this.canvas.width = 776; this.canvas.height = 352;
    css(this.canvas, { width: "388px", height: "176px", display: "block" });
    this.make = pixText(this.vp, { text: "Make it\nyours.", size: 120, x: 70, y: 150, lh: 1.02, ink: "#f7ecec", shadow: "#000000" });
    this.sel = el("div", "abs", this.vp);
    css(this.sel, { left: "40px", top: "110px", width: "520px", height: "300px", border: "3px dashed #5ab0ff" });
    this.selTag = el("div", "abs", this.vp);
    css(this.selTag, { left: "40px", top: "66px", padding: "6px 12px", background: "#5ab0ff", color: "#06131f", font: "700 20px var(--pixel)", letterSpacing: ".06em", whiteSpace: "nowrap" });
    this.sel.innerHTML = [[0, 0], [100, 0], [0, 100], [100, 100]].map(([x, y]) => `<i style="position:absolute;left:calc(${x}% - 8px);top:calc(${y}% - 8px);width:13px;height:13px;background:#fff;border:3px solid #5ab0ff"></i>`).join("");
    // inspector
    const I = el("div", "abs", E);
    css(I, { left: "1560px", top: "64px", width: "360px", height: "696px", background: "#18131e", borderLeft: "3px solid #2c2236", padding: "18px 22px" });
    el("div", "", I, `<div style="${PIX};font-size:20px;color:#8a7a99">INSPECTOR · PHONE</div><div style="${PIX};font-size:26px;color:#f5b227;margin-top:14px">ROOM</div>`);
    this.sws = LIST.map((n, i) => pixSwitch(I, { label: n, s: 0.62, x: 22, y: 106 + i * 40, labelSize: 34, ink: "#e8dcef" }));
    el("div", "abs", I, `<div style="position:absolute;left:0;top:590px;${PIX};font-size:22px;color:#8a7a99;width:300px">HELPER</div>`);
    this.swIsko = pixSwitch(I, { label: "Isko", s: 0.62, x: 22, y: 620, labelSize: 34, ink: "#e8dcef" });
    this.swOff = pixSwitch(I, { label: "Offline mode", s: 0.62, x: 22, y: 660, labelSize: 34, ink: "#e8dcef" });
    // timeline
    const TL = el("div", "abs", E);
    css(TL, { left: "0", top: "760px", width: "1920px", height: "320px", background: "#120e17", borderTop: "3px solid #2c2236" });
    const tx = (b) => 300 + ((b - T0) / (T1 - T0)) * 1580;
    this.tx = tx;
    let ruler = "";
    for (let bb = T0; bb <= T1; bb++) ruler += `<i style="position:absolute;left:${tx(bb)}px;top:${bb % 4 ? 30 : 16}px;width:3px;height:${bb % 4 ? 12 : 26}px;background:${bb % 4 ? "#3b2f47" : "#6a5680"}"></i>${bb % 4 ? "" : `<b style="position:absolute;left:${tx(bb) + 6}px;top:10px;${PIX};font-size:18px;color:#8a7a99">${bb}</b>`}`;
    el("div", "abs", TL, ruler);
    const tracks = ["Isko", "Type", "Phone", "Room", "Music", "SFX"];
    tracks.forEach((n, i) => {
      el("div", "abs", TL, `<div style="position:absolute;left:0;top:${58 + i * 42}px;width:300px;height:38px;${PIX};font-size:20px;color:#b9a8c9;padding:8px 22px">${n}</div>
        <div style="position:absolute;left:300px;right:0;top:${58 + i * 42}px;height:38px;background:${i % 2 ? "#17121d" : "#1a1421"}"></div>`);
    });
    // music waveform + clip blocks
    let wave = "";
    for (let x = 300; x < 1900; x += 8) {
      const bb = T0 + ((x - 300) / 1580) * (T1 - T0);
      const h = 6 + hash(Math.floor(bb * 4), 3) * 22 * (bb % 1 < 0.2 ? 1.3 : 0.8);
      wave += `<i style="position:absolute;left:${x}px;top:${58 + 4 * 42 + 19 - h / 2}px;width:5px;height:${h}px;background:#5d3f78"></i>`;
    }
    el("div", "abs", TL, wave);
    el("div", "abs", TL, `<div style="position:absolute;left:${tx(100)}px;width:${tx(116) - tx(100)}px;top:${58 + 2 * 42 + 4}px;height:30px;background:#2f5a8a"></div>
      <div style="position:absolute;left:${tx(96)}px;width:${tx(100) - tx(96)}px;top:${58 + 2 * 42 + 4}px;height:30px;background:#3a2f55"></div>
      <div style="position:absolute;left:${tx(102)}px;width:${tx(112) - tx(102)}px;top:${58 + 1 * 42 + 4}px;height:30px;background:#6a4a1a"></div>
      <div style="position:absolute;left:${tx(100)}px;width:${tx(116) - tx(100)}px;top:${58 + 0 * 42 + 4}px;height:30px;background:#4a2f5e"></div>`);
    this.keys = FLIPS.map(([at]) => {
      const k = el("div", "abs", TL);
      css(k, { left: `${tx(at) - 9}px`, top: `${58 + 3 * 42 + 10}px`, width: "18px", height: "18px", background: "#f5b227", transform: "rotate(45deg)" });
      return k;
    });
    this.sfx = FLIPS.map(([at]) => {
      const k = el("div", "abs", TL);
      css(k, { left: `${tx(at)}px`, top: `${58 + 5 * 42 + 8}px`, width: "10px", height: "22px", background: "#58c792" });
      return k;
    });
    this.ph = el("div", "abs", TL);
    css(this.ph, { top: "0", width: "4px", height: "320px", background: "#ff4d5e" });
    this.phHead = el("div", "abs", TL);
    css(this.phHead, { top: "0", width: "20px", height: "20px", background: "#ff4d5e", clipPath: "polygon(0 0,100% 0,50% 100%)" });
    // cursor + Isko
    this.cursor = el("div", "abs", layer,
      `<svg width="38" height="52" viewBox="0 0 17 23" shape-rendering="crispEdges"><path d="M1 1 L1 18 L5.5 13.8 L8.6 21 L11.4 19.8 L8.4 12.8 L14.5 12.8 Z" fill="#fff" stroke="#000" stroke-width="1.4"/></svg>`);
    this.isko = makeIsko(layer, 4);
    this.bubble = makeBubble(layer);
  },
  render(b, t) {
    // ---- editor camera: start with the viewport filling the frame, pull
    // back (100 → 101.3), push back in (114.8 → 116)
    const out = springB(b, 100, 1.3, 0.78);
    const back = pb(b, 114.8, 116, ease.inCubic);
    const s = lerp(FILL, 1, out) * (1 - back) + FILL * 1.25 * back;
    const cx = VP.x + VP.w / 2, cy = VP.y + VP.h / 2;
    const ox = lerp(960, lerp(cx, 960, 1), out), oy = lerp(540, cy, out);
    const fx = lerp(ox, 960, back), fy = lerp(oy, 540, back);
    this.E.style.transform = `translate(${fx - cx * s}px, ${fy - cy * s}px) scale(${s})`;
    const toScreen = (x, y) => [fx - cx * s + x * s, fy - cy * s + y * s];

    // ---- timecode + playhead: the real film time
    const fr = Math.floor(t * 60);
    const tcs = `00:${String(Math.floor(t / 60)).padStart(2, "0")}:${String(Math.floor(t % 60)).padStart(2, "0")}:${String(fr % 60).padStart(2, "0")}`;
    if (this.tc.textContent !== tcs) this.tc.textContent = tcs;
    const px = this.tx(b);
    this.ph.style.left = `${px - 2}px`;
    this.phHead.style.left = `${px - 10}px`;

    // ---- rooms
    const ri = roomAt(b);
    const room = ROOM[LIST[ri]];
    this.P.setRoom(LIST[ri]);
    css(this.vp, { background: room.ground });
    css(this.vpDots, { backgroundImage: `radial-gradient(${room.dot.slice(0, 7)}55 2px, transparent 2.6px)` });
    const flip = FLIPS.reduce((a, [at]) => Math.max(a, pulse(b, at, 0.45)), 0);
    const pk = springB(b, 100, 2, 0.7);
    this.P.root.style.transform = `translate(${VP.w / 2 + 120 - 230}px, ${VP.h / 2 + 10 - 481}px) scale(${lerp(0.9 / FILL, 0.62, pk) * (1 + flip * 0.03)}) rotate(${flip * -1.2}deg)`;
    this.P.root.style.transformOrigin = "230px 481px";
    this.P.setTab("today");
    for (const k of ["schedule", "grades", "study", "notes", "assis"]) this.P.views[k].node.style.display = "none";
    this.P.views.today.node.style.display = "";
    const cv = renderCampus(t, { hour: 8 + (ri % 4) * 3, net: 1, camX: Math.sin(t * 0.3) * 2, camZ: 30, w: 776, h: 352, aspect: 776 / 352, next: 101 });
    this.canvas.getContext("2d").drawImage(cv, 0, 0, 776, 352);
    const hist = [[-Infinity, 0], ...FLIPS].filter(([at]) => b >= at);
    const cur = hist[hist.length - 1], prevI = hist.length > 1 ? hist[hist.length - 2][1] : -1;
    this.sws.forEach((w, i) => {
      let k = 0, pr = 0;
      if (i === cur[1]) { k = cur[0] === -Infinity ? 1 : pb(b, cur[0], cur[0] + 0.12); pr = cur[0] === -Infinity ? 0 : pulse(b, cur[0], 0.3); }
      else if (i === prevI) k = 1 - pb(b, cur[0], cur[0] + 0.12);
      w.render(k, pr);
    });
    this.swIsko.render(1);
    this.swOff.render(0);
    this.keys.forEach((k, i) => (k.style.display = b >= FLIPS[i][0] ? "" : "none"));
    this.sfx.forEach((k, i) => (k.style.display = b >= FLIPS[i][0] ? "" : "none"));
    this.layers.forEach((r, i) => (r.style.background = (i === 3 && b >= 101.5) || (i === 1 && b >= 101.2 && b < 101.5) ? "#2c2236" : ""));
    // ---- "Make it yours." as a selected text layer
    // the text layer is edited too: every flip morphs its face and recolours it
    const flipsDone = FLIPS.filter(([at]) => b >= at);
    const nf = flipsDone.length, lastAt = nf ? flipsDone[nf - 1][0] : 0;
    const faceNow = nf % 2, facePrev = nf ? (nf - 1) % 2 : 0;
    const mk = nf ? lerp(facePrev, faceNow, ease.inOutCubic(pb(b, lastAt, lastAt + 0.45))) : 0;
    const ink = nf ? room.gold : "#f7ecec";
    this.make.render(b, { at: 101.4, dur: 1.2, out: 114.6, outDur: 0.4, m: b >= 102.6 ? mk : undefined, ink });
    const selOn = b >= 102.4 && b < 114.6;
    this.sel.style.display = this.selTag.style.display = selOn ? "" : "none";
    const tag = `TEXT · ${faceNow ? "PIXELIFY 700" : "MONTSERRAT 800"} · ${ink.toUpperCase()}`;
    if (this.selTag.textContent !== tag) this.selTag.textContent = tag;
    this.selTag.style.transform = `scale(${1 + pulse(b, lastAt, 0.35) * 0.08})`;

    // ---- cursor: glides switch to switch, clicks on the beat
    const sw = (i) => { const r = this.sws[i].track.getBoundingClientRect(); return [r.left + r.width * 0.5, r.top + r.height * 0.55]; };
    const fl = FLIPS.filter(([at]) => at !== 112);
    let idx = fl.findIndex(([at]) => b < at);
    if (idx < 0) idx = fl.length - 1;
    const [at1, i1] = fl[idx], [at0, i0] = fl[Math.max(0, idx - 1)];
    const mv = idx === 0 ? 1 : pb(b, at0 + 0.15, at1 - 0.12, ease.inOutCubic);
    const [x0, y0] = sw(i0), [x1, y1] = sw(i1);
    const [cxs, cys] = idx === 0 ? [lerp(1300, x1, pb(b, 100.8, 101.8, ease.inOutCubic)), lerp(700, y1, pb(b, 100.8, 101.8, ease.inOutCubic))] : [lerp(x0, x1, mv), lerp(y0, y1, mv)];
    const press = FLIPS.reduce((a, [at]) => Math.max(a, pulse(b, at, 0.25)), 0);
    this.cursor.style.display = b >= 100.8 && b < 114.8 && !(b >= 111.4 && b < 112.6) ? "" : "none";
    this.cursor.style.transform = `translate(${cxs - 3}px, ${cys - 3}px) scale(${(1 - press * 0.2) * s})`;
    this.cursor.style.transformOrigin = "0 0";

    // ---- Isko: in the viewport beside the phone, hops out to flip #11
    const [vx, vy] = toScreen(VP.x + VP.w / 2 + 120 - 260, VP.y + VP.h / 2 + 250);
    const [tx1, ty1] = sw(11);
    const hop = pb(b, 111.2, 111.95, ease.inOutCubic), ret = pb(b, 112.6, 113.4, ease.inOutCubic);
    const x = lerp(lerp(vx, tx1 - 30, hop), vx, ret), y = lerp(lerp(vy, ty1 + 20, hop), vy, ret) - Math.sin(hop * Math.PI) * 220 - Math.sin(ret * Math.PI) * 160;
    this.isko.root.style.display = b >= 100.6 && b < 115.2 ? "" : "none";
    this.isko.pose({ x, y, t, scale: s * (0.9 + 0.1 * pk), squash: pulse(b, 112, 0.4) * 0.8 - Math.sin(hop * Math.PI) * 0.3,
      expr: b >= 111 && b < 113.4 ? (b >= 112 ? "happy" : "focus") : blinkAt(t, 8), gesture: b >= 113.4 && b < 114.5 ? "wave" : b >= 111.6 && b < 112.4 ? "reach" : "idle", gk: 1, look: b < 111 ? 1 : -1 });
    this.bubble.render(b, [[102.2, 1.6, "Ooh, let's redecorate."], [105.1, 1.4, "Sakura? Cute."], [108.1, 1.4, "Matrix. Hacker hours."],
      [110.1, 1.3, "Catppuccin, cozy."], [112.3, 1.6, "My pick: PUP Maroon!"]], x, y - 23 * 4 * s);
    void hash;
  },
};
