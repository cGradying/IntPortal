// Beta Pass IDs (beats 224–end). The Beta Pass slides out big: an ID card
// whose pixel-art photo is whoever is holding it. On every beat-and-a-bit
// the photo glitches (pixel cells + chroma split) to the next student and the
// name and number flip with it: ten different people, ten different IDs.
// The passes fan into a deck, then one is left with an empty photo: "Yours?"
// → Join the beta waitlist, SOON on a split-flap. End card: the icon's live
// portal, "IntPortal", "Step through.", and Isko dives in on the final hit.
import { clamp, css, ease, el, hash, lerp, pb, pulse, springB } from "../lib/core.js";
import { blinkAt, makeIsko } from "../art/isko.js";
import { faceCanvas, PEOPLE } from "../art/faces.js";
import { pixText } from "../ui/pixtype.js";

export const WAITLIST_URL = ""; // set to the real waitlist link before publishing

const SWAP0 = 225, SWAPDT = 0.8; // first face swap, spacing (beats)
const swapAt = (i) => SWAP0 + (i - 1) * SWAPDT; // face i (1..9) arrives
const FAN = 233.2, SOLO = 234.6;
const SW = ["#170509", "#540a1c", "#941c30", "#cca128", "#faebb3"];
const B2 = (x, y) => ((x / 2 + y * y * 0.75) % 1 + 1) % 1;
const bayer = (x, y) => B2(Math.floor(x / 2), Math.floor(y / 2)) * 0.25 + B2(x, y);

function drawIcon(g, t) {
  const O = ["#4a3160", "#34203f", "#5c3f78"];
  g.fillStyle = "#170b1a";
  g.fillRect(0, 0, 20, 24);
  for (let y = 0; y < 24; y++) for (let x = 0; x < 20; x++) {
    if (x < 3 || x > 16 || y < 3 || y > 20) {
      const edge = x % 3 === 2 || y % 3 === 2;
      g.fillStyle = edge ? "#120a15" : O[Math.floor(hash(Math.floor(x / 3), Math.floor(y / 3), 4) * 3)];
      g.fillRect(x, y, 1, 1);
      continue;
    }
    const u = (x - 10) / 7, v = (y - 12) / 9, d = Math.hypot(u * 1.1, v * 0.8);
    const a = Math.atan2(v, u) + t * 0.9 + d * 3.2;
    const val = clamp(0.5 + 0.3 * Math.sin(a * 2 + d * 5 - t * 2.2) + (0.55 - d) * 0.9);
    g.fillStyle = SW[clamp(Math.floor(val * 4 + bayer(x, y) - 0.5), 0, 4)];
    g.fillRect(x, y, 1, 1);
  }
}

/** One Beta Pass ID card. Returns { node, photo (ctx), name, no, stamp }. */
function makePass(parent, i) {
  const d = el("div", "abs notch", parent, `
    <div style="position:absolute;left:0;top:0;right:0;height:64px;background:#7a1128;display:flex;align-items:center;justify-content:space-between;padding:0 30px">
      <div style="font:700 26px var(--pixel);letter-spacing:.16em;color:#f5b227">BETA PASS</div>
      <div style="font:800 28px var(--display);letter-spacing:-.02em;color:#f7ecec">IntPortal</div></div>
    <div style="position:absolute;left:34px;top:94px;width:220px;height:264px;background:#2a1a30;outline:6px solid #1c1517"><canvas data-r="ph" width="20" height="24" class="px" style="width:220px;height:264px;display:block"></canvas></div>
    <div style="position:absolute;left:290px;top:92px;right:30px">
      <div style="font:700 18px var(--pixel);letter-spacing:.14em;color:#766c6f">NAME</div>
      <div data-r="name" style="font:800 66px var(--display);letter-spacing:-.04em;color:#1c1517;line-height:1.05;white-space:nowrap"></div>
      <div style="display:flex;gap:40px;margin-top:14px">
        <div><div style="font:700 18px var(--pixel);letter-spacing:.14em;color:#766c6f">No.</div><div data-r="no" style="font:700 36px var(--pixel);color:#1c1517"></div></div>
        <div><div style="font:700 18px var(--pixel);letter-spacing:.14em;color:#766c6f">CAMPUS</div><div data-r="campus" style="font:700 36px var(--pixel);color:#1c1517">ANY</div></div></div>
      <div data-r="bars" style="height:44px;display:flex;gap:3px;margin-top:22px"></div>
    </div>
    <div data-r="stamp" style="position:absolute;right:26px;bottom:26px;font:700 30px var(--pixel);letter-spacing:.12em;color:#7a1128;border:6px solid #7a1128;padding:4px 14px;transform:rotate(-5deg)">EARLY<br>ACCESS</div>`);
  css(d, { left: "0", top: "0", width: "820px", height: "400px", background: i % 2 ? "#f7ecec" : "#fff6dc", boxShadow: "0 40px 80px -24px rgba(0,0,0,.7)", transformOrigin: "50% 50%" });
  const r = {};
  d.querySelectorAll("[data-r]").forEach((n) => (r[n.dataset.r] = n));
  for (let k = 0; k < 40; k++) {
    const bar = el("i", "", r.bars);
    css(bar, { width: `${hash(k, 2) > 0.6 ? 7 : 3}px`, background: "#1c1517", display: "block", opacity: hash(k, 3) > 0.15 ? 1 : 0 });
  }
  return { node: d, photo: r.ph.getContext("2d"), photoEl: r.ph, name: r.name, no: r.no, stamp: r.stamp };
}

