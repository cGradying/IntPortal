// Magnet portal (beats 16–36). The cracked page hangs in the void as 48
// shards (8×6), face-on, still showing the old portal. On beat 17 the field
// switches on: dotted pixel field-lines reach from 24 shards to their slots,
// and they snap home one per sixteenth, flipping from page to obsidian as
// they fly, each with a white weld. The frame draws itself; the other 24
// shards spiral into the centre and the swirl ignites on 24. The last
// fragment pops back out as Isko. He flips the "Step through" switch, dives
// in, and the camera follows through the warp.
import * as THREE from "three";
import { BEAT, clamp, css, ease, el, hash, lerp, pb, pulse, springB, tb } from "../lib/core.js";
import { drawBloom } from "../art/gl.js";
import { makeMotes, makePortal, OBSIDIAN, setSwirl } from "../art/portal.js";
import { blinkAt, makeIsko, trailFrom } from "../art/isko.js";
import { drawLogin, PH, PW } from "../ui/oldportal.js";
import { pixText } from "../ui/pixtype.js";
import { pixSwitch } from "../ui/switch.js";
import { makeBubble } from "../ui/bubble.js";

const GX = 8, GY = 6;
const SNAP0 = 17, SNAP = 0.25; // first snap, spacing (beats)
const FLY = 0.7; // beats of flight before contact
const IGNITE = 24;
export const WARP_FROM = 32, WARP_TO = 35.4;

/** Integrated swirl phase: speed 1, ramping to ×9 through the warp. */
export function swirlPhase(b, warpFrom = WARP_FROM, warpTo = WARP_TO, extra = 8) {
  const t = tb(b);
  if (b <= warpFrom) return t;
  const steps = 48, end = Math.min(b, warpTo + 2);
  let acc = 0;
  for (let i = 0; i < steps; i++) {
    const x = warpFrom + ((end - warpFrom) * (i + 0.5)) / steps;
    acc += extra * pb(x, warpFrom, warpTo) ** 2;
  }
  return t + (acc * (end - warpFrom) * BEAT) / steps;
}

function obsidianFace(seed) {
  const c = document.createElement("canvas");
  c.width = c.height = 16;
  const g = c.getContext("2d");
  const [base, hi, lo, spec] = OBSIDIAN;
  g.fillStyle = base; g.fillRect(0, 0, 16, 16);
  g.fillStyle = lo; g.fillRect(0, 14, 16, 2); g.fillRect(14, 0, 2, 16);
  g.fillStyle = hi; g.fillRect(0, 0, 16, 2); g.fillRect(0, 0, 2, 16);
  for (let k = 0; k < 6; k++) {
    g.fillStyle = k % 2 ? spec : hi;
    g.fillRect(3 + Math.floor(hash(seed, k, 1) * 10), 3 + Math.floor(hash(seed, k, 2) * 10), 1 + (k % 2), 1);
  }
  const t = new THREE.CanvasTexture(c);
  t.magFilter = t.minFilter = THREE.NearestFilter;
  t.colorSpace = THREE.SRGBColorSpace;
  return t;
}

