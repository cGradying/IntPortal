// The void (beats 6.9–20.3): the shattered page's dark becomes the void, the
// obsidian frame drops in block by block on 16ths, the swirl ignites on the
// downbeat, Isko runs in and points, the app's own "Step through" button is
// tapped, Isko hops in, and the camera warps through (pixel cell grows,
// swirl speeds up ×9, gold-white flash).
import * as THREE from "three";
import { BEAT, clamp, css, ease, el, hash, pb, pulse, springB, tb } from "../lib/core.js";
import { drawBloom } from "../art/gl.js";
import { makeMotes, makePlatform, makePortal, setSwirl } from "../art/portal.js";
import { blinkAt, makeIsko } from "../art/isko.js";

const PX = 1.6; // portal x

/** Integrated swirl phase: speed 1, ramping to ×9 in the warp. */
export function swirlPhase(b, warpFrom = 16, warpTo = 19.4, extra = 8) {
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

export default {
  id: "world", from: 6.9, to: 20.3,
  cell(b) {
    return 1 + 7 * pb(b, 17.6, 19.4, ease.inCubic);
  },
  init(layer) {
    const s = (this.scene = new THREE.Scene());
    s.fog = new THREE.Fog(0x0a080c, 14, 34);
    this.cam = new THREE.PerspectiveCamera(38, 1920 / 1080, 0.05, 100);
    s.add(new THREE.HemisphereLight(0x8a70b0, 0x1a0a08, 0.9));
    const rim = new THREE.DirectionalLight(0x8fa8ff, 1.4);
    rim.position.set(4, 6, -8);
    s.add(rim);
    s.background = new THREE.Color(0x0a080c);
    const key = new THREE.DirectionalLight(0xffe2b0, 0.5);
    key.position.set(-6, 10, 8);
    s.add(key);
    this.portal = makePortal({ seed: 3 });
    this.portal.group.position.x = PX;
    s.add(this.portal.group);
    const plat = makePlatform(9, 4);
    plat.position.set(PX, 0, 1.2);
    s.add(plat);
    this.motes = makeMotes(110, 21, 22);
    s.add(this.motes.mesh);
    // ignite ring on the platform
    this.ring = new THREE.Mesh(new THREE.RingGeometry(0.9, 1.0, 64), new THREE.MeshBasicMaterial({ color: 0xf5b227, transparent: true, toneMapped: false, side: THREE.DoubleSide }));
    this.ring.rotation.x = -Math.PI / 2;
    this.ring.position.set(PX, 0.02, 1.2);
    s.add(this.ring);
    // far stars: a thin layer of pixel points
    const n = 260, pos = new Float32Array(n * 3);
    for (let i = 0; i < n; i++) {
      pos[i * 3] = (hash(i, 1) - 0.5) * 90;
      pos[i * 3 + 1] = hash(i, 2) * 40 - 4;
      pos[i * 3 + 2] = -30 - hash(i, 3) * 20;
    }
    const pg = new THREE.BufferGeometry();
    pg.setAttribute("position", new THREE.BufferAttribute(pos, 3));
    this.stars = new THREE.Points(pg, new THREE.PointsMaterial({ color: 0x8a7aa0, size: 2.2, sizeAttenuation: false, fog: false, transparent: true }));
    s.add(this.stars);

    // DOM: Isko + the app's landing button
    this.isko = makeIsko(layer, 7);
    this.brand = el("div", "abs display", layer, `<span style="color:#f5b227">Student</span> IntPortal`);
    css(this.brand, { left: "1340px", top: "360px", fontSize: "68px", whiteSpace: "nowrap" });
    this.tag = el("div", "abs", layer, "PUP SIS, in your pocket");
    css(this.tag, { left: "1344px", top: "446px", fontSize: "32px", color: "#a9a9b1" });
    this.btn = el("div", "abs notch display", layer, "Step through");
    css(this.btn, { width: "380px", height: "96px", lineHeight: "96px", textAlign: "center", fontSize: "40px", letterSpacing: "-0.01em", background: "#f5b227", color: "#1b1406", transformOrigin: "50% 50%" });
    this.cap = el("div", "abs", layer, "PUP SIS · Sta. Mesa");
    css(this.cap, { fontFamily: "var(--pixel)", fontSize: "26px", color: "#a9a9b1", letterSpacing: "0.06em", width: "380px", textAlign: "center" });
    this.tap = el("div", "abs", layer);
    css(this.tap, { width: "40px", height: "40px", borderRadius: "50%", border: "4px solid #f5b227" });
    this.v = new THREE.Vector3();
  },
  project(x, y, z) {
    this.v.set(x, y, z).project(this.cam);
    return [(this.v.x + 1) * 960, (1 - this.v.y) * 540];
  },
  render(b, t) {
    const P = this.portal;
    // ---- blocks drop in: 6.9 → 7.95, bottom row first
    const order = [...P.blocks].sort((a, c) => a.y - c.y || Math.abs(a.x - 2.5) - Math.abs(c.x - 2.5));
    order.forEach((blk, i) => {
      const at = 6.9 + (i / order.length) * 1.0;
      const k = springB(b, at, 3.4, 0.5);
      const visible = b >= at;
      blk.mesh.visible = visible;
      blk.mesh.position.set(blk.home.x, blk.home.y + (1 - k) * 7, blk.home.z);
      blk.mesh.rotation.set((1 - k) * 0.6 * (hash(i, 5) - 0.5), (1 - k) * 0.8 * (hash(i, 6) - 0.5), 0);
    });
    // ---- ignite at 8
    const lit = pb(b, 8, 8.6, ease.outCubic);
    const warp = pb(b, 16, 19.4);
    setSwirl(P.mat, { phase: swirlPhase(b), lit, cells: 40 - 24 * warp, flash: pb(b, 18.8, 19.4) ** 2 });
    P.light.intensity = lit * (60 + pulse(b, 8, 1.2) * 160) + warp * 80;
    P.light.distance = 22;
    const rk = pb(b, 8, 9.2, ease.outCubic);
    this.ring.scale.setScalar(1 + rk * 9);
    this.ring.material.opacity = (1 - rk) * (b >= 8 ? 0.9 : 0);
    this.motes.update(t, this.cam, lit);
    this.stars.material.opacity = 0.35 + 0.25 * lit;

    // ---- camera
    const dolly = pb(b, 6.9, 16, ease.inOutCubic);
    const orbit = -0.16 + 0.26 * dolly;
    const dist = 21 - 5.5 * dolly;
    const look = new THREE.Vector3(PX - 1.6 + 0.6 * dolly, 3.9, 0);
    let cx = look.x + Math.sin(orbit) * dist, cz = Math.cos(orbit) * dist, cy = 3.2 + 0.6 * dolly;
    // warp: dive to the swirl centre, ease-in ^2.6
    const w = ease.inPow(warp, 2.6);
    const target = new THREE.Vector3(PX, 4, 0);
    cx += (target.x - cx) * w; cy += (target.y - cy) * w; cz += (0.15 - cz) * w;
    look.lerp(target, pb(b, 15.5, 17, ease.inOutCubic));
    this.cam.fov = 38 + 34 * w;
    this.cam.updateProjectionMatrix();
    this.cam.position.set(cx, cy, cz);
    this.cam.lookAt(look);
    drawBloom(this.scene, this.cam, { strength: 0.75 + warp * 0.8, radius: 0.6, threshold: 0.55 });

    // ---- Isko: runs in 8 → 9, points 9.3 → 11, idles, hops in at 15
    const I = this.isko;
    const showIsko = b >= 7.9 && b < 15.9;
    I.root.style.display = showIsko ? "" : "none";
    if (showIsko) {
      const run = pb(b, 7.9, 9, ease.outCubic);
      let x = -9 + (PX - 3.9 + 9) * run, y = 0, scale = 1;
      const hop = pb(b, 15, 15.85, ease.inOutCubic);
      if (b >= 15) {
        x = PX - 3.9 + 3.9 * hop;
        y = Math.sin(hop * Math.PI) * 2.2 + hop * 2.2;
        scale = 1 - hop * 0.85;
      }
      const [fx, fy] = this.project(x, y, 1.6);
      const [, hy] = this.project(x, y + 2.9, 1.6);
      const px = (fy - hy) / (37 * 7);
      const land = pulse(b, 9, 0.5);
      const crouch = pulse(b, 14.6, 0.35) * (b < 15 ? 1 : 0);
      I.pose({
        x: fx, y: fy, scale: px * scale, face: 1, t,
        walk: b < 9 ? (b - 7.9) * Math.PI * 4 : null,
        point: pb(b, 9.3, 9.7, ease.outBack) * (1 - pb(b, 11, 11.4)),
        wave: pb(b, 12.2, 12.5) * (1 - pb(b, 13.6, 14)),
        wavePhase: (b - 12) * Math.PI * 2,
        squash: land * 0.8 - crouch * 0.6 + (b >= 15 ? -0.3 * Math.sin(hop * Math.PI) : 0),
        tilt: b >= 9.3 && b < 11 ? 4 : 0,
        expr: b >= 12 && b < 14 ? "happy" : blinkAt(t, 2),
        cardSwing: -land * 16,
        opacity: 1 - pb(b, 15.6, 15.9),
      });
    }
    // ---- landing button + tap
    const bx = 1530, by = 520;
    const bk = pb(b, 11.6, 12.3, ease.outExpo) * (1 - pb(b, 15.4, 16, ease.inCubic));
    this.brand.style.display = this.tag.style.display = b >= 11.6 && b < 16 ? "" : "none";
    this.brand.style.transform = `translateX(${(1 - bk) * 80}px)`;
    this.brand.style.opacity = bk;
    this.tag.style.transform = `translateX(${(1 - pb(b, 11.8, 12.5, ease.outExpo)) * 80}px)`;
    this.tag.style.opacity = bk * 0.95;
    const rise = pb(b, 12, 12.6, ease.outExpo) * (1 - pb(b, 15.4, 16, ease.inCubic));
    const press = pulse(b, 14, 0.5);
    const bOn = b >= 12 && b < 16;
    this.btn.style.display = this.cap.style.display = bOn ? "" : "none";
    this.btn.style.transform = `translate(${bx - 190}px, ${by - 20 + (1 - rise) * 120}px) scale(${1 - press * 0.08})`;
    this.btn.style.opacity = rise;
    this.btn.style.background = press > 0.05 ? "#ffc84a" : "#f5b227";
    this.cap.style.transform = `translate(${bx - 190}px, ${by + 94 + (1 - rise) * 160}px)`;
    this.cap.style.opacity = rise * 0.9;
    const tk = pb(b, 14, 14.8, ease.outCubic);
    this.tap.style.display = b >= 14 && b < 14.8 ? "" : "none";
    this.tap.style.transform = `translate(${bx - 20 + 60}px, ${by + 28}px) scale(${1 + tk * 5})`;
    this.tap.style.opacity = 1 - tk;
  },
};