// face sources, drawn once
let FACES = null;
const faceSrc = (i) => (FACES ??= PEOPLE.map((_, k) => faceCanvas(k)))[i];
/** Paint face i into a 20x24 photo ctx at a cell size (1 = crisp). */
function paintFace(g, i, cell = 1) {
  g.imageSmoothingEnabled = false;
  g.clearRect(0, 0, 20, 24);
  if (i < 0) { g.fillStyle = "#2a1a30"; g.fillRect(0, 0, 20, 24); return; }
  if (cell <= 1) { g.drawImage(faceSrc(i), 0, 0); return; }
  const s = document.createElement("canvas");
  s.width = Math.ceil(20 / cell); s.height = Math.ceil(24 / cell);
  const x = s.getContext("2d");
  x.imageSmoothingEnabled = true;
  x.drawImage(faceSrc(i), 0, 0, s.width, s.height);
  g.drawImage(s, 0, 0, s.width * cell, s.height * cell);
}

export default {
  id: "faceid", from: 224, to: 400,
  init(layer) {
    this.bg = el("div", "abs", layer);
    css(this.bg, { inset: "0", background: "radial-gradient(circle at 45% 50%, #2a1024 0%, #140a14 40%, #09070b 75%)" });
    this.floor = el("div", "abs", layer);
    css(this.floor, { left: "-1200px", right: "-1200px", top: "700px", height: "1400px", transformOrigin: "50% 0%", transform: "perspective(900px) rotateX(72deg)",
      backgroundImage: "radial-gradient(rgba(245,178,39,.3) 2px, transparent 2.6px)", backgroundSize: "46px 46px",
      maskImage: "linear-gradient(to bottom, transparent, #000 25%, #000 60%, transparent)", WebkitMaskImage: "linear-gradient(to bottom, transparent, #000 25%, #000 60%, transparent)" });
    // the hero pass whose photo changes per person
    this.hero = makePass(layer, 0);
    this.q = el("div", "abs", this.hero.node, "?");
    css(this.q, { left: "34px", top: "94px", width: "220px", height: "264px", font: "700 200px/264px var(--pixel)", color: "#8663a8", textAlign: "center", border: "6px dashed #8663a8" });
    // the deck: one pass per person
    this.deck = PEOPLE.map((p, i) => {
      const P = makePass(layer, i);
      paintFace(P.photo, i);
      P.name.textContent = p.name;
      P.no.textContent = String(i + 1).padStart(4, "0");
      return P;
    });
    this.tagA = pixText(layer, { text: "Your ID,", size: 120, x: 110, y: 110, ink: "#f7ecec", shadow: "#000" });
    this.tagB = pixText(layer, { text: "your face.", size: 120, x: 110, y: 240, ink: "#f5b227", shadow: "#000" });
    this.yours = pixText(layer, { text: "Yours?", size: 190, x: 1180, y: 150, ink: "#f5b227", shadow: "#000" });
    this.join1 = pixText(layer, { text: "Join the", size: 120, x: 1060, y: 420, ink: "#f7ecec", shadow: "#000" });
    this.join2 = pixText(layer, { text: "beta waitlist.", size: 120, x: 1060, y: 550, ink: "#f5b227", shadow: "#000" });
    this.flapRow = el("div", "abs", layer);
    css(this.flapRow, { left: "1066px", top: "740px", display: "flex", gap: "10px", alignItems: "center" });
    el("div", "", this.flapRow, `<span style="font:700 30px var(--pixel);color:#cdbbd8;letter-spacing:.1em;margin-right:14px">BOARDING</span>`);
    this.flaps = "SOON".split("").map(() => {
      const f = el("div", "", this.flapRow);
      css(f, { width: "72px", height: "92px", background: "#1c1517", color: "#f5b227", font: "700 64px/92px var(--pixel)", textAlign: "center", border: "3px solid #3a2f44" });
      return f;
    });
    this.ctaSub = el("div", "abs", layer, WAITLIST_URL || "Beta opening soon · link in the post");
    css(this.ctaSub, { left: "1068px", top: "870px", font: "600 32px var(--ui)", color: "#cfcfd6", whiteSpace: "nowrap" });
    // end card
    this.iconWrap = el("div", "abs", layer);
    this.icon = document.createElement("canvas");
    this.icon.width = 20; this.icon.height = 24;
    this.icon.className = "px";
    css(this.icon, { width: "300px", height: "360px", display: "block" });
    this.iconWrap.appendChild(this.icon);
    this.word = pixText(layer, { text: "IntPortal", size: 190, x: 760, y: 300, ink: "#f7ecec", shadow: "#000" });
    this.step = pixText(layer, { text: "Step through.", size: 120, x: 766, y: 520, ink: "#f5b227", shadow: "#000" });
    this.line = el("div", "abs", layer, "Your portal, for every campus.");
    css(this.line, { left: "770px", top: "690px", font: "500 40px var(--ui)", color: "#cfcfd6", whiteSpace: "nowrap" });
    this.plat = el("div", "abs", layer, ["iOS", "Mac", "PC"].map((p) => `<span style="padding:8px 18px;border:3px solid #ffffff2a;margin-right:12px">${p}</span>`).join(""));
    css(this.plat, { left: "770px", top: "780px", font: "700 26px var(--pixel)", color: "#cfcfd6", whiteSpace: "nowrap", letterSpacing: ".08em" });
    this.fine = el("div", "abs", layer, "Unofficial student project. Not affiliated with PUP or any university shown. Beta waitlist opening soon.");
    css(this.fine, { left: "0", width: "1920px", top: "1006px", textAlign: "center", font: "500 22px var(--ui)", color: "#8a8a93" });
    this.isko = makeIsko(layer, 7);
    this.last = "";
  },
  render(b, t) {
    const endK = pb(b, 237.6, 238.4, ease.inOutCubic);
    this.floor.style.backgroundPosition = `0px ${b * 50}px`;
    this.floor.style.display = b < 238.4 ? "" : "none";
    // ---- hero pass: slides out 224, photo swaps per person, fans at FAN
    const H = this.hero;
    const heroOn = b >= 224 && b < FAN + 0.1 || (b >= SOLO && b < 238.4);
    H.node.style.display = heroOn ? "" : "none";
    let who = 0;
    for (let i = 1; i < PEOPLE.length; i++) if (b >= swapAt(i)) who = i;
    const solo = b >= SOLO;
    if (heroOn) {
      const inK = springB(b, solo ? SOLO : 224, 1.5, 0.7);
      const x = solo ? lerp(200, 180, 0) : 560, y = solo ? 330 : 380;
      H.node.style.transform = `translate(${x + (1 - clamp(inK, 0, 1)) * (solo ? 0 : -700)}px, ${y + (solo ? (1 - clamp(inK, 0, 1)) * 500 : 0)}px) perspective(1600px) rotateY(${Math.sin(t * 0.8) * 3 + (1 - clamp(inK, 0, 1)) * -30}deg) scale(${(0.4 + 0.6 * clamp(inK, 0, 1.05)) * (1 - endK * 0.7) * (1 + pulse(b, who ? swapAt(who) : 224, 0.4) * 0.03)})`;
      // photo: pixel-cell glitch into each new face (cells 6 → 3 → 1 over 3 frames' worth)
      const since = who ? b - swapAt(who) : b - 224.3;
      const cell = solo ? 1 : since < 0.08 ? 6 : since < 0.16 ? 3 : 1;
      const key = solo ? "solo" : `${who}|${cell}`;
      if (key !== this.last) {
        this.last = key;
        paintFace(H.photo, solo ? -1 : b < 224.3 ? -1 : who, cell);
        const p = PEOPLE[who];
        H.name.textContent = solo ? "You" : p.name;
        H.no.textContent = solo ? "????" : String(who + 1).padStart(4, "0");
      }
      H.photoEl.style.filter = !solo && since < 0.16 ? "drop-shadow(8px 0 0 rgba(0,229,255,.7)) drop-shadow(-8px 0 0 rgba(255,43,214,.7))" : "";
      this.q.style.display = solo ? "" : "none";
      const st = b - 225.5;
      H.stamp.style.opacity = solo || st >= 0 ? 1 : 0;
      if (!solo && st >= 0) {
        const s = st < 0.25 ? 1.9 - 0.98 * ease.outCubic(st / 0.25) : 0.92 + 0.08 * ease.outCubic(clamp((st - 0.25) / 0.35));
        H.stamp.style.transform = `rotate(-5deg) scale(${s})`;
      }
    }
    this.tagA.render(b, { at: 225.2, dur: 0.9, out: FAN - 0.3, outDur: 0.4 });
    this.tagB.render(b, { at: 225.7, dur: 0.9, out: FAN - 0.2, outDur: 0.4, glitchAt: [229] });
    // ---- deck fan: FAN → SOLO, ten IDs, ten people
    this.deck.forEach((P, i) => {
      const on = b >= FAN && b < SOLO + 0.4;
      P.node.style.display = on ? "" : "none";
      if (!on) return;
      const k = springB(b, FAN + i * 0.04, 2.2, 0.62);
      const out = pb(b, SOLO - 0.3, SOLO + 0.4, ease.inCubic);
      const a = (i - 4.5) * 0.16;
      const x = 560 + Math.sin(a) * 1500 * clamp(k, 0, 1.05) * 0.55, y = 380 + (1 - Math.cos(a)) * 900 * clamp(k, 0, 1) * 0.8 - 40 * clamp(k, 0, 1);
      P.node.style.transform = `translate(${x}px, ${y + out * 900}px) rotate(${a * 57 * 0.9 * clamp(k, 0, 1)}deg) scale(${0.58})`;
      P.node.style.zIndex = 20 + i;
    });
    // ---- "Yours?" + CTA
    this.yours.render(b, { at: SOLO + 0.4, dur: 0.8, out: 237.4, outDur: 0.4 });
    this.join1.render(b, { at: 235.2, dur: 0.9, out: 237.5, outDur: 0.5 });
    this.join2.render(b, { at: 235.6, dur: 0.9, out: 237.6, outDur: 0.5, glitchAt: [236.8] });
    const fOn = b >= 235.8 && b < 237.9;
    this.flapRow.style.display = fOn ? "flex" : "none";
    const L = "SOON", ABC = "ABCDEFGHJKLMNOPRSTUVWXYZ";
    this.flaps.forEach((f, i) => {
      const at = 236.25 + i * 0.25;
      const ch = b >= at ? L[i] : ABC[Math.floor(hash(i, Math.floor(b * 10)) * ABC.length)];
      if (f.textContent !== ch) f.textContent = ch;
      f.style.transform = `scaleY(${1 - pulse(b, at, 0.25) * 0.6})`;
    });
    this.ctaSub.style.display = b >= 236.4 && b < 237.9 ? "" : "none";
    // ---- end card
    drawIcon(this.icon.getContext("2d"), t);
    const iconOn = b >= 237.9;
    this.iconWrap.style.display = iconOn ? "" : "none";
    const ik = springB(b, 237.9, 1.8, 0.6);
    css(this.iconWrap, { left: "300px", top: "300px", transform: `scale(${clamp(ik, 0, 1.1) * (1 + pulse(b, 240, 1) * 0.08)})`, transformOrigin: "150px 180px" });
    this.word.render(b, { at: 238.2, dur: 1.2, glitchAt: [242] });
    this.step.render(b, { at: 240, dur: 0.9 });
    const lk = pb(b, 241, 241.6, ease.outExpo);
    this.line.style.display = b >= 241 ? "" : "none";
    this.line.style.transform = `translateY(${(1 - lk) * 30}px)`;
    this.line.style.opacity = lk;
    this.plat.style.display = b >= 241.5 ? "" : "none";
    this.plat.style.opacity = pb(b, 241.5, 242);
    this.fine.style.display = b >= 242 ? "" : "none";
    this.fine.style.opacity = pb(b, 242, 243);
    // ---- Isko: beside the pass, then by the icon; dives in at 243
    const I = this.isko;
    const iOn = b >= 224.6 && b < 243.6;
    I.root.style.display = iOn ? "" : "none";
    if (iOn) {
      const move = pb(b, 237.6, 238.6, ease.inOutCubic);
      const dive = pb(b, 242.8, 243.5, ease.inCubic);
      const inK = springB(b, 224.6, 1.6, 0.6);
      const sol = pb(b, SOLO - 0.4, SOLO + 0.4, ease.inOutCubic);
      const x0 = lerp(1500, 960, sol) + (1 - inK) * 500, y0 = lerp(900, 1000, sol);
      let x = lerp(x0, 560, move), y = lerp(y0, 860, move) - Math.sin(move * Math.PI) * 120;
      x = lerp(x, 450, dive); y = lerp(y, 480, dive) - Math.sin(dive * Math.PI) * 140;
      const e = b >= 240 && b < 242.8 ? "happy" : b >= 242.8 ? "wink" : b >= SOLO && b < SOLO + 1 ? "wow" : blinkAt(t, 14, (b - SWAP0) % SWAPDT < 0.3 && b < FAN ? "happy" : "open");
      I.pose({ x, y, t, scale: 1 - dive * 0.9, squash: -dive * 0.4, expr: e,
        gesture: b < FAN ? "thumbs" : b >= 240 && b < 242.8 ? "wave" : b >= SOLO && b < 236 ? "point" : "idle", gk: 1, look: -1, tilt: dive * -25, opacity: 1 - pb(b, 243.4, 243.6) });
    }
  },
};
