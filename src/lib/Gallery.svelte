<script lang="ts">
  // Review-build gallery: every pixel piece in one scroll, in the current room.
  import { closable } from "./back";
  import CampusStrip from "./CampusStrip.svelte";
  import Glance from "./Glance.svelte";
  import Flame from "./Flame.svelte";
  import Isko from "./Isko.svelte";
  import Lar from "./lar/Lar.svelte";
  import { MOODS } from "./lar/sprite";
  import Jeepney from "./Jeepney.svelte";
  import { glanceView } from "./glance";
  import PixelIcon, { SPRITES, type SpriteName } from "./PixelIcon.svelte";
  import Scene, { SCENES } from "./Scene.svelte";

  const GESTURES = ["idle", "wave", "point", "reach", "thumbs"] as const;
  let { onclose }: { onclose: () => void } = $props();
  $effect(() => closable(() => onclose()));
  const hours = [6, 9, 12.5, 17.4, 18.6, 22];
  const states = [
    ["next", glanceView({ kind: "next_today", code: "GEED 10053", when: "in 12m" }, "GEED 10053 · in 12m", false, false, false)],
    ["in session", glanceView({ kind: "in_session", code: "COMP 20073", until: "9AM" }, "COMP 20073 · until 9AM", false, false, false)],
    ["syncing", glanceView(undefined, undefined, true, false, false)],
    ["arrived", glanceView(undefined, undefined, false, true, false)],
    ["stalled", glanceView({ kind: "sync_trouble", message: "Couldn't reach SIS" }, "Couldn't reach SIS · Try again", false, false, true)],
    ["day done", glanceView({ kind: "day_done", tomorrow: "PATHFIT 2 at 8AM" }, "No more classes today · Tomorrow PATHFIT 2 at 8AM", false, false, false)],
  ] as const;
  const label = (h: number) => `${Math.floor(h) % 12 || 12}:${String(Math.round((h % 1) * 60)).padStart(2, "0")} ${h < 12 ? "AM" : "PM"}`;
</script>

