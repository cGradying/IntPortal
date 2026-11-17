<script lang="ts">
  // The install view (spec 021 C6, C9): it stays from Add until the install is done, failed or paused.
  // The bar is the field itself: the dot grid's own cells (11 px on the 14 px pitch) light gold as
  // the bytes land, the one idea of DESIGN.md. LAR thinks while it comes, dozes while it waits for a
  // connection, and is happy at the end.
  import { onMount } from "svelte";
  import { buzz } from "../haptics";
  import Lar from "../lar/Lar.svelte";
  import PixelNum from "../PixelNum.svelte";
  import { assis, cancelDownload, closeInstall, etaLine, install, mb, open } from "./assis.svelte";

  const i = $derived(assis.install);
  const pct = $derived(assis.total ? Math.min(100, Math.floor((assis.done / assis.total) * 100)) : 0);
  const running = $derived(assis.busy === "downloading");
  const failed = $derived(!running && !i.ready && !!assis.error);
  const speed = $derived(i.speed > 0 ? `${mb(i.speed)}/s` : "");
  const eta = $derived(etaLine(assis.total - assis.done, i.speed));
  const lar = $derived(i.ready ? "happy" : failed ? "error" : i.waiting ? "sleep" : "think");

  // Each file's place: done once the bar has passed its end, the current one, or next.
  const rows = $derived.by(() => {
    let end = 0;
    return i.files.map((m, n) => {
      end += m.bytes;
      const state = i.ready || assis.done >= end ? "done" : n === i.file ? "now" : "next";
      return { name: m.chat ? "LAR's brain" : "Note search", size: mb(m.bytes), state };
    });
  });

  // Android's web view says when the phone is on mobile data; iOS doesn't, so the line never shows there.
  const cellular = (globalThis.navigator as { connection?: { type?: string } } | undefined)?.connection?.type === "cellular";

  // Screen readers hear the speed and time left at most every 5 s (Accessibility).
  let spoken = $state("");
  onMount(() => {
    const say = () => (spoken = running ? [`${pct}%`, speed, eta].filter(Boolean).join(", ") : "");
    say();
    const t = setInterval(say, 5000);
    return () => clearInterval(t);
  });

  let buzzed = false;
  $effect(() => {
    if (i.ready && !buzzed) {
      buzzed = true;
      buzz.done();
    }
  });

  function ask() {
    closeInstall();
    open();
  }
</script>

