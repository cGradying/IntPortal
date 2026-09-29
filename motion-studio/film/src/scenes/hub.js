// The hub lights up (beats 139.6–172). Out of the flash: the hub ring, PUP SIS
// lit. For one beat the next frame flickers on as Mabini (PUP online, soon).
// Then the ring turns one frame per beat and a state university's portal
// ignites in its own colour. Crane up: the portals fly to where they are on a
// dotted Philippines, campus dots bloom around each, and light-arcs connect
// them. A teaser, labelled as one: "Not connected yet".
import * as THREE from "three";
import { clamp, css, ease, el, hash, lerp, pb, pulse, springB } from "../lib/core.js";
import { drawBloom } from "../art/gl.js";
import { makePortal, setSwirl } from "../art/portal.js";
import { mapDots, toWorld, UNIS } from "../art/phmap.js";
import { headline } from "../ui/type.js";
import { swirlPhase } from "./world.js";

const N = UNIS.length;
const R = 13;
const STEP = (Math.PI * 2) / N;
const litAt = (i) => (i === 0 ? 0 : i === 1 ? 142.3 : 144 + (i - 2));
const frontAt = (i) => (i === 0 ? 0 : i === 1 ? 142 : 143.8 + (i - 2));

function ramp(h) {
  const c = (s, l, dh = 0) => "#" + new THREE.Color().setHSL((h + dh + 1) % 1, s, l).getHexString();
  return [c(0.6, 0.05), c(0.75, 0.2), c(0.75, 0.38), c(0.85, 0.58, 0.04), c(0.9, 0.86, 0.07)];
}

