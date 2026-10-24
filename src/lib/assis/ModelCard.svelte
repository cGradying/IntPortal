<script lang="ts">
  // The Storage card for LAR's brain. Light is the default: nothing is
  // downloaded unless the student asks, and they can take it off again.
  import { assis, cancelDownload, chatModel, embedModel, install, installed, larStyle, mb, open, remove, setLarStyle, STYLE_MAX } from "./assis.svelte";
  import { buzz } from "../haptics";

  const m = $derived(chatModel());
  const e = $derived(embedModel());
  // Both models install together; someone who added only LAR's brain before can add the note search later.
  const total = $derived((m?.bytes ?? 0) + (e && !e.installed ? e.bytes : 0));
  const searchMissing = $derived(!!e && !e.installed);
  const pct = $derived(assis.total ? Math.min(100, Math.round((assis.done / assis.total) * 100)) : 0);
  let confirming = $state(false);
  let style = $state(larStyle());
</script>

{#if m}
  <section class="card notch block" aria-label="IntAssis">
    <p class="label">IntAssis</p>
    {#if assis.busy === "downloading"}
      <div class="line"><span>Downloading IntAssis</span><strong class="num">{pct}%</strong></div>
      <div class="bar" role="progressbar" aria-valuenow={pct} aria-valuemin="0" aria-valuemax="100"><i style:width="{pct}%"></i></div>
      <p class="fine">{mb(assis.done)} of {mb(assis.total)}. Keep this open; if it stops, tap again and it carries on.</p>
      <button class="ghost" onclick={cancelDownload}>Pause</button>
    {:else if installed()}
      <div class="line"><span>On · {m.name}</span><strong>{mb(m.bytes + (e?.installed ? e.bytes : 0))} on this phone</strong></div>
      <p class="fine">{searchMissing ? "LAR answers from your schedule and grades." : "LAR answers from your schedule, grades and notes, and can summarize or tidy a note."} It runs on this phone, so it works offline and nothing is sent anywhere.</p>
      <button class="primary" onclick={open}>Ask LAR</button>
      <label class="style">
        <span class="label">How LAR talks to me</span>
        <textarea bind:value={style} oninput={() => setLarStyle(style)} maxlength={STYLE_MAX} rows="2" placeholder="Optional, like “call me Ate” or “Taglish, a bit playful”"></textarea>
        <span class="fine">{style.length}/{STYLE_MAX}. Only changes how LAR sounds; it still follows its own rules and never changes your data without your tap.</span>
      </label>
      {#if searchMissing && e}
        <button class="ghost" onclick={() => { buzz.tick(); install(); }}>Add note search · {mb(e.bytes)}</button>
      {/if}
      {#if confirming}
        <div class="row">
          <button class="danger" onclick={() => { confirming = false; remove(); }}>Remove, free {mb(m.bytes + (e?.installed ? e.bytes : 0))}</button>
          <button class="ghost" onclick={() => (confirming = false)}>Keep</button>
        </div>
      {:else}
        <button class="ghost" onclick={() => (confirming = true)}>Remove from this phone</button>
      {/if}
    {:else}
      <div class="line"><span>Light</span><strong>No AI, nothing downloaded</strong></div>
      <p class="fine">Add IntAssis to ask LAR about your classes, deadlines, grades and notes, to save a note or a reminder by asking, and to make flashcards on a topic. It is a one-time {mb(total)} download (use Wi-Fi) and it works offline after that.</p>
      {#if m.fits === "refuse"}
        <p class="fine warn">This phone doesn't have enough free memory for it right now. Close other apps and open this again.</p>
      {:else}
        {#if m.fits === "warn"}<p class="fine warn">It may be a tight fit on this phone; LAR could be slow.</p>{/if}
        <button class="primary" onclick={() => { buzz.tick(); install(); }}>Add IntAssis · {mb(total)}</button>
      {/if}
    {/if}
    {#if assis.error}<p class="fine warn">{assis.error}</p>{/if}
  </section>
{/if}

<style>
  .block {
    --step: 4px;
    display: grid;
    gap: 10px;
    padding: 16px;
  }
  .line {
    display: flex;
    justify-content: space-between;
    gap: 12px;
    font-size: min(0.882rem, 27px);
    color: var(--ink-2);
  }
  .line strong {
    color: var(--ink);
    font-weight: 600;
    text-align: right;
  }
  .fine {
    margin: 0;
    font-size: min(0.765rem, 23px);
    line-height: 1.4;
    color: var(--ink-3);
  }
  .warn {
    color: var(--ink-2);
  }
  .style {
    display: grid;
    gap: 6px;
  }
  textarea {
    min-width: 0;
    padding: 10px 12px;
    border: 0;
    border-radius: 10px;
    background: var(--sunk);
    box-shadow: inset 0 0 0 1px var(--edge);
    color: var(--ink);
    font: inherit;
    font-size: max(16px, min(0.941rem, 29px));
    resize: none;
  }
  .bar {
    height: 10px;
    background: var(--sunk);
    box-shadow: inset 0 0 0 1px var(--edge);
  }
  .bar i {
    display: block;
    height: 100%;
    background: var(--gold);
    transition: width 0.4s linear;
  }
  button {
    height: 44px;
    border: 0;
    border-radius: 10px;
    font-family: var(--font-display);
    font-weight: 700;
    font-size: min(0.824rem, 25px);
  }
  .primary {
    background: var(--gold);
    color: var(--on-gold);
  }
  .ghost {
    background: var(--sunk);
    box-shadow: inset 0 0 0 1px var(--edge);
  }
  .danger {
    background: var(--bad);
    color: #fff;
  }
  .row {
    display: grid;
    grid-template-columns: 1.4fr 1fr;
    gap: 8px;
  }
</style>
