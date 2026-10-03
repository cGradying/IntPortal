<script lang="ts">
  // Pull down from the top of Today, Schedule or Grades to sync. The page
  // follows the finger a little; past the threshold it says so, and letting
  // go syncs.
  import Jeepney from "./Jeepney.svelte";
  import { buzz } from "./haptics";
  import { app, syncNow } from "./state.svelte";

  const PULL = 72;
  let start: number | null = null;
  let pull = $state(0);
  let armed = false;

  const enabled = () => ["today", "schedule", "grades"].includes(app.tab) && !app.editing && !app.subject && scrollY <= 0;

  function down(e: TouchEvent) {
    start = enabled() ? e.touches[0].clientY : null;
    pull = 0;
    armed = false;
  }

  function move(e: TouchEvent) {
    if (start === null) return;
    pull = Math.max(0, Math.min(PULL * 1.5, (e.touches[0].clientY - start) * 0.5));
    if (armed !== pull >= PULL) buzz.pull();
    armed = pull >= PULL;
  }

  function up() {
    if (armed) {
      buzz.release();
      syncNow();
    }
    start = null;
    pull = 0;
    armed = false;
  }
</script>

<svelte:window ontouchstart={down} ontouchmove={move} ontouchend={up} ontouchcancel={up} />

{#if pull > 8 || app.sync === "syncing"}
  <div class="pull" style:height="{app.sync === "syncing" ? PULL * 0.6 : pull}px" aria-live="polite">
    <Jeepney mode="drive" />
    <span>{app.sync === "syncing" ? "Syncing with SIS…" : pull >= PULL ? "Let go to sync" : "Pull to sync"}</span>
  </div>
{/if}

<style>
  .pull {
    display: flex;
    align-items: flex-end;
    justify-content: center;
    gap: 10px;
    overflow: hidden;
    padding-bottom: 8px;
    font-size: min(0.765rem, 23px);
    font-weight: 600;
    color: var(--ink-3);
  }
</style>
