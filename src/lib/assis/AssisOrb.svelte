<script lang="ts">
  // The way into LAR, shown only after IntAssis has been added. Light users
  // never see it.
  import { buzz } from "../haptics";
  import Lar from "../lar/Lar.svelte";
  import { assis, installed, open } from "./assis.svelte";
</script>

{#if installed()}
  <button class="orb notch" aria-label="Ask LAR" onclick={() => { buzz.tick(); open(); }}>
    <Lar size={2} cube={false} state={assis.busy === "thinking" || assis.busy === "waking" ? "think" : "idle"} />
  </button>
{/if}

<style>
  .orb {
    --step: 4px;
    position: fixed;
    right: var(--gutter);
    bottom: calc(var(--safe-bottom) + 84px);
    z-index: 22;
    width: 64px;
    height: 60px;
    overflow: hidden;
    display: grid;
    place-items: center;
    border: 0;
    background: #170b1a;
    box-shadow: inset 0 2px 0 #3a2446, inset 0 -2px 0 #060307;
  }
  :global([data-glance="dock"]) .orb {
    bottom: calc(var(--safe-bottom) + 142px);
  }
  :global(html[data-keyboard="open"]) .orb {
    display: none;
  }
</style>
