// The campus network (beats 200–224). Out of the flash: the hub ring, PUP SIS
// lit and live. Mabini flickers on for one beat ("PUP online · soon"). Then
// the ring turns two frames a beat and the major universities ignite, each
// in its own colour, tagged "Not connected yet". Crane up: the portals fly to
// where they are on a dotted Philippines, and the network keeps growing past
// the majors, school by school outward from Manila, to 100+ universities
// and colleges. A vision, labelled as one.
import * as THREE from "three";
import { clamp, css, ease, el, hash, lerp, pb, pulse, springB } from "../lib/core.js";
import { drawBloom } from "../art/gl.js";
import { makePortal, setSwirl } from "../art/portal.js";
import { mapDots, toWorld } from "../art/phmap.js";
import { blinkAt, makeIsko } from "../art/isko.js";
import { MAJORS, PUP, SCHOOLS } from "../data/schools.js";
import { pixText } from "../ui/pixtype.js";
import { swirlPhase } from "./magnet.js";

const RING = [PUP, { id: "MABINI", name: "Mabini", sub: "PUP online · soon", ll: [121.01, 14.6], hue: 0.47 }, ...MAJORS];
const N = RING.length;
const R = 15;
const STEP = (Math.PI * 2) / N;
const frontAt = (i) => (i === 0 ? 0 : i === 1 ? 200.8 : 202 + (i - 2) * 0.5);
const litAt = (i) => (i === 0 ? 0 : i === 1 ? 201 : frontAt(i) + 0.15);
const MANILA = [121.0, 14.6];
const GROW0 = 219.8, GROW1 = 221.8;
const IN0 = 209.3, IN1 = 210.8, OUT0 = 219.4, OUT1 = 221.6; // push into the portal, crane out to the map
const PAGE = 32, DEAL0 = 212, DEALDT = 1.55;

function ramp(h) {
  const c = (s, l, dh = 0) => "#" + new THREE.Color().setHSL((h + dh + 1) % 1, s, l).getHexString();
  return [c(0.6, 0.05), c(0.75, 0.2), c(0.75, 0.38), c(0.85, 0.58, 0.04), c(0.9, 0.86, 0.07)];
}

