// The drop (beats 148–164): the music cuts out and so does the signal. A
// giant pixel Wi-Fi glyph drains arc by arc (its pixels fall away), the
// phone sits small in the dark with a heartbeat, and Isko flips the
// Airplane-mode switch: the only loud sound. He covers his eyes, peeks, and
// the light of every pixel on screen gathers into the phone for the bomb.
// Half a beat of black before 164.
import { clamp, css, ease, el, hash, lerp, pb, pulse, springB } from "../lib/core.js";
import { blinkAt, makeIsko } from "../art/isko.js";
import { makePhone } from "../ui/phone.js";
import { pixText } from "../ui/pixtype.js";
import { pixSwitch } from "../ui/switch.js";

const C = 26; // wifi pixel size (px)
const GW = 25, GH = 17; // glyph grid

function wifiCells() {
  // concentric arcs around (12, 16): dot r<1.6, arcs at r 5, 9.5, 14
  const cells = [];
  const cx = 12, cy = 15.5;
  for (let j = 0; j < GH; j++) for (let i = 0; i < GW; i++) {
    const dx = i - cx, dy = j - cy, r = Math.hypot(dx, dy);
    const ang = Math.atan2(-dy, dx);
    if (ang < Math.PI * 0.22 || ang > Math.PI * 0.78) { if (r >= 1.6) continue; }
    let arc = -1;
    if (r < 1.9) arc = 0;
    else if (r > 4.2 && r < 6.2) arc = 1;
    else if (r > 8.4 && r < 10.4) arc = 2;
    else if (r > 12.6 && r < 14.6) arc = 3;
    if (arc >= 0) cells.push({ i, j, arc, r1: hash(i, j, 1), r2: hash(i, j, 2) });
  }
  return cells;
}

