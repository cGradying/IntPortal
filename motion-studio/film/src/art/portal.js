// The portal: obsidian block frame + the dithered swirl (GLSL port of the
// app's Portal.metal) + an isometric platform + drifting motes.
import * as THREE from "three";
import { hash } from "../lib/core.js";

export const SWIRL_PUP = ["#170509", "#540a1c", "#941c30", "#cca128", "#faebb3"];

const VERT = /* glsl */ `
varying vec2 vUv;
void main() { vUv = uv; gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0); }`;

const FRAG = /* glsl */ `
precision highp float;
varying vec2 vUv;
uniform float uPhase, uFlow, uLit, uCells, uAspect, uFlash;
uniform vec3 c0, c1, c2, c3, c4;
float h(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float n(vec2 p) { vec2 i = floor(p), f = fract(p); f = f * f * (3.0 - 2.0 * f);
  return mix(mix(h(i), h(i + vec2(1, 0)), f.x), mix(h(i + vec2(0, 1)), h(i + vec2(1, 1)), f.x), f.y); }
float fbm(vec2 p) { float v = 0.0, a = 0.5; for (int k = 0; k < 4; k++) { v += a * n(p); p *= 2.03; a *= 0.5; } return v; }
float b2(vec2 a) { a = floor(a); return fract(a.x / 2.0 + a.y * a.y * 0.75); }
float bayer(vec2 a) { return b2(0.5 * a) * 0.25 + b2(a); }
void main() {
  vec2 cells = vec2(uCells, uCells / uAspect);
  vec2 q0 = floor(vUv * cells);
  vec2 uv = ((q0 + 0.5) / cells - 0.5) * vec2(uAspect, 1.0);
  float d = length(uv * vec2(1.25, 0.8));
  float a = atan(uv.y, uv.x) + uPhase + d * 3.2;
  vec2 q = vec2(cos(a), sin(a)) * d * 2.4;
  float v = fbm(q * 2.2 + vec2(0.0, -uFlow));
  v += 0.22 * sin(uv.x * 16.0 + fbm(uv * 3.0 + uFlow * 0.5) * 7.0 + uFlow * 3.2);
  v = clamp(v * 0.95 + (0.55 - d) * 0.55, 0.0, 1.0) * uLit;
  float k = clamp(floor(v * 4.0 + bayer(q0) - 0.5), 0.0, 4.0);
  vec3 col = k < 0.5 ? c0 : k < 1.5 ? c1 : k < 2.5 ? c2 : k < 3.5 ? c3 : c4;
  col = mix(col, c4, uFlash);
  gl_FragColor = vec4(col, 1.0);
}`;

export function swirlMaterial(ramp = SWIRL_PUP) {
  const u = { uPhase: { value: 0 }, uFlow: { value: 0 }, uLit: { value: 1 }, uCells: { value: 40 }, uAspect: { value: 0.75 }, uFlash: { value: 0 } };
  ramp.forEach((c, i) => (u[`c${i}`] = { value: new THREE.Color(c) }));
  return new THREE.ShaderMaterial({ uniforms: u, vertexShader: VERT, fragmentShader: FRAG, toneMapped: false });
}

/** Swirl state at time t (seconds) with speed multiplier integrated by caller. */
export function setSwirl(mat, { phase, lit = 1, cells = 40, flash = 0 }) {
  mat.uniforms.uPhase.value = phase * 0.28;
  mat.uniforms.uFlow.value = phase * 0.5;
  mat.uniforms.uLit.value = lit;
  mat.uniforms.uCells.value = cells;
  mat.uniforms.uFlash.value = flash;
}

// --------------------------------------------------------------- obsidian
function obsidianTexture(seed, tint) {
  const c = document.createElement("canvas");
  c.width = c.height = 16;
  const g = c.getContext("2d");
  const [base, hi, lo, spec] = tint;
  g.fillStyle = base; g.fillRect(0, 0, 16, 16);
  g.fillStyle = lo; g.fillRect(0, 14, 16, 2); g.fillRect(14, 0, 2, 16);
  g.fillStyle = hi; g.fillRect(0, 0, 16, 2); g.fillRect(0, 0, 2, 16);
  for (let k = 0; k < 6; k++) {
    g.fillStyle = k % 2 ? spec : hi;
    const x = 3 + Math.floor(hash(seed, k, 1) * 10), y = 3 + Math.floor(hash(seed, k, 2) * 10);
    g.fillRect(x, y, 1 + (k % 2), 1);
  }
  const t = new THREE.CanvasTexture(c);
  t.magFilter = THREE.NearestFilter;
  t.minFilter = THREE.NearestFilter;
  t.colorSpace = THREE.SRGBColorSpace;
  return t;
}
export const OBSIDIAN = ["#3a2649", "#5d3f78", "#1a0f20", "#8a66a8"];

