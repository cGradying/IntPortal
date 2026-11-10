<script lang="ts">
  // The view through the portal (spec 010 C37): it opens out of the mouth in
  // pixel steps and shows what the app keeps, page by page, with sample data.
  // A tap turns the page; the last page, a tap outside or a field closes it.
  import { PAGES } from "./peek";

  type Box = { x: number; y: number; w: number; h: number };
  let {
    box,
    room,
    inset,
    page,
    accent,
    onnext,
  }: {
    /** The portal's frame, in CSS px of the stage. */
    box: Box;
    /** The stage's own size, so the view never spills past it. */
    room: { w: number; h: number };
    /** The frame's thickness in CSS px: the view opens from inside it. */
    inset: number;
    page: number;
    accent: string;
    onnext: () => void;
  } = $props();

  const W = $derived(Math.min(room.w - 16, 340));
  const H = $derived(Math.min(room.h - 8, Math.max(box.h, 236)));
  const L = $derived(Math.max(8, Math.min(room.w - W - 8, box.x + box.w / 2 - W / 2)));
  const T = $derived(Math.max(4, Math.min(room.h - H - 4, box.y + box.h / 2 - H / 2)));
  // Where the mouth sits inside the view: the iris opens from it.
  const clip = $derived({
    t: Math.max(0, box.y + inset - T),
    r: Math.max(0, L + W - (box.x + box.w - inset)),
    b: Math.max(0, T + H - (box.y + box.h - inset)),
    l: Math.max(0, box.x + inset - L),
  });
  const p = $derived(PAGES[page]);
  // A week of sample blocks: column, start row, length, tone.
  const WEEK = [
    [0, 0, 3, 1], [0, 5, 2, 2], [1, 2, 3, 3], [2, 0, 3, 1], [2, 5, 2, 2],
    [3, 2, 3, 3], [4, 0, 2, 4], [4, 4, 3, 1], [5, 1, 4, 2],
  ];
</script>

<button
  class="peek"
  style:left="{L}px"
  style:top="{T}px"
  style:width="{W}px"
  style:height="{H}px"
  style:--ct="{clip.t}px"
  style:--cr="{clip.r}px"
  style:--cb="{clip.b}px"
  style:--cl="{clip.l}px"
  style:--accent={accent}
  aria-label="{p.title}, a sample of what IntPortal shows. Tap for the next one."
  onclick={onnext}
