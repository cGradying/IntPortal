<script lang="ts">
  import PixelIcon, { type SpriteName } from "./PixelIcon.svelte";
  import { app, type Tab } from "./state.svelte";

  const tabs: { id: Tab; label: string; icon: SpriteName }[] = [
    { id: "today", label: "Today", icon: "today" },
    { id: "schedule", label: "Schedule", icon: "schedule" },
    { id: "grades", label: "Grades", icon: "grades" },
    { id: "you", label: "You", icon: "you" },
  ];
</script>

<nav class="bar">
  {#each tabs as t (t.id)}
    <button class:on={app.tab === t.id} onclick={() => (app.tab = t.id)} aria-current={app.tab === t.id ? "page" : undefined}>
      <PixelIcon name={t.icon} size={22} accent={app.tab === t.id ? "var(--gold)" : "currentColor"} />
      <span>{t.label}</span>
    </button>
  {/each}
</nav>

<style>
  .bar {
    position: fixed;
    left: 0;
    right: 0;
    bottom: 0;
    z-index: 20;
    display: grid;
    grid-template-columns: repeat(4, 1fr);
    padding: 8px 8px calc(var(--safe-bottom) + 6px);
    background: color-mix(in srgb, var(--ground) 86%, transparent);
    backdrop-filter: blur(16px);
    box-shadow: 0 -1px 0 var(--edge);
  }
  button {
    display: grid;
    justify-items: center;
    gap: 4px;
    padding: 6px 0;
    border: 0;
    background: none;
    color: var(--ink-3);
    transition: color 0.2s;
  }
  button span {
    font-family: var(--font-display);
    font-size: 11px;
    font-weight: 600;
  }
  button.on {
    color: var(--ink);
  }
  button.on span {
    color: var(--gold);
  }
  button.on :global(svg) {
    animation: hop 0.35s steps(3);
  }
  @keyframes hop {
    40% { transform: translateY(-3px); }
  }
</style>
