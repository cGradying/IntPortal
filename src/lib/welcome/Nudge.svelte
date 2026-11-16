<script lang="ts">
  // A sample of the reminder, as the phone would show it (spec 049 C10).
  import MiniPortal from "../MiniPortal.svelte";
  import type { Portal } from "../api";
  import { CLASS } from "./intro";

  let { portal, name = "" }: { portal: Portal; name?: string } = $props();
</script>

<div class="note">
  <span class="icon"><MiniPortal {portal} /></span>
  <span class="text">
    <span class="head"><b>IntPortal</b><small>now</small></span>
    <span class="title">{CLASS.code} in 10 minutes</span>
    <span class="body">{CLASS.room}, {CLASS.title}. Tara na{name ? `, ${name}` : ""}!</span>
  </span>
</div>

<style>
  .note {
    display: grid;
    grid-template-columns: 36px minmax(0, 1fr);
    gap: 10px;
    padding: 10px 12px;
    border-radius: var(--radius-lg);
    background: var(--void-lift);
    box-shadow: inset 0 0 0 1px rgb(244 236 216 / 0.12);
    font-family: var(--font-ui);
  }
  .icon {
    display: grid;
    place-items: center;
    width: 36px;
    height: 36px;
    border-radius: var(--radius);
    background: var(--void);
  }
  .icon :global(svg) {
    width: 15px;
    height: 21px;
  }
  .text {
    display: grid;
    min-width: 0;
  }
  .head {
    display: flex;
    align-items: baseline;
    gap: 8px;
    font: 600 var(--text-caption) var(--font-ui);
    color: rgb(244 236 216 / 0.7);
  }
  .head small {
    margin-left: auto;
    font-weight: 400;
    color: rgb(244 236 216 / 0.5);
  }
  .title {
    font: 600 var(--text-sub) var(--font-ui);
    color: var(--cream);
  }
  .body {
    font: 400 var(--text-sub) / 1.35 var(--font-ui);
    color: rgb(244 236 216 / 0.78);
  }
</style>
