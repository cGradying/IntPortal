<script lang="ts">
  // The way into LAR, shown only after IntAssis has been added: the cube he
  // holds, floating free over the page. Opening the chat sends it flying up
  // to him (AssisSheet), so it is away while the chat is open. Light users
  // never see it.
  import { buzz } from "../haptics";
  import Cube from "../lar/Cube.svelte";
  import { assis, installed, open } from "./assis.svelte";

  const thinking = $derived(assis.busy === "thinking" || assis.busy === "waking");
</script>

{#if installed()}
  <button class="orb" data-orb class:away={assis.open} aria-label="Ask LAR" onclick={() => { buzz.tick(); open(); }}>
    <Cube size={4} speed={thinking ? 4 : 1} />
    {#if thinking}<span class="pip" aria-hidden="true"><i></i><i></i><i></i></span>{/if}
  </button>
{/if}

<style>
  /* A 56 px target; the cube and its glow spill past it, nothing clips them. */
  .orb {
    position: fixed;
    right: var(--gutter);
    bottom: calc(var(--safe-bottom) + 84px);
    z-index: 22;
    width: 56px;
    height: 56px;
    display: grid;
    place-items: center;
    padding: 0;
    border: 0;
    background: none;
    -webkit-tap-highlight-color: transparent;
    transition:
      opacity 0.2s var(--ease),
      transform 0.2s var(--ease);
  }
  .orb :global(canvas) {
    grid-area: 1 / 1;
  }
  .orb:active {
    transform: scale(0.92);
  }
  .orb.away {
    opacity: 0;
    pointer-events: none;
  }
  .orb:focus-visible {
    outline: 2px solid var(--gold);
    outline-offset: 2px;
  }
  /* Three gold pixels over the cube while he thinks. */
  .pip {
    grid-area: 1 / 1;
    align-self: start;
    display: flex;
    gap: 3px;
    margin-top: -6px;
  }
  .pip i {
    width: 4px;
    height: 4px;
    background: var(--gold);
    animation: blink 1s steps(2, jump-none) infinite;
  }
  .pip i:nth-child(2) {
    animation-delay: 0.2s;
  }
  .pip i:nth-child(3) {
    animation-delay: 0.4s;
  }
  @keyframes blink {
    50% {
      opacity: 0.2;
    }
  }
  :global([data-glance="dock"]) .orb {
    bottom: calc(var(--safe-bottom) + 142px);
  }
  :global(html[data-keyboard="open"]) .orb {
    display: none;
  }
  @media (prefers-reduced-motion: reduce) {
    .pip i {
      animation: none;
    }
  }
</style>
