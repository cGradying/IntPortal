<script lang="ts">
  // Spec 058 C1–C4: search everything on the site. A native modal <dialog>, so
  // focus stays inside and Escape closes it; the index loads on first open.
  import { onMount, tick } from "svelte";
  import { afterNavigate } from "$app/navigation";
  import PixelIcon from "$app_lib/PixelIcon.svelte";
  import { KINDS, PAGES, search, type Hit } from "./search";

  let dialog = $state<HTMLDialogElement>();
  let field = $state<HTMLInputElement>();
  let list = $state<HTMLElement>();
  let index = $state<Hit[] | null>(null);
  let failed = $state(false);
  let q = $state("");
  let at = $state(0);

  const groups = $derived([...search(index ?? PAGES, q)].map(([kind, hits]) => ({ name: KINDS.find((k) => k.kind === kind)!.name, hits })));
  const flat = $derived(groups.flatMap((g) => g.hits));
  const count = $derived(flat.length);

  $effect(() => {
    void q;
    at = 0;
  });

  /** Opens the search, with `text` in the field when given (060 C18). */
  export async function open(text?: string) {
    if (!dialog || dialog.open) return;
    dialog.showModal();
    if (text) {
      q = text;
      await tick();
    }
    field?.select();
    if (index) return;
    try {
      const r = await fetch("/search.json");
      if (!r.ok) throw new Error(String(r.status));
      index = await r.json();
      failed = false;
    } catch {
      failed = true;
    }
  }

  const typing = (t: EventTarget | null) => t instanceof HTMLElement && (t.isContentEditable || /^(INPUT|TEXTAREA|SELECT)$/.test(t.tagName));

  function global(e: KeyboardEvent) {
    if ((e.key === "k" && (e.metaKey || e.ctrlKey)) || (e.key === "/" && !typing(e.target) && !e.metaKey && !e.ctrlKey && !e.altKey)) {
      e.preventDefault();
      open();
    }
  }

  function move(e: KeyboardEvent) {
    // A search field eats the first Escape to clear itself; close at once instead.
    if (e.key === "Escape") {
      e.preventDefault();
      return dialog?.close();
    }
    if (!count) return;
    if (e.key === "ArrowDown" || e.key === "ArrowUp") {
      e.preventDefault();
      at = (at + (e.key === "ArrowDown" ? 1 : -1) + count) % count;
      list?.querySelector(`#hit-${at}`)?.scrollIntoView({ block: "nearest" });
    } else if (e.key === "Enter") {
      e.preventDefault();
      list?.querySelector<HTMLAnchorElement>(`#hit-${at}`)?.click();
    }
  }

  afterNavigate(() => dialog?.close());

  // Any page can open it: dispatchEvent(new CustomEvent("site-search", { detail: { q } })).
  onMount(() => {
    const on = (e: Event) => open((e as CustomEvent<{ q?: string } | null>).detail?.q);
    addEventListener("site-search", on);
    return () => removeEventListener("site-search", on);
  });
</script>

<svelte:window onkeydown={global} />

