// Shared WebGL renderer on #gl. Scenes render into it in order each seek;
// `cell` > 1 renders at reduced resolution and the canvas is upscaled with
// nearest-neighbour — the warp's pixel growth.
import * as THREE from "three";
import { EffectComposer } from "three/addons/postprocessing/EffectComposer.js";
import { RenderPass } from "three/addons/postprocessing/RenderPass.js";
import { UnrealBloomPass } from "three/addons/postprocessing/UnrealBloomPass.js";
import { OutputPass } from "three/addons/postprocessing/OutputPass.js";

export const W = 1920, H = 1080;
export let renderer;
let cell = 1;
let composer, renderPass, bloom;

export function initGL() {
  const canvas = document.getElementById("gl");
  renderer = new THREE.WebGLRenderer({ canvas, antialias: true, preserveDrawingBuffer: true, alpha: false, powerPreference: "high-performance" });
  renderer.setPixelRatio(1);
  renderer.setSize(W, H, false);
  renderer.autoClear = false;
  renderer.outputColorSpace = THREE.SRGBColorSpace;
  renderer.toneMapping = THREE.ACESFilmicToneMapping;
  renderer.toneMappingExposure = 1.05;
  composer = new EffectComposer(renderer);
  composer.renderToScreen = true;
  renderPass = new RenderPass(new THREE.Scene(), new THREE.PerspectiveCamera());
  renderPass.clear = true;
  bloom = new UnrealBloomPass(new THREE.Vector2(W, H), 0.9, 0.55, 0.62);
  composer.addPass(renderPass);
  composer.addPass(bloom);
  composer.addPass(new OutputPass());
  return renderer;
}

export function beginFrame(c = 1, clear = 0x0a080c) {
  c = Math.max(1, Math.round(c));
  if (c !== cell) {
    cell = c;
    renderer.setSize(Math.round(W / c), Math.round(H / c), false);
    composer.setSize(Math.round(W / c), Math.round(H / c));
  }
  renderer.setClearColor(clear, 1);
  renderer.clear(true, true, true);
}

export function draw(scene, camera) {
  renderer.clearDepth();
  renderer.render(scene, camera);
}

/** Render with bloom (for scenes whose light sources should bloom: swirl, arcs). */
export function drawBloom(scene, camera, { strength = 0.9, radius = 0.55, threshold = 0.62, clear = 0x0a080c } = {}) {
  renderPass.scene = scene;
  renderPass.camera = camera;
  bloom.strength = strength;
  bloom.radius = radius;
  bloom.threshold = threshold;
  scene.background = scene.background ?? new THREE.Color(clear);
  composer.render();
}
