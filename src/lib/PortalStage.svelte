<script lang="ts">
  // The landing's stage: the 3D pixel portal, LAR coming through it, and the
  // three stones he pulls out of the swirl. Everything is drawn from one
  // moment of the landing timeline (landing.ts) plus a little drag parallax.
  // Without WebGL the portal falls back to a flat pixel drawing.
  import { onMount } from "svelte";
  import Lar, { type Gesture } from "./lar/Lar.svelte";
  import type { Mood } from "./lar/sprite";
  import PixelIcon, { type SpriteName } from "./PixelIcon.svelte";
  import { PIECE_GAP, type Moment } from "./landing";
  import { FRAME, PIECES } from "./pentomino";
  import { OPENING, SWIRL_PUP, clamp, createPortalScene, lerp, orbit, spring, type Cam } from "./portal3d";

  let {
    moment,
    t,
    lift,
    span = 15,
    mood,
    gesture,
    still = false,
  }: { moment: Moment; t: number; lift: number; span?: number; mood: Mood; gesture: Gesture; still?: boolean } = $props();

  // Art pixels are this many CSS px, for the portal and for LAR alike.
  const CELL = 3;
  const STONES: { name: string; icon: SpriteName; at: [number, number, number] }[] = [
    { name: "Schedule", icon: "schedule", at: [-5.4, 8.6, 0.6] },
    { name: "Grades", icon: "grades", at: [5.5, 9.4, 0.4] },
    { name: "Study", icon: "study", at: [5.1, 4.2, 1.2] },
  ];

  let host: HTMLDivElement;
  let canvas: HTMLCanvasElement;
  let fallback = $state(false);
  let scene: ReturnType<typeof createPortalScene> | null = null;
  let lar = $state({ x: 0, y: 0, scale: 0, spin: 0, show: false });
  let stones = $state(STONES.map(() => ({ x: 0, y: 0, k: 0 })));

  // Drag sways the camera a few degrees; it eases back when you let go.
  let drag = 0;
  let sway = 0;
  let from: number | null = null;
  const down = (e: PointerEvent) => (from = e.clientX - drag * 6);
  const move = (e: PointerEvent) => from !== null && (drag = clamp((e.clientX - from) / 6, -10, 10));
  const up = () => {
    from = null;
    drag = 0;
  };

  // Far enough back that `span` world units fit the screen's width.
  let aspect = 0.46;
  const fit = (fov: number) => span / (2 * Math.tan((fov * Math.PI) / 360) * Math.min(aspect, 0.75));

  function camFor(m: Moment, now: number): Cam {
    sway = lerp(sway, drag, 0.12);
    const idle = Math.sin(now * 0.25) * 6;
    const d = fit(35);
    const rest = orbit(idle + sway, 9, d);
    if (m.phase === "dark" || m.phase === "assembling") {
      // Start a little wide and low, settle in as the frame builds.
      const k = spring(m.form ?? 9, 30, 11);
      return orbit(lerp(-24, idle, k), lerp(4, 9, k), lerp(d * 1.25, d, k));
    }
    if (m.phase !== "stepping" && m.phase !== "entered") return rest;
    // The dive: straight into the swirl, widening as we pass through.
    const k = m.phase === "entered" ? 1 : m.k * m.k;
    return {
      x: lerp(rest.x, 0, k),
      y: lerp(rest.y, OPENING.y, k),
      z: lerp(rest.z, -1.5, k),
      tx: 0,
      ty: OPENING.y,
      tz: lerp(0, -8, k),
      fov: lerp(35, 80, k),
    };
  }

  function draw() {
    const m = moment;
    const lit = m.phase === "dark" || m.phase === "assembling" ? 0 : m.phase === "igniting" ? spring(m.k * 0.7, 60, 13) : 1;
    const diving = m.phase === "stepping" ? m.k : m.phase === "entered" ? 1 : 0;
    const flash = m.phase === "igniting" ? Math.max(0, 1 - Math.abs(m.k - 0.85) * 6) * 0.6 : diving > 0.7 ? (diving - 0.7) / 0.3 : 0;
    if (scene) {
      scene.render({
        t,
        form: m.form,
        gap: PIECE_GAP,
        lit,
        speed: 1 + diving * 8,
        flash,
        cell: CELL + diving * diving * 21,
        cam: camFor(m, t),
        lift: lift * (1 - diving),
      });
    }
    place(m);
  }

  // LAR and the stones are DOM, pinned to points in the scene.
  function place(m: Moment) {
    const at = (x: number, y: number, z: number) => scene?.project(x, y, z) ?? flatAt(x, y);
    const arrive = m.phase === "arrival" ? m.k : ["glimpse", "rest", "stepping", "entered"].includes(m.phase) ? 1 : 0;
    const e = spring(arrive * 1.2, 120, 13);
    const [x, y] = at(0, lerp(OPENING.y, 0.15, e), lerp(-1, 2.4, e));
    lar = { x, y, scale: lerp(0.15, 1, clamp(e)), spin: (1 - clamp(arrive * 1.6)) * 540, show: arrive > 0 && m.phase !== "entered" };
    const out = m.phase === "glimpse" ? m.k : ["rest", "stepping"].includes(m.phase) ? 1 : 0;
    stones = STONES.map((s, i) => {
      const k = clamp(spring(out * 1.4 - i * 0.12, 140, 16));
      const bob = still ? 0 : Math.sin(t * 1.3 + i * 2) * 0.18;
      const [sx, sy] = at(lerp(0, s.at[0], k), lerp(OPENING.y, s.at[1] + bob, k), lerp(-0.5, s.at[2], k));
      return { x: sx, y: sy, k };
    });
  }

  // Without WebGL: the frame and a still swirl drawn flat, at the same pixel size.
  let flatBox = { x: 0, y: 0, unit: 0 };
  function flatAt(x: number, y: number): [number, number, number] {
    return [flatBox.x + (x + FRAME.cols / 2) * flatBox.unit, flatBox.y + (FRAME.rows - y) * flatBox.unit, 0];
  }
  function drawFlat(w: number, h: number) {
    const ctx = canvas.getContext("2d");
    if (!ctx) return;
    const cols = Math.round(w / CELL);
    const rows = Math.round(h / CELL);
    canvas.width = cols;
    canvas.height = rows;
    ctx.fillStyle = "#0b0710";
    ctx.fillRect(0, 0, cols, rows);
    const unit = Math.floor(Math.min(cols * 0.62, rows * 0.5) / FRAME.cols);
    const ox = Math.round((cols - unit * FRAME.cols) / 2);
    const oy = Math.round(rows * (0.46 - lift) - unit * FRAME.rows * 0.5);
    flatBox = { x: ox * CELL, y: oy * CELL, unit: unit * CELL };
    for (let j = 0; j < (FRAME.rows - 4) * unit; j++)
      for (let i = 0; i < (FRAME.cols - 4) * unit; i++) {
        const dx = i / ((FRAME.cols - 4) * unit) - 0.5;
        const dy = j / ((FRAME.rows - 4) * unit) - 0.5;
        const v = clamp(0.95 - Math.hypot(dx * 1.2, dy) * 1.6 + Math.sin(Math.atan2(dy, dx) * 2 + Math.hypot(dx, dy) * 9) * 0.18 + ((i * 7 + j * 13) % 4) * 0.04);
        ctx.fillStyle = SWIRL_PUP[Math.min(4, Math.floor(v * 5))];
        ctx.fillRect(ox + 2 * unit + i, oy + 2 * unit + j, 1, 1);
      }
    PIECES.forEach((p, n) => {
      for (const [c, r] of p.cells) {
        ctx.fillStyle = n % 2 ? "#1c0f20" : "#170b1a";
        ctx.fillRect(ox + c * unit, oy + r * unit, unit, unit);
        ctx.fillStyle = "#3a2446";
        ctx.fillRect(ox + c * unit, oy + r * unit, unit, 1);
      }
    });
  }

  onMount(() => {
    try {
      scene = createPortalScene(canvas);
    } catch {
      fallback = true;
    }
    const fit = () => {
      const { width, height } = host.getBoundingClientRect();
      aspect = width / Math.max(1, height);
      if (scene) scene.resize(width, height, Math.min(devicePixelRatio, 3));
      else drawFlat(width, height);
    };
    const ro = new ResizeObserver(fit);
    ro.observe(host);
    fit();
    return () => {
      ro.disconnect();
      scene?.dispose();
      scene = null;
    };
  });

  $effect(() => {
    void moment;
    void t;
    draw();
  });
