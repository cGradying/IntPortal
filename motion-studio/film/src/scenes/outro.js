// Outro (beats 172–end): beta waitlist. The app icon's portal forms out of
// the flash, a Beta Pass slides out of it like a boarding pass, EARLY ACCESS
// thunks on the downbeat, SOON flips in on a split-flap, and the CTA reads
// "Join the waitlist". Isko waves. Everything folds back into the portal:
// "Step through."
import { clamp, css, ease, el, hash, pb, pulse, springB } from "../lib/core.js";
import { pixelCanvas, sized } from "../art/pixel.js";
import { blinkAt, makeIsko } from "../art/isko.js";

export const WAITLIST_URL = ""; // set to the real waitlist link before publishing

const SW = ["#170509", "#540a1c", "#941c30", "#cca128", "#faebb3"];
const B2 = (x, y) => ((x / 2 + y * y * 0.75) % 1 + 1) % 1;
const bayer = (x, y) => B2(Math.floor(x / 2), Math.floor(y / 2)) * 0.25 + B2(x, y);

/** Draw the app icon (pixel portal) with a live swirl into a 20x24 canvas. */
function drawIcon(g, t) {
  const O = ["#4a3160", "#34203f", "#5c3f78"];
  g.fillStyle = "#170b1a";
  g.fillRect(0, 0, 20, 24);
  for (let y = 0; y < 24; y++) {
    for (let x = 0; x < 20; x++) {
      const frame = x < 3 || x > 16 || y < 3 || y > 20;
      if (frame) {
        const bx = Math.floor(x / 3), by = Math.floor(y / 3);
        const edge = x % 3 === 2 || y % 3 === 2;
        g.fillStyle = edge ? "#120a15" : O[Math.floor(hash(bx, by, 4) * 3)];
        g.fillRect(x, y, 1, 1);
        continue;
      }
      const u = (x - 10) / 7, v = (y - 12) / 9;
      const d = Math.hypot(u * 1.1, v * 0.8);
      const a = Math.atan2(v, u) + t * 0.9 + d * 3.2;
      let val = 0.5 + 0.5 * Math.sin(a * 2 + d * 5 - t * 2.2) * 0.6 + (0.55 - d) * 0.9;
      val = clamp(val);
      const k = clamp(Math.floor(val * 4 + bayer(x, y) - 0.5), 0, 4);
      g.fillStyle = SW[k];
      g.fillRect(x, y, 1, 1);
    }
  }
}