const FIRE = ["#fff6dc", "#f5b227", "#e8662a", "#c2203a", "#5a0a1c"];
const OBS = ["#b996d8", "#8663a8", "#5f3f7e", "#43295a", "#2c1c3a"];
const BAY = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5];
/** Pixel fireball (cool = 0) cooling into an obsidian ball (cool = 1). Pure. */
function drawFireball(g, t, cool) {
  g.clearRect(0, 0, 40, 40);
  const cx = 20, cy = 23;
  for (let j = 0; j < 40; j++) for (let i = 0; i < 40; i++) {
    const dx = (i - cx) / 11, up = j < cy ? (cy - j) / (11 + (1 - cool) * 14) : (j - cy) / 11;
    const wob = (1 - cool) * 0.18 * Math.sin(i * 0.9 + t * 14 + j * 0.3);
    const r = Math.hypot(dx + wob * (j < cy ? 1 : 0), up);
    const flick = (1 - cool) * 0.25 * (hash(i, j, Math.floor(t * 20)) - 0.5);
    const heat = 1 - r + flick;
    if (heat <= 0.05) continue;
    const th = BAY[(j & 3) * 4 + (i & 3)] / 16;
    const solid = cool > 0 && r < 1.0 && cool * 1.3 > th * 0.6 + (1 - r) * 0.5;
    if (solid) {
      const lit = clamp(0.5 - (i - cx) * 0.035 - (j - cy) * 0.04 + (1 - r) * 0.3);
      const crack = cool < 0.85 && hash(Math.floor(i / 2), Math.floor(j / 2), 5) > 0.82;
      g.fillStyle = crack ? FIRE[1] : r > 0.9 ? "#1a0f20" : OBS[clamp(Math.floor((1 - lit) * 4.99), 0, 4)];
    } else {
      if (cool > 0.6) continue;
      const idx = clamp(Math.floor((1 - heat) * 5 + th - 0.5), 0, 4);
      g.fillStyle = FIRE[idx];
    }
    g.fillRect(i, j, 1, 1);
  }
}