export default {
  id: "drop", from: 148, to: 164,
  init(layer) {
    css(layer, { background: "#050407" });
    this.glyph = el("div", "abs", layer);
    css(this.glyph, { left: `${960 - (GW * C) / 2}px`, top: "70px", width: `${GW * C}px`, height: `${GH * C}px` });
    this.ghost = wifiCells().map((c) => {
      const d = el("div", "abs", this.glyph);
      css(d, { left: `${c.i * C}px`, top: `${c.j * C}px`, width: `${C - 3}px`, height: `${C - 3}px`, background: "#2a2330" });
      return d;
    });
    this.cells = wifiCells().map((c) => {
      const d = el("div", "abs", this.glyph);
      css(d, { left: `${c.i * C}px`, top: `${c.j * C}px`, width: `${C - 3}px`, height: `${C - 3}px` });
      return { ...c, d };
    });
    this.slash = el("div", "abs", this.glyph);
    css(this.slash, { left: "40px", top: `${GH * C / 2 - 12}px`, width: `${GW * C - 80}px`, height: "24px", background: "#e5484d", transform: "rotate(35deg)" });
    this.P = makePhone(layer);
    this.P.setRoom("Night");
    this.P.setTab("today");
    for (const k of ["schedule", "grades", "study", "notes", "assis"]) this.P.views[k].node.style.display = "none";
    this.P.views.today.r.campus.style.background = "#0e1030";
    this.sw = pixSwitch(layer, { label: "AIRPLANE MODE", s: 2.2, x: 0, y: 0, labelSize: 26, on: "#f5b227" });
    this.isko = makeIsko(layer, 7);
    this.gather = Array.from({ length: 90 }, (_, i) => {
      const d = el("div", "abs", layer);
      css(d, { width: "12px", height: "12px", background: i % 3 ? "#f5b227" : "#fff1c4" });
      return { d, a: hash(i, 3) * Math.PI * 2, r: 700 + hash(i, 4) * 500, s: hash(i, 5) };
    });
    this.off = pixText(layer, { text: "Offline.", size: 120, font: "pixel", x: 960, y: 940, anchor: "c", ink: "#f7ecec" });
    this.black = el("div", "abs", layer);
    css(this.black, { inset: "0", background: "#000" });
  },
  render(b, t) {
    const heart = Math.max(...[148, 150, 152, 154, 156, 158, 160].map((a) => pulse(b, a, 0.5)));
    // wifi glyph: arcs drain top-down on 152, 153, 154, 155
    const drainAt = [155, 154, 153, 152];
    const dead = b >= 155.4;
    this.cells.forEach((c) => {
      const at = drainAt[c.arc] + c.r1 * 0.35;
      const k = pb(b, at, at + 0.9, ease.inQuad);
      const col = b < drainAt[c.arc] ? "#f5b227" : "#6a5f73";
      c.d.style.display = k >= 1 ? "none" : "";
      c.d.style.background = col;
      c.d.style.transform = `translate(${(c.r2 - 0.5) * 60 * k}px, ${k * k * 700}px) rotate(${(c.r2 - 0.5) * 200 * k}deg)`;
    });
    this.glyph.style.transform = `scale(${1 + heart * 0.015})`;
    this.glyph.style.opacity = b < 148.3 ? pb(b, 148, 148.3) : 1;
    this.slash.style.display = dead && b < 158 ? "" : "none";
    this.slash.style.transform = `rotate(35deg) scaleX(${pb(b, 155.4, 155.7, ease.outExpo)})`;
    // phone, small and dim, heartbeat; brightens as the light gathers
    const gatherK = pb(b, 158, 163.4, ease.inCubic);
    const ps = 0.62 + heart * 0.012 + gatherK * 0.18;
    this.P.root.style.transformOrigin = "230px 481px";
    this.P.root.style.transform = `translate(${960 - 230}px, ${640 - 481}px) scale(${ps})`;
    this.P.root.style.filter = `brightness(${0.45 + gatherK * 1.2 + heart * 0.08})`;
    this.P.setAirplane(b >= 156);
    const isl = b < 156 ? "Wi-Fi · <b>weak</b>" : "✈ <b>Airplane mode</b>";
    if (this.P.islandT.innerHTML !== isl) this.P.islandT.innerHTML = isl;
    // the switch: Isko flips it on 156
    const swIn = springB(b, 154.6, 2, 0.7);
    this.sw.root.style.display = b >= 154.5 && b < 159 ? "" : "none";
    this.sw.root.style.transform = `translate(${1260}px, ${760 + (1 - swIn) * 300}px)`;
    this.sw.render(pb(b, 156, 156.1), pulse(b, 156, 0.3));
    this.off.render(b, { at: 156.5, dur: 1, out: 159.5, outDur: 0.5 });
    // Isko
    const I = this.isko;
    const iIn = springB(b, 153.5, 1.4, 0.7);
    const toSw = pb(b, 155.2, 155.9, ease.inOutCubic), back = pb(b, 156.6, 157.3, ease.inOutCubic);
    const x = lerp(lerp(700 - (1 - iIn) * 500, 1180, toSw), 700, back);
    const y = lerp(lerp(860, 870, toSw), 860, back) - Math.sin(toSw * Math.PI) * 140 - Math.sin(back * Math.PI) * 100;
    I.root.style.display = b >= 153.4 && b < 163.5 ? "" : "none";
    const cover = b >= 157.4 && b < 160;
    I.pose({ x, y, t, scale: 1, squash: pulse(b, 156, 0.4) * 0.7, expr: cover ? "blink" : b >= 160 && b < 161 ? "wink" : b >= 161 ? "wow" : b >= 155 && b < 156.5 ? "focus" : blinkAt(t, 9),
      gesture: cover ? "cover" : b >= 155.6 && b < 156.3 ? "point" : b >= 161 ? "reach" : "idle", gk: 1, look: b < 157 ? 1 : 0, swirlSpeed: 1 + gatherK * 6 });
    // the light gathers into the phone
    this.gather.forEach((g) => {
      const k = clamp((gatherK - g.s * 0.35) / 0.65);
      const on = k > 0 && k < 1;
      g.d.style.display = on ? "" : "none";
      if (!on) return;
      const r = g.r * (1 - ease.inCubic(k));
      g.d.style.transform = `translate(${960 + Math.cos(g.a + k * 1.5) * r - 6}px, ${640 + Math.sin(g.a + k * 1.5) * r * 0.7 - 6}px)`;
    });
    this.black.style.display = b >= 163.5 ? "" : "none";
    void heart;
  },
};
