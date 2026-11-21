<script lang="ts">
  // The living campus: the student's campus as a 192x80 pixel scene, drawn by a
  // fragment shader (campus/render.ts). The sky follows the real hour, the next
  // class is a lit window, a jeepney passes now and then, at a stepped 12 fps.
  import { onMount } from "svelte";
  import { api } from "./api";
  import { app } from "./state.svelte";
  import { gateName } from "./ownClass";
  import { refreshCampus, resolveCampus, sceneKey } from "./campus/choice.svelte";
  import { build, type Built } from "./campus/paint";
  import { startStrip, type Strip } from "./campus/render";
  import { loadScene } from "./campus/scenes";
  import type { SchoolLook } from "./campus/scenes/school";
  import { litWindow } from "./campus/sky";

  let { litKey = "", hour = $bindable<number | null>(null), scene = "" }: { litKey?: string; hour?: number | null; scene?: string } = $props();

  let cv: HTMLCanvasElement;
  let built = $state<Built | null>(null);
  let strip: Strip | null = null;
  // Own schedule draws its school's gate, not a PUP campus, unless a listed school was picked (spec 060 C7).
  const key = $derived(scene || (app.ownSchedule !== null && !sceneKey().startsWith("school:") ? "school:own" : sceneKey()));
  const lit = $derived(built ? litWindow(litKey, built.windows) : -1);

  let portals: Promise<SchoolLook[]> | null = null;
  async function schoolLook(id: string): Promise<SchoolLook | undefined> {
    portals ??= api.portals().then((ps) => ps.map((p) => ({ id: p.id, name: p.name, accent: p.theme.accent, ramp: p.theme.ramp, motif: p.motif })), () => []);
    const look = (await portals).find((p) => p.id === id);
    // Own schedule's gate carries the student's school (spec 060 C7).
    return look && id === "own" && app.ownSchedule ? { ...look, name: gateName(app.ownSchedule) } : look;
  }

  // Only the picked campus's scene is fetched; a load that a newer pick overtook is dropped.
  $effect(() => {
    const k = key;
    let live = true;
    (async () => {
      const def = await loadScene(k, k.startsWith("school:") ? await schoolLook(k.slice(7)) : undefined);
      if (live) built = build(def);
    })().catch(() => {});
    return () => {
      live = false;
    };
  });

  $effect(() => {
    if (!built) return;
    if (strip) strip.set(built, lit);
    else strip = startStrip(cv, built, { lit, hour: () => hour });
  });

  onMount(() => {
    if (!scene) {
      refreshCampus();
      resolveCampus();
    }
    return () => strip?.stop();
  });
</script>

<div role="img" aria-label="{built?.label ?? 'Your campus'} at this hour"><canvas bind:this={cv} width="192" height="80"></canvas></div>

<style>
  canvas {
    display: block;
    width: 100%;
    height: auto;
    aspect-ratio: 192 / 80;
    image-rendering: pixelated;
  }
</style>
