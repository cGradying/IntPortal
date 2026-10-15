<script lang="ts">
  // After a wrong answer: LAR says why the right one is right and gives one
  // way to remember it. Only there once IntAssis has been added.
  import { buzz } from "../haptics";
  import { assis, explain, installed } from "./assis.svelte";

  let { front, back, typed, subject }: { front: string; back: string; typed: string; subject: string | null } = $props();
  let said = $state<{ why: string; tip: string } | null>(null);
  let problem = $state("");

  async function ask() {
    buzz.select();
    problem = "";
    try {
      said = await explain(front, back, typed, subject);
    } catch (e) {
      problem = typeof e === "string" ? e : (e as Error).message;
    }
  }
</script>

{#if installed()}
  {#if said}
    <div class="lar" aria-live="polite">
      <p class="tag">LAR</p>
      <p>{said.why}</p>
      <p class="tip"><b>Remember it:</b> {said.tip}</p>
    </div>
  {:else}
    <button class="why" onclick={ask} disabled={!!assis.busy}>{assis.busy ? "LAR is thinking…" : "Why?"}</button>
    {#if problem}<p class="problem" role="alert">{problem}</p>{/if}
  {/if}
{/if}

<style>
  .why {
    justify-self: start;
    min-height: 44px;
    padding: 0 16px;
    border: 0;
    border-radius: 10px;
    background: var(--sunk);
    box-shadow: inset 0 0 0 1px var(--edge);
    font-family: var(--font-display);
    font-weight: 700;
    font-size: min(0.824rem, 25px);
  }
  .why:disabled {
    opacity: 0.6;
  }
  .lar {
    display: grid;
    gap: 6px;
    padding: 10px 12px;
    background: #170b1a;
    color: #f4e8d6;
    box-shadow: inset 0 2px 0 #3a2446, inset 0 -2px 0 #060307;
  }
  .lar p {
    margin: 0;
    font-size: min(0.824rem, 25px);
    line-height: 1.4;
  }
  .tag {
    font-family: var(--font-pixel);
    font-size: min(0.706rem, 22px);
    letter-spacing: 0.08em;
    color: var(--gold);
  }
  .tip b {
    font-weight: 600;
  }
  .problem {
    margin: 0;
    font-size: min(0.765rem, 23px);
    color: var(--bad);
  }
</style>
