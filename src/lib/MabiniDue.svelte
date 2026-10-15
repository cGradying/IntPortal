<script lang="ts">
  // eMabini work that is due, on Today: what's overdue first, then what's
  // coming. Tap a row to open it in eMabini.
  import { dueLabel, splitDeadlines, subjectOf, titleOf } from "./deadlines";
  import { openLink } from "./openLink";
  import { app } from "./state.svelte";

  const MAX = 5;
  const now = new Date();
  const split = $derived(splitDeadlines(app.mabini?.deadlines ?? [], now, MAX));
  const rows = $derived([...split.overdue, ...split.upcoming].slice(0, MAX));
</script>

{#if app.mabiniConnected}
  <section class="due card notch">
    <p class="label">Due on eMabini</p>
    {#if rows.length}
      <ul>
        {#each rows as d (d.id)}
          {@const late = dueLabel(d, now) === "Overdue"}
          <li>
            <button onclick={() => openLink(d.url)}>
              <span class="when" class:late>{dueLabel(d, now)}</span>
              <span class="what"><strong>{titleOf(d.name)}</strong><small>{subjectOf(d.course)}</small></span>
            </button>
          </li>
        {/each}
      </ul>
      <button class="all" onclick={() => (app.mabiniPage = true)}>All courses and deadlines</button>
    {:else}
      <p class="none"><b>LAR</b> Walang due sa eMabini. Ayos!</p>
    {/if}
  </section>
{/if}

<style>
  .due {
    --step: 4px;
    display: grid;
    gap: 8px;
    padding: 14px 16px;
  }
  ul {
    list-style: none;
    margin: 0;
    padding: 0;
    display: grid;
    gap: 4px;
  }
  li button {
    width: 100%;
    display: flex;
    align-items: center;
    gap: 12px;
    padding: 6px 0;
    border: 0;
    background: none;
    color: var(--ink);
    text-align: left;
  }
  .when {
    width: 72px;
    flex: none;
    font-family: var(--font-display);
    font-weight: 700;
    font-size: min(0.765rem, 23px);
    color: var(--gold);
  }
  .when.late {
    color: var(--bad);
  }
  .what {
    display: grid;
    min-width: 0;
  }
  small {
    font-size: min(0.706rem, 22px);
    color: var(--ink-3);
  }
  .all {
    height: 36px;
    border: 0;
    border-radius: 10px;
    background: var(--sunk);
    box-shadow: inset 0 0 0 1px var(--edge);
    color: var(--ink);
    font-family: var(--font-display);
    font-weight: 700;
    font-size: min(0.765rem, 23px);
  }
  .none {
    margin: 0;
    font-size: min(0.824rem, 25px);
    color: var(--ink-2);
  }
  .none b {
    margin-right: 6px;
    font-family: var(--font-pixel);
    font-weight: 400;
    letter-spacing: 0.06em;
    color: var(--gold);
  }
</style>
