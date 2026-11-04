<script lang="ts">
  // Pull down from the top of Today, Schedule or Grades to sync. The page
  // follows the finger a little; past the threshold it says so, and letting
  // go syncs.
  import Jeepney from "./Jeepney.svelte";
  import { buzz } from "./haptics";
  import { fieldPulse } from "./fieldPulse";
  import { app, syncNow } from "./state.svelte";

  const PULL = 72;
  let start: number | null = null;
  let pull = $state(0);
  let armed = false;
  // A sync the student pulled for lands with a stamp and one ripple (spec 045 C25).
  let pulled = false;
  let seenCount = app.syncCount;
  let stamped = $state(false);
  $effect(() => {
    const n = app.syncCount;
    if (n === seenCount) return;
    seenCount = n;
    if (!pulled) return;
    pulled = false;
    stamped = true;
    fieldPulse(innerWidth / 2, 60, 1.2);
    setTimeout(() => (stamped = false), 1700);
  });

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
      pulled = true;
      syncNow();
    }
    start = null;
    pull = 0;
    armed = false;
  }
</script>

<svelte:window ontouchstart={down} ontouchmove={move} ontouchend={up} ontouchcancel={up} />

{#if stamped}<span class="synced" role="status">SYNCED</span>{/if}
{#if pull > 8 || app.sync === "syncing"}
  <div class="pull" style:height="{app.sync === "syncing" ? PULL * 0.6 : pull}px" aria-live="polite">
    <Jeepney mode="drive" />
    <span>{app.sync === "syncing" ? "Syncing with SIS…" : pull >= PULL ? "Let go to sync" : "Pull to sync"}</span>
  </div>
{/if}

<style>
  .synced {
    position: fixed;
    left: 50%;
    top: calc(var(--safe-top) + 10px);
    z-index: 30;
    translate: -50% 0;
    rotate: -4deg;
    padding: 2px 8px;
    font: 700 min(0.706rem, 22px) var(--font-pixel);
    letter-spacing: 0.08em;
    color: var(--good);
    background: var(--ground);
    box-shadow: inset 0 0 0 2px var(--good);
    animation:
      land 0.42s steps(5) both,
      leave 0.3s ease 1.4s forwards;
  }
  @keyframes land {
    0% { scale: 2.2; opacity: 0; }
    55% { scale: 0.92; opacity: 1; }
    100% { scale: 1; opacity: 1; }
  }
  @keyframes leave {
    to { opacity: 0; }
  }
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
