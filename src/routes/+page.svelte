<script lang="ts">
  import { invoke } from "@tauri-apps/api/core";
  import {
    isPermissionGranted,
    requestPermission,
    sendNotification,
  } from "@tauri-apps/plugin-notification";
  import { onMount } from "svelte";

  // S1 spike: can a phone webview hold a full-screen pixel scene at 60 fps,
  // and do the keychain and local notifications work from Tauri?
  const W = 180;
  const H = 320;

  let canvas: HTMLCanvasElement;
  let fps = $state(0);
  let hourOverride = $state<number | null>(null);
  let log = $state<string[]>([]);

  const say = (m: string) => (log = [m, ...log].slice(0, 6));

  type Stop = [number, string, string];
  // Sky top and horizon colours through the day.
  const skies: Stop[] = [
    [0, "#0b1030", "#1b2350"],
    [5, "#23284f", "#a0566b"],
    [7, "#5aa0d8", "#f2c38a"],
    [12, "#4b92d6", "#b8dcf2"],
    [17, "#3d5a9a", "#f09a5b"],
    [19, "#1c2150", "#7a4a78"],
    [21, "#0b1030", "#1b2350"],
  ];

  function sky(h: number): [string, string, boolean] {
    let s = skies[0];
    for (const x of skies) if (h >= x[0]) s = x;
    return [s[1], s[2], h < 5 || h >= 19];
  }

  function rect(g: CanvasRenderingContext2D, c: string, x: number, y: number, w: number, h: number) {
    g.fillStyle = c;
    g.fillRect(x | 0, y | 0, w | 0, h | 0);
  }

  const stars = Array.from({ length: 40 }, (_, i) => [(i * 67) % W, (i * 37) % 140, i % 3]);

  function draw(g: CanvasRenderingContext2D, t: number) {
    const now = new Date();
    const h = hourOverride ?? now.getHours() + now.getMinutes() / 60;
    const [top, horizon, night] = sky(h);

    const grad = g.createLinearGradient(0, 0, 0, 200);
    grad.addColorStop(0, top);
    grad.addColorStop(1, horizon);
    g.fillStyle = grad;
    g.fillRect(0, 0, W, 200);

    if (night) {
      for (const [x, y, k] of stars) {
        if ((Math.floor(t / 400) + k) % 5) rect(g, "#f4ecc8", x, y, 1, 1);
      }
    }

    // Main building: maroon block, gold trim, rows of windows.
    rect(g, "#5a1a1a", 20, 140, 140, 70);
    rect(g, "#c9a227", 20, 138, 140, 2);
    rect(g, "#6d2323", 70, 118, 40, 22);
    const lit = Math.floor(t / 900) % 12;
    for (let r = 0; r < 3; r++) {
      for (let c = 0; c < 8; c++) {
        const on = night ? (r * 8 + c) % 5 === 0 : false;
        const next = r === 1 && c === 5;
        const col = next ? (lit % 2 ? "#ffd75e" : "#f2b233") : on ? "#e8c46a" : "#2b1010";
        rect(g, col, 28 + c * 16, 150 + r * 18, 8, 10);
      }
    }

    // Obelisk.
    rect(g, "#d9d2c0", 86, 60, 8, 80);
    rect(g, "#d9d2c0", 88, 54, 4, 6);

    // Ground and lagoon.
    rect(g, "#3c6b3a", 0, 210, W, 30);
    rect(g, night ? "#1d2c55" : "#3f7fb0", 0, 240, W, 80);
    for (let i = 0; i < 12; i++) {
      const x = ((i * 29 + t / 60) % (W + 20)) - 10;
      rect(g, night ? "#34497a" : "#8fc3e6", x, 250 + ((i * 13) % 60), 6, 1);
    }

    // Jeepney crossing the road.
    const jx = ((t / 25) % (W + 60)) - 40;
    rect(g, "#b3202a", jx, 222, 30, 10);
    rect(g, "#e6e0cf", jx + 3, 224, 20, 4);
    rect(g, "#c9a227", jx, 220, 30, 2);
    rect(g, "#1a1a1a", jx + 4, 232, 5, 4);
    rect(g, "#1a1a1a", jx + 21, 232, 5, 4);
  }

  onMount(() => {
    const g = canvas.getContext("2d")!;
    g.imageSmoothingEnabled = false;
    let frames = 0;
    let last = performance.now();
    let raf = 0;
    const loop = (t: number) => {
      draw(g, t);
      frames++;
      if (t - last >= 1000) {
        fps = Math.round((frames * 1000) / (t - last));
        frames = 0;
        last = t;
      }
      raf = requestAnimationFrame(loop);
    };
    raf = requestAnimationFrame(loop);
    return () => cancelAnimationFrame(raf);
  });

  async function keychain() {
    try {
      say(await invoke<string>("keychain_roundtrip"));
    } catch (e) {
      say(`keychain failed: ${e}`);
    }
  }

  async function notify() {
    let ok = await isPermissionGranted();
    if (!ok) ok = (await requestPermission()) === "granted";
    if (!ok) return say("notifications: permission denied");
    sendNotification({ title: "COMP 20073 in 10 min", body: "Data Structures · Room S501" });
    say("notification sent");
  }
</script>

<main>
  <canvas bind:this={canvas} width={W} height={H}></canvas>
  <div class="hud">
    <span class="fps" class:bad={fps > 0 && fps < 55}>{fps} fps</span>
    <label>
      hour
      <input type="range" min="0" max="23.9" step="0.5"
        value={hourOverride ?? new Date().getHours()}
        oninput={(e) => (hourOverride = +e.currentTarget.value)} />
    </label>
    <div class="row">
      <button onclick={keychain}>Keychain</button>
      <button onclick={notify}>Notify</button>
    </div>
    {#each log as line}<p>{line}</p>{/each}
  </div>
</main>

<style>
  :global(html, body) {
    margin: 0;
    height: 100%;
    background: #0b1030;
    color: #f4ecc8;
    font-family: "Source Sans 3", system-ui, sans-serif;
  }
  main {
    position: fixed;
    inset: 0;
  }
  canvas {
    width: 100%;
    height: 100%;
    object-fit: cover;
    image-rendering: pixelated;
  }
  .hud {
    position: absolute;
    left: 16px;
    right: 16px;
    bottom: calc(16px + env(safe-area-inset-bottom));
    background: rgba(20, 8, 8, 0.8);
    border: 2px solid #c9a227;
    clip-path: polygon(6px 0, calc(100% - 6px) 0, 100% 6px, 100% calc(100% - 6px), calc(100% - 6px) 100%, 6px 100%, 0 calc(100% - 6px), 0 6px);
    padding: 12px;
  }
  .fps {
    font-variant-numeric: tabular-nums;
    font-weight: 700;
  }
  .bad {
    color: #ff7a6b;
  }
  label {
    display: flex;
    gap: 8px;
    align-items: center;
    margin: 8px 0;
  }
  input {
    flex: 1;
  }
  .row {
    display: flex;
    gap: 8px;
  }
  button {
    flex: 1;
    min-height: 44px;
    background: #5a1a1a;
    color: #f4ecc8;
    border: 2px solid #c9a227;
    font: inherit;
    font-weight: 600;
  }
  p {
    margin: 4px 0 0;
    font-size: 13px;
  }
</style>