<div class="gallery">
  <header>
    <h1>Gallery</h1>
    <button onclick={onclose}>Done</button>
  </header>

  <p class="label">Isko (for your approval)</p>
  <div class="row">
    <figure class="card notch icon"><Isko size={96} pose="stand" /><figcaption>standing</figcaption></figure>
    <figure class="card notch icon"><Isko size={96} /><figcaption>waving</figcaption></figure>
    <figure class="card notch icon"><Isko size={96} pose="cheer" /><figcaption>cheering</figcaption></figure>
    <figure class="card notch icon"><Isko size={48} /><figcaption>small</figcaption></figure>
  </div>

  <p class="label">LAR, the Lakbay-Aral Robot</p>
  <div class="row">
    {#each MOODS as mood (mood)}<figure class="card notch icon"><Lar size={3} {mood} cube={false} /><figcaption>{mood}</figcaption></figure>{/each}
    {#each GESTURES as gesture (gesture)}<figure class="card notch icon"><Lar size={3} {gesture} /><figcaption>{gesture}</figcaption></figure>{/each}
  </div>

  <p class="label">Streak flame</p>
  <div class="row">
    <figure class="card notch icon"><Flame size={36} /><figcaption>flicker</figcaption></figure>
    <figure class="card notch icon"><Flame /><figcaption>inline</figcaption></figure>
  </div>

  <p class="label">Campus through the day</p>
  <div class="grid2">
    {#each hours as h (h)}
      <figure class="card notch"><CampusStrip hour={h} litKey="COMP 20073" /><figcaption>{label(h)}</figcaption></figure>
    {/each}
  </div>

  <p class="label">Empty-state scenes</p>
  <div class="grid2">
    {#each Object.keys(SCENES) as s (s)}
      <figure class="card notch scene"><Scene name={s} label={s} /><figcaption>{s}</figcaption></figure>
    {/each}
  </div>

  <p class="label">Sync journey</p>
  <div class="row">
    {#each ["drive", "arrived", "stalled"] as const as m (m)}
      <figure class="card notch pill"><span class="isl"><Jeepney mode={m} /></span><figcaption>{m}</figcaption></figure>
    {/each}
  </div>

  <p class="label">Glance: dock, for phones without an island</p>
  <div class="stack">
    {#each states as [name, v] (name)}<figure class="glances"><Glance preview={v} /><figcaption>{name}</figcaption></figure>{/each}
    <figure class="glances"><Glance preview={states[0][1]} startOpen /><figcaption>expanded</figcaption></figure>
  </div>

  <p class="label">Icons</p>
  <div class="row">
    {#each Object.keys(SPRITES) as n (n)}
      <figure class="card notch icon"><PixelIcon name={n as SpriteName} size={36} /><figcaption>{n}</figcaption></figure>
    {/each}
  </div>

  <p class="label">Stamps</p>
  <div class="row stamps">
    <span class="stamp">1.25</span><span class="stamp fresh">1.00</span><span class="stamp fail">5.00</span><span class="stamp mark">INC</span><span class="pending">Pending</span>
  </div>
</div>

<style>
  .gallery {
    display: grid;
    gap: 12px;
  }
  header {
    display: flex;
    justify-content: space-between;
    align-items: center;
  }
  h1 {
    margin: 0;
    font-family: var(--font-display);
    font-size: min(1.647rem, 36px);
  }
  header button {
    padding: 8px 14px;
    border: 0;
    border-radius: 10px;
    background: var(--gold);
    color: var(--on-gold);
    font-weight: 700;
  }
  .label {
    margin: 10px 0 0;
  }
  .grid2 {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 8px;
  }
  .row {
    display: flex;
    flex-wrap: wrap;
    gap: 8px;
  }
  .stack {
    display: grid;
    gap: 8px;
    justify-items: start;
  }
  figure {
    --step: 3px;
    margin: 0;
    overflow: hidden;
  }
  figcaption {
    padding: 6px 8px;
    font-size: min(0.706rem, 22px);
    color: var(--ink-2);
  }
  .scene {
    display: grid;
    justify-items: center;
    padding-top: 8px;
  }
  .scene :global(svg) {
    width: 100%;
    height: auto;
  }
  .pill,
  .icon {
    display: grid;
    justify-items: center;
    padding: 10px 10px 0;
  }
  .isl {
    display: inline-flex;
    align-items: center;
    padding: 8px 14px;
    border-radius: 19px;
    background: var(--island);
    color: #f1f1f3;
    font-family: var(--font-display);
    font-size: min(0.765rem, 23px);
    font-weight: 600;
  }
  .glances {
    justify-self: stretch;
    display: grid;
    gap: 4px;
    margin: 0;
  }
  .glances figcaption {
    text-align: center;
  }
  .stamps {
    align-items: center;
    padding: 6px 4px;
  }
  .stamp {
    min-width: 54px;
    padding: 4px 6px;
    text-align: center;
    font-family: var(--font-display);
    font-variant-numeric: tabular-nums;
    font-weight: 800;
    font-size: min(0.882rem, 27px);
    color: var(--good);
    box-shadow: inset 0 0 0 2px currentColor;
    transform: rotate(-4deg);
  }
  .stamp.fresh {
    animation: thunk 0.55s steps(6) infinite alternate;
  }
  .stamp.fail {
    color: var(--bad);
  }
  .stamp.mark {
    color: var(--ink-2);
  }
  @keyframes thunk {
    0% { transform: rotate(-12deg) scale(2.2); opacity: 0; }
    60% { transform: rotate(-3deg) scale(0.92); opacity: 1; }
    100% { transform: rotate(-4deg) scale(1); }
  }
  .pending {
    padding: 4px 10px;
    border-radius: 10px;
    background: var(--sunk);
    font-size: min(0.765rem, 23px);
    font-weight: 600;
    color: var(--ink-2);
  }
</style>
