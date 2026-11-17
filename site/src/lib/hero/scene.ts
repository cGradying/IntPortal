// Spec 057 C3–C8: the tile portal in Three.js. Loaded only by Hero.svelte with a
// dynamic import, so no other page carries three. Rendered at a third of the
// screen and scaled up nearest-neighbour: one rendered pixel is the app's 3 px
// art pixel, so the blocks read as pixel art with depth, not glossy 3D.
import * as THREE from "three";
import { ACCENT, COLS, RAMP, ROWS, TONES, frameTiles } from "./portal";

export type Hero = { stop(): void; scroll(p: number): void; pointer(x: number, y: number): void };
type Opts = {
  /** The box the still portal fills; the 3D frame is fitted to it so the swap never jumps. */
  box: HTMLElement;
  onFirst: () => void;
  /** Frames stayed over 40 ms for a second (C8): fall back to the still. */
  onSlow: () => void;
};

const SCALE = 3;
const FOV = 30;
const SPAWN = 0.6;
const POP = 0.1;
const OPEN = 0.7;
const VOID = "#060607";
const LIGHT = "#fff6dc";
const GOLD = "#f5b227";

const smooth = (a: number, b: number, x: number) => {
  const t = Math.min(1, Math.max(0, (x - a) / (b - a)));
  return t * t * (3 - 2 * t);
};

const vert = /* glsl */ `
  varying vec2 vUv;
  void main() { vUv = uv; gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0); }
`;

// The mouth: the SIS swirl through a 4x4 Bayer dither (C4). Diving, its pitch
// gets finer, rings rush out of the centre, and at the end every cell flares
// gold and shrinks to a dot (C6).
const frag = /* glsl */ `
  uniform float uTime;
  uniform float uDive;
  uniform float uOpen;
  uniform vec3 uRamp[5];
  uniform vec3 uVoid;
  uniform vec3 uGold;
  varying vec2 vUv;
  const float B[16] = float[16](0.,8.,2.,10.,12.,4.,14.,6.,3.,11.,1.,9.,15.,7.,13.,5.);
  float bayer(vec2 c) { int x = int(mod(c.x, 4.0)); int y = int(mod(c.y, 4.0)); return B[y * 4 + x] / 16.0; }
  void main() {
    vec2 g = vec2(32.0, 48.0) * mix(1.0, 7.0, uDive * uDive) * mix(1.0, 3.0, smoothstep(0.7, 1.0, uDive));
    vec2 c = floor(vUv * g);
    vec2 q = (c + 0.5) / g - 0.5;
    q.x *= 8.0 / 12.0;
    float r = length(q);
    float a = atan(q.y, q.x);
    float arms = sin(a * 3.0 - r * 14.0 + uTime * 1.6) * 0.5 + 0.5;
    float v = arms * (1.0 - r * 1.25) + 0.42 * (1.0 - r * 2.1);
    float ring = fract(0.16 / (r + 0.03) - uTime * 0.7 - uDive * 4.0);
    float tun = (1.0 - abs(ring - 0.5) * 2.0) * (1.0 - r * 0.9) + 0.2;
    v = mix(v, max(v * 0.55, tun), smoothstep(0.08, 0.45, uDive));
    float d = bayer(c);
    int idx = int(clamp(floor(v * 4.6 + d - 0.5), 0.0, 4.0));
    vec3 col = uRamp[idx];
    if (d >= uOpen) col = uVoid;
    float e = smoothstep(0.72, 0.97, uDive);
    vec2 f = abs(fract(vUv * g) - 0.5);
    // Each cell flares gold, then settles to the page's faint dot as it shrinks.
    col = mix(col, uGold, smoothstep(0.0, 0.4, e) * (1.0 - smoothstep(0.5, 1.0, e)));
    col = mix(col, mix(uVoid, uGold, 0.22), smoothstep(0.55, 1.0, e));
    if (max(f.x, f.y) > 0.5 * (1.0 - e * 0.8)) col = mix(col, uVoid, smoothstep(0.0, 0.15, e));
    gl_FragColor = vec4(col, 1.0);
    #include <colorspace_fragment>
  }
`;

