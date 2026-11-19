// Spec 057 C3–C8: the tile portal in Three.js. Loaded only by Hero.svelte with a
// dynamic import, so no other page carries three. Rendered at a third of the
// screen and scaled up nearest-neighbour: one rendered pixel is the app's 3 px
// art pixel, so the blocks read as pixel art with depth, not glossy 3D.
import * as THREE from "three";
import { ACCENT, COLS, RAMP, ROWS, TONES, frameTiles } from "./portal";
import { FORMS, MAX, type Voxel } from "./forms";

export type Hero = {
  stop(): void;
  scroll(p: number): void;
  pointer(x: number, y: number): void;
  /** 059 C1: the sculpture the portal sends out, or none. */
  form(id: string | null): void;
};
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
// The page's own void, and its 26% gold dot blended in sRGB, so the dive ends on
// exactly the ground the page continues with.
const VOID = "#0b0710";
const DOT = "#483416";
const LIGHT = "#fff6dc";
const RIM = "#140b14";
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
  uniform float uPhase;
  uniform float uEnergy;
  uniform float uBreath;
  uniform float uBurst;
  uniform float uDive;
  uniform float uOpen;
  uniform vec3 uRamp[5];
  uniform vec3 uVoid;
  uniform vec3 uGold;
  uniform vec3 uDot;
  varying vec2 vUv;
  const float B[16] = float[16](0.,8.,2.,10.,12.,4.,14.,6.,3.,11.,1.,9.,15.,7.,13.,5.);
  float bayer(vec2 c) { int x = int(mod(c.x, 4.0)); int y = int(mod(c.y, 4.0)); return B[y * 4 + x] / 16.0; }
  void main() {
    vec2 g = vec2(32.0, 48.0) * mix(1.0, 7.0, uDive * uDive);
    vec2 c = floor(vUv * g);
    vec2 q = (c + 0.5) / g - 0.5;
    q.x *= 8.0 / 12.0;
    float r = length(q);
    float a = atan(q.y, q.x);
    float arms = sin(a * 3.0 - r * 14.0 + uPhase * 1.6) * 0.5 + 0.5;
    float v = arms * (1.0 - r * 1.25) + 0.42 * (1.0 - r * 2.1);
    // 059 C3: it breathes, and brightens as the pointer nears or a sculpture leaves it.
    v += uBreath * 0.06 + uEnergy * 0.16 * (1.0 - r * 1.6);
    // 059 C5: the kawoosh, a bright ring running out to the frame as it opens.
    if (uBurst >= 0.0) v += 0.95 * exp(-pow((r - uBurst) * 13.0, 2.0)) * (1.0 - uBurst * 1.4);
    float ring = fract(0.16 / (r + 0.03) - uTime * 0.7 - uDive * 4.0);
    float tun = (1.0 - abs(ring - 0.5) * 2.0) * (1.0 - r * 0.9) + 0.2;
    v = mix(v, max(v * 0.55, tun), smoothstep(0.08, 0.45, uDive));
    float d = bayer(c);
    int idx = int(clamp(floor(v * 4.6 + d - 0.5), 0.0, 4.0));
    vec3 col = uRamp[idx];
    if (d >= uOpen) col = uVoid;
    // The end (C6): a dither break. Screen pixels leave the swirl in Bayer order and
    // land on the page's ground: a 3 px gold dot every 15 px (5 rendered px) on the void.
    float e = smoothstep(0.62, 0.95, uDive);
    vec2 px = floor(gl_FragCoord.xy);
    vec2 sp = mod(px, 5.0);
    float on = step(sp.x, 0.5) * step(sp.y, 0.5);
    vec3 ground = mix(uVoid, uDot, on);
    if (bayer(floor(px / 2.0)) < e) col = ground;
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

// 059 C4: motes spiral into the mouth on slow inward paths and are reborn at the
// rim, worked out in the vertex shader from a seed, so the CPU does nothing.
const moteVert = /* glsl */ `
  attribute vec3 aSeed;
  uniform float uTime;
  uniform float uStay;
  varying float vLife;
  varying float vPale;
  void main() {
    float life = fract(aSeed.y + uTime * (0.05 + aSeed.z * 0.06));
    float rad = mix(4.6, 0.25, life * life);
    float ang = aSeed.x + life * 5.5;
    vec3 p = vec3(cos(ang) * rad * 0.66, sin(ang) * rad, 0.15 + (1.0 - life) * 0.9);
    vLife = life;
    vPale = step(0.7, aSeed.z);
    gl_Position = projectionMatrix * modelViewMatrix * vec4(p, 1.0);
    gl_PointSize = (aSeed.z > 0.85 ? 2.0 : 1.0) * uStay;
  }
`;
const moteFrag = /* glsl */ `
  uniform vec3 uGold;
  uniform vec3 uPale;
  varying float vLife;
  varying float vPale;
  const float B[16] = float[16](0.,8.,2.,10.,12.,4.,14.,6.,3.,11.,1.,9.,15.,7.,13.,5.);
  void main() {
    // Born and swallowed through the dither, never a soft fade.
    float fade = smoothstep(0.0, 0.12, vLife) * (1.0 - smoothstep(0.82, 1.0, vLife));
    ivec2 c = ivec2(mod(gl_FragCoord.xy, 4.0));
    if (B[c.y * 4 + c.x] / 16.0 >= fade) discard;
    gl_FragColor = vec4(mix(uGold, uPale, vPale), 1.0);
    #include <colorspace_fragment>
  }
`;

/** A sculpture voxel: a cube with pre-shaded faces, like the frame's tiles. */
function voxelGeometry() {
  const geo = new THREE.BoxGeometry(0.62, 0.62, 0.62);
  const shade = [0.62, 0.9, 1.15, 0.5, 1, 0.55];
  const colors: number[] = [];
  for (const s of shade) for (let i = 0; i < 4; i++) colors.push(s, s, s);
  geo.setAttribute("color", new THREE.Float32BufferAttribute(colors, 3));
  return geo;
}

/** A damped spring from 0 to 1 with a little overshoot, for a voxel springing into place. */
const spring = (u: number) => (u <= 0 ? 0 : 1 - Math.exp(-5.5 * u) * Math.cos(7.5 * u));

const VOX = 0.7;
const IN_SPAN = 0.55;
const IN_DUR = 0.4;
const OUT_DUR = 0.35;

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
    uPhase: { value: 0 },
    uEnergy: { value: 0 },
    uBreath: { value: 0 },
    uBurst: { value: -1 },
    uDive: { value: 0 },
    uOpen: { value: 0 },
    uRamp: { value: RAMP.map((h) => new THREE.Color(h)) },
    uVoid: { value: new THREE.Color(VOID) },
    uGold: { value: new THREE.Color(GOLD) },
    uDot: { value: new THREE.Color(DOT) },
  };
  const mouth = new THREE.Mesh(new THREE.PlaneGeometry(COLS - 4, ROWS - 4), new THREE.ShaderMaterial({ vertexShader: vert, fragmentShader: frag, uniforms }));
  mouth.position.z = -0.3;
  portal.add(mouth);

  // 059 C4: the motes.
  const MOTES = 40;
  const seeds = new Float32Array(MOTES * 3);
  for (let i = 0; i < MOTES; i++) seeds.set([Math.random() * Math.PI * 2, i / MOTES, Math.random()], i * 3);
  const moteGeo = new THREE.BufferGeometry();
  moteGeo.setAttribute("position", new THREE.BufferAttribute(new Float32Array(MOTES * 3), 3));
  moteGeo.setAttribute("aSeed", new THREE.BufferAttribute(seeds, 3));
  const moteUniforms = { uTime: { value: 0 }, uStay: { value: 1 }, uGold: { value: new THREE.Color(GOLD) }, uPale: { value: new THREE.Color(RAMP[4]) } };
  const motes = new THREE.Points(moteGeo, new THREE.ShaderMaterial({ vertexShader: moteVert, fragmentShader: moteFrag, uniforms: moteUniforms }));
  motes.frustumCulled = false;
  portal.add(motes);

  // 059 C1: the sculpture, one instanced mesh of at most MAX voxels.
  const sculpt = new THREE.Group();
  sculpt.position.set(0, 2.6, 1.6);
  portal.add(sculpt);
  const vox = new THREE.InstancedMesh(voxelGeometry(), new THREE.MeshBasicMaterial({ vertexColors: true }), MAX);
  vox.count = 0;
  vox.frustumCulled = false;
  sculpt.add(vox);
  // A one-pixel obsidian outline, so gold voxels read against the gold swirl: the
  // same voxels a little larger, back faces only, drawn behind them.
  const rim = new THREE.InstancedMesh(new THREE.BoxGeometry(0.62, 0.62, 0.62), new THREE.MeshBasicMaterial({ color: RIM, side: THREE.BackSide }), MAX);
  rim.count = 0;
  rim.frustumCulled = false;
  sculpt.add(rim);
  const ramp = RAMP.map((h) => new THREE.Color(h));
  const grow = new THREE.Vector3(1.32, 1.32, 1.32);
  // Where each voxel comes from: the mouth's centre, in the sculpture's space.
  const origin = new THREE.Vector3(0, -sculpt.position.y, -sculpt.position.z - 0.3);
  let shown: Voxel[] = [];
  let wanted: Voxel[] | null = null;
  let tIn = -9;
  let tOut = -9;
  let kick = 0;
  function order(v: Voxel[]) {
    // Out of the mouth bottom first, then left to right, back to front.
    return [...v].sort((a, b) => a.y - b.y || a.x - b.x || a.z - b.z);
  }
  function setForm(id: string | null, t: number) {
    const next = id && FORMS[id] ? order(FORMS[id].voxels) : [];
    if (!shown.length) {
      shown = next;
      tIn = t;
      kick = shown.length ? 1 : kick;
      wanted = null;
      return;
    }
    wanted = next;
    if (tOut < tIn) tOut = t;
  }

  // 059 C6: where the pointer meets the portal, in its own space.
  const ray = new THREE.Raycaster();
  const ndc = new THREE.Vector2();
  const plane = new THREE.Plane();
  const hit = new THREE.Vector3();
  const normal = new THREE.Vector3();
  const lift = new Float32Array(tiles.length);
  let pointerSeen = false;

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
  let pending: string | null | undefined = undefined;
  let phase = 0;
  let energy = 0;
  // 059 C9: a phone draws at most 30 frames a second.
  const coarse = matchMedia("(pointer: coarse)").matches;

  const io = new IntersectionObserver(([e]) => (visible = e.isIntersecting));
  io.observe(canvas);

  function frame(now: number) {
    raf = requestAnimationFrame(frame);
    if (!visible || document.hidden) {
      last = now;
      return;
    }
    if (coarse && now - last < 32) return;
    const dt = now - last;
    last = now;
    const t = (now - t0) / 1000;
    if (pending !== undefined) {
      setForm(pending, t);
      pending = undefined;
    }
    if (t > 1.5) {
      // A single long stall (sleep, a tab restore) counts at most 250 ms, so only a run
      // of slow frames trips it; any good frame resets the run.
      slow = dt > 40 ? slow + Math.min(dt, 250) : 0;
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
    // 059 C6: the pointer on the portal plane, in tile units.
    let lx = 1e9;
    let ly = 1e9;
    if (pointerSeen && dive < 0.05) {
      ndc.set(px, -py);
      ray.setFromCamera(ndc, camera);
      normal.set(0, 0, 1).applyQuaternion(portal.quaternion);
      plane.setFromNormalAndCoplanarPoint(normal, portal.position);
      if (ray.ray.intersectPlane(plane, hit)) {
        portal.worldToLocal(hit);
        lx = hit.x;
        ly = hit.y;
      }
    }
    const near = Math.max(0, 1 - Math.hypot(lx, ly * 0.75) / 7);
    // 059 C7: as the dive starts, the frame opens like an iris, outer ring first.
    const iris = smooth(0.02, 0.4, dive);
    for (let i = 0; i < tiles.length; i++) {
      const tile = tiles[i];
      const tx = tile.x - COLS / 2 + 0.5;
      const ty = tile.y - ROWS / 2 + 0.5;
      const d = Math.hypot(tx - lx, ty - ly);
      const want = d < 2.5 ? 0.5 * (1 - (d / 2.5) ** 2) : 0;
      lift[i] += (want - lift[i]) * 0.14;
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
      if (k >= 1 && lift[i] > 0.12) col = tone[Math.min(3, toneOf[i] + 1)];
      const out = 1 + iris * (0.25 + (tile.x === 0 || tile.x === COLS - 1 || tile.y === 0 || tile.y === ROWS - 1 ? 0.2 : 0));
      m.makeScale(s, s, s).setPosition(tx * out, ty * out, lift[i] + iris * 0.6);
      mesh.setMatrixAt(i, m);
      mesh.setColorAt(i, col);
    }
    mesh.instanceMatrix.needsUpdate = true;
    if (mesh.instanceColor) mesh.instanceColor.needsUpdate = true;

    // 059 C3: breath, and energy from the pointer's nearness and a sculpture leaving.
    kick *= Math.exp(-dt / 600);
    energy += (Math.min(1, near + kick) - energy) * 0.06;
    phase += (dt / 1000) * (1 + energy * 0.8);
    uniforms.uTime.value = t;
    uniforms.uPhase.value = phase;
    uniforms.uEnergy.value = energy;
    uniforms.uBreath.value = Math.sin((t * Math.PI * 2) / 5);
    const opened = SPAWN + 0.15;
    uniforms.uBurst.value = t > opened && t < opened + 0.6 ? (t - opened) / 0.6 * 0.62 : -1;
    uniforms.uOpen.value = smooth(SPAWN + 0.15, SPAWN + 0.15 + OPEN, t) * 1.0001;
    uniforms.uDive.value = dive;
    moteUniforms.uTime.value = t;

    // The dive (C6): the camera flies into the mouth as the page scrolls.
    const e = smooth(0, 1, dive);
    const stay = 1 - smooth(0, 0.55, dive);
    camera.position.set(0, 0, THREE.MathUtils.lerp(fitD, 0.9, Math.pow(e, 0.8)));
    portal.position.set(fitX * stay, fitY * stay, 0);
    rx += (py * 0.1 * stay - rx) * 0.06;
    ry += (px * 0.14 * stay - ry) * 0.06;
    portal.rotation.set(rx, ry, 0);
    moteUniforms.uStay.value = stay;

    // 059 C1: the sculpture goes back in, last voxel first, then the next comes out.
    if (wanted && tOut >= tIn && t - tOut > OUT_DUR + 0.05) {
      shown = wanted;
      wanted = null;
      tIn = t;
      if (shown.length) kick = 1;
    }
    const n = shown.length;
    const leaving = tOut >= tIn;
    // 059 C7: the sculpture is back in the mouth before the camera gets close.
    const gone = 1 - smooth(0, 0.18, dive);
    for (let i = 0; i < n; i++) {
      const v = shown[i];
      let p: number;
      let sc: number;
      let arc: number;
      if (leaving) {
        const u = Math.min(1, Math.max(0, (t - tOut - (1 - i / n) * 0.2) / 0.15));
        p = 1 - u * u * (3 - 2 * u);
        sc = p;
        arc = 0;
      } else {
        const u = (t - tIn - (i / n) * IN_SPAN) / IN_DUR;
        p = spring(u);
        sc = Math.min(1, Math.max(0, u * 3));
        arc = Math.sin(Math.PI * Math.min(1, Math.max(0, u))) * 1.2;
      }
      sc *= gone;
      m.makeScale(sc, sc, sc).setPosition(
        origin.x + (v.x * VOX - origin.x) * p,
        origin.y + (v.y * VOX - origin.y) * p,
        origin.z + (v.z * VOX - origin.z) * p + arc,
      );
      vox.setMatrixAt(i, m);
      vox.setColorAt(i, ramp[v.tone]);
      m.scale(grow);
      rim.setMatrixAt(i, m);
    }
    vox.count = rim.count = n;
    if (n) {
      vox.instanceMatrix.needsUpdate = true;
      rim.instanceMatrix.needsUpdate = true;
      if (vox.instanceColor) vox.instanceColor.needsUpdate = true;
    }
    sculpt.rotation.y = Math.sin(t * 0.5) * 0.44;
    sculpt.position.y = 2.6 + Math.sin(t * 1.3) * 0.15;

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
    vox.dispose();
    rim.dispose();
    renderer.dispose();
    renderer.forceContextLoss();
  }

  canvas.addEventListener("webglcontextlost", (e) => {
    e.preventDefault();
    stop();
    opts.onSlow();
  });

  return {
    stop,
    scroll: (p) => (dive = Math.min(1, Math.max(0, p))),
    pointer: (x, y) => ((px = x), (py = y), (pointerSeen = true)),
    form: (id) => (pending = id),
  };
}