export default {
  id: "hub", from: 139.6, to: 172.2,
  init(layer) {
    const s = (this.scene = new THREE.Scene());
    s.background = new THREE.Color(0x07060a);
    s.fog = new THREE.Fog(0x07060a, 30, 80);
    s.add(new THREE.HemisphereLight(0x8a70b0, 0x100808, 0.8));
    const key = new THREE.DirectionalLight(0xffe2b0, 0.6);
    key.position.set(-10, 20, 12);
    s.add(key);
    this.cam = new THREE.PerspectiveCamera(40, 1920 / 1080, 0.1, 300);
    this.ring = new THREE.Group();
    s.add(this.ring);
    this.portals = UNIS.map((u, i) => {
      const P = makePortal({ ramp: i === 0 ? undefined : ramp(u.hue), seed: 11 + i, w: 5, h: 7 });
      P.group.scale.setScalar(0.9);
      this.ring.add(P.group);
      return P;
    });
    // map dots
    const dots = mapDots(0.16);
    const geo = new THREE.BoxGeometry(0.11, 0.05, 0.11);
    this.dots = new THREE.InstancedMesh(geo, new THREE.MeshBasicMaterial({ color: 0x6a5a7a, transparent: true }), dots.length);
    const o = new THREE.Object3D();
    this.dotBase = dots;
    dots.forEach(([x, z], i) => {
      o.position.set(x, 0, z);
      o.updateMatrix();
      this.dots.setMatrixAt(i, o.matrix);
    });
    this.mapGroup = new THREE.Group();
    this.mapGroup.add(this.dots);
    s.add(this.mapGroup);
    // campus dots + arcs
    this.camp = [];
    this.arcs = [];
    const pup = toWorld(...UNIS[0].main);
    UNIS.forEach((u, i) => {
      const col = new THREE.Color().setHSL(u.hue, 0.85, 0.62);
      u.camp.forEach(([lo, la], j) => {
        const [x, z] = toWorld(lo, la);
        const m = new THREE.Mesh(new THREE.BoxGeometry(0.16, 0.16, 0.16), new THREE.MeshBasicMaterial({ color: col, toneMapped: false, transparent: true }));
        m.position.set(x, 0.12, z);
        this.mapGroup.add(m);
        this.camp.push({ m, i, j });
      });
      if (i >= 2) {
        const [x, z] = toWorld(...u.main);
        const a = new THREE.Vector3(pup[0], 0.3, pup[1]), b = new THREE.Vector3(x, 0.3, z);
        const mid = a.clone().lerp(b, 0.5);
        mid.y = 1.2 + a.distanceTo(b) * 0.35;
        const curve = new THREE.QuadraticBezierCurve3(a, mid, b);
        const g = new THREE.TubeGeometry(curve, 48, 0.035, 5, false);
        const mat = new THREE.MeshBasicMaterial({ color: col.clone().lerp(new THREE.Color(0xf5b227), 0.4), toneMapped: false, transparent: true });
        const tube = new THREE.Mesh(g, mat);
        this.mapGroup.add(tube);
        const pulseM = new THREE.Mesh(new THREE.SphereGeometry(0.12, 8, 6), new THREE.MeshBasicMaterial({ color: 0xfff1c4, toneMapped: false }));
        this.mapGroup.add(pulseM);
        this.arcs.push({ tube, mat, curve, pulseM, i, g });
      }
    });
    // DOM: front tag, map labels, headlines, chips
    this.tagName = el("div", "abs display", layer);
    css(this.tagName, { left: "0", top: "0", fontSize: "96px", whiteSpace: "nowrap", textAlign: "center", width: "1200px", marginLeft: "-600px" });
    this.tagSub = el("div", "abs", layer);
    css(this.tagSub, { left: "0", top: "0", font: "600 32px var(--ui)", color: "#cfcfd6", width: "1200px", marginLeft: "-600px", textAlign: "center", letterSpacing: "0.02em" });
    this.labels = UNIS.map((u) => {
      const l = el("div", "abs", layer, u.name === "PUP SIS" ? "PUP · Metro Manila" : u.name);
      css(l, { font: "800 22px var(--display)", color: "#fff", whiteSpace: "nowrap", textShadow: "0 2px 8px #000" });
      return l;
    });
    this.head1 = headline(layer, [{ text: "Every campus", at: 150 }, { text: "has a portal.", at: 150.6, gold: true }], { x: 100, y: 70, size: 104, out: 157.6 });
    this.head2 = headline(layer, [{ text: "Someday,", at: 160 }, { text: "all connected.", at: 160.6, gold: true }], { x: 100, y: 70, size: 104, out: 171.4 });
    this.chips = ["Cross-campus study rooms", "Shared decks", "Campus streaks"].map((t, i) => {
      const c = el("div", "abs notch display", layer, t);
      css(c, { left: `${100}px`, top: `${330 + i * 92}px`, padding: "16px 24px", fontSize: "34px", background: i === 1 ? "#f5b227" : "#f7ecec", color: "#1b1406", whiteSpace: "nowrap" });
      return c;
    });
    this.note = el("div", "abs", layer, "Future vision · Not connected yet");
    css(this.note, { left: "104px", top: "622px", font: "600 26px var(--ui)", color: "#a9a9b1", letterSpacing: "0.04em" });
    this.v = new THREE.Vector3();
  },
  project(p) {
    this.v.copy(p).project(this.cam);
    return [(this.v.x + 1) * 960, (1 - this.v.y) * 540, this.v.z];
  },
  render(b, t) {
    // ---- which index is at the front of the ring (spring per step)
    let rot = 0;
    for (let i = 1; i < N; i++) rot += springB(b, frontAt(i), 3.2, 0.82);
    const toMap = pb(b, 157, 161.5, ease.inOutCubic);
    const spinUp = pb(b, 155.8, 158.5, ease.inCubic) * 1.4;
    this.portals.forEach((P, i) => {
      const a = (i - rot - spinUp * 3) * STEP;
      const ringPos = new THREE.Vector3(Math.sin(a) * R, 0, Math.cos(a) * R - R);
      const [mx, mz] = toWorld(...UNIS[i].main);
      const mapPos = new THREE.Vector3(mx + (i === 1 ? 0.5 : 0), 0.1, mz + (i === 13 ? 0.4 : 0));
      P.group.position.lerpVectors(ringPos, mapPos, toMap);
      P.group.rotation.y = a * (1 - toMap);
      P.group.scale.setScalar(lerp(0.9, 0.13, toMap));
      const la = litAt(i);
      // Mabini flickers on for a beat, then settles half-lit ("soon")
      let lit = i === 0 ? 1 : b >= la ? pb(b, la, la + 0.4, ease.outCubic) : 0;
      if (i === 1) lit *= b < la + 0.9 ? (hash(Math.floor(b * 16), 3) > 0.35 ? 1 : 0.25) : 0.6;
      setSwirl(P.mat, { phase: swirlPhase(b) + i * 1.7, lit, cells: 30, flash: 0 });
      P.swirl.visible = lit > 0.02;
      P.light.intensity = lit * (14 + pulse(b, la, 1) * 50) * (1 - toMap * 0.8);
      P.light.distance = 12;
    });
    // ---- map
    const mapIn = pb(b, 158, 161, ease.outCubic);
    this.mapGroup.visible = mapIn > 0;
    this.dots.material.opacity = mapIn * 0.9;
    this.camp.forEach(({ m, i, j }) => {
      const k = springB(b, 161 + i * 0.25 + j * 0.05, 2.4, 0.5);
      m.scale.setScalar(clamp(k, 0, 1.3) + 0.001);
      m.material.opacity = mapIn;
    });
    this.arcs.forEach(({ mat, curve, pulseM, i, g }) => {
      const at = 161.5 + (i - 2) * 0.5;
      const k = pb(b, at, at + 1.2, ease.inOutCubic);
      g.setDrawRange(0, Math.floor(g.index.count * k / 3) * 3);
      mat.opacity = 0.85;
      const ph = ((b - at) * 0.35 + i * 0.13) % 1;
      pulseM.visible = k >= 1;
      pulseM.position.copy(curve.getPoint(ph));
    });
    // ---- camera: out of the flash close on PUP SIS, pull to ring, crane up to the map
    const pull = springB(b, 139.8, 0.9, 0.85);
    const ringCam = new THREE.Vector3(0, lerp(4.2, 5.2, pull), lerp(4, 15, pull));
    const ringLook = new THREE.Vector3(0, 3.4, -2);
    const mapCam = new THREE.Vector3(-1.4 + Math.sin(t * 0.2) * 1.0, 22, 13.5);
    const mapLook = new THREE.Vector3(-2.6, 0, -0.9);
    const crane = pb(b, 156.5, 162, ease.inOutCubic);
    this.cam.position.lerpVectors(ringCam, mapCam, crane);
    const look = ringLook.clone().lerp(mapLook, crane);
    this.cam.fov = 40 - 6 * crane;
    this.cam.updateProjectionMatrix();
    this.cam.lookAt(look);
    const drift = pb(b, 162, 172.2) * 0.35;
    this.cam.position.x += Math.sin(drift * 3) * 1.5;
    this.cam.lookAt(look);
    drawBloom(this.scene, this.cam, { strength: 0.55 + crane * 0.35, radius: 0.5, threshold: 0.72 - crane * 0.2 });

    // ---- front tag (ring phase)
    let front = 0;
    for (let i = 1; i < N; i++) if (b >= frontAt(i) + 0.22) front = i;
    const tagOn = b >= 140.4 && b < 156.2;
    this.tagName.style.display = this.tagSub.style.display = tagOn ? "" : "none";
    if (tagOn) {
      const u = UNIS[front];
      const fp = [960, 836];
      const k = pb(b, Math.max(140.4, frontAt(front) + 0.22), Math.max(140.4, frontAt(front) + 0.22) + 0.3, ease.outExpo);
      this.tagName.textContent = u.name;
      this.tagName.style.color = front === 0 ? "#f5b227" : "#" + new THREE.Color().setHSL(u.hue, 0.8, 0.66).getHexString();
      this.tagName.style.transform = `translate(${fp[0]}px, ${fp[1] + 10 + (1 - k) * 40}px)`;
      this.tagName.style.opacity = k;
      this.tagSub.textContent = u.live ? u.sub : u.soon ? u.sub : `${u.sub} · Not connected yet`;
      this.tagSub.style.transform = `translate(${fp[0]}px, ${fp[1] + 118 + (1 - k) * 50}px)`;
      this.tagSub.style.opacity = k;
    }
    // ---- map labels
    this.labels.forEach((l, i) => {
      const on = b >= 161 && !["MABINI", "TUP", "RTU", "CVSU", "BULSU"].includes(UNIS[i].id);
      l.style.display = on ? "" : "none";
      if (!on) return;
      const p = this.project(this.portals[i].group.position.clone().add(new THREE.Vector3(0.3, 0.9, 0)));
      const k = pb(b, 161 + i * 0.2, 161.5 + i * 0.2, ease.outExpo);
      l.style.transform = `translate(${p[0]}px, ${p[1] - 14}px)`;
      l.style.opacity = k;
      l.style.color = i === 0 ? "#f5b227" : "#fff";
    });
    this.head1(b);
    this.head2(b);
    this.chips.forEach((c, i) => {
      const at = 164 + i * 1.5;
      const k = springB(b, at, 2.2, 0.6);
      c.style.display = b >= at && b < 171.6 ? "" : "none";
      c.style.transform = `translateX(${(1 - clamp(k, 0, 1)) * -120}px) scale(${clamp(k, 0, 1.08)})`;
    });
    const nk = pb(b, 168.5, 169.2, ease.outExpo);
    this.note.style.display = b >= 168.5 && b < 171.6 ? "" : "none";
    this.note.style.transform = `translateY(${(1 - nk) * 30}px)`;
    this.note.style.opacity = nk;
  },
};
