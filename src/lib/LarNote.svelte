<script lang="ts">
  // LAR saying one line, for empty states and tips. LAR talks; Isko is you.
  import type { Snippet } from "svelte";
  import Lar, { type Gesture } from "./lar/Lar.svelte";
  import type { Mood, State } from "./lar/sprite";

  let { mood = "open", gesture = "idle", state = "idle", children }: { mood?: Mood; gesture?: Gesture; state?: State; children: Snippet } = $props();
</script>

<div class="card notch note">
  <Lar size={2} {mood} {gesture} {state} cube={false} />
  <p>{@render children()}</p>
</div>

<style>
  .note {
    --step: 4px;
    display: flex;
    align-items: center;
    gap: 14px;
    padding: 20px 16px 14px;
  }
  p {
    margin: 0;
    font-size: min(0.882rem, 27px);
    line-height: 1.4;
    color: var(--ink-2);
  }
</style>
