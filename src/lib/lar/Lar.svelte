<script lang="ts" module>
  import { app } from "../state.svelte";
  import { SIS, THEMES, type Theme } from "./sprite";

  export type Gesture = "idle" | "wave" | "point" | "reach" | "thumbs";

  /** The colours of the portal the student uses: Mabini's when it is the only one connected. */
  export const larTheme = (): Theme => (app.mabiniConnected && !app.sisConnected ? THEMES.mabini : SIS);
</script>

<script lang="ts">
  // LAR on screen: one canvas, drawn by drawLar (sprite.ts) from his pose for
  // the state he is in. A rig eases every change of state, so nothing pops.
  // He wears the colours of the student's portal unless given a `theme`.
  // Pass `t` to drive him from a timeline; without it he keeps his own
  // clock. Reduce Motion holds him in a still pose.
  import { onMount } from "svelte";
  import { BOX, H, W, drawLar, rig, type Mood, type State } from "./sprite";

  let {
    size = 4,
    mood,
    gesture = "idle",
    state: mode = "idle",
    theme,
    vx,
    vy,
    t: driven,
    cube = true,
    fit = false,
    label = "LAR, the Lakbay-Aral Robot",
  }: {
    size?: number;
    /** Overrides the face his state would wear. */
    mood?: Mood;
    gesture?: Gesture;
    state?: State;
    /** A portal's ramp and accent; defaults to the portal the student uses. */
    theme?: Theme;
    /** Fly velocity in sprite px per second. */
    vx?: number;
    vy?: number;
    t?: number;
    cube?: boolean;
    /** Take up the room his cube, mitts and glow reach, so a box round him never clips them. */
    fit?: boolean;
    label?: string;
  } = $props();

  const reduce = typeof matchMedia !== "undefined" && matchMedia("(prefers-reduced-motion: reduce)").matches;
  let own = $state(0);
  const t = $derived(driven ?? (reduce ? 0 : own));
  const look = $derived(theme ?? larTheme());

  onMount(() => {
    if (driven !== undefined || reduce) return;
    let raf = 0;
    const start = performance.now();
    const frame = (now: number) => {
      own = (now - start) / 1000;
      raf = requestAnimationFrame(frame);
    };
    raf = requestAnimationFrame(frame);
    return () => cancelAnimationFrame(raf);
  });

  // [dx, dy, rot] per mitt, in sprite pixels from where it floats.
  const GEST: Record<Gesture, [number, number, number][]> = {
    idle: [[0, 0, 0], [0, 0, 0]],
    wave: [[0, 0, 0], [3, -12, -30]],
    point: [[0, 0, 0], [9, -6, -20]],
    reach: [[-3, -10, -30], [3, -10, 30]],
    thumbs: [[0, 0, 0], [3, -7, 0]],
  };

  // Starts idle, so a first state of error or spawn plays its entrance.
  const r = rig();
  let canvas: HTMLCanvasElement;
  const BW = BOX.x1 - BOX.x0;
  const BH = BOX.y1 - BOX.y0;

  $effect(() => {
    const now = t;
    const o = { vx, vy };
    r.set(mode, now, o);
    const p = r.at(now, o, reduce);
    if (mood && mood !== "open") p.mood = mood;
    p.mitts.forEach((m, i) => {
      const [dx, dy, rot] = GEST[gesture][i];
      m.x += dx;
      m.y += dy;
      m.rot += rot + (gesture === "wave" && i === 1 ? Math.sin(now * 9) * 28 : 0);
      if (gesture === "thumbs" && i === 1) m.kind = "thumb";
    });
    const dpr = Math.min(3, devicePixelRatio || 1);
    const s = size * dpr;
    const w = Math.round(BW * s);
    const h = Math.round(BH * s);
    if (canvas.width !== w || canvas.height !== h) {
      canvas.width = w;
      canvas.height = h;
    }
    const ctx = canvas.getContext("2d")!;
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.clearRect(0, 0, w, h);
    ctx.setTransform(s, 0, 0, s, -BOX.x0 * s, -BOX.y0 * s);
    drawLar(ctx, p, look, now, { cube });
  });
</script>

<span class="lar" class:fit role="img" aria-label={label} style:width="{(fit ? BW : W) * size}px" style:height="{(fit ? BH : H) * size}px" style:--s="{size}px">
  <canvas bind:this={canvas} style:left="{fit ? 0 : BOX.x0 * size}px" style:top="{fit ? 0 : BOX.y0 * size}px" style:width="{BW * size}px" style:height="{BH * size}px"></canvas>
</span>

<style>
  /* The mitts float 5 sprite pixels past the body on each side. */
  .lar {
    position: relative;
    display: inline-block;
    flex: none;
    margin-inline: calc(var(--s) * 5);
  }
  .lar.fit {
    margin-inline: 0;
  }
  canvas {
    position: absolute;
    pointer-events: none;
    image-rendering: pixelated;
  }
</style>