/** A tile: a box whose faces are pre-shaded, lit from the top left, multiplied by its tone. */
function tileGeometry() {
  const geo = new THREE.BoxGeometry(0.8, 0.8, 1.2);
  // BoxGeometry faces: +x, -x, +y, -y, +z, -z, four vertices each.
  const shade = [0.55, 0.85, 1.2, 0.45, 1, 0.5];
  const colors: number[] = [];
  for (const s of shade) for (let i = 0; i < 4; i++) colors.push(s, s, s);
  geo.setAttribute("color", new THREE.Float32BufferAttribute(colors, 3));
  return geo;
}

function stars(count: number, spread: number, z: number, size: number, alpha: number) {
  const pos = new Float32Array(count * 3);
  for (let i = 0; i < count; i++) {
    pos[i * 3] = (Math.random() - 0.5) * spread;
    pos[i * 3 + 1] = (Math.random() - 0.5) * spread * 0.7;
    pos[i * 3 + 2] = z - Math.random() * 10;
  }
  const geo = new THREE.BufferGeometry();
  geo.setAttribute("position", new THREE.BufferAttribute(pos, 3));
  const mat = new THREE.PointsMaterial({ color: "#f4ecd8", size, sizeAttenuation: false, transparent: true, opacity: alpha });
  return new THREE.Points(geo, mat);
}