<div class="install ground" role="dialog" aria-modal="true" aria-labelledby="install-title">
  <div class="art"><Lar size={4} state={lar} /></div>

  <section class="card notch panel">
    <h1 id="install-title">{i.ready ? "IntAssis is ready" : "Adding IntAssis"}</h1>

    <div class="count" aria-hidden="true"><PixelNum text={String(i.ready ? 100 : pct)} size={6} /><span class="unit">%</span></div>

    <div class="field" role="progressbar" aria-label="IntAssis download" aria-valuemin="0" aria-valuemax="100" aria-valuenow={i.ready ? 100 : pct}>
      <i style:width="{i.ready ? 100 : (assis.done / Math.max(1, assis.total)) * 100}%"></i>
    </div>

    <div class="line num">
      <span>{mb(i.ready ? assis.total : assis.done)} of {mb(assis.total)}</span>
      {#if running && !i.waiting && speed}<span>{speed}{eta ? ` · ${eta}` : ""}</span>{/if}
    </div>
    <p class="sr" aria-live="polite">{spoken}</p>

    <ul class="files">
      {#each rows as r (r.name)}
        <li class:done={r.state === "done"}>
          <span class="name">{r.name}</span>
          <span class="size num">{r.size}</span>
          <span class="chip" class:now={r.state === "now"}>{r.state === "done" ? "Done" : r.state === "now" ? "Now" : "Next"}</span>
        </li>
      {/each}
    </ul>

    {#if failed}
      <p class="note bad" role="alert">{assis.error}</p>
    {:else if i.ready}
      <p class="note">LAR runs on this phone now. It works offline, and nothing you ask leaves it.</p>
    {:else if i.waiting}
      <p class="note warn" role="status">{i.waiting}</p>
    {:else}
      <p class="note">You can leave the app; it keeps going.{cellular ? ` On mobile data · ${mb(assis.total)}.` : ""}</p>
    {/if}
  </section>

  <div class="actions">
    {#if i.ready}
      <button class="primary" onclick={ask}>Ask LAR</button>
      <button class="ghost" onclick={closeInstall}>Done</button>
    {:else if failed}
      <button class="primary" onclick={() => { buzz.tick(); install(); }}>Resume</button>
      <button class="ghost" onclick={closeInstall}>Close</button>
    {:else}
      <button class="ghost" onclick={() => { buzz.select(); cancelDownload(); }}>Pause</button>
    {/if}
  </div>
</div>

<style>
  .install {
    position: fixed;
    inset: 0;
    z-index: 63;
    display: grid;
    align-content: end;
    gap: 14px;
    padding: calc(var(--safe-top) + 24px) var(--gutter) calc(var(--safe-bottom) + 24px);
  }
  .art {
    display: flex;
    justify-content: center;
    padding-bottom: 4px;
  }
  .panel {
    --step: 4px;
    display: grid;
    gap: 12px;
    padding: 20px 16px 16px;
  }
  h1 {
    margin: 0;
    font-family: var(--font-display);
    font-size: var(--text-title);
    font-weight: 800;
    letter-spacing: -0.035em;
    color: var(--ink);
  }
  .count {
    display: flex;
    align-items: end;
    gap: 6px;
    color: var(--ink);
  }
  .unit {
    font-family: var(--font-pixel);
    font-size: var(--text-title);
    font-weight: 700;
    line-height: 1;
    color: var(--ink-3);
  }
  /* The dot grid's cells: 11 px tiles on the 14 px pitch, sunk until the bytes light them. */
  .field {
    --cells: repeating-linear-gradient(90deg, #000 0 11px, transparent 11px 14px);
    position: relative;
    height: 11px;
    background: var(--sunk);
    -webkit-mask: var(--cells);
    mask: var(--cells);
  }
  .field i {
    position: absolute;
    inset: 0 auto 0 0;
    background: var(--gold);
    transition: width var(--t-flow) var(--ease);
  }
  .line {
    display: flex;
    justify-content: space-between;
    gap: 12px;
    font-size: var(--text-sub);
    color: var(--ink-2);
  }
  .num {
    font-variant-numeric: tabular-nums;
  }
  .files {
    display: grid;
    gap: 6px;
    margin: 4px 0 0;
    padding: 0;
    list-style: none;
  }
  .files li {
    display: grid;
    grid-template-columns: 1fr auto auto;
    align-items: center;
    gap: 10px;
    min-height: 44px;
    padding: 0 12px;
    border-radius: var(--radius);
    background: var(--sunk);
    box-shadow: inset 0 0 0 1px var(--edge);
    font-size: var(--text-body);
  }
  .files .size {
    color: var(--ink-3);
    font-size: var(--text-sub);
  }
  .chip {
    font-family: var(--font-pixel);
    font-size: var(--text-label);
    padding: 3px 7px;
    border-radius: var(--radius-sm);
    color: var(--ink-3);
    box-shadow: inset 0 0 0 1px var(--edge-2);
  }
  .chip.now {
    color: var(--gold);
    box-shadow: inset 0 0 0 1px var(--gold);
  }
  .files li.done .chip {
    color: var(--on-gold);
    background: var(--gold);
    box-shadow: none;
  }
  .note {
    margin: 0;
    font-size: var(--text-sub);
    line-height: 1.45;
    color: var(--ink-2);
  }
  .note.warn {
    color: var(--ink);
  }
  .note.bad {
    color: var(--bad);
  }
  .sr {
    position: absolute;
    width: 1px;
    height: 1px;
    overflow: hidden;
    clip-path: inset(50%);
  }
  .actions {
    display: grid;
    grid-auto-flow: column;
    grid-auto-columns: 1fr;
    gap: 8px;
  }
  button {
    height: 52px;
    border: 0;
    border-radius: var(--radius);
    font-family: var(--font-display);
    font-weight: 700;
    font-size: var(--text-body);
  }
  .primary {
    background: var(--gold);
    color: var(--on-gold);
  }
  .ghost {
    background: var(--sunk);
    color: var(--ink);
    box-shadow: inset 0 0 0 1px var(--edge);
  }
</style>
