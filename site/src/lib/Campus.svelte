<script lang="ts">
  // The app's campus scene, drawn live by the app's own renderer at the
  // visitor's hour (051 C6). A campus picker swaps the scene.
  import { onMount } from "svelte";
  import { build } from "$app_lib/campus/paint";
  import { startStrip, type Strip } from "$app_lib/campus/render";
  import { loadScene } from "$app_lib/campus/scenes";
  import { litWindow } from "$app_lib/campus/sky";

  let { campus = "Sta. Mesa" }: { campus?: string } = $props();
  let cv: HTMLCanvasElement;
  let strip: Strip | null = null;
  let label = $state("PUP Sta. Mesa");

  async function show(name: string) {
    const built = build(await loadScene(name));
    const lit = litWindow("COMP 20073", built.windows);
    label = `PUP ${name}`;
    if (strip) strip.set(built, lit);
    else strip = startStrip(cv, built, { lit, hour: () => null });
  }

  onMount(() => () => strip?.stop());
  $effect(() => {
    if (cv) void show(campus);
  });
</script>

<div class="scene" role="img" aria-label="{label}, drawn in pixels at this hour, with a jeepney passing">
  <canvas bind:this={cv} width="192" height="80"></canvas>
</div>

<style>
  .scene {
    position: relative;
    overflow: hidden;
    /* The sky fades into the page's night, so the scene has no top edge. */
    mask-image: linear-gradient(to bottom, transparent 0, #000 22%);
    -webkit-mask-image: linear-gradient(to bottom, transparent 0, #000 22%);
  }
  /* 060 C10: whole-number scales only (192 px wide art), so every pixel stays square. */
  canvas {
    display: block;
    width: 768px;
    height: auto;
    margin-left: 50%;
    transform: translateX(-50%);
    image-rendering: pixelated;
    /* Where the viewport outgrows the scene, its sides fade into the night. */
    mask-image: linear-gradient(90deg, transparent, #000 8%, #000 92%, transparent);
    -webkit-mask-image: linear-gradient(90deg, transparent, #000 8%, #000 92%, transparent);
  }
  @media (min-width: 900px) {
    canvas {
      width: 960px;
    }
  }
  @media (min-width: 1152px) {
    canvas {
      width: 1152px;
    }
  }
</style>