export function start(canvas: HTMLCanvasElement, opts: Opts): Hero {
  const renderer = new THREE.WebGLRenderer({ canvas, antialias: false, alpha: true, powerPreference: "high-performance" });
  renderer.setPixelRatio(1 / SCALE);
  renderer.setClearColor(0x000000, 0);

  const scene = new THREE.Scene();
  const camera = new THREE.PerspectiveCamera(FOV, 1, 0.1, 200);
  const portal = new THREE.Group();
  scene.add(portal);

  // The frame (C3): one instanced box per tile.
  const tiles = frameTiles();
  const mesh = new THREE.InstancedMesh(tileGeometry(), new THREE.MeshBasicMaterial({ vertexColors: true }), tiles.length);
  const tone = TONES.map((h) => new THREE.Color(h));
  const light = new THREE.Color(LIGHT);
  const accent = new THREE.Color(ACCENT);
  const m = new THREE.Matrix4();
  const flips = new Float64Array(tiles.length).fill(-9);
  const toneOf = tiles.map((t) => t.tone);
  portal.add(mesh);

  // The mouth (C4).
  const uniforms = {
    uTime: { value: 0 },
    uDive: { value: 0 },
    uOpen: { value: 0 },
    uRamp: { value: RAMP.map((h) => new THREE.Color(h)) },
    uVoid: { value: new THREE.Color(VOID) },
    uGold: { value: new THREE.Color(GOLD) },
  };
  const mouth = new THREE.Mesh(new THREE.PlaneGeometry(COLS - 4, ROWS - 4), new THREE.ShaderMaterial({ vertexShader: vert, fragmentShader: frag, uniforms }));
  mouth.position.z = -0.3;
  portal.add(mouth);

  // Stars in three layers, drifting at three speeds.
  const layers = [stars(70, 90, -20, 1, 0.35), stars(40, 110, -35, 1, 0.5), stars(18, 130, -50, 2, 0.6)];
  layers.forEach((l) => scene.add(l));

  let fitD = 40;
  let fitX = 0;
  let fitY = 0;
  function fit() {
    const w = canvas.clientWidth;
    const h = canvas.clientHeight;
    if (!w || !h) return;
    renderer.setSize(w, h, false);
    camera.aspect = w / h;
    camera.updateProjectionMatrix();
    const b = opts.box.getBoundingClientRect();
    const c = canvas.getBoundingClientRect();
    // The frame is ROWS units tall; place the camera so it is the box's height.
    const unit = ROWS / b.height;
    fitD = (h * unit) / (2 * Math.tan((FOV * Math.PI) / 360));
    fitX = (b.left + b.width / 2 - (c.left + w / 2)) * unit;
    fitY = -(b.top + b.height / 2 - (c.top + h / 2)) * unit;
  }
  const ro = new ResizeObserver(fit);
  ro.observe(canvas);
  fit();

  let dive = 0;
  let px = 0;
  let py = 0;
  let rx = 0;
  let ry = 0;
  let raf = 0;
  let visible = true;
  let last = performance.now();
  const t0 = last;
  let slow = 0;
  let first = true;
  let nextFlip = 0;

  const io = new IntersectionObserver(([e]) => (visible = e.isIntersecting));
  io.observe(canvas);

  function frame(now: number) {
    raf = requestAnimationFrame(frame);
    if (!visible || document.hidden) {
      last = now;
      return;
    }
    const dt = now - last;
    last = now;
    const t = (now - t0) / 1000;
    if (t > 1.5) {
      // A single long stall (sleep, a tab restore) is not slowness: only frames between
      // 40 and 250 ms count, and any good frame resets the run.
      slow = dt > 40 && dt < 250 ? slow + dt : dt >= 250 ? slow : 0;
      if (slow > 1000) {
        stop();
        opts.onSlow();
        return;
      }
    }

    // Spawn: each tile pops light core, accent, then its tone (C3); later a
    // few flip tone with a short shrink (C4).
    if (t > SPAWN + 0.5 && t > nextFlip) {
      const i = Math.floor(Math.random() * tiles.length);
      flips[i] = t;
      nextFlip = t + 0.35 + Math.random() * 0.6;
    }
    for (let i = 0; i < tiles.length; i++) {
      const tile = tiles[i];
      const k = (t - tile.order * SPAWN) / POP;
      let s = 1;
      let col = tone[toneOf[i]];
      if (k < 0) s = 0;
      else if (k < 1 / 3) (s = 0.45), (col = light);
      else if (k < 2 / 3) (s = 0.8), (col = accent);
      const f = t - flips[i];
      if (f >= 0 && f < 0.3) {
        s *= 0.82;
        if (f > 0.15 && f - dt / 1000 <= 0.15) toneOf[i] = (toneOf[i] + 1) % 4;
      }
      m.makeScale(s, s, s).setPosition(tile.x - COLS / 2 + 0.5, tile.y - ROWS / 2 + 0.5, 0);
      mesh.setMatrixAt(i, m);
      mesh.setColorAt(i, col);
    }
    mesh.instanceMatrix.needsUpdate = true;
    if (mesh.instanceColor) mesh.instanceColor.needsUpdate = true;

    uniforms.uTime.value = t;
    uniforms.uOpen.value = smooth(SPAWN + 0.15, SPAWN + 0.15 + OPEN, t) * 1.0001;
    uniforms.uDive.value = dive;

    // The dive (C6): the camera flies into the mouth as the page scrolls.
    const e = smooth(0, 1, dive);
    const stay = 1 - smooth(0, 0.55, dive);
    camera.position.set(0, 0, THREE.MathUtils.lerp(fitD, 0.9, Math.pow(e, 0.8)));
    portal.position.set(fitX * stay, fitY * stay, 0);
    rx += (py * 0.1 * stay - rx) * 0.06;
    ry += (px * 0.14 * stay - ry) * 0.06;
    portal.rotation.set(rx, ry, 0);

    layers.forEach((l, i) => {
      l.position.x = ((l.position.x + (dt / 1000) * (0.4 + i * 0.5) + 60) % 120) - 60;
      l.position.z = e * (14 + i * 10);
    });

    renderer.render(scene, camera);
    if (first) {
      first = false;
      opts.onFirst();
    }
  }
  raf = requestAnimationFrame(frame);

  let stopped = false;
  function stop() {
    if (stopped) return;
    stopped = true;
    cancelAnimationFrame(raf);
    ro.disconnect();
    io.disconnect();
    scene.traverse((o) => {
      const m = o as THREE.Mesh;
      m.geometry?.dispose();
      (Array.isArray(m.material) ? m.material : m.material ? [m.material] : []).forEach((x) => x.dispose());
    });
    mesh.dispose();
    renderer.dispose();
    renderer.forceContextLoss();
  }

  canvas.addEventListener("webglcontextlost", () => {
    stop();
    opts.onSlow();
  });

  return {
    stop,
    scroll: (p) => (dive = Math.min(1, Math.max(0, p))),
    pointer: (x, y) => ((px = x), (py = y)),
  };
}