</script>

<div class="stage" bind:this={host} onpointerdown={down} onpointermove={move} onpointerup={up} onpointercancel={up} role="presentation">
  <canvas bind:this={canvas} class:flat={fallback} aria-hidden="true"></canvas>
  {#each STONES as s, i (s.name)}
    {@const p = stones[i]}
    <span class="stone" style:transform="translate({p.x}px, {p.y}px) translate(-50%, -50%) scale({0.4 + p.k * 0.6})" style:opacity={p.k}>
      <span class="face" class:east={s.at[0] < 0}>
        <PixelIcon name={s.icon} size={18} accent="#f5b227" />
        <span>{s.name}</span>
      </span>
    </span>
  {/each}
  {#if lar.show}
    <span class="lar" style:transform="translate({lar.x}px, {lar.y}px) translate(-50%, -100%) rotate({lar.spin}deg) scale({lar.scale})">
      <Lar size={CELL} {mood} {gesture} />
    </span>
  {/if}
</div>

<style>
  .stage {
    position: absolute;
    inset: 0;
    overflow: hidden;
    background: #0b0710;
    touch-action: pan-y;
  }
  canvas {
    display: block;
    width: 100%;
    height: 100%;
  }
  canvas.flat {
    image-rendering: pixelated;
  }
  .lar,
  .stone {
    position: absolute;
    top: 0;
    left: 0;
    pointer-events: none;
    transform-origin: 0 0;
  }
  .lar {
    transform-origin: 50% 100%;
  }
  /* The shadow sits on the unclipped wrapper; clip-path would cut it off the face. */
  .stone {
    filter: drop-shadow(0 6px 8px rgb(0 0 0 / 0.5));
  }
  /* A slab of the frame's own obsidian: flecks, a lit top edge, and the
     swirl's warm light on the side that faces the portal. */
  .face {
    display: grid;
    justify-items: center;
    gap: 3px;
    padding: 8px 9px 6px;
    background:
      linear-gradient(to left, rgb(148 28 48 / 0.32), transparent 60%),
      radial-gradient(circle at 30% 40%, #4a2c58 1.5px, transparent 2px) 0 0 / 13px 11px,
      radial-gradient(circle at 70% 70%, #4a2c58 1px, transparent 1.5px) 5px 3px / 17px 13px,
      #170b1a;
    box-shadow:
      inset 0 3px 0 #5a3a6c,
      inset 0 -3px 0 #060307;
    font-family: var(--font-pixel);
    font-size: min(0.647rem, 14px);
    letter-spacing: 0.04em;
    color: #f4e8d6;
    clip-path: polygon(0 3px, 3px 3px, 3px 0, calc(100% - 3px) 0, calc(100% - 3px) 3px, 100% 3px, 100% calc(100% - 3px), calc(100% - 3px) calc(100% - 3px), calc(100% - 3px) 100%, 3px 100%, 3px calc(100% - 3px), 0 calc(100% - 3px));
  }
  .face.east {
    background:
      linear-gradient(to right, rgb(148 28 48 / 0.32), transparent 60%),
      radial-gradient(circle at 30% 40%, #4a2c58 1.5px, transparent 2px) 0 0 / 13px 11px,
      radial-gradient(circle at 70% 70%, #4a2c58 1px, transparent 1.5px) 5px 3px / 17px 13px,
      #170b1a;
  }
  /* Motes drift under the status bar, not across the clock. */
  .stage::after {
    content: "";
    position: absolute;
    inset: 0 0 auto;
    height: calc(var(--safe-top) + 8px);
    background: linear-gradient(#0b0710 70%, transparent);
    pointer-events: none;
  }
</style>
