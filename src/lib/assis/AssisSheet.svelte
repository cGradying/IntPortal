<script lang="ts">
  // Talking to LAR. His lines sit on the obsidian slab with his pixel tag;
  // yours are quiet. When he offers to do something, a card says exactly
  // what, and nothing changes until you tap the gold button.
  import { tick } from "svelte";
  import { closable } from "../back";
  import { buzz } from "../haptics";
  import Lar from "../lar/Lar.svelte";
  import { app, openNote } from "../state.svelte";
  import { describe, starters as startersFor } from "./apply";
  import { apply, ask, assis, dismiss, newChat, stop } from "./assis.svelte";

  let { onclose }: { onclose: () => void } = $props();
  $effect(() => closable(() => onclose()));

  // With the keyboard up, iOS shrinks the visual viewport and scrolls the page,
  // so a bottom-pinned sheet would slide its top off screen. Follow the visual
  // viewport instead while it is smaller than the window.
  let vv = $state({ h: innerHeight, top: 0 });
  const keyboard = $derived(vv.h < innerHeight - 120);
  $effect(() => {
    const v = window.visualViewport;
    if (!v) return;
    const sync = () => (vv = { h: v.height, top: v.offsetTop });
    sync();
    v.addEventListener("resize", sync);
    v.addEventListener("scroll", sync);
    return () => {
      v.removeEventListener("resize", sync);
      v.removeEventListener("scroll", sync);
    };
  });

  let draft = $state("");
  let log: HTMLElement | undefined = $state();
  const starters = $derived(startersFor(!!app.editing));
  const last = $derived(assis.chat[assis.chat.length - 1]);
  // Dots show from the moment a message is sent until the first word arrives.
  const waiting = $derived(assis.busy === "waking" || (assis.busy === "thinking" && !last?.text));
  const writing = $derived(assis.busy === "thinking");

  async function send(text: string) {
    draft = "";
    buzz.select();
    const sending = ask(text);
    await tick();
    log?.scrollTo({ top: log.scrollHeight });
    await sending;
    await tick();
    log?.scrollTo({ top: log.scrollHeight, behavior: "smooth" });
  }

  function prefill(s: { label: string; fill: boolean }) {
    // Starters that need the student's own words fill the field; the rest just ask.
    if (s.fill) draft = s.label;
    else send(s.label);
  }

  /** The sheet sits above the editor, so a source chip closes it and shows the note. */
  function show(key: string, title: string) {
    onclose();
    openNote(key, title);
  }
</script>

<div class="scrim" role="presentation" onclick={onclose}></div>
<!-- A frame that is exactly the visual viewport, so the keyboard shrinks it and
     the sheet stays inside it, whatever the page scrolled to. -->
