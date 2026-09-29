// Rooms (beats 68–84): every beat the whole app — and the world around the
// phone — changes room. 15 rooms in 15 beats, then home to Night.
import { clamp, css, ease, el, pb, pulse, springB } from "../lib/core.js";
import { renderCampus } from "../art/campus.js";
import { makePhone } from "../ui/phone.js";
import { ROOM } from "../ui/rooms.js";

const ORDER = ["Night", "Astra Moon", "Sakura", "Tokyo Night", "Maroon Night", "Matrix", "Day", "Dracula", "Gruvbox", "Nord",
  "Solarized Light", "Catppuccin", "PUP Maroon", "One Dark", "Ivory", "Night"];

export default {
  id: "rooms", from: 68, to: 84,
  init(layer) {
    this.bg = el("div", "abs", layer);
    css(this.bg, { inset: "0" });
    this.dots = el("div", "abs", layer);
    css(this.dots, { inset: "-40px", backgroundSize: "34px 34px" });
    this.glow = el("div", "abs", layer);
    css(this.glow, { width: "1500px", height: "1500px", left: "560px", top: "-210px", borderRadius: "50%" });
    this.P = makePhone(layer);
    this.canvas = el("canvas", "", this.P.views.today.r.campus);
    this.canvas.width = 776; this.canvas.height = 352;
    css(this.canvas, { width: "388px", height: "176px", display: "block" });
    this.make = el("div", "abs mask display", layer, "<span>Make it yours.</span>");
    css(this.make, { left: "110px", top: "300px", fontSize: "76px" });
    this.names = ORDER.map((n) => {
      const m = el("div", "abs mask display", layer, `<span>${n}</span>`);
      css(m, { left: "106px", top: "400px", fontSize: "150px", whiteSpace: "nowrap" });
      return m;
    });
    this.count = el("div", "abs", layer);
    css(this.count, { left: "112px", top: "600px", font: "600 30px var(--ui)", letterSpacing: "0.12em" });
    this.sw = [0, 1, 2].map((i) => {
      const s = el("div", "abs notch", layer);
      css(s, { left: `${112 + i * 70}px`, top: "660px", width: "56px", height: "56px" });
      return s;
    });
  },
  render(b, t) {
    const i = clamp(Math.floor(b - 68), 0, ORDER.length - 1);
    const R = ROOM[ORDER[i]];
    this.P.setRoom(R);
    const hit = pulse(b, 68 + i, 0.5);
    css(this.bg, { background: R.dark ? `linear-gradient(160deg, ${R.ground2}, ${R.ground})` : `linear-gradient(160deg, ${R.card}, ${R.ground})` });
    css(this.dots, { backgroundImage: `radial-gradient(${R.gold}33 2px, transparent 2.6px)`, transform: `translateY(${(b - 68) * -12}px)` });
    this.glow.style.background = `radial-gradient(circle, ${R.gold}55 0%, ${R.gold}18 35%, transparent 62%)`;
    // phone: arrives from the spin at centre, settles right; kicks on each beat
    const settle = springB(b, 68, 1.2, 0.75);
    const x = 960 + (1300 - 960) * settle, y = 560;
    const kick = (i % 2 ? 1 : -1) * 9 * springB(b, 68 + i, 2.2, 0.35) * (1 - pb(b, 83, 84));
    this.P.root.style.transformOrigin = "230px 480px";
    this.P.root.style.transform = `perspective(2400px) translate3d(${x - 230}px, ${y - 480}px, 0) rotateY(${-12 + kick}deg) rotateX(4deg) scale(${1.02 + hit * 0.03})`;
    const cv = renderCampus(t, { hour: 7.4, net: 1, w: 776, h: 352, aspect: 776 / 352, next: 101 });
    this.canvas.getContext("2d").drawImage(cv, 0, 0);
    this.P.setTab("today");
    for (const k of ["schedule", "grades", "study", "assis"]) this.P.views[k].node.style.display = "none";
    this.P.views.today.node.style.display = "";
    this.P.views.today.r.scroll.style.transform = "translateY(0px)";
    // type
    const mk = pb(b, 69.8, 70.3, ease.outExpo);
    this.make.firstChild.style.transform = `translateY(${(1 - mk) * 105}%)`;
    this.make.style.color = R.dark ? "#f7ecec" : R.ink;
    this.names.forEach((m, k) => {
      const on = k === i || k === i - 1;
      m.style.display = on ? "" : "none";
      if (!on) return;
      const p = pb(b, 68 + k, 68 + k + 0.35, ease.outExpo);
      m.firstChild.style.transform = k === i ? `translateY(${(1 - p) * 105}%)` : `translateY(${-pb(b, 68 + i, 68 + i + 0.3, ease.outExpo) * 105}%)`;
      m.style.color = R.gold;
    });
    this.count.textContent = `${String(Math.min(i + 1, 15)).padStart(2, "0")} / 15 rooms`;
    this.count.style.color = R.dark ? "#cfcfd6" : R.ink2;
    [R.ground, R.card, R.gold].forEach((c, k) => {
      this.sw[k].style.background = c;
      this.sw[k].style.transform = `translateY(${-pulse(b, 68 + i + k * 0.08, 0.35) * 14}px)`;
      this.sw[k].style.outline = `2px solid ${R.dark ? "rgba(255,255,255,.12)" : "rgba(0,0,0,.12)"}`;
    });
  },
};
