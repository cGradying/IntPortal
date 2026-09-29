// The new campus scene (replaces the flat pixel PUP): the Sta. Mesa main
// building as soft 3D volumes with lit windows, a Bayer-dithered sky that
// follows the time of day, pixel stars, and fine light-lines rising from the
// windows into a constellation — the campus as a node in a network.
// Own renderer + canvas, so it can sit inside a phone card or fill a frame.
import * as THREE from "three";
import { clamp, hash, lerp } from "../lib/core.js";

let R, scene, cam, sky, win, lines, pulses, nodes, canvas, bmat;
const WIN = [];

const SKY_FRAG = /* glsl */ `
precision highp float;
varying vec2 vUv;
uniform vec3 top, mid, bot;
uniform float cells, starA, seed;
float b2(vec2 a) { a = floor(a); return fract(a.x / 2.0 + a.y * a.y * 0.75); }
float bayer(vec2 a) { return b2(0.5 * a) * 0.25 + b2(a); }
float h(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7)) + seed) * 43758.5453); }
void main() {
  vec2 q = floor(vUv * vec2(cells, cells * 0.5));
  float y = (q.y + 0.5) / (cells * 0.5);
  float steps = 7.0;
  float g = floor(y * steps + bayer(q) - 0.5) / steps;
  vec3 c = g < 0.5 ? mix(bot, mid, clamp(g * 2.0, 0.0, 1.0)) : mix(mid, top, clamp(g * 2.0 - 1.0, 0.0, 1.0));
  float s = step(0.992, h(q)) * starA * smoothstep(0.35, 0.8, y);
  gl_FragColor = vec4(c + vec3(s), 1.0);
}`;

// Sky palettes by hour (top, mid, bottom)
const SKIES = [
  [0, ["#070b24", "#141a44", "#2a1d4a"]],
  [5.5, ["#1b1f4d", "#6b3b6e", "#e0875c"]],
  [7.5, ["#3d78c9", "#84b4e6", "#f2d6a2"]],
  [12, ["#2f6fcf", "#6fa8ea", "#bfe0f7"]],
  [17.3, ["#3b4f9a", "#d4786a", "#f6c27a"]],
  [18.8, ["#1a1a4a", "#5a2f6a", "#b8566a"]],
  [21, ["#070b24", "#141a44", "#2a1d4a"]],
  [24, ["#070b24", "#141a44", "#2a1d4a"]],
];
function skyAt(hour) {
  let i = 0;
  while (i < SKIES.length - 2 && SKIES[i + 1][0] <= hour) i++;
  const [h0, a] = SKIES[i], [h1, b] = SKIES[i + 1];
  const k = clamp((hour - h0) / (h1 - h0));
  return a.map((c, j) => new THREE.Color(c).lerp(new THREE.Color(b[j]), k));
}

function box(w, h, d, color, x, y, z, parent) {
  const m = new THREE.Mesh(new THREE.BoxGeometry(w, h, d), new THREE.MeshStandardMaterial({ color, roughness: 0.8 }));
  m.position.set(x, y + h / 2, z);
  parent.add(m);
  return m;
}