export default {
  id: "outro", from: 171.95, to: 400,
  init(layer) {
    this.bg = el("div", "abs", layer);
    css(this.bg, { inset: "0", background: "radial-gradient(circle at 30% 50%, #22101c 0%, #0a080c 60%)" });
    this.iconWrap = el("div", "abs", layer);
    this.icon = document.createElement("canvas");
    this.icon.width = 20; this.icon.height = 24;
    this.icon.className = "px";
    css(this.icon, { width: "240px", height: "288px", display: "block" });
    this.iconWrap.appendChild(this.icon);
    // beta pass
    this.pass = el("div", "abs notch", layer);
    css(this.pass, { left: "0", top: "0", width: "900px", height: "420px", background: "#f7ecec", color: "#1c1517", display: "flex", overflow: "hidden" });
    this.pass.innerHTML = `
      <div style="flex:1;padding:30px 34px;position:relative;overflow:visible;z-index:2">
        <div style="display:flex;justify-content:space-between;align-items:center"><div style="font:600 18px var(--ui);letter-spacing:.2em;color:#7a1128">BETA PASS</div><div style="font:600 18px var(--ui);letter-spacing:.12em;color:#766c6f">No. 0001</div></div>
        <div style="font:800 76px var(--display);letter-spacing:-.04em;margin:8px 0 18px">IntPortal</div>
        <div style="display:grid;grid-template-columns:1fr 1fr;gap:16px 30px;font:600 15px var(--ui);color:#766c6f;letter-spacing:.1em">
          <div>STUDENT<div style="font:800 28px var(--display);color:#1c1517;letter-spacing:-.01em">You</div></div>
          <div>FROM<div style="font:800 28px var(--display);color:#1c1517;letter-spacing:-.01em">Any campus</div></div>
          <div>GATE<div style="font:800 28px var(--display);color:#1c1517;letter-spacing:-.01em">PUP SIS</div></div>
          <div>BOARDING<div data-r="soon" style="display:flex;gap:6px;margin-top:4px"></div></div>
        </div>
        <div data-r="stamp" style="position:absolute;right:-60px;top:250px;z-index:3;font:700 36px var(--pixel);letter-spacing:.12em;color:#7a1128;border:6px solid #7a1128;padding:6px 16px;background:rgba(247,236,236,.6)">EARLY<br>ACCESS</div>
      </div>
      <div style="width:230px;border-left:3px dashed #cbc3b9;padding:30px 24px;display:flex;flex-direction:column;justify-content:space-between;background:#efe3e3">
        <div data-r="isko" style="height:160px;position:relative;background:#22101c;overflow:hidden" class="notch"></div>
        <div data-r="bars" style="height:70px;display:flex;gap:3px;align-items:stretch"></div>
      </div>`;
    this.r = {};
    this.pass.querySelectorAll("[data-r]").forEach((n) => (this.r[n.dataset.r] = n));
    for (let i = 0; i < 32; i++) {
      const bar = el("i", "", this.r.bars);
      css(bar, { width: `${hash(i, 2) > 0.6 ? 6 : 3}px`, background: "#1c1517", display: "block", opacity: hash(i, 3) > 0.15 ? 1 : 0 });
    }
    this.flaps = "SOON".split("").map(() => {
      const f = el("div", "", this.r.soon);
      css(f, { width: "40px", height: "50px", background: "#1c1517", color: "#f5b227", font: "800 34px var(--display)", textAlign: "center", lineHeight: "50px", borderRadius: "4px", position: "relative", overflow: "hidden" });
      return f;
    });
    const photo = makeIsko(this.r.isko, 4);
    photo.pose({ x: 91, y: 214, scale: 1, face: 1, t: 0, expr: "happy" });
    // CTA
    this.cta = el("div", "abs notch display", layer, "Join the waitlist");
    css(this.cta, { padding: "26px 44px", fontSize: "48px", background: "#f5b227", color: "#1b1406", whiteSpace: "nowrap" });
    this.ctaSub = el("div", "abs", layer, WAITLIST_URL || "Beta opening soon · link in the post");
    css(this.ctaSub, { font: "600 28px var(--ui)", color: "#cfcfd6", whiteSpace: "nowrap" });
    this.plat = el("div", "abs", layer, ["iOS", "Android", "macOS", "Windows", "Web"].map((p) => `<span style="padding:8px 16px;border:2px solid #ffffff2a;margin-right:10px">${p}</span>`).join(""));
    css(this.plat, { font: "700 24px var(--display)", color: "#cfcfd6", whiteSpace: "nowrap" });
    this.isko = makeIsko(layer, 7);
    // end card
    this.word = el("div", "abs display", layer, `<span style="color:#f5b227">Int</span>Portal`);
    css(this.word, { fontSize: "150px", whiteSpace: "nowrap" });
    this.step = el("div", "abs mask display", layer, "<span>Step through.</span>");
    css(this.step, { fontSize: "92px", color: "#f5b227", whiteSpace: "nowrap" });
    this.line = el("div", "abs", layer, "Your portal, for every campus.");
    css(this.line, { font: "500 34px var(--ui)", color: "#cfcfd6", whiteSpace: "nowrap" });
    this.fine = el("div", "abs", layer, "Unofficial student project. Not affiliated with PUP or any university shown. Beta waitlist opening soon.");
    css(this.fine, { left: "0", width: "1920px", top: "1006px", textAlign: "center", font: "500 20px var(--ui)", color: "#8a8a93" });
  },
  render(b, t) {
    drawIcon(this.icon.getContext("2d"), t);
    const fold = pb(b, 186, 187.8, ease.inOutCubic);
    const endK = pb(b, 187.8, 188.6, ease.outExpo);
    // icon: centre-left, pulses on the downbeats; moves for the end card
    const ik = springB(b, 172, 1.8, 0.6);
    const ix = 250 + (1 - fold) * 0, iy = 396;
    const ex = 250 + fold * 150, ey = iy - fold * 10;
    // arrives huge (the swirl you just flew through) and collapses into the icon
    const col = springB(b, 171.95, 1.3, 0.8);
    const iscale = (3.6 - 2.6 * col) * (1 + pulse(b, 188, 1) * 0.1);
    const cxp = 840 + (ix - 840) * col, cyp = 396 + (iy - 396) * col;
    css(this.iconWrap, { left: `${b < 186 ? cxp : ex}px`, top: `${b < 186 ? cyp : ey}px`, transform: `scale(${iscale})`, transformOrigin: "120px 144px" });
    this.bg.style.background = `radial-gradient(circle at ${18 + 12 * col}% 50%, #3a1424 0%, #1a0b14 35%, #0a080c 70%)`;
    // pass slides out of the portal (173.5 → 175), stamp thunk at 176
    const pk = springB(b, 173.3, 1.4, 0.72);
    const passX = 560 + (1 - pk) * -520, passY = 330;
    const passOn = b >= 173.3 && fold < 1;
    this.pass.style.display = passOn ? "flex" : "none";
    this.pass.style.transform = `translate(${passX}px, ${passY - fold * 40}px) perspective(1600px) rotateY(${(1 - pk) * -40 + Math.sin(t * 0.8) * 2}deg) scale(${(0.3 + 0.7 * clamp(pk, 0, 1.05)) * (1 - fold)})`;
    this.pass.style.transformOrigin = "0% 50%";
    const st = b - 176;
    this.r.stamp.style.opacity = st >= 0 ? 1 : 0;
    if (st >= 0) {
      const s = st < 0.25 ? 1.9 - 0.98 * ease.outCubic(st / 0.25) : 0.92 + 0.08 * ease.outCubic(clamp((st - 0.25) / 0.35));
      this.r.stamp.style.transform = `rotate(-4deg) scale(${s})`;
      this.r.stamp.style.filter = `blur(${clamp(1 - st / 0.25) * 3}px)`;
    }
    // split-flap SOON: each letter settles on its beat 178..181
    const L = "SOON", ABC = "ABCDEFGHJKLMNOPRSTUVWXYZ";
    this.flaps.forEach((f, i) => {
      const at = 178 + i * 0.5;
      const ch = b >= at ? L[i] : b >= 176.5 ? ABC[Math.floor(hash(i, Math.floor(b * 8)) * ABC.length)] : "";
      if (f.textContent !== ch) f.textContent = ch;
      f.style.transform = `scaleY(${1 - pulse(b, at, 0.25) * 0.6})`;
    });
    // CTA from 179
    const ck = springB(b, 179, 1.8, 0.6);
    const ctaOn = b >= 179 && fold < 1;
    this.cta.style.display = this.ctaSub.style.display = ctaOn ? "" : "none";
    this.cta.style.transform = `translate(${560}px, ${800 + (1 - clamp(ck, 0, 1)) * 120}px) scale(${1 + pulse(b, 180, 0.6) * 0.04 - fold * 0.5})`;
    this.ctaSub.style.transform = `translate(${1170}px, ${840 + (1 - clamp(springB(b, 179.5, 1.8, 0.7), 0, 1)) * 80}px)`;
    this.ctaSub.style.opacity = 1 - fold;
    // platforms row
    const pr = pb(b, 182, 182.6, ease.outExpo);
    this.plat.style.display = b >= 182 && fold < 1 ? "" : "none";
    this.plat.style.transform = `translate(${560 + (1 - pr) * 60}px, ${230}px)`;
    this.plat.style.opacity = pr * (1 - fold);
    // Isko walks in and waves by the pass, 181 → 186
    const iOn = b >= 180.5 && b < 187;
    this.isko.root.style.display = iOn ? "" : "none";
    if (iOn) {
      const w = pb(b, 180.5, 182, ease.outCubic);
      this.isko.pose({ x: 2000 - 290 * w, y: 780, scale: 1, face: -1, t, walk: b < 182 ? (b - 180.5) * Math.PI * 4 : null,
        wave: pb(b, 182.4, 182.8) * (1 - pb(b, 185.5, 186)), wavePhase: (b - 182) * Math.PI * 2.2, expr: b > 182.5 ? "happy" : blinkAt(t, 1),
        squash: pulse(b, 182, 0.5) * 0.6, opacity: 1 - fold });
    }
    // end card
    const endOn = b >= 186.4;
    this.word.style.display = this.step.style.display = this.line.style.display = endOn ? "" : "none";
    this.fine.style.display = b >= 188 ? "" : "none";
    if (endOn) {
      const wk = pb(b, 186.4, 187.2, ease.outExpo);
      this.word.style.transform = `translate(${760 + (1 - wk) * 80}px, ${330}px)`;
      this.word.style.opacity = wk;
      this.step.style.transform = `translate(${766}px, ${500}px)`;
      this.step.firstChild.style.transform = `translateY(${(1 - pb(b, 186, 186.5, ease.outExpo)) * 105}%)`;
      this.line.style.transform = `translate(${768}px, ${622}px)`;
      this.line.style.opacity = endK;
      this.fine.style.opacity = pb(b, 188, 189);
    }
  },
};