export default {
  id: "hub", from: 200, to: 224,
  init(layer) {
    const s = (this.scene = new THREE.Scene());
    s.background = new THREE.Color(0x07060a);
    s.fog = new THREE.Fog(0x07060a, 34, 90);
    s.add(new THREE.HemisphereLight(0x8a70b0, 0x100808, 0.8));
    const key = new THREE.DirectionalLight(0xffe2b0, 0.6);
    key.position.set(-10, 20, 12);
    s.add(key);
    this.cam = new THREE.PerspectiveCamera(40, 1920 / 1080, 0.1, 300);
    this.portals = RING.map((u, i) => {
      const P = makePortal({ ramp: i === 0 ? undefined : ramp(u.hue), seed: 11 + i, w: 5, h: 7 });
      s.add(P.group);
      return P;
    });
    // map dots
    const dots = mapDots(0.16);
    this.dots = new THREE.InstancedMesh(new THREE.BoxGeometry(0.11, 0.05, 0.11), new THREE.MeshBasicMaterial({ color: 0x6a5a7a, transparent: true }), dots.length);
    const o = new THREE.Object3D();
    dots.forEach(([x, z], i) => { o.position.set(x, 0, z); o.updateMatrix(); this.dots.setMatrixAt(i, o.matrix); });
    this.mapGroup = new THREE.Group();
    this.mapGroup.add(this.dots);
    s.add(this.mapGroup);
    // every other school: a small cube, blooming outward from Manila
    const dist = (ll) => Math.hypot(ll[0] - MANILA[0], ll[1] - MANILA[1]);
    const dmax = Math.max(...SCHOOLS.map((q) => dist(q.ll)));
    void dmax;
    this.schools = SCHOOLS.map((q, i) => ({ ...q, d: dist(q.ll) + hash(i, 5) * 0.4, w: toWorld(...q.ll) }))
      .sort((a, c) => a.d - c.d)
      .map((q, r, all) => ({ ...q, at: GROW0 + 0.3 + (r / all.length) * (GROW1 - GROW0 - 0.8) }));
    this.sch = new THREE.InstancedMesh(new THREE.BoxGeometry(0.15, 0.15, 0.15), new THREE.MeshBasicMaterial({ color: 0xffffff, toneMapped: false }), this.schools.length);
    this.schools.forEach((q, i) => this.sch.setColorAt(i, new THREE.Color(q.pub ? 0xf5b227 : 0xc6a4f0)));
    this.sch.frustumCulled = false;
    this.mapGroup.add(this.sch);
    // web: a line from the nearest lit major (or PUP) to each school
    const pos = new Float32Array(this.schools.length * 6);
    const hubs = [PUP, ...MAJORS].map((m) => toWorld(...m.ll));
    this.schools.forEach((q, i) => {
      let best = hubs[0], bd = 1e9;
      for (const h of hubs) { const d = Math.hypot(h[0] - q.w[0], h[1] - q.w[1]); if (d < bd && d > 0.05) { bd = d; best = h; } }
      pos.set([best[0], 0.25, best[1], q.w[0], 0.1, q.w[1]], i * 6);
    });
    const lg = new THREE.BufferGeometry();
    lg.setAttribute("position", new THREE.BufferAttribute(pos, 3));
    this.web = new THREE.LineSegments(lg, new THREE.LineBasicMaterial({ color: 0x8663a8, transparent: true, opacity: 0.6, toneMapped: false }));
    this.web.frustumCulled = false;
    this.mapGroup.add(this.web);
    // arcs PUP → each major
    this.arcs = [];
    const pup = toWorld(...PUP.ll);
    MAJORS.forEach((u, i) => {
      const col = new THREE.Color().setHSL(u.hue, 0.85, 0.62);
      const [x, z] = toWorld(...u.ll);
      const a = new THREE.Vector3(pup[0], 0.3, pup[1]), c = new THREE.Vector3(x, 0.3, z);
      const mid = a.clone().lerp(c, 0.5);
      mid.y = 0.8 + a.distanceTo(c) * 0.4;
      const curve = new THREE.QuadraticBezierCurve3(a, mid, c);
      const g = new THREE.TubeGeometry(curve, 48, 0.035, 5, false);
      const mat = new THREE.MeshBasicMaterial({ color: col.clone().lerp(new THREE.Color(0xf5b227), 0.4), toneMapped: false, transparent: true });
      const tube = new THREE.Mesh(g, mat);
      this.mapGroup.add(tube);
      const pulseM = new THREE.Mesh(new THREE.BoxGeometry(0.2, 0.2, 0.2), new THREE.MeshBasicMaterial({ color: 0xfff1c4, toneMapped: false }));
      this.mapGroup.add(pulseM);
      this.arcs.push({ mat, curve, pulseM, i, g });
    });
    // DOM
    this.tagName = el("div", "abs", layer);
    css(this.tagName, { left: "0", top: "0", font: "800 104px var(--display)", letterSpacing: "-0.035em", whiteSpace: "nowrap", textAlign: "center", width: "1400px", marginLeft: "-700px" });
    this.tagSub = el("div", "abs", layer);
    css(this.tagSub, { left: "0", top: "0", font: "600 32px var(--ui)", color: "#cfcfd6", width: "1400px", marginLeft: "-700px", textAlign: "center" });
    this.labels = [PUP, ...MAJORS].map((u, i) => {
      const l = el("div", "abs", layer, i === 0 ? "PUP" : u.name);
      css(l, { font: `700 ${i === 0 ? 30 : 22}px var(--pixel)`, color: i === 0 ? "#f5b227" : "#fff", whiteSpace: "nowrap", textShadow: "0 2px 0 #000, 2px 0 0 #000" });
      return l;
    });
    this.head1 = pixText(layer, { text: "Every campus\nhas a portal.", size: 110, x: 100, y: 70, lh: 1.02, ink: "#f7ecec", shadow: "#000" });
    this.head2 = pixText(layer, { text: "Someday,\nall connected.", size: 84, x: 1830, y: 70, anchor: "r", lh: 1.02, ink: "#f7ecec", shadow: "#000" });
    this.count = el("div", "abs", layer);
    css(this.count, { left: "104px", top: "60px", font: "700 200px/1 var(--pixel)", color: "#f5b227", textShadow: "8px 8px 0 #2a0a14" });
    this.countLab = pixText(layer, { text: "universities and colleges", size: 56, x: 112, y: 262, lh: 1.05, ink: "#f7ecec", shadow: "#000" });
    this.note = el("div", "abs", layer, "Future vision · not connected yet · names only");
    css(this.note, { left: "108px", top: "990px", font: "600 28px var(--ui)", color: "#a9a9b1" });
    // pages: every school as a card, out of the portal as one stack, dealt page by page
    this.dim = el("div", "abs", layer);
    css(this.dim, { inset: "0", background: "radial-gradient(circle at 50% 60%, rgba(8,6,12,.55), rgba(8,6,12,.92) 70%)" });
    this.deck = el("div", "abs p3d", layer);
    css(this.deck, { left: "0", top: "0", width: "1920px", height: "1080px", perspective: "1800px" });
    const region = (ll) => (ll[1] >= 12.3 || ll[0] < 119.9 ? "LUZON" : ll[1] >= 8.8 && ll[0] < 126 ? "VISAYAS" : "MINDANAO");
    const all = [{ name: "PUP · PUP SIS", ll: PUP.ll, pub: true, live: true }, { name: "PUP Mabini", ll: PUP.ll, pub: true, soon: true },
      ...MAJORS.map((m) => ({ name: m.sub.split(" · ")[0], ll: m.ll, pub: !["UST", "DLSU", "ADMU", "FEU", "MAPUA", "SLU", "USC"].includes(m.id), major: true, hue: m.hue })),
      ...SCHOOLS];
    this.cards = all.map((q, i) => {
      const hue = q.hue ?? hash(i, 7);
      const col = q.live ? "#f5b227" : q.soon ? "#6fd6c0" : "#" + new THREE.Color().setHSL(hue, 0.7, 0.62).getHexString();
      const d = el("div", "abs", this.deck, `<div style="font:700 20px/1.12 var(--ui);color:#f7ecec;height:46px;overflow:hidden">${q.name}</div>
        <div style="display:flex;gap:8px;margin-top:8px;font:700 13px var(--pixel);letter-spacing:.08em"><span style="color:${col}">${q.live ? "LIVE" : q.soon ? "SOON" : region(q.ll)}</span><span style="color:#8a7a99">${q.pub ? "PUBLIC" : "PRIVATE"}</span></div>`);
      css(d, { left: "0", top: "0", width: "196px", height: "108px", padding: "12px 14px", background: q.major || q.live ? "#2a1f36" : "#1f1828", borderLeft: `6px solid ${col}`, boxShadow: "0 18px 30px -12px rgba(0,0,0,.7)", backfaceVisibility: "hidden" });
      return { d, i, p: Math.floor(i / PAGE), s: i % PAGE };
    });
    css(this.dim, { zIndex: 1 }); css(this.deck, { zIndex: 2 });
    for (const n of [this.count, this.countLab.node, this.head1.node, this.head2.node, this.note, ...this.labels]) n.style.zIndex = 5;
    this.pageTag = el("div", "abs", layer);
    css(this.pageTag, { zIndex: 5, left: "1560px", top: "292px", font: "700 26px var(--pixel)", color: "#cdbbd8", letterSpacing: ".1em" });
    this.isko = makeIsko(layer, 4);
    this.v = new THREE.Vector3();
  },
  project(p) {
    this.v.copy(p).project(this.cam);
    return [(this.v.x + 1) * 960, (1 - this.v.y) * 540, this.v.z];
  },
  render(b, t) {
    let rot = 0;
    for (let i = 1; i < N; i++) rot += springB(b, frontAt(i), i === 1 ? 3.2 : 4.6, 0.85);
    const toMap = pb(b, OUT0, OUT1, ease.inOutCubic);
    const spinUp = 0;
    const mapPos = (u) => { const [mx, mz] = toWorld(...u.ll); return new THREE.Vector3(mx, 0.1, mz); };
    this.portals.forEach((P, i) => {
      const a = (i - rot - spinUp * 3) * STEP;
      const ringPos = new THREE.Vector3(Math.sin(a) * R, 0, Math.cos(a) * R - R);
      const mp = mapPos(RING[i]);
      if (i === 1) mp.x += 0.4;
      P.group.position.lerpVectors(ringPos, mp, toMap);
      P.group.rotation.y = a * (1 - toMap);
      P.group.scale.setScalar(lerp(0.9, i < 2 ? 0.16 : 0.1, toMap));
      P.group.visible = !(i === 1 && toMap > 0.5);
      const la = litAt(i);
      let lit = i === 0 ? 1 : b >= la ? pb(b, la, la + 0.3, ease.outCubic) : 0;
      if (i === 1) lit *= b < la + 0.8 ? (hash(Math.floor(b * 16), 3) > 0.35 ? 1 : 0.25) : 0.55;
      setSwirl(P.mat, { phase: swirlPhase(b) + i * 1.7, lit, cells: 30, flash: 0 });
      P.swirl.visible = lit > 0.02;
      P.light.intensity = lit * (14 + pulse(b, la, 1) * 50) * (1 - toMap * 0.8);
      P.light.distance = 12;
    });
    // map
    const mapIn = pb(b, OUT0 + 0.4, OUT1, ease.outCubic);
    this.mapGroup.visible = mapIn > 0;
    this.dots.material.opacity = mapIn * 0.9;
    const o = new THREE.Object3D();
    let lit = 0;
    this.schools.forEach((q, i) => {
      const k = springB(b, q.at, 2.6, 0.5);
      if (b >= q.at) lit++;
      o.position.set(q.w[0], 0.12, q.w[1]);
      o.scale.setScalar(b >= q.at ? clamp(k, 0, 1.4) + 0.001 : 0.0001);
      o.updateMatrix();
      this.sch.setMatrixAt(i, o.matrix);
    });
    this.sch.instanceMatrix.needsUpdate = true;
    this.web.geometry.setDrawRange(0, lit * 2);
    this.web.material.opacity = 0.55 * mapIn;
    this.arcs.forEach(({ mat, curve, pulseM, i, g }) => {
      const at = 220.2 + i * 0.08;
      const k = pb(b, at, at + 1, ease.inOutCubic);
      g.setDrawRange(0, Math.floor((g.index.count * k) / 3) * 3);
      mat.opacity = 0.9;
      pulseM.visible = k >= 1;
      pulseM.position.copy(curve.getPoint(((b - at) * 0.35 + i * 0.13) % 1));
    });
    // camera
    const pull = springB(b, 200, 0.9, 0.85);
    const ringCam = new THREE.Vector3(0, lerp(4.2, 5.4, pull), lerp(4, 16, pull));
    const ringLook = new THREE.Vector3(0, 3.4, -2);
    const mapCam = new THREE.Vector3(1.2 + Math.sin(t * 0.2) * 0.8, 23, 12.5);
    const mapLook = new THREE.Vector3(0.6, 0, -1.2);
    const crane = pb(b, OUT0, OUT1, ease.inOutCubic);
    const push = pb(b, IN0, IN1, ease.inOutCubic) * (1 - crane);
    const inCam = new THREE.Vector3(0, 3.15, 0.8), inLook = new THREE.Vector3(0, 3.15, -1);
    const pos = ringCam.clone().lerp(inCam, push);
    const look = ringLook.clone().lerp(inLook, push);
    if (crane > 0) { pos.copy(inCam.clone().lerp(mapCam, crane)); look.copy(inLook.clone().lerp(mapLook, crane)); }
    this.cam.position.copy(pos);
    this.cam.position.y -= pb(b, OUT1, 224) * 2;
    this.cam.fov = 40 - 4 * crane + Math.sin(Math.PI * clamp(push)) * 8;
    this.cam.updateProjectionMatrix();
    this.cam.lookAt(look);
    drawBloom(this.scene, this.cam, { strength: 0.55 + crane * 0.35, radius: 0.5, threshold: 0.72 - crane * 0.2 });

    // front tag (ring phase)
    let front = 0;
    for (let i = 1; i < N; i++) if (b >= frontAt(i) + 0.12) front = i;
    const tagOn = b >= 200.3 && b < 209.6;
    this.tagName.style.display = this.tagSub.style.display = tagOn ? "" : "none";
    if (tagOn) {
      const u = RING[front];
      const k = pb(b, Math.max(200.3, frontAt(front) + 0.12), Math.max(200.3, frontAt(front) + 0.12) + 0.2, ease.outExpo);
      if (this.tagName.textContent !== u.name) this.tagName.textContent = u.name;
      this.tagName.style.color = front === 0 ? "#f5b227" : "#" + new THREE.Color().setHSL(u.hue, 0.8, 0.66).getHexString();
      this.tagName.style.transform = `translate(960px, ${850 + (1 - k) * 40}px)`;
      const sub = front === 0 ? "PUP SIS · live now" : front === 1 ? u.sub : `${u.sub} · not connected yet`;
      if (this.tagSub.textContent !== sub) this.tagSub.textContent = sub;
      this.tagSub.style.transform = `translate(960px, ${972 + (1 - k) * 50}px)`;
      this.tagName.style.opacity = this.tagSub.style.opacity = k;
    }
    // map labels (majors)
    this.labels.forEach((l, i) => {
      const u = i === 0 ? PUP : MAJORS[i - 1];
      const hide = ["PNU", "TUP", "UST", "FEU", "MAPUA", "DLSU", "CTU"].includes(u.id);
      const on = b >= 221 && !hide;
      l.style.display = on ? "" : "none";
      if (!on) return;
      const [px, py] = this.project(mapPos(u).add(new THREE.Vector3(0.25, 0.5, 0)));
      l.style.transform = `translate(${px}px, ${py - 16}px)`;
      l.style.opacity = pb(b, 221 + i * 0.05, 221.4 + i * 0.05);
    });
    this.head1.render(b, { at: 204, dur: 1, out: 209.4, outDur: 0.5 });
    this.head2.render(b, { at: 212, dur: 1, out: 216.6, outDur: 0.5 });
    // pages: stack out of the portal (211), dealt page by page, then collapse (219.3)
    const pOn = b >= 210.6 && b < OUT0 + 0.8;
    this.dim.style.display = this.deck.style.display = pOn ? "" : "none";
    this.dim.style.opacity = 0.35 + 0.65 * pb(b, 211.2, 212) * (1 - pb(b, OUT0, OUT0 + 0.8));
    const emerge = springB(b, 210.8, 1.4, 0.7);
    const collapse = pb(b, OUT0 - 0.1, OUT0 + 0.7, ease.inCubic);
    let dealt = 0;
    const pages = Math.ceil(this.cards.length / PAGE);
    const curPage = clamp(Math.floor((b - DEAL0) / DEALDT), 0, pages - 1);
    if (pOn) this.cards.forEach((c) => {
      const deal = DEAL0 + c.p * DEALDT + c.s * 0.022;
      const turn = c.p < pages - 1 ? DEAL0 + (c.p + 1) * DEALDT - 0.12 + c.s * 0.01 : 999;
      const k = ease.outCubic(pb(b, deal, deal + 0.45));
      const tk = ease.inCubic(pb(b, turn, turn + 0.4));
      if (b >= deal) dealt = Math.max(dealt, c.i + 1);
      const gx = 104 + (c.s % 8) * 216, gy = 340 + Math.floor(c.s / 8) * 124;
      const depth = c.i - dealt;
      const sx = 862, sy = 560 - Math.min(40, Math.max(0, depth)) * 0.6;
      const on = tk < 1 && (b < deal ? depth < 40 : true);
      c.d.style.display = on ? "" : "none";
      if (!on) return;
      let x = lerp(sx, gx, k), y = lerp(sy, gy, k) - Math.sin(k * Math.PI) * 120;
      let z = lerp(-Math.max(0, depth) * 2 - (1 - clamp(emerge)) * 3000, 0, k), rx = (1 - k) * 70, ry = 0;
      x -= tk * 420; ry = -tk * 95; z -= tk * 200;
      const cs = 1 - collapse;
      x = lerp(862, x, cs); y = lerp(560, y, cs); z -= collapse * 1800;
      c.d.style.transform = `translate3d(${x}px, ${y}px, ${z}px) rotateX(${rx}deg) rotateY(${ry}deg) scale(${b < deal ? clamp(emerge, 0.02, 1) : 1})`;
      c.d.style.zIndex = b < deal ? 500 - Math.max(0, depth) : 600 + c.s;
    });
    const tg = `PAGE ${curPage + 1} / ${pages}`;
    this.pageTag.style.display = b >= DEAL0 && b < OUT0 ? "" : "none";
    if (this.pageTag.textContent !== tg) this.pageTag.textContent = tg;
    const total = b >= OUT0 ? this.cards.length : dealt;
    const cOn = b >= 211.6 && b < 223.6;
    this.count.style.display = cOn ? "" : "none";
    const cs2 = total >= 100 ? "100+" : String(total);
    if (this.count.textContent !== cs2) this.count.textContent = cs2;
    this.count.style.transform = `scale(${1 + pulse(b, DEAL0 + 3 * DEALDT + 0.1, 0.8) * 0.18})`;
    this.count.style.transformOrigin = "0 50%";
    this.countLab.render(b, { at: 211.8, dur: 0.8, out: 223.2, outDur: 0.4 });
    const nk = pb(b, 212.4, 213, ease.outExpo);
    this.note.style.display = b >= 212.4 && b < 223.4 ? "" : "none";
    this.note.style.transform = `translateY(${(1 - nk) * 30}px)`;
    // Isko rides the Mindanao arc
    const iOn = b >= 220.4 && b < 223.4;
    this.isko.root.style.display = iOn ? "" : "none";
    if (iOn) {
      const arc = this.arcs[this.arcs.length - 1];
      const u = pb(b, 220.4, 223.2, ease.inOutCubic);
      const [x, y] = this.project(arc.curve.getPoint(u).clone().add(new THREE.Vector3(0, 0.2, 0)));
      this.isko.pose({ x, y, t, scale: 0.9, expr: u > 0.9 ? "happy" : blinkAt(t, 13), gesture: "carry", gk: 1, look: 1, shadow: false, tilt: -10 });
    }
  },
};