export function initCampus() {
  canvas = document.createElement("canvas");
  canvas.width = 1200;
  canvas.height = 560;
  canvas.style.display = "block";
  R = new THREE.WebGLRenderer({ canvas, antialias: true, preserveDrawingBuffer: true });
  R.setPixelRatio(1);
  R.setSize(1200, 560, false);
  R.outputColorSpace = THREE.SRGBColorSpace;
  scene = new THREE.Scene();
  cam = new THREE.PerspectiveCamera(30, 1200 / 560, 0.1, 200);

  sky = new THREE.Mesh(new THREE.PlaneGeometry(160, 60), new THREE.ShaderMaterial({
    uniforms: { top: { value: new THREE.Color() }, mid: { value: new THREE.Color() }, bot: { value: new THREE.Color() }, cells: { value: 150 }, starA: { value: 1 }, seed: { value: 3 } },
    vertexShader: "varying vec2 vUv; void main(){ vUv = uv; gl_Position = projectionMatrix * modelViewMatrix * vec4(position,1.0); }",
    fragmentShader: SKY_FRAG, depthWrite: false,
  }));
  sky.position.set(0, 18, -40);
  scene.add(sky);
  scene.add(new THREE.HemisphereLight(0xb8c4ff, 0x3a2020, 0.9));
  const sun = new THREE.DirectionalLight(0xffe0b8, 1.1);
  sun.position.set(-8, 12, 10);
  scene.add(sun);
  scene.userData.sun = sun;

  // ground + road
  const ground = new THREE.Mesh(new THREE.PlaneGeometry(200, 60), new THREE.MeshStandardMaterial({ color: 0x2a3a30, roughness: 1 }));
  ground.rotation.x = -Math.PI / 2;
  scene.add(ground);
  const road = new THREE.Mesh(new THREE.PlaneGeometry(200, 3.2), new THREE.MeshStandardMaterial({ color: 0x24252b, roughness: 1 }));
  road.rotation.x = -Math.PI / 2;
  road.position.set(0, 0.01, 6.5);
  scene.add(road);
  for (let i = -30; i < 30; i++) {
    const dash = new THREE.Mesh(new THREE.PlaneGeometry(1.1, 0.12), new THREE.MeshBasicMaterial({ color: 0xc9a227 }));
    dash.rotation.x = -Math.PI / 2;
    dash.position.set(i * 2.2, 0.02, 6.5);
    scene.add(dash);
  }

  // the main building: two long wings, a taller centre block, the pylon + flag
  const B = new THREE.Group();
  scene.add(B);
  const maroon = 0x6d1224, maroonD = 0x4a0c18, trim = 0xc9a227;
  box(12, 3.2, 3, maroon, -8.5, 0, 0, B);
  box(12, 3.2, 3, maroon, 8.5, 0, 0, B);
  box(12.2, 0.18, 3.1, trim, -8.5, 3.2, 0, B);
  box(12.2, 0.18, 3.1, trim, 8.5, 3.2, 0, B);
  box(5.2, 5, 3.6, maroonD, 0, 0, 0.2, B);
  box(5.4, 0.2, 3.7, trim, 0, 5, 0.2, B);
  box(2.2, 1.3, 2.2, maroonD, 0, 5.2, 0.2, B);
  const pylon = box(0.55, 7.2, 0.55, 0x8d8a92, 0, 0, 2.6, B);
  const cap = new THREE.Mesh(new THREE.ConeGeometry(0.42, 0.9, 4), new THREE.MeshStandardMaterial({ color: trim, emissive: 0x6a4a00 }));
  cap.position.set(0, 7.65, 2.6);
  B.add(cap);
  box(0.06, 3, 0.06, 0xdddddd, 1.5, 6.5, 0.2, B);
  box(0.9, 0.5, 0.02, 0xc0283a, 1.97, 9.0, 0.2, B);
  // columns on the centre block
  for (let i = -2; i <= 2; i++) box(0.22, 3.4, 0.22, 0xbcb3a6, i * 0.9, 0, 2.05, B);
  // trees
  for (const x of [-16.5, -15, 15, 16.8]) {
    box(0.3, 1.4, 0.3, 0x4a3326, x, 0, 1, B);
    const c = new THREE.Mesh(new THREE.SphereGeometry(1.0, 8, 6), new THREE.MeshStandardMaterial({ color: 0x1f4a33, flatShading: true }));
    c.position.set(x, 2.2, 1);
    B.add(c);
  }
  // windows: instanced quads on the wing fronts
  const wg = new THREE.PlaneGeometry(0.42, 0.62);
  const positions = [];
  for (const side of [-1, 1]) {
    for (let r = 0; r < 3; r++) {
      for (let c = 0; c < 14; c++) positions.push([side * (3.4 + c * 0.78), 0.55 + r * 0.95, 1.52]);
    }
  }
  for (let r = 0; r < 4; r++) for (let c = 0; c < 4; c++) positions.push([-1.8 + c * 1.2, 0.8 + r * 1.05, 2.02]);
  bmat = new THREE.MeshBasicMaterial({ color: 0xffffff, toneMapped: false });
  win = new THREE.InstancedMesh(wg, bmat, positions.length);
  const o = new THREE.Object3D();
  positions.forEach((p, i) => {
    o.position.set(...p);
    o.updateMatrix();
    win.setMatrixAt(i, o.matrix);
    WIN.push({ p, r: hash(i, 77), r2: hash(i, 78) });
  });
  win.instanceColor = new THREE.InstancedBufferAttribute(new Float32Array(positions.length * 3), 3);
  B.add(win);

  // network: light-lines from a few windows up to sky nodes
  nodes = Array.from({ length: 9 }, (_, i) => new THREE.Vector3((i - 4) * 5.5 + (hash(i, 5) - 0.5) * 3, 12 + hash(i, 6) * 6, -8 - hash(i, 7) * 6));
  lines = new THREE.Group();
  pulses = [];
  const pick = [3, 17, 30, 45, 58, 70, 84, 88, 95];
  pick.forEach((wi, i) => {
    const a = new THREE.Vector3(...WIN[wi % WIN.length].p);
    const b = nodes[i];
    const mid = a.clone().lerp(b, 0.5).add(new THREE.Vector3(0, 4, 0));
    const curve = new THREE.QuadraticBezierCurve3(a, mid, b);
    const g = new THREE.BufferGeometry().setFromPoints(curve.getPoints(40));
    const l = new THREE.Line(g, new THREE.LineBasicMaterial({ color: 0xf5b227, transparent: true, opacity: 0.35, toneMapped: false }));
    lines.add(l);
    const p = new THREE.Mesh(new THREE.PlaneGeometry(0.28, 0.28), new THREE.MeshBasicMaterial({ color: 0xffe7a8, toneMapped: false, transparent: true }));
    lines.add(p);
    pulses.push({ curve, p, off: hash(i, 9), line: l });
  });
  // node pips + links between neighbours
  nodes.forEach((n, i) => {
    const pip = new THREE.Mesh(new THREE.PlaneGeometry(0.36, 0.36), new THREE.MeshBasicMaterial({ color: 0xf5b227, toneMapped: false }));
    pip.position.copy(n);
    lines.add(pip);
    if (i < nodes.length - 1) {
      const g = new THREE.BufferGeometry().setFromPoints([n, nodes[i + 1]]);
      lines.add(new THREE.Line(g, new THREE.LineBasicMaterial({ color: 0xf5b227, transparent: true, opacity: 0.18 })));
    }
  });
  scene.add(lines);
}