export default {
  id: "magnet", from: 16, to: 36,
  cell(b) {
    return 1 + 7 * pb(b, 33.6, 35.4, ease.inCubic);
  },
  init(layer) {
    const s = (this.scene = new THREE.Scene());
    s.background = new THREE.Color(0x0a080c);
    s.fog = new THREE.Fog(0x0a080c, 16, 40);
    this.cam = new THREE.PerspectiveCamera(38, 1920 / 1080, 0.05, 100);
    s.add(new THREE.HemisphereLight(0x9a80c0, 0x1a0a08, 1.0));
    const rim = new THREE.DirectionalLight(0x8fa8ff, 1.2);
    rim.position.set(5, 6, -8);
    s.add(rim);
    const key = new THREE.DirectionalLight(0xfff0dc, 1.1);
    key.position.set(-4, 7, 12);
    s.add(key);
    this.portal = makePortal({ seed: 3 });
    this.portal.blocks.forEach((bk) => (bk.mesh.visible = false));
    s.add(this.portal.group);
    this.motes = makeMotes(110, 21, 22);
    s.add(this.motes.mesh);

    // page texture: the final cracked state of the old portal
    const pc = document.createElement("canvas");
    pc.width = PW; pc.height = PH;
    drawLogin(pc.getContext("2d"), { t: 0, num: "2024-00123-MN-0", pw: 10, cap: "x7kq9", dim: 0.2, err: "Incorrect characters. Please try again.", btn: "Sign in again", stamp: true });
    const pageTex = new THREE.CanvasTexture(pc);
    pageTex.colorSpace = THREE.SRGBColorSpace;
    const obs = [0, 1, 2, 3].map((i) => new THREE.MeshStandardMaterial({ map: obsidianFace(30 + i), roughness: 0.55, metalness: 0.15 }));
    const edge = new THREE.MeshStandardMaterial({ color: 0x2a1c34, roughness: 0.7 });
    // slots: 24 frame blocks, drawn around the frame from bottom-left, clockwise
    const slots = [];
    for (let y = 0; y < 8; y++) slots.push([0, y]);
    for (let x = 1; x < 6; x++) slots.push([x, 7]);
    for (let y = 6; y >= 0; y--) slots.push([5, y]);
    for (let x = 4; x >= 1; x--) slots.push([x, 0]);
    // shard order: which page tile flies to which slot (seeded shuffle)
    const ids = Array.from({ length: GX * GY }, (_, k) => k).sort((a, c) => hash(a, 77) - hash(c, 77));
    this.shards = ids.map((k, n) => {
      const i = k % GX, j = Math.floor(k / GX);
      const tex = pageTex.clone();
      tex.needsUpdate = true;
      tex.repeat.set(1 / GX, 1 / GY);
      tex.offset.set(i / GX, 1 - (j + 1) / GY);
      const front = new THREE.MeshStandardMaterial({ map: tex, roughness: 0.8, emissive: new THREE.Color(0xffffff), emissiveIntensity: 0 });
      const o = obs[Math.floor(hash(k, 3) * 4)];
      const home = o.clone();
      home.emissive = new THREE.Color(0xffd27a);
      home.emissiveIntensity = 0;
      // +x -x +y -y +z(obsidian: faces camera once home) -z(page)
      const mesh = new THREE.Mesh(new THREE.BoxGeometry(1, 1, 1), [edge, edge, edge, edge, home, front]);
      s.add(mesh);
      const page = new THREE.Vector3((i - (GX - 1) / 2) * 1.02, 4 + ((GY - 1) / 2 - j) * 1.02, 1.6);
      const out = page.clone().sub(new THREE.Vector3(0, 4, 1.6));
      const cloud = page.clone().add(out.multiplyScalar(0.55)).add(new THREE.Vector3((hash(k, 4) - 0.5) * 1.6, (hash(k, 5) - 0.5) * 1.4, (hash(k, 6) - 0.2) * 4));
      const frame = n < 24;
      const sl = frame ? slots[n] : null;
      const slot = frame ? new THREE.Vector3(sl[0] - 2.5, sl[1] + 0.5, 0) : new THREE.Vector3(0, 4, 0);
      return { mesh, page, cloud, slot, frame, at: frame ? SNAP0 + 0.6 + Math.floor(n / 4) * 0.9 : 22.3 + hash(k, 12) * 0.8, seg: frame ? Math.floor(n / 4) : -1, n, k, mats: [home, front], spin: [hash(k, 7) - 0.5, hash(k, 8) - 0.5, hash(k, 9) - 0.5] };
    });
    // segments: 6 runs of 4 blocks gather into a formation, then snap together
    for (let sg = 0; sg < 6; sg++) {
      const mem = this.shards.filter((d) => d.seg === sg);
      const c = mem.reduce((a, d) => a.add(d.slot), new THREE.Vector3()).multiplyScalar(1 / mem.length);
      const off = c.clone().sub(new THREE.Vector3(0, 4, 0)).setZ(0).normalize().multiplyScalar(2.6).add(new THREE.Vector3(0, 0, 3.2));
      mem.forEach((d) => (d.segOff = off));
    }
    this.shards.filter((d) => !d.frame).forEach((d, j) => {
      const a = (j / 24) * Math.PI * 2;
      d.ring = new THREE.Vector3(Math.cos(a) * 3.4, 4 + Math.sin(a) * 3.0, 1.2);
      d.j = j;
    });
    this.debris = new THREE.InstancedMesh(new THREE.BoxGeometry(0.3, 0.3, 0.3), new THREE.MeshStandardMaterial({ color: 0x3a2649, roughness: 0.45, metalness: 0.2, emissive: new THREE.Color(0xc2403a), emissiveIntensity: 0.18 }), 24 * 8);
    this.debris.frustumCulled = false;
    s.add(this.debris);
    // field lines: 14 dots per shard
    this.DOTS = 14;
    const pos = new Float32Array(24 * this.DOTS * 3);
    const col = new Float32Array(24 * this.DOTS * 3);
    const g = new THREE.BufferGeometry();
    g.setAttribute("position", new THREE.BufferAttribute(pos, 3));
    g.setAttribute("color", new THREE.BufferAttribute(col, 3));
    this.field = new THREE.Points(g, new THREE.PointsMaterial({ size: 11, sizeAttenuation: false, vertexColors: true, toneMapped: false, fog: false }));
    this.field.frustumCulled = false;
    s.add(this.field);
    // weld squares
    const sq = new THREE.BufferGeometry().setFromPoints([[-0.5, -0.5], [0.5, -0.5], [0.5, 0.5], [-0.5, 0.5]].map(([x, y]) => new THREE.Vector3(x, y, 0)));
    this.welds = this.shards.filter((d) => d.frame).map(() => {
      const l = new THREE.LineLoop(sq, new THREE.LineBasicMaterial({ color: 0xffffff, transparent: true, toneMapped: false }));
      s.add(l);
      return l;
    });
    // far stars
    const n = 260, sp = new Float32Array(n * 3);
    for (let i = 0; i < n; i++) { sp[i * 3] = (hash(i, 1) - 0.5) * 90; sp[i * 3 + 1] = hash(i, 2) * 40 - 4; sp[i * 3 + 2] = -30 - hash(i, 3) * 20; }
    const sg = new THREE.BufferGeometry();
    sg.setAttribute("position", new THREE.BufferAttribute(sp, 3));
    this.stars = new THREE.Points(sg, new THREE.PointsMaterial({ color: 0x8a7aa0, size: 2.2, sizeAttenuation: false, fog: false, transparent: true }));
    s.add(this.stars);

    // DOM: Isko, his name, the switch
    // the last fragment comes back out as a fireball that cools into Isko
    this.fire = el("canvas", "abs px", layer);
    this.fire.width = this.fire.height = 40;
    css(this.fire, { left: "0", top: "0", width: "280px", height: "280px" });
    this.embers = Array.from({ length: 10 }, (_, i) => {
      const e = el("div", "abs", layer);
      css(e, { width: "14px", height: "14px", background: i % 2 ? "#f5b227" : "#e8662a" });
      return e;
    });
    this.isko = makeIsko(layer, 10);
    this.bubble = makeBubble(layer);
    this.name = pixText(layer, { text: "ISKO", size: 260, font: "pixel", x: 100, y: 250, ink: "#f5b227", shadow: "#3a0a18", ramp: ["#8663a8", "#e27bd0", "#f5b227", "#fff1c4"] });
    this.sub1 = pixText(layer, { text: "Your helper,", size: 76, x: 108, y: 560, ink: "#f7ecec" });
    this.sub2 = pixText(layer, { text: "from the other side.", size: 76, x: 108, y: 650, ink: "#cdbbd8" });
    this.sw = pixSwitch(layer, { label: "STEP THROUGH", s: 1.6, x: 0, y: 0, labelSize: 30 });
    this.v = new THREE.Vector3();
  },
  project(x, y, z) {
    this.v.set(x, y, z).project(this.cam);
    return [(this.v.x + 1) * 960, (1 - this.v.y) * 540];
  },
  render(b, t) {
    const P = this.portal;
    // ---- camera: face-on to the page, then orbit and settle with the
    // portal right of centre; then dive through the warp
    const settle = pb(b, 16.2, 24, ease.inOutCubic);
    const look = new THREE.Vector3(lerp(0, -2.4, settle), 4, 0);
    const dist = lerp(16.5, 15.5, settle) - pb(b, 24, 31.5, ease.inOutCubic) * 2.2;
    const orbit = lerp(0, -0.2, settle) + Math.sin(b * 0.15) * 0.02;
    let cx = look.x + Math.sin(orbit) * dist, cy = lerp(4, 3.4, settle), cz = Math.cos(orbit) * dist;
    const warp = pb(b, WARP_FROM, WARP_TO);
    const w = ease.inPow(warp, 2.6);
    const target = new THREE.Vector3(0, 4, 0);
    cx += (target.x - cx) * w; cy += (target.y - cy) * w; cz += (0.15 - cz) * w;
    look.lerp(target, pb(b, 31, 33, ease.inOutCubic));
    this.cam.fov = 38 + 34 * w;
    this.cam.updateProjectionMatrix();
    this.cam.position.set(cx, cy, cz);
    this.cam.lookAt(look);

    // ---- shards
    const DOTS = this.DOTS;
    const pos = this.field.geometry.attributes.position.array;
    const col = this.field.geometry.attributes.color.array;
    const drift = pb(b, 16, 17.2, ease.outCubic);
    let li = 0;
    for (const d of this.shards) {
      const m = d.mesh;
      // hang: page → cloud, tumbling a little, page side to camera (rot.y = π)
      const hang = d.page.clone().lerp(d.cloud, drift);
      hang.y += Math.sin(t * 1.3 + d.k) * 0.08 * drift;
      const tumble = drift * 0.35;
      let rx = d.spin[0] * tumble, ry = Math.PI + d.spin[1] * tumble, rz = d.spin[2] * tumble;
      let p = hang, sc = 1;
      const f0 = d.at - FLY;
      if (d.frame) {
        // gather into the segment's formation, flipping page → obsidian
        const form = d.slot.clone().add(d.segOff);
        const g1 = ease.inOutCubic(pb(b, d.at - 1.6, d.at - 0.75));
        if (g1 > 0) {
          p = hang.clone().lerp(form, g1).add(new THREE.Vector3(0, Math.sin(g1 * Math.PI) * 0.5, 0));
          ry = lerp(ry, 0, g1);
          rx *= 1 - g1; rz *= 1 - g1;
        }
        // the whole segment travels home as one piece
        const g2 = ease.inOutQuart(pb(b, d.at - 0.75, d.at));
        if (g2 > 0) p = form.clone().lerp(d.slot, g2);
        if (b >= d.at) {
          const o = 1 - springB(b, d.at, 3.6, 0.45);
          p = d.slot.clone().add(d.segOff.clone().multiplyScalar(o * 0.08));
          rx = ry = rz = 0;
        }
        const weld = pulse(b, d.at, 0.5);
        d.mats[0].emissiveIntensity = weld * 0.22;
        const wl = this.welds[d.n];
        wl.visible = b >= d.at && b < d.at + 0.5;
        if (wl.visible) {
          const wk = pb(b, d.at, d.at + 0.5, ease.outCubic);
          wl.position.set(d.slot.x, d.slot.y, 0.52);
          wl.scale.setScalar(1 + wk * 0.8);
          wl.material.opacity = 1 - wk;
        }
        // field line: from shard to slot, visible while the field reaches for it
        const on = b >= Math.max(SNAP0 - 0.3, d.at - 2.3) && b < d.at;
        const reach = pb(b, d.at - 2.3, d.at - 1.6, ease.outCubic);
        for (let q = 0; q < DOTS; q++) {
          const u = (q + 0.5) / DOTS;
          const idx = (d.n * DOTS + q) * 3;
          if (!on || u > reach) { pos[idx] = 0; pos[idx + 1] = -200; pos[idx + 2] = 0; continue; }
          const a = p, c = d.slot;
          pos[idx] = lerp(a.x, c.x, u);
          pos[idx + 1] = lerp(a.y, c.y, u) + Math.sin(u * Math.PI) * 0.3;
          pos[idx + 2] = lerp(a.z, c.z, u) + Math.sin(u * Math.PI) * 0.6;
          const flow = (u * 4 - (b - f0) * 6) % 1;
          const hot = flow < 0 ? flow + 1 : flow;
          const gold = hot < 0.35;
          col[idx] = gold ? 1.0 : 0.53; col[idx + 1] = gold ? 0.7 : 0.39; col[idx + 2] = gold ? 0.15 : 0.66;
        }
        li++;
      } else {
        // interior: drift to a ring around the frame, then break into
        // pieces that spiral into the swirl
        const k1 = ease.inOutCubic(pb(b, 20.8, d.at));
        if (k1 > 0) {
          p = hang.clone().lerp(d.ring, k1);
          ry = lerp(ry, 0, k1);
          rx *= 1 - k1; rz *= 1 - k1;
        }
        d.mats[1].emissiveIntensity = pb(b, d.at - 0.4, d.at) * 0.8;
        m.visible = b < d.at;
        const o3 = new THREE.Object3D();
        for (let q = 0; q < 8; q++) {
          const idx = d.j * 8 + q;
          const kk = pb(b, d.at, IGNITE + 0.1, ease.inCubic);
          const live = b >= d.at && kk < 1;
          const off = new THREE.Vector3((q & 1) - 0.5, ((q >> 1) & 1) - 0.5, ((q >> 2) & 1) - 0.5).multiplyScalar(0.5);
          const start = d.ring.clone().add(off.clone().multiplyScalar(1 + pb(b, d.at, d.at + 0.3, ease.outCubic) * 1.5));
          const rel = start.clone().sub(new THREE.Vector3(0, 4, 0));
          const ang = Math.atan2(rel.y, rel.x) + kk * 4.5;
          const r = Math.hypot(rel.x, rel.y) * (1 - kk);
          o3.position.set(Math.cos(ang) * r, 4 + Math.sin(ang) * r, lerp(start.z, 0, kk));
          o3.rotation.set(kk * 6 + q, kk * 4, 0);
          o3.scale.setScalar(live ? 1 - kk * 0.85 : 0.0001);
          o3.updateMatrix();
          this.debris.setMatrixAt(idx, o3.matrix);
        }
      }
      m.position.copy(p);
      m.rotation.set(rx, ry, rz);
      m.scale.setScalar(sc);
    }
    void li;
    this.debris.instanceMatrix.needsUpdate = true;
    this.field.geometry.attributes.position.needsUpdate = true;
    this.field.geometry.attributes.color.needsUpdate = true;

    // ---- swirl
    const lit = pb(b, IGNITE, IGNITE + 0.6, ease.outCubic);
    const wk = pb(b, WARP_FROM, WARP_TO);
    P.swirl.visible = b >= IGNITE - 0.2;
    setSwirl(P.mat, { phase: swirlPhase(b), lit, cells: 40 - 24 * wk, flash: Math.max(pulse(b, IGNITE, 0.8) * 0.8, pb(b, 35.1, 35.8) ** 2 * 0.7) });
    P.light.intensity = lit * (60 + pulse(b, IGNITE, 1.2) * 160 + pulse(b, 30, 1) * 80) + wk * 80;
    P.light.distance = 22;
    this.motes.update(t, this.cam, 0.3 + 0.7 * lit);
    this.stars.material.opacity = 0.3 + 0.3 * lit;
    drawBloom(this.scene, this.cam, { strength: 0.7 + wk * 0.8 + pulse(b, IGNITE, 1) * 0.5, radius: 0.6, threshold: 0.55 });

    // ---- the last fragment → Isko (25 → 31.75)
    const [scx, scy] = this.project(0, 4, 0.1);
    const iskoHome = [scx - 330, scy + 280];
    // fireball: out of the swirl 25 → 25.9, cools to obsidian 25.9 → 26.5, pops open 26.4
    const fOn = b >= 24.9 && b < 26.7;
    this.fire.style.display = fOn ? "" : "none";
    const fpath = (bb) => {
      const k = ease.outCubic(pb(bb, 24.9, 25.9));
      return [lerp(scx, iskoHome[0], k), lerp(scy, iskoHome[1] - 110, k) - Math.sin(k * Math.PI) * 180, k];
    };
    if (fOn) {
      const [fx, fy, fk] = fpath(b);
      const cool = pb(b, 25.9, 26.45, ease.inOutCubic);
      drawFireball(this.fire.getContext("2d"), t, cool);
      const sc = (0.35 + 0.65 * fk) * (1 - pb(b, 26.4, 26.7, ease.inCubic)) * (1 + pulse(b, 25.9, 0.5) * 0.12);
      this.fire.style.transform = `translate(${fx - 140}px, ${fy - 160}px) scale(${sc})`;
    }
    this.embers.forEach((e, i) => {
      const bb = b - (i + 1) * 0.06;
      const on = fOn && bb > 24.95 && b < 25.95;
      e.style.display = on ? "" : "none";
      if (!on) return;
      const [x, y] = fpath(bb);
      e.style.transform = `translate(${x - 7 + Math.sin(i * 2.1 + t * 9) * 10}px, ${y - 7 + i * 3}px) scale(${1 - i * 0.08})`;
    });
    const I = this.isko;
    const iOn = b >= 26.4 && b < 31.8;
    I.root.style.display = iOn ? "" : "none";
    if (!iOn) this.bubble.render(-1, [], 0, 0);
    if (iOn) {
      // path: pop at home, hover, fly to the switch (29 → 29.9), flip at 30,
      // then dive into the swirl (31 → 31.75)
      const swX = scx - 870, swY = scy + 500;
      const fly = pb(b, 29, 29.9, ease.inOutCubic);
      const dive = pb(b, 31, 31.75, ease.inCubic);
      let x = lerp(iskoHome[0], swX - 20, fly), y = lerp(iskoHome[1], swY - 30, fly) + Math.sin(fly * Math.PI) * 90;
      x = lerp(x, scx, dive); y = lerp(y, scy + 60, dive) - Math.sin(dive * Math.PI) * 180;
      const pop = springB(b, 26.4, 2.4, 0.45);
      const trailPath = (tt) => {
        const bb = b + (tt - t) / BEAT;
        const f = pb(bb, 29, 29.9, ease.inOutCubic), dv = pb(bb, 31, 31.75, ease.inCubic);
        let xx = lerp(iskoHome[0], swX - 20, f), yy = lerp(iskoHome[1], swY - 30, f) + Math.sin(f * Math.PI) * 90;
        xx = lerp(xx, scx, dv); yy = lerp(yy, scy + 60, dv) - Math.sin(dv * Math.PI) * 180;
        return [xx, yy];
      };
      const expr = b < 26.9 ? "wow" : b < 28.6 ? (b < 27.4 ? "happy" : blinkAt(t, 4)) : b < 30.6 ? "focus" : b < 31 ? "wink" : "happy";
      I.pose({
        x, y, t, scale: clamp(pop, 0, 1.3) * (1 - dive * 0.9), squash: pulse(b, 26.4, 0.6) * 0.8 - pulse(b, 30, 0.4) * 0.5 + dive * -0.4,
        expr, gesture: b >= 26.5 && b < 28 ? "wave" : b >= 29.6 && b < 30.4 ? "point" : b >= 30.4 && b < 31 ? "thumbs" : "idle",
        gk: 1, wavePhase: (b - 26.5) * Math.PI * 2.2, look: b < 28.5 ? 0.6 : 1, tilt: dive * 30,
        trail: trailFrom(trailPath, t), opacity: 1 - pb(b, 31.6, 31.8),
      });
      this.bubble.render(b, [[29.9, 1.1, "Ready? Hold on!"]], x, y - 230);
    }
    this.name.render(b, { at: 26.5, dur: 1.2, out: 31.2, outDur: 0.6 });
    this.sub1.render(b, { at: 27.5, dur: 0.8, out: 31.2, outDur: 0.5, band: false });
    this.sub2.render(b, { at: 28.0, dur: 0.8, out: 31.3, outDur: 0.5, band: false });
    // ---- the switch
    const swOn = b >= 27 && b < 32;
    this.sw.root.style.display = swOn ? "" : "none";
    if (swOn) {
      const rise = springB(b, 27, 2.2, 0.6);
      this.sw.root.style.transform = `translate(${scx - 760}px, ${scy + 400 + (1 - rise) * 200}px)`;
      this.sw.render(pb(b, 30, 30.12), pulse(b, 30, 0.3));
    }
  },
};
