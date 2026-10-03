<script lang="ts">
  // Covers the app while it's locked or in the background (so the app
  // switcher shows Isko, not the student's grades).
  import Isko from "./Isko.svelte";
  import { lock, unlock } from "./lock.svelte";

  $effect(() => {
    if (lock.locked && !lock.hidden) unlock();
  });
</script>

<div class="cover" role="dialog" aria-label="IntPortal is locked">
  <Isko size={96} wave={false} />
  <p class="wordmark"><span>Student</span> IntPortal</p>
  {#if lock.locked && !lock.hidden}
    <button onclick={unlock}>Unlock</button>
    {#if lock.error}<p class="fine">{lock.error}</p>{/if}
  {/if}
</div>

<style>
  .cover {
    position: fixed;
    inset: 0;
    z-index: 100;
    display: grid;
    place-content: center;
    justify-items: center;
    gap: 16px;
    background: var(--ground);
  }
  .wordmark {
    margin: 0;
    font-family: var(--font-display);
    font-size: min(1.412rem, 31px);
    font-weight: 800;
    color: var(--ink);
  }
  .wordmark span {
    color: var(--gold);
  }
  button {
    height: 48px;
    padding: 0 28px;
    border: 0;
    border-radius: 12px;
    background: var(--gold);
    color: var(--on-gold);
    font-family: var(--font-display);
    font-weight: 700;
    font-size: min(0.941rem, 29px);
  }
  .fine {
    max-width: 280px;
    margin: 0;
    text-align: center;
    font-size: min(0.765rem, 23px);
    color: var(--ink-3);
  }
</style>