/**
 * Paint the campus at time t (s), time-of-day `hour`, with `next` = the lit
 * next-class window index. `net` 0..1 shows the network lines. Returns canvas.
 */
export function renderCampus(t, { hour = 7, net = 1, camX = 0, camZ = 30, fov = 30, aspect = 1200 / 560, w = 1200, h = 560, next = 12 } = {}) {
  if (canvas.width !== w || canvas.height !== h) R.setSize(w, h, false);
  const [top, mid, bot] = skyAt(hour);
  const u = sky.material.uniforms;
  u.top.value.copy(top); u.mid.value.copy(mid); u.bot.value.copy(bot);
  const night = hour < 6 || hour > 18.5 ? 1 : hour < 7 ? 1 - (hour - 6) : hour > 17.5 ? hour - 17.5 : 0;
  u.starA.value = clamp(night);
  scene.userData.sun.intensity = lerp(1.2, 0.25, clamp(night));
  // windows: warm lit at night, glassy by day; the next class window pulses gold
  const col = new THREE.Color();
  WIN.forEach((wd, i) => {
    const lit = wd.r < lerp(0.18, 0.62, clamp(night)) || i === next;
    if (i === next) col.set("#ffc23d").multiplyScalar(1.2 + 0.4 * Math.sin(t * 6));
    else if (lit) col.set("#ffd98a").multiplyScalar(0.8 + 0.2 * wd.r2);
    else col.set(night > 0.5 ? "#1b1422" : "#7aa4c9").multiplyScalar(0.8);
    win.setColorAt(i, col);
  });
  win.instanceColor.needsUpdate = true;
  // network pulses
  lines.visible = net > 0.001;
  pulses.forEach((P) => {
    const k = (t * 0.35 + P.off) % 1;
    P.p.position.copy(P.curve.getPoint(k));
    P.p.quaternion.copy(cam.quaternion);
    P.p.material.opacity = net * Math.sin(k * Math.PI);
    P.line.material.opacity = 0.32 * net;
  });
  lines.children.forEach((c) => {
    if (c.material && c.type === "Mesh" && !pulses.find((p) => p.p === c)) c.material.opacity = net;
  });
  cam.aspect = aspect;
  cam.fov = fov;
  cam.updateProjectionMatrix();
  cam.position.set(camX, 4.2, camZ);
  cam.lookAt(camX * 0.6, 4.4, 0);
  R.render(scene, cam);
  return canvas;
}

export function campusCanvas() {
  return canvas;
}
