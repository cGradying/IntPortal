<script lang="ts">
  // What every screen shows when its data couldn't load: LAR, surprised,
  // what went wrong in plain words, and a way to try again.
  import Lar from "./lar/Lar.svelte";

  let { error, onretry }: { error: string; onretry: () => void } = $props();
</script>

<section class="card notch problem" role="alert">
  <Lar size={2} state="error" cube={false} />
  <div>
    <p class="what">Couldn't load this</p>
    <p class="why">{error}</p>
    <button onclick={onretry}>Try again</button>
  </div>
</section>

<style>
  .problem {
    --step: 4px;
    display: flex;
    align-items: center;
    gap: 14px;
    padding: 20px 16px 16px;
  }
  .what {
    margin: 0;
    font-family: var(--font-display);
    font-weight: 700;
  }
  .why {
    margin: 2px 0 10px;
    font-size: min(0.765rem, 23px);
    color: var(--ink-3);
    overflow-wrap: anywhere;
  }
  button {
    height: 36px;
    padding: 0 14px;
    border: 0;
    border-radius: 10px;
    background: var(--gold);
    color: var(--on-gold);
    font-family: var(--font-display);
    font-weight: 700;
    font-size: min(0.765rem, 23px);
  }
</style>
