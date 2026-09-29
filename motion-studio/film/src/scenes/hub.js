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
const GROW0 = 213.5, GROW1 = 220.5;

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
    this.head2 = pixText(layer, { text: "Someday,\nall connected.", size: 104, x: 100, y: 64, lh: 1.02, ink: "#f7ecec", shadow: "#000" });
    this.count = el("div", "abs", layer);
    css(this.count, { left: "104px", top: "330px", font: "700 230px/1 var(--pixel)", color: "#f5b227", textShadow: "8px 8px 0 #2a0a14" });
    this.countLab = pixText(layer, { text: "universities\nand colleges", size: 72, x: 108, y: 590, lh: 1.05, ink: "#f7ecec", shadow: "#000" });
    this.note = el("div", "abs", layer, "Future vision · not connected yet · names only");
    css(this.note, { left: "108px", top: "800px", font: "600 28px var(--ui)", color: "#a9a9b1" });
    this.ticker = el("div", "abs", layer);
    css(this.ticker, { left: "0", top: "1000px", whiteSpace: "nowrap", font: "700 26px var(--pixel)", color: "#cdbbd8", letterSpacing: ".04em" });
    this.ticker.textContent = this.schools.map((q) => q.name.toUpperCase()).join("   ·   ");
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
    const toMap = pb(b, 210, 213.5, ease.inOutCubic);
    const spinUp = pb(b, 209.2, 211.5, ease.inCubic) * 1.2;
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
    const mapIn = pb(b, 211, 213.5, ease.outCubic);
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
      const at = 212 + i * 0.12;
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
    const crane = pb(b, 209.8, 214.5, ease.inOutCubic);
    this.cam.position.lerpVectors(ringCam, mapCam, crane);
    this.cam.position.y -= pb(b, 214.5, 224) * 2;
    this.cam.fov = 40 - 4 * crane;
    this.cam.updateProjectionMatrix();
    this.cam.lookAt(ringLook.clone().lerp(mapLook, crane));
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
      const on = b >= 213 && !hide;
      l.style.display = on ? "" : "none";
      if (!on) return;
      const [px, py] = this.project(mapPos(u).add(new THREE.Vector3(0.25, 0.5, 0)));
      l.style.transform = `translate(${px}px, ${py - 16}px)`;
      l.style.opacity = pb(b, 213 + i * 0.08, 213.4 + i * 0.08);
    });
    this.head1.render(b, { at: 204, dur: 1, out: 209.4, outDur: 0.5 });
    this.head2.render(b, { at: 211.8, dur: 1, out: 215.6, outDur: 0.5 });
    // counter: 18 portals + every school lit
    const total = 2 + MAJORS.length + lit;
    const cOn = b >= 214 && b < 223.6;
    this.count.style.display = cOn ? "" : "none";
    const cs = total >= 100 ? "100+" : String(total);
    if (this.count.textContent !== cs) this.count.textContent = cs;
    this.count.style.transform = `scale(${1 + (total >= 100 ? pulse(b, this.schools[Math.max(0, 100 - 2 - MAJORS.length - 1)].at, 0.8) * 0.2 : 0)})`;
    this.count.style.transformOrigin = "0 50%";
    this.countLab.render(b, { at: 214.4, dur: 0.8, out: 223.2, outDur: 0.4 });
    const nk = pb(b, 218, 218.6, ease.outExpo);
    this.note.style.display = b >= 218 && b < 223.4 ? "" : "none";
    this.note.style.transform = `translateY(${(1 - nk) * 30}px)`;
    this.ticker.style.display = b >= 214 && b < 223.6 ? "" : "none";
    this.ticker.style.transform = `translateX(${1920 - (b - 214) * 620}px)`;
    // Isko rides the Mindanao arc
    const iOn = b >= 216 && b < 223;
    this.isko.root.style.display = iOn ? "" : "none";
    if (iOn) {
      const arc = this.arcs[this.arcs.length - 1];
      const u = pb(b, 216, 222.5, ease.inOutCubic);
      const [x, y] = this.project(arc.curve.getPoint(u).clone().add(new THREE.Vector3(0, 0.2, 0)));
      this.isko.pose({ x, y, t, scale: 0.9, expr: u > 0.9 ? "happy" : blinkAt(t, 13), gesture: "carry", gk: 1, look: 1, shadow: false, tilt: -10 });
    }
  },
};