<!-- svelte-ignore a11y_click_events_have_key_events, a11y_no_noninteractive_element_interactions -->
<dialog bind:this={dialog} aria-label="Search" onclick={(e) => e.target === dialog && dialog?.close()} onclose={() => (q = "")}>
  <div class="box">
    <div class="bar">
      <PixelIcon name="search" size={18} />
      <input
        bind:this={field}
        bind:value={q}
        onkeydown={move}
        type="search"
        placeholder="Search features, help and releases"
        aria-label="Search"
        role="combobox"
        aria-expanded={count > 0}
        aria-controls="hits"
        aria-autocomplete="list"
        aria-activedescendant={count ? `hit-${at}` : undefined}
        autocomplete="off"
        spellcheck="false"
      />
      <button class="x" aria-label="Close the search" onclick={() => dialog?.close()}><PixelIcon name="close" size={16} /></button>
    </div>
    {#if failed}<p class="note">Search didn't load. Check your connection.</p>{/if}
    {#if !count}<p class="note">Nothing called that yet. <a href="/help" onclick={() => dialog?.close()}>Help</a> might know.</p>{/if}
    <div class="hits" id="hits" role="listbox" aria-label="Results" bind:this={list}>
      {#each groups as g (g.name)}
        <p class="kind pixel" aria-hidden="true">{g.name}</p>
        {#each g.hits as h (h.href)}
          {@const i = flat.indexOf(h)}
          <a id="hit-{i}" href={h.href} role="option" aria-selected={i === at} class:on={i === at} onmousemove={() => (at = i)} onclick={() => dialog?.close()}>
            <span class="t">{h.title}</span>
            <span class="l">{h.line}</span>
          </a>
        {/each}
      {/each}
    </div>
    <p class="keys pixel" aria-hidden="true">↑↓ to move · Enter to open · Esc to close</p>
    <p class="sr" aria-live="polite">{q ? `${count} ${count === 1 ? "result" : "results"}` : ""}</p>
  </div>
</dialog>

<style>
  dialog {
    width: min(640px, calc(100vw - 32px));
    max-height: min(560px, calc(100svh - 96px));
    margin: max(64px, 12vh) auto auto;
    padding: 0;
    border: 0;
    border-radius: 14px;
    background: var(--card);
    color: var(--site-ink);
    box-shadow: inset 0 0 0 1px var(--edge-2), 0 40px 80px -20px rgba(0, 0, 0, 0.9);
    overflow: hidden;
  }
  dialog[open] {
    display: flex;
    animation: rise 120ms var(--ease);
  }
  dialog::backdrop {
    background: rgba(5, 3, 8, 0.72);
    backdrop-filter: blur(2px);
  }
  .box {
    display: flex;
    flex-direction: column;
    width: 100%;
    min-height: 0;
  }
  .bar {
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 0 8px 0 18px;
    color: var(--site-ink-3);
    box-shadow: inset 0 -1px 0 var(--site-line);
  }
  input {
    flex: 1;
    min-width: 0;
    height: 60px;
    border: 0;
    background: none;
    color: var(--site-ink);
    font: 500 1.1rem/1 var(--site-body);
    outline: none;
    caret-color: var(--gold);
  }
  input::placeholder {
    color: var(--site-ink-3);
  }
  input::-webkit-search-cancel-button {
    display: none;
  }
  .x {
    display: grid;
    place-items: center;
    width: 44px;
    height: 44px;
    border: 0;
    border-radius: var(--radius);
    background: none;
    color: var(--site-ink-3);
    cursor: pointer;
  }
  .x:hover {
    color: var(--site-ink);
    background: rgba(244, 236, 216, 0.06);
  }
  .hits {
    flex: 1;
    min-height: 0;
    overflow-y: auto;
    overscroll-behavior: contain;
    padding: 6px 8px 10px;
  }
  .kind {
    margin: 14px 10px 6px;
    color: var(--site-ink-3);
    font-size: 0.72rem;
    letter-spacing: 0.06em;
  }
  .hits > a {
    display: grid;
    gap: 1px;
    padding: 9px 12px;
    border-radius: 8px;
    text-decoration: none;
    scroll-margin: 8px;
  }
  .hits > a.on {
    background: var(--gold-soft);
  }
  .t {
    font-weight: 600;
    color: var(--site-ink);
  }
  .on .t {
    color: var(--gold);
  }
  .l {
    overflow: hidden;
    color: var(--site-ink-2);
    font-size: 0.9rem;
    white-space: nowrap;
    text-overflow: ellipsis;
  }
  .note {
    margin: 18px 12px;
    color: var(--site-ink-2);
  }
  .keys {
    margin: 0;
    padding: 10px 18px;
    color: var(--site-ink-3);
    font-size: 0.7rem;
    box-shadow: inset 0 1px 0 var(--site-line);
  }
  @media (pointer: coarse) {
    .keys {
      display: none;
    }
  }
  .sr {
    position: absolute;
    width: 1px;
    height: 1px;
    overflow: hidden;
    clip-path: inset(50%);
  }
  @keyframes rise {
    from {
      opacity: 0;
      transform: translateY(6px);
    }
  }
  @media (prefers-reduced-motion: reduce) {
    dialog[open] {
      animation: none;
    }
  }
</style>