>
  <span class="glass">
    <span class="top">
      <b>{p.title}</b>
      <small>Sample</small>
    </span>
    {#key page}
      <span class="body">
        {#if p.id === "today"}
          <span class="lab">Up next · 7:30 AM</span>
          <span class="big">COMP 20073</span>
          <span class="sub">Data Structures and Algorithms · S512</span>
          <span class="row"><i class="box" aria-hidden="true"></i>Quiz 2<em>Due Fri</em></span>
          <span class="row free">1h 30m free after</span>
        {:else if p.id === "schedule"}
          <span class="week" aria-hidden="true">
            {#each ["M", "T", "W", "Th", "F", "S"] as d (d)}<span class="day">{d}</span>{/each}
            {#each WEEK as [c, r, n, k], i (i)}
              <i class="blk t{k}" style:grid-column={c + 1} style:grid-row="{r + 2} / span {n}"></i>
            {/each}
          </span>
          <span class="sub">Vacant, online and moved classes are marked.</span>
        {:else if p.id === "grades"}
          <span class="lab">This term</span>
          <span class="big">1.28</span>
          <span class="row">COMP 20073<em>1.25</em></span>
          <span class="row">MATH 20013<em>1.50</em></span>
          <span class="row">GEED 10053<em>1.00</em></span>
        {:else}
          <span class="card">
            <span class="q">Binary search runs in…</span>
            <span class="a">O(log n)</span>
          </span>
          <span class="row">12 cards due today<em>Review</em></span>
        {/if}
      </span>
    {/key}
    <span class="dots" aria-hidden="true">
      {#each PAGES as _, i (i)}<i class:on={i === page}></i>{/each}
      <small>{page + 1 < PAGES.length ? "Tap for next" : "Tap to close"}</small>
    </span>
  </span>
</button>

<style>
  /* The view opens out of the mouth in six pixel steps, like the tiles. */
  .peek {
    position: absolute;
    z-index: 2;
    display: block;
    padding: 0;
    border: 0;
    background: transparent;
    -webkit-appearance: none;
    appearance: none;
    text-align: left;
    color: var(--parch);
    animation: iris 0.42s steps(6, end) both;
    filter: drop-shadow(0 12px 28px rgb(0 0 0 / 0.55));
  }
  @keyframes iris {
    from {
      clip-path: inset(var(--ct) var(--cr) var(--cb) var(--cl));
    }
    to {
      clip-path: inset(0);
    }
  }
  .glass {
    display: grid;
    grid-template-rows: auto minmax(0, 1fr) auto;
    gap: 10px;
    height: 100%;
    padding: 14px 16px 12px;
    background:
      radial-gradient(120% 70% at 50% 0%, color-mix(in srgb, var(--accent) 16%, transparent), transparent 70%),
      var(--void-2);
    box-shadow: inset 0 0 0 1px color-mix(in srgb, var(--accent) 45%, transparent);
    clip-path: polygon(0 4px, 4px 4px, 4px 0, calc(100% - 4px) 0, calc(100% - 4px) 4px, 100% 4px, 100% calc(100% - 4px), calc(100% - 4px) calc(100% - 4px), calc(100% - 4px) 100%, 4px 100%, 4px calc(100% - 4px), 0 calc(100% - 4px));
  }
  .top {
    display: flex;
    align-items: baseline;
    justify-content: space-between;
  }
  .top b {
    font: 700 min(1.06rem, 26px) var(--font-display);
    color: var(--cream);
  }
  .top small,
  .dots small {
    font: 500 min(0.65rem, 18px) var(--font-pixel);
    letter-spacing: 0.06em;
    color: rgb(244 236 216 / 0.6);
    text-transform: uppercase;
  }
  .body {
    display: grid;
    align-content: start;
    gap: 6px;
    min-height: 0;
    overflow: hidden;
    animation: turn 0.3s var(--ease) both;
  }
  @keyframes turn {
    from {
      opacity: 0;
      translate: 10px 0;
    }
  }
  .lab {
    font: 500 min(0.7rem, 19px) var(--font-pixel);
    letter-spacing: 0.06em;
    text-transform: uppercase;
    color: var(--accent);
  }
  .big {
    font: 700 min(1.5rem, 34px) / 1.05 var(--font-display);
    color: var(--cream);
    font-variant-numeric: tabular-nums;
  }
  .sub {
    font: 400 min(0.8rem, 22px) / 1.35 var(--font-ui);
    color: rgb(244 236 216 / 0.72);
  }
  .row {
    display: flex;
    align-items: center;
    gap: 8px;
    min-height: 30px;
    padding: 0 10px;
    border-radius: 8px;
    background: rgb(244 236 216 / 0.05);
    font: 600 min(0.8rem, 22px) var(--font-ui);
    color: var(--cream);
  }
  .row em {
    margin-left: auto;
    font-style: normal;
    font-weight: 500;
    color: var(--accent);
    font-variant-numeric: tabular-nums;
  }
  .row.free {
    font-weight: 500;
    color: rgb(244 236 216 / 0.6);
    background: repeating-linear-gradient(90deg, rgb(244 236 216 / 0.08) 0 2px, transparent 2px 6px);
  }
  .box {
    width: 12px;
    height: 12px;
    box-shadow: inset 0 0 0 2px rgb(244 236 216 / 0.6);
  }
  .week {
    display: grid;
    grid-template-columns: repeat(6, 1fr);
    grid-template-rows: 16px repeat(7, 13px);
    gap: 3px;
  }
  .day {
    text-align: center;
    font: 500 min(0.62rem, 18px) var(--font-pixel);
    color: rgb(244 236 216 / 0.6);
  }
  .blk {
    border-radius: 2px;
  }
  .t1 {
    background: color-mix(in srgb, var(--accent) 85%, transparent);
  }
  .t2 {
    background: rgb(122 170 220 / 0.75);
  }
  .t3 {
    background: rgb(200 90 110 / 0.75);
  }
  .t4 {
    background: rgb(120 200 160 / 0.7);
  }
  .card {
    display: grid;
    gap: 6px;
    padding: 12px;
    border-radius: 10px;
    background: rgb(244 236 216 / 0.07);
    box-shadow: inset 0 0 0 1px rgb(244 236 216 / 0.12);
  }
  .q {
    font: 500 min(0.85rem, 23px) / 1.3 var(--font-ui);
    color: rgb(244 236 216 / 0.8);
  }
  .a {
    font: 700 min(1.2rem, 30px) var(--font-display);
    color: var(--cream);
    animation: reveal 0.3s steps(3, end) 1.2s both;
  }
  @keyframes reveal {
    from {
      opacity: 0;
    }
  }
  .dots {
    display: flex;
    align-items: center;
    gap: 6px;
  }
  .dots i {
    width: 6px;
    height: 6px;
    background: rgb(244 236 216 / 0.25);
  }
  .dots i.on {
    background: var(--portal-gold);
  }
  .dots small {
    margin-left: auto;
  }
  .peek:focus-visible {
    outline: 2px solid var(--portal-gold);
    outline-offset: 3px;
  }
  @media (prefers-reduced-motion: reduce) {
    .peek,
    .body,
    .a {
      animation: none;
    }
  }
</style>
