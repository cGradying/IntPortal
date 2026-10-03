<script lang="ts">
  // The legacy week view: a column per day, blocks placed by time, today's
  // column tinted and a gold line at the current minute. Days with no
  // classes drop out, except today.
  import { subjectColor, WEEKDAYS, type Meeting } from "./api";

  let { meetings, colors, todayIdx, onpick }: { meetings: Meeting[]; colors: Record<string, string>; todayIdx: number; onpick: (m: Meeting) => void } = $props();

  const HOUR = 44;
  const days = $derived(WEEKDAYS.map((d, i) => ({ d, i })).filter(({ d, i }) => i === todayIdx || meetings.some((m) => m.session.day === d)));
  const first = $derived(Math.floor(Math.min(7 * 60, ...meetings.map((m) => m.session.start)) / 60));
  const last = $derived(Math.ceil(Math.max(17 * 60, ...meetings.map((m) => m.session.end)) / 60));
  const hours = $derived(Array.from({ length: last - first }, (_, k) => first + k));
  const y = (min: number) => ((min - first * 60) / 60) * HOUR;

  let now = $state(new Date());
  $effect(() => {
    const t = setInterval(() => (now = new Date()), 60_000);
    return () => clearInterval(t);
  });
  const nowMin = $derived(now.getHours() * 60 + now.getMinutes());
  const label = (h: number) => `${h % 12 || 12}${h < 12 ? "a" : "p"}`;
</script>

<div class="grid" style:--cols={days.length} style:--h="{hours.length * HOUR}px">
  <div class="head">
    <span></span>
    {#each days as { d, i } (d)}<span class:today={i === todayIdx}>{d.slice(0, 3)}</span>{/each}
  </div>
  <div class="body">
    <div class="hours">
      {#each hours as h (h)}<span style:top="{y(h * 60)}px">{label(h)}</span>{/each}
    </div>
    {#each days as { d, i } (d)}
      <div class="col" class:today={i === todayIdx}>
        {#each hours as h (h)}<i class="rule" style:top="{y(h * 60)}px"></i>{/each}
        {#each meetings.filter((m) => m.session.day === d) as m (m.id)}
          <button
            class="block"
            data-mark={m.mark}
            style:top="{y(m.session.start)}px"
            style:height="{Math.max(18, y(m.session.end) - y(m.session.start) - 2)}px"
            style:--c={subjectColor(m.session.subject_code, colors)}
            onclick={() => onpick(m)}
            aria-label="{m.session.subject_code}, {d}"
          >
            <strong>{m.session.subject_code.split(" ")[0]}</strong>
            <small>{m.session.subject_code.split(" ").slice(1).join(" ")}</small>
          </button>
        {/each}
        {#if i === todayIdx && nowMin >= first * 60 && nowMin <= last * 60}
          <i class="now" style:top="{y(nowMin)}px"></i>
        {/if}
      </div>
    {/each}
  </div>
</div>

<style>
  .grid {
    display: grid;
    gap: 4px;
  }
  .head,
  .body {
    display: grid;
    grid-template-columns: 28px repeat(var(--cols), 1fr);
    gap: 3px;
  }
  .head span {
    text-align: center;
    font-size: min(0.647rem, 20px);
    font-weight: 700;
    text-transform: uppercase;
    color: var(--ink-3);
  }
  .head span.today {
    color: var(--gold);
  }
  .body {
    height: var(--h);
  }
  .hours,
  .col {
    position: relative;
  }
  .hours span {
    position: absolute;
    right: 2px;
    transform: translateY(-50%);
    font-size: min(0.588rem, 18px);
    color: var(--ink-3);
  }
  .col {
    border-radius: 6px;
  }
  .col.today {
    background: var(--gold-soft);
  }
  .rule {
    position: absolute;
    left: 0;
    right: 0;
    height: 1px;
    background: var(--edge);
  }
  .block {
    position: absolute;
    left: 1px;
    right: 1px;
    display: grid;
    align-content: start;
    padding: 3px 3px 0;
    overflow: hidden;
    border: 0;
    border-radius: 5px;
    background: color-mix(in srgb, var(--c) 30%, var(--card));
    box-shadow: inset 2px 0 0 var(--c);
    color: var(--ink);
    text-align: left;
    line-height: 1.15;
  }
  .block strong {
    font-family: var(--font-display);
    font-size: min(0.588rem, 18px);
  }
  .block small {
    font-size: min(0.588rem, 18px);
    color: var(--ink-2);
  }
  .block[data-mark="vacant"] {
    opacity: 0.35;
  }
  .block[data-mark="online"] {
    box-shadow: inset 2px 0 0 var(--c), inset 0 0 0 1px var(--c);
  }
  .now {
    position: absolute;
    left: -2px;
    right: -2px;
    height: 2px;
    background: var(--gold);
    box-shadow: 0 0 6px var(--gold);
  }
</style>
