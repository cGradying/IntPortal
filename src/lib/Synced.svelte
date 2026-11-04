<script lang="ts">
  // Spec 040 C6: how fresh this tab is, on every phone; a tap syncs.
  import { ago } from "./glance";
  import { app, syncNow } from "./state.svelte";

  const when = $derived((app.today, ago(app.snapshot?.last_synced)));
</script>

{#if app.sisConnected}
  <button class="synced" onclick={syncNow} disabled={app.sync === "syncing"} aria-label="Last synced {when}. Sync now.">
    {app.sync === "syncing" ? "Syncing…" : when === "never" ? "Not synced yet" : `Synced ${when}`}
  </button>
{/if}

<style>
  .synced {
    min-height: 44px;
    padding: 0;
    border: 0;
    background: none;
    color: var(--ink-3);
    font-size: min(0.706rem, 22px);
    text-align: left;
  }
</style>
