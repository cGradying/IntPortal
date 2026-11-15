<script lang="ts">
  // The one question left after sign-in (spec 049 C16): Light or With AI. Who LAR is, where the
  // data lives and reminders moved into the intro before sign-in, so on a build without AI this
  // never shows (+page checks `showFirstRun`).
  import { buzz } from "./haptics";
  import Lar from "./lar/Lar.svelte";
  import { chatModel, downloadSizes, embedModel, install, mb } from "./assis/assis.svelte";

  let { ondone }: { ondone: () => void } = $props();
  /** Spec 020 C9: Light is preselected; skipping is the same as Light. */
  let pick = $state<"light" | "ai">("light");

  const todo = $derived([chatModel(), embedModel()].filter((m): m is NonNullable<typeof m> => !!m && !m.installed));
  const size = $derived(mb(todo.reduce((n, m) => n + m.bytes, 0)));

  function go() {
    if (pick === "ai") {
      buzz.tick();
      install();
    } else buzz.select();
    ondone();
  }
</script>

<div class="first ground" role="dialog" aria-labelledby="first-title">
  <div class="art"><Lar size={4} state="happy" /></div>
  <div class="card notch text">
    <h1 id="first-title">Light or With AI?</h1>
    <p>You can add AI later on You. A one-time download of {size}: {downloadSizes(todo)}. It works offline.</p>
  </div>
  <div class="pick" role="radiogroup" aria-label="Light or With AI">
    <button role="radio" aria-checked={pick === "light"} class:on={pick === "light"} onclick={() => { buzz.select(); pick = "light"; }}>
      <b>Light</b><small>No AI. Nothing downloaded.</small>
    </button>
    <button role="radio" aria-checked={pick === "ai"} class:on={pick === "ai"} onclick={() => { buzz.select(); pick = "ai"; }}>
      <b>With AI · {size}</b><small>Ask LAR about your classes and notes. One-time download, works offline. Use Wi-Fi.</small>
    </button>
  </div>
  <button class="primary" onclick={go}>Continue</button>
</div>

<style>
  .first {
    position: fixed;
    inset: 0;
    z-index: 60;
    display: grid;
    align-content: end;
    gap: 14px;
    padding: calc(var(--safe-top) + 24px) var(--gutter) calc(var(--safe-bottom) + 24px);
  }
  .art {
    display: flex;
    align-items: end;
    justify-content: center;
    padding-bottom: 8px;
  }
  .text {
    --step: 4px;
    padding: 20px;
  }
  h1 {
    margin: 0 0 8px;
    font-family: var(--font-display);
    font-size: var(--text-title);
  }
  .text p {
    margin: 0;
    font-size: var(--text-body);
    line-height: 1.5;
    color: var(--ink-2);
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
  .pick {
    display: grid;
    gap: 8px;
  }
  .pick button {
    height: auto;
    min-height: 52px;
    padding: 12px 14px;
    display: grid;
    gap: 2px;
    text-align: left;
    background: var(--sunk);
    color: var(--ink);
    border: 2px solid var(--edge);
  }
  .pick button.on {
    border-color: var(--gold);
  }
  .pick small {
    font-family: inherit;
    font-weight: 400;
    color: var(--ink-2);
  }
</style>