<div class="frame" class:typing={keyboard} style:top="{vv.top}px" style:height="{vv.h}px">
<div class="sheet notch" role="dialog" aria-label="Ask LAR">
  <header>
    <span class="tag">LAR</span>
    <span class="head">
      {#if assis.chat.length && !assis.busy}<button class="x" onclick={newChat}>New chat</button>{/if}
      <button class="x" onclick={onclose} aria-label="Close">Close</button>
    </span>
  </header>

  <div class="log" bind:this={log} aria-live="polite">
    {#if !assis.chat.length}
      <div class="lar hello"><Lar size={2} cube={false} gesture="wave" /><p>Hi! Ask me about your classes, what's due, or your grades. I can also save a note or set a reminder, if you say so.</p></div>
      <div class="starters">
        {#each starters as s (s.label)}<button onclick={() => prefill(s)}>{s.label}</button>{/each}
      </div>
    {/if}
    {#each assis.chat as m, i (i)}
      {#if m.from === "me"}
        <p class="me">{m.text}</p>
      {:else}
        {#if m.text}<div class="lar"><p>{m.text}</p></div>{/if}
        {#if m.sources}
          <div class="from">
            {#each m.sources as src (src.key)}<button onclick={() => show(src.key, src.title)}>From: {src.title}</button>{/each}
          </div>
        {/if}
        {#if m.proposal}
          {@const d = describe(m.proposal)}
          <div class="offer card notch" class:done={m.state === "done"}>
            <p class="label">{d.label}</p>
            <p class="what">{d.text}</p>
            {#if m.state === "pending"}
              <div class="two">
                <button class="yes" onclick={() => apply(i)} disabled={assis.busy === "cards"}>{assis.busy === "cards" ? "Making…" : d.yes}</button>
                <button class="no" onclick={() => dismiss(i)}>Not now</button>
              </div>
            {:else if m.state === "done"}
              <p class="ok">Done</p>
            {:else}
              <p class="fine">Skipped</p>
            {/if}
            {#if m.problem}<p class="problem">{m.problem}</p>{/if}
          </div>
        {/if}
      {/if}
    {/each}
    {#if waiting}
      <div class="lar" aria-label="LAR is thinking"><p class="think">{assis.busy === "waking" ? "Waking up" : "Thinking"}<i></i><i></i><i></i></p></div>
    {/if}
  </div>

  <form onsubmit={(e) => { e.preventDefault(); send(draft); }}>
    <input bind:value={draft} placeholder="Ask LAR…" aria-label="Message LAR" enterkeyhint="send" autocomplete="off" />
    {#if writing}
      <button class="send" type="button" onclick={stop}>Stop</button>
    {:else}
      <button class="send" type="submit" disabled={!draft.trim() || !!assis.busy}>Send</button>
    {/if}
  </form>
  <p class="fine">Runs on this phone. Nothing leaves it.</p>
</div>
</div>

<style>
  .scrim {
    position: fixed;
    inset: 0;
    z-index: 60;
    background: rgba(0, 0, 0, 0.45);
    animation: fade 0.2s both;
  }
  .frame {
    position: fixed;
    left: var(--gutter);
    right: var(--gutter);
    z-index: 61;
    display: flex;
    align-items: flex-end;
    padding: calc(var(--safe-top) + 8px) 0 calc(var(--safe-bottom) + 12px);
    pointer-events: none;
  }
  .frame.typing {
    padding-bottom: 8px;
  }
  .sheet {
    --step: 4px;
    pointer-events: auto;
    width: 100%;
    max-height: 100%;
    display: grid;
    grid-template-rows: auto minmax(0, 1fr) auto auto;
    gap: 10px;
    height: min(78%, 640px);
    padding: 14px 14px 12px;
    background: var(--card-2);
    animation: rise 0.35s var(--ease) both;
  }
  header {
    display: flex;
    justify-content: space-between;
    align-items: center;
  }
  .tag {
    font-family: var(--font-pixel);
    font-size: min(0.706rem, 22px);
    letter-spacing: 0.08em;
    color: var(--gold);
  }
  .head {
    display: flex;
    gap: 4px;
  }
  .from {
    display: flex;
    flex-wrap: wrap;
    gap: 6px;
  }
  .from button {
    min-height: 40px;
    max-width: 100%;
    padding: 6px 10px;
    border: 0;
    border-radius: 10px;
    background: var(--sunk);
    box-shadow: inset 0 0 0 1px var(--edge);
    color: var(--ink-2);
    font-size: min(0.765rem, 23px);
    text-align: left;
    overflow-wrap: anywhere;
  }
  .x {
    height: 32px;
    padding: 0 10px;
    border: 0;
    background: none;
    color: var(--ink-2);
    text-decoration: underline;
  }
  .log {
    display: grid;
    align-content: start;
    gap: 10px;
    overflow-y: auto;
    overscroll-behavior: contain;
    padding-right: 2px;
  }
  .lar {
    justify-self: start;
    max-width: 92%;
    padding: 10px 12px;
    background: #170b1a;
    color: #f4e8d6;
    box-shadow: inset 0 2px 0 #3a2446, inset 0 -2px 0 #060307;
  }
  .lar p {
    margin: 0;
    font-size: min(0.824rem, 25px);
    line-height: 1.4;
    white-space: pre-line;
  }
  .hello {
    display: flex;
    gap: 10px;
    align-items: center;
    max-width: 100%;
  }
  .me {
    justify-self: end;
    max-width: 85%;
    margin: 0;
    padding: 9px 12px;
    background: var(--sunk);
    box-shadow: inset 0 0 0 1px var(--edge);
    border-radius: 12px;
    font-size: min(0.882rem, 27px);
    line-height: 1.35;
  }
  .starters {
    display: flex;
    flex-wrap: wrap;
    gap: 8px;
  }
  .starters button {
    min-height: 40px;
    padding: 6px 12px;
    border: 0;
    border-radius: 10px;
    background: var(--sunk);
    box-shadow: inset 0 0 0 1px var(--edge);
    font-size: min(0.824rem, 25px);
    text-align: left;
  }
  .offer {
    --step: 4px;
    justify-self: start;
    width: 92%;
    display: grid;
    gap: 6px;
    padding: 12px;
  }
  .offer.done {
    opacity: 0.7;
  }
  .what {
    margin: 0;
    font-size: min(0.941rem, 29px);
    line-height: 1.35;
    overflow-wrap: anywhere;
  }
  .two {
    display: grid;
    grid-template-columns: 1.3fr 1fr;
    gap: 8px;
    margin-top: 4px;
  }
  .two button,
  .send {
    height: 44px;
    border: 0;
    border-radius: 10px;
    font-family: var(--font-display);
    font-weight: 700;
    font-size: min(0.824rem, 25px);
  }
  .yes,
  .send {
    background: var(--gold);
    color: var(--on-gold);
  }
  .no {
    background: var(--sunk);
    box-shadow: inset 0 0 0 1px var(--edge);
  }
  button:disabled {
    opacity: 0.45;
  }
  .ok,
  .fine {
    margin: 0;
    font-size: min(0.765rem, 23px);
    color: var(--ink-3);
  }
  .ok {
    color: var(--good);
    font-weight: 600;
  }
  .problem {
    margin: 0;
    font-size: min(0.765rem, 23px);
    color: var(--bad);
  }
  form {
    display: grid;
    grid-template-columns: 1fr auto;
    gap: 8px;
  }
  input {
    min-width: 0;
    height: 44px;
    padding: 0 12px;
    border: 0;
    border-radius: 10px;
    background: var(--sunk);
    box-shadow: inset 0 0 0 1px var(--edge);
    color: var(--ink);
    font: inherit;
    font-size: max(16px, min(0.941rem, 29px));
  }
  .send {
    padding: 0 16px;
  }
  @media (prefers-reduced-motion: reduce) {
    .think i {
      animation: none;
    }
  }
  .think i {
    display: inline-block;
    width: 4px;
    height: 4px;
    margin-left: 4px;
    background: var(--gold);
    animation: blink 1s steps(2, jump-none) infinite;
  }
  .think i:nth-child(2) { animation-delay: 0.2s; }
  .think i:nth-child(3) { animation-delay: 0.4s; }
  @keyframes fade {
    from { opacity: 0; }
  }
  @keyframes rise {
    from { opacity: 0; transform: translateY(24px); }
  }
  @keyframes blink {
    50% { opacity: 0.2; }
  }
</style>