/**
 * Frame of blocks (6 wide x 8 tall, 1 unit blocks) with a swirl plane inside.
 * Returns { group, blocks: [{mesh, home}], swirl, mat, light }.
 */
export function makePortal({ ramp = SWIRL_PUP, tint = OBSIDIAN, seed = 1, w = 6, h = 8 } = {}) {
  const group = new THREE.Group();
  const geo = new THREE.BoxGeometry(1, 1, 1);
  const mats = Array.from({ length: 4 }, (_, i) => new THREE.MeshStandardMaterial({ map: obsidianTexture(seed * 10 + i, tint), roughness: 0.55, metalness: 0.15 }));
  const blocks = [];
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      if (x > 0 && x < w - 1 && y > 0 && y < h - 1) continue;
      const m = new THREE.Mesh(geo, mats[Math.floor(hash(seed, x, y) * 4)]);
      const home = new THREE.Vector3(x - (w - 1) / 2, y + 0.5, 0);
      m.position.copy(home);
      group.add(m);
      blocks.push({ mesh: m, home, x, y });
    }
  }
  const mat = swirlMaterial(ramp);
  mat.uniforms.uAspect.value = (w - 2) / (h - 2);
  const swirl = new THREE.Mesh(new THREE.PlaneGeometry(w - 2, h - 2), mat);
  swirl.position.set(0, h / 2, 0);
  group.add(swirl);
  const light = new THREE.PointLight(new THREE.Color(ramp[3]), 0, 14, 1.6);
  light.position.set(0, h / 2, 1.2);
  group.add(light);
  return { group, blocks, swirl, mat, light };
}

/** Isometric-ish platform of stone tiles under the portal. */
export function makePlatform(n = 7, seed = 5) {
  const g = new THREE.Group();
  const geo = new THREE.BoxGeometry(1, 0.5, 1);
  for (let z = 0; z < n; z++) {
    for (let x = 0; x < n; x++) {
      const d = Math.hypot(x - (n - 1) / 2, z - (n - 1) / 2);
      if (d > n / 2) continue;
      const v = hash(seed, x, z);
      const col = new THREE.Color().setHSL(0.07, 0.35, 0.16 + v * 0.06 - d * 0.012);
      const m = new THREE.Mesh(geo, new THREE.MeshStandardMaterial({ color: col, roughness: 0.9 }));
      m.position.set(x - (n - 1) / 2, -0.25 - v * 0.04, z - (n - 1) / 2);
      g.add(m);
    }
  }
  return g;
}

/** Motes: small gold squares drifting upward; positions are a function of t. */
export function makeMotes(count = 90, seed = 9, spread = 16) {
  const geo = new THREE.PlaneGeometry(0.07, 0.07);
  const mat = new THREE.MeshBasicMaterial({ color: new THREE.Color("#f5b227"), transparent: true, toneMapped: false });
  const mesh = new THREE.InstancedMesh(geo, mat, count);
  const base = Array.from({ length: count }, (_, i) => [hash(seed, i, 1), hash(seed, i, 2), hash(seed, i, 3), hash(seed, i, 4)]);
  const o = new THREE.Object3D();
  function update(t, camera, alpha = 1) {
    for (let i = 0; i < count; i++) {
      const [a, b, c, d] = base[i];
      const y = ((b * 10 + t * (0.15 + d * 0.25)) % 10) - 1;
      o.position.set((a - 0.5) * spread, y, (c - 0.5) * spread * 0.6 - 2);
      o.quaternion.copy(camera.quaternion);
      const s = (0.5 + d) * (y > 7 ? Math.max(0, (9 - y) / 2) : 1);
      o.scale.setScalar(s);
      o.updateMatrix();
      mesh.setMatrixAt(i, o.matrix);
    }
    mesh.instanceMatrix.needsUpdate = true;
    mat.opacity = alpha;
  }
  return { mesh, update };
}
