// The portal as a 3D scene, rendered small and scaled up so it stays pixel
// art. Ported from the film rig (intportal-films/lib/portal3d.js): obsidian
// blocks on a platform holding the Portal.metal swirl with depth. Here the
// frame is the pentomino ring from pentomino.ts, each piece five joined
// blocks that drop in and lock. render(state) paints one frame from
// nothing but `state`.
import * as THREE from "three";
import { FRAME, PIECES, type Cell } from "./pentomino";

export const SWIRL_PUP = ["#170509", "#540a1c", "#941c30", "#cca128", "#faebb3"];
const OBSIDIAN = { base: "#170b1a", hi: "#3a2446", lo: "#060307", fleck: "#4a2c58" };

export const clamp = (x: number, a = 0, b = 1) => Math.min(b, Math.max(a, x));
export const lerp = (a: number, b: number, p: number) => a + (b - a) * p;
/** Closed-form damped spring, 0 to 1, `t` seconds after it started. */
export function spring(t: number, k = 170, d = 26) {
  if (t <= 0) return 0;
  const w0 = Math.sqrt(k);
  const z = d / (2 * w0);
  if (z < 1) {
    const wd = w0 * Math.sqrt(1 - z * z);
    return 1 - Math.exp(-z * w0 * t) * (Math.cos(wd * t) + ((z * w0) / wd) * Math.sin(wd * t));
  }
  return 1 - Math.exp(-w0 * t) * (1 + w0 * t);
}
/** Seeded PRNG (mulberry32), so the flecks and motes never shimmer between frames. */
export function rng(seed: number) {
  return () => {
    seed = (seed + 0x6d2b79f5) | 0;
    let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

/** Where a frame cell sits in the world: one unit per block, bottom row on the platform. */
export const cellAt = ([c, r]: Cell) => new THREE.Vector3(c - (FRAME.cols - 1) / 2, FRAME.rows - 1 - r + 0.5, 0);
/** The opening's centre and size, inside the two-block ring. */
export const OPENING = {
  w: FRAME.cols - 2 * FRAME.thick,
  h: FRAME.rows - 2 * FRAME.thick,
  y: FRAME.thick + (FRAME.rows - 2 * FRAME.thick) / 2,
};

const SWIRL_VERT = /* glsl */ `
varying vec2 vUv;
void main() { vUv = uv; gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0); }`;

// Portal.metal's swirl with the shipped five-tone Bayer dither.
const SWIRL_FRAG = /* glsl */ `
precision highp float;
varying vec2 vUv;
uniform float uTime, uSpeed, uLit, uAspect, uScale, uAlpha, uFlash, uDepth;
uniform vec3 c0, c1, c2, c3, c4;
float h(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float n(vec2 p) { vec2 i = floor(p), f = fract(p); f = f * f * (3.0 - 2.0 * f);
  return mix(mix(h(i), h(i + vec2(1, 0)), f.x), mix(h(i + vec2(0, 1)), h(i + vec2(1, 1)), f.x), f.y); }
float fbm(vec2 p) { float v = 0.0, a = 0.5; for (int k = 0; k < 5; k++) { v += a * n(p); p *= 2.03; a *= 0.5; } return v; }
float b2(vec2 a) { a = floor(a); return fract(a.x / 2.0 + a.y * a.y * 0.75); }
float bayer(vec2 a) { return b2(0.5 * a) * 0.25 + b2(a); }
void main() {
  vec2 uv = (vUv - 0.5) * vec2(uAspect, 1.0) * uScale;
  float t = uTime;
  float d = length(uv * vec2(1.25, 0.8));
  float a = atan(uv.y, uv.x) + t * 0.28 * uSpeed + d * 5.5 + uDepth * 1.7;
  vec2 q = vec2(cos(a), sin(a)) * d * 2.4;
  float v = fbm(q * 2.2 + vec2(uDepth * 3.1, -t * 0.5 * uSpeed));
  v += 0.22 * sin(uv.x * 16.0 + fbm(uv * 3.0 + t * 0.25 * uSpeed) * 7.0 + t * 1.6 * uSpeed);
  // Three arms wind into the core, so it reads as a vortex at rest.
  float arms = sin(atan(uv.y, uv.x) * 3.0 - log(d + 0.03) * 4.0 - t * 1.3 * uSpeed);
  v = mix(v, 0.5 + 0.5 * arms, 0.45 * smoothstep(0.8, 0.1, d));
  v = clamp(v * 0.95 + (0.55 - d) * 0.55 + max(0.0, 0.16 - d) * 2.6, 0.0, 1.0);
  // The rim falls into shadow, so the opening reads as a tunnel, not a curtain.
  float edge = min(min(vUv.x, 1.0 - vUv.x) * uAspect, min(vUv.y, 1.0 - vUv.y));
  if (uDepth < 0.5) v *= mix(0.25, 1.0, smoothstep(0.0, 0.16, edge));
  v *= smoothstep(uLit * 1.3, uLit * 1.3 - 0.35, d / uScale) * (0.35 + 0.65 * uLit);
  float k = clamp(floor(v * 4.0 + bayer(gl_FragCoord.xy) - 0.5), 0.0, 4.0);
  vec3 col = k < 0.5 ? c0 : k < 1.5 ? c1 : k < 2.5 ? c2 : k < 3.5 ? c3 : c4;
  col = mix(col, c4, uFlash * uFlash * uFlash);
  gl_FragColor = vec4(col, uAlpha);
}`;

// The front layer and the back wall, both stencil-masked to the opening.
const DEPTHS = [0.05, 4];
function swirlMaterial(layer: number) {
  const uniforms: Record<string, THREE.IUniform> = {
    uTime: { value: 0 },
    uSpeed: { value: 1 },
    uLit: { value: 1 },
    uAspect: { value: OPENING.w / OPENING.h },
    uScale: { value: 1 },
    uAlpha: { value: 1 },
    uFlash: { value: 0 },
    uDepth: { value: layer },
  };
  SWIRL_PUP.forEach((c, i) => (uniforms[`c${i}`] = { value: new THREE.Color(c) }));
  const back = layer === 1;
  return new THREE.ShaderMaterial({
    uniforms,
    vertexShader: SWIRL_VERT,
    fragmentShader: SWIRL_FRAG,
    toneMapped: false,
    transparent: !back,
    depthWrite: back,
    depthTest: false,
    stencilWrite: true,
    stencilRef: 1,
    stencilFunc: THREE.EqualStencilFunc,
  });
}

/**
 * One block's face: obsidian with flecks, and a bevel drawn only on the
 * sides that don't touch another block of the same piece, so each piece
 * reads as one joined shape.
 */
function blockTextures(seed: number, tint: number, open: { top: boolean; left: boolean; bottom: boolean; right: boolean }) {
  const r = rng(seed);
  const S = 16;
  const map = document.createElement("canvas");
  const em = document.createElement("canvas");
  map.width = map.height = em.width = em.height = S;
  const g = map.getContext("2d")!;
  const e = em.getContext("2d")!;
  // Each piece is its own shade of obsidian, so the puzzle reads.
  g.fillStyle = `#${new THREE.Color(OBSIDIAN.base).lerp(new THREE.Color(OBSIDIAN.hi), tint / 100).getHexString()}`;
  g.fillRect(0, 0, S, S);
  e.fillStyle = "#000";
  e.fillRect(0, 0, S, S);
  g.fillStyle = "#5a3a6c";
  if (open.top) g.fillRect(0, 0, S, 2);
  if (open.left) g.fillRect(0, 0, 2, S);
  g.fillStyle = OBSIDIAN.lo;
  if (open.bottom) g.fillRect(0, S - 2, S, 2);
  if (open.right) g.fillRect(S - 2, 0, 2, S);
  for (let i = 0; i < 4; i++) {
    const x = 2 + Math.floor(r() * 11);
    const y = 2 + Math.floor(r() * 11);
    const w = 1 + Math.floor(r() * 2);
    g.fillStyle = e.fillStyle = OBSIDIAN.fleck;
    g.fillRect(x, y, w, w);
    e.fillRect(x, y, w, w);
  }
  const tex = (c: HTMLCanvasElement) => {
    const t = new THREE.CanvasTexture(c);
    t.magFilter = THREE.NearestFilter;
    t.minFilter = THREE.NearestFilter;
    t.colorSpace = THREE.SRGBColorSpace;
    return t;
  };
  return { map: tex(map), emissiveMap: tex(em) };
}

function buildFrame() {
  const group = new THREE.Group();
  // Square blocks: the joins inside a piece vanish, only its outline is drawn.
  const geo = new THREE.BoxGeometry(1, 1, 1);
  const pieces = PIECES.map((p, i) => {
    const piece = new THREE.Group();
    const own = new Set(p.cells.map(([c, r]) => `${c},${r}`));
    const centre = p.cells.reduce((a, cell) => a.add(cellAt(cell)), new THREE.Vector3()).divideScalar(5);
    const mats: THREE.MeshPhysicalMaterial[] = [];
    for (const [c, r] of p.cells) {
      const { map, emissiveMap } = blockTextures(i * 10 + c * 31 + r, [0, 22, 10, 30, 5, 16][i % 6], {
        top: !own.has(`${c},${r - 1}`),
        bottom: !own.has(`${c},${r + 1}`),
        left: !own.has(`${c - 1},${r}`),
        right: !own.has(`${c + 1},${r}`),
      });
      const mat = new THREE.MeshPhysicalMaterial({
        map,
        emissiveMap,
        emissive: new THREE.Color(OBSIDIAN.fleck),
        emissiveIntensity: 0.9,
        roughness: 0.32,
        metalness: 0.15,
        clearcoat: 0.7,
        clearcoatRoughness: 0.25,
      });
      mats.push(mat);
      const m = new THREE.Mesh(geo, mat);
      m.position.copy(cellAt([c, r])).sub(centre);
      piece.add(m);
    }
    piece.userData = { home: centre, mats };
    group.add(piece);
    return piece;
  });

  const mask = new THREE.Mesh(
    new THREE.PlaneGeometry(OPENING.w, OPENING.h),
    new THREE.MeshBasicMaterial({
      colorWrite: false,
      depthWrite: false,
      stencilWrite: true,
      stencilRef: 1,
      stencilFunc: THREE.AlwaysStencilFunc,
      stencilZPass: THREE.ReplaceStencilOp,
    }),
  );
  mask.position.set(0, OPENING.y, 0.02);
  mask.renderOrder = 1;
  group.add(mask);
  const layers = DEPTHS.map((depth, L) => {
    const mat = swirlMaterial(L);
    const s = 1 + depth * 0.42;
    mat.uniforms.uScale.value = s;
    const m = new THREE.Mesh(new THREE.PlaneGeometry(OPENING.w * s, OPENING.h * s), mat);
    m.position.set(0, OPENING.y, -depth);
    m.renderOrder = 3 - L;
    group.add(m);
    return m;
  });
  // The swirl lights the platform and the frame's inner faces.
  const light = new THREE.PointLight("#cca128", 0, 16, 1.6);
  light.position.set(0, OPENING.y - 0.4, 1.4);
  group.add(light);
  return { group, pieces, layers, light, geo };
}

function buildPlatform() {
  const g = new THREE.Group();
  const tones = ["#3a2c27", "#33261f", "#41302a", "#2e231e"];
  const r = rng(9);
  const geo = new THREE.BoxGeometry(1.96, 0.7, 1.96);
  for (let i = 0; i < 5; i++)
    for (let j = 0; j < 3; j++) {
      const centre = i === 2 && j === 2;
      const m = new THREE.Mesh(
        geo,
        new THREE.MeshStandardMaterial({ color: centre ? "#5a3f2c" : tones[Math.floor(r() * tones.length)], roughness: 0.92, metalness: 0 }),
      );
      m.position.set(-4 + i * 2, -0.35, -1.5 + j * 2);
      g.add(m);
    }
  return g;
}

export interface Cam {
  x: number;
  y: number;
  z: number;
  tx: number;
  ty: number;
  tz: number;
  fov: number;
}

/** Camera on an orbit around a target: az and el in degrees, dist in units. */
export function orbit(az: number, el: number, dist: number, ty = OPENING.y, fov = 35): Cam {
  const a = (az * Math.PI) / 180;
  const e = (el * Math.PI) / 180;
  return { x: Math.sin(a) * Math.cos(e) * dist, y: ty + Math.sin(e) * dist, z: Math.cos(a) * Math.cos(e) * dist, tx: 0, ty, tz: 0, fov };
}

export interface PortalState {
  /** Seconds, for the swirl and the motes. */
  t: number;
  /** Seconds since the first piece began to fall; null when the frame is already built. */
  form: number | null;
  /** Seconds between pieces starting to fall. */
  gap: number;
  /** 0 to 1: the swirl's ignition, from the core outward. */
  lit: number;
  speed: number;
  /** 0 to 1: a gold-white flash over the swirl. */
  flash: number;
  /** Pixel size of one art pixel, in CSS px. */
  cell: number;
  cam: Cam;
  /** Shifts the picture up the screen (fraction of the height), to leave room below. */
  lift: number;
}

export function createPortalScene(canvas: HTMLCanvasElement) {
  const renderer = new THREE.WebGLRenderer({ canvas, antialias: false, alpha: false, powerPreference: "high-performance" });
  renderer.outputColorSpace = THREE.SRGBColorSpace;
  renderer.toneMapping = THREE.NoToneMapping;

  const scene = new THREE.Scene();
  scene.background = new THREE.Color("#0b0710");
  // Far past the camera: only the back of the platform fades.
  scene.fog = new THREE.Fog("#0b0710", 60, 110);
  scene.add(new THREE.AmbientLight("#3a2440", 2.2));
  const rim = new THREE.DirectionalLight("#8663a8", 3.2);
  rim.position.set(-4, 9, -8);
  const key = new THREE.DirectionalLight("#f4e8d6", 1.6);
  key.position.set(6, 10, 8);
  const front = new THREE.DirectionalLight("#b8a8ff", 1.4);
  front.position.set(-3, 5, 14);
  scene.add(rim, key, front);

  const platform = buildPlatform();
  const frame = buildFrame();
  scene.add(platform, frame.group);

  // Gold motes: seeded, one art pixel each, drifting up.
  const N = 56;
  const r = rng(5);
  const pos = new Float32Array(N * 3);
  const seeds = Array.from({ length: N }, () => [(r() - 0.5) * 22, r() * 16, (r() - 0.5) * 10 - 2, 0.15 + r() * 0.35, r()]);
  const motesGeo = new THREE.BufferGeometry();
  motesGeo.setAttribute("position", new THREE.BufferAttribute(pos, 3));
  const motes = new THREE.Points(motesGeo, new THREE.PointsMaterial({ color: "#f5b227", size: 1, sizeAttenuation: false, transparent: true, opacity: 0.55 }));
  scene.add(motes);

  const camera = new THREE.PerspectiveCamera(35, 1, 0.05, 200);
  // Every frame renders small into this target, then scales up with nearest
  // filtering: that's the pixel look.
  // Half float: an 8-bit target holding linear values rounds the night
  // ground (#0b0710) and the obsidian's deepest purples down to grey.
  const target = new THREE.WebGLRenderTarget(1, 1, {
    magFilter: THREE.NearestFilter,
    minFilter: THREE.NearestFilter,
    stencilBuffer: true,
    type: THREE.HalfFloatType,
  });
  const blitScene = new THREE.Scene();
  const blitMat = new THREE.MeshBasicMaterial({ map: target.texture });
  blitScene.add(new THREE.Mesh(new THREE.PlaneGeometry(2, 2), blitMat));
  const blitCam = new THREE.OrthographicCamera(-1, 1, 1, -1, 0, 1);

  let w = 1;
  let h = 1;
  function resize(cssW: number, cssH: number, dpr: number) {
    w = cssW;
    h = cssH;
    renderer.setPixelRatio(dpr);
    renderer.setSize(cssW, cssH, false);
    // Point sizes scale with the pixel ratio; a mote is one art pixel.
    (motes.material as THREE.PointsMaterial).size = 1 / dpr;
    camera.aspect = cssW / cssH;
  }

  function render(s: PortalState) {
    frame.pieces.forEach((piece, i) => {
      const since = s.form === null ? Infinity : s.form - i * s.gap;
      const land = s.form === null ? 1 : spring(since, 260, 22);
      const { home, mats } = piece.userData as { home: THREE.Vector3; mats: THREE.MeshPhysicalMaterial[] };
      piece.visible = since > 0;
      piece.position.copy(home);
      piece.position.y += (1 - land) * 9;
      piece.rotation.set((1 - land) * 0.5, (1 - land) * 0.8, (1 - land) * (i % 2 ? 0.4 : -0.4));
      // The flecks flare as the piece locks.
      const flare = since > 0.3 && Number.isFinite(since) ? 6 * Math.exp(-(since - 0.3) * 6) : 0;
      for (const m of mats) m.emissiveIntensity = 0.9 + flare;
    });
    frame.layers.forEach((m, L) => {
      const u = (m.material as THREE.ShaderMaterial).uniforms;
      u.uTime.value = s.t;
      u.uSpeed.value = s.speed;
      u.uLit.value = s.lit;
      u.uFlash.value = s.flash;
      u.uAlpha.value = 1;
      m.visible = s.lit > 0.002;
    });
    frame.light.intensity = s.lit * 26 * (1 + s.flash * 3);

    for (let i = 0; i < N; i++) {
      const [x, y0, z, v, ph] = seeds[i];
      pos[i * 3] = x + Math.sin(s.t * 0.4 + ph * 6.28) * 0.3;
      pos[i * 3 + 1] = ((y0 + s.t * v) % 16) - 1;
      pos[i * 3 + 2] = z;
    }
    motesGeo.attributes.position.needsUpdate = true;

    camera.fov = s.cam.fov;
    camera.position.set(s.cam.x, s.cam.y, s.cam.z);
    camera.lookAt(s.cam.tx, s.cam.ty, s.cam.tz);
    // Lift moves the image up the screen without tilting the camera.
    camera.setViewOffset(w, h, 0, s.lift * h, w, h);
    camera.updateProjectionMatrix();

    const cell = Math.max(1, s.cell);
    target.setSize(Math.max(1, Math.round(w / cell)), Math.max(1, Math.round(h / cell)));
    renderer.setRenderTarget(target);
    renderer.render(scene, camera);
    renderer.setRenderTarget(null);
    renderer.render(blitScene, blitCam);
  }

  /** A world point to CSS px on the stage, using the camera from the last render. */
  function project(x: number, y: number, z: number): [number, number, number] {
    const v = new THREE.Vector3(x, y, z).project(camera);
    return [(v.x * 0.5 + 0.5) * w, (-v.y * 0.5 + 0.5) * h, v.z];
  }

  function dispose() {
    scene.traverse((o) => {
      const m = o as THREE.Mesh;
      m.geometry?.dispose();
      const mat = m.material as THREE.Material | THREE.Material[] | undefined;
      for (const x of Array.isArray(mat) ? mat : mat ? [mat] : []) {
        for (const v of Object.values(x)) if (v instanceof THREE.Texture) v.dispose();
        x.dispose();
      }
    });
    target.dispose();
    blitMat.dispose();
    renderer.dispose();
  }

  return { render, resize, project, dispose };
}
