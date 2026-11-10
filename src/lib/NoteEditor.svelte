<script lang="ts">
  // A full-screen page for one note (spec 046 C9–C14, C17a, C18–C20). The text is
  // plain Markdown, shown formatted as it is typed (CodeMirror 6, `editor/cm.ts`);
  // every edit is a pure function in `editor/md.ts`. The crystal's + opens the
  // tools, Aa the page's look, the dots this note's options. It saves while you
  // type, never blank text, and again on Done.
  import { onMount, untrack } from "svelte";
  import { api, isoDate, type Deck } from "./api";
  import { appended, replaced } from "./assis/apply";
  import { assis, indexNotes, installed, noteAi, stop, type NoteMode } from "./assis/assis.svelte";
  import { tidy, type Draft } from "./assis/cards";
  import { closable } from "./back";
  import type { NoteView } from "./editor/cm";
  import { addEntry, applyTemplate, block, cardLines, entryHeading, setLines, TEMPLATES, toggleCheck, words, wrap, type CardLine, type Edit, type Inline, type LineKind, type Template } from "./editor/md";
  import { readLook, writeLook, type PageLook } from "./editor/page";
  import { buzz } from "./haptics";
  import PixelIcon, { type SpriteName } from "./PixelIcon.svelte";
  import { shareFile } from "./share";
  import { app, refreshNotes } from "./state.svelte";

  let { key, heading, title, entry = false }: { key: string; heading: string; title: string | null; subject?: string; entry?: boolean } = $props();

  const item = $derived(app.notes.find((n) => n.key === key));
  // svelte-ignore state_referenced_locally
  let text = $state(app.notes.find((n) => n.key === key)?.text ?? "");
  /** What the core last holds for this note: LAR's additions are measured against it (C12a). */
  let lastSaved = untrack(() => text);
  const named = $derived(key.startsWith("note:"));
  // svelte-ignore state_referenced_locally
  let name = $state(title ?? "");
  let saved = $state(true);
  let problem = $state("");
  let timer: ReturnType<typeof setTimeout> | undefined;

  let host: HTMLDivElement;
  let nv: NoteView | null = null;
  let sel = $state<[number, number]>([0, 0]);
  let focused = $state(false);
  let can = $state({ undo: false, redo: false });
  let look = $state<PageLook>(readLook());
  type Sheet = "tools" | "page" | "note" | "templates" | "ai" | "move" | "find" | "cards";
  let sheet = $state<Sheet | null>(null);
  let confirming = $state(false);

  // ------------------------------------------------------------ saving

  async function save() {
    clearTimeout(timer);
    // Blank text is never saved: select-all and retype loses nothing (C17a).
    if (!text.trim()) return;
    const body = text;
    try {
      await api.setNote(key, body, named ? name.trim() || null : title);
      lastSaved = body;
      // A note started in a notebook joins it once it has text (046 C2).
      const filed = app.editing?.subject;
      if (filed && app.editing) {
        await api.setNoteSubject(key, filed);
        app.editing.subject = undefined;
      }
      saved = text === body;
      problem = "";
      refreshNotes();
    } catch (e) {
      problem = String(e);
    }
  }

  function typed() {
    saved = false;
    clearTimeout(timer);
    if (text.trim()) timer = setTimeout(save, 600);
  }

  // LAR's text added to this note while it is open shows here, and the next save keeps it (C12a).
  $effect(() => {
    const ext = item?.text;
    if (ext === undefined || ext === lastSaved) return;
    untrack(() => {
      const merged = ext.startsWith(lastSaved) ? text + ext.slice(lastSaved.length) : saved ? ext : text;
      lastSaved = ext;
      if (merged === text) return;
      text = merged;
      nv?.set(merged);
      if (!saved) typed();
    });
  });

  async function done() {
    clearTimeout(timer);
    // Closing on blank text deletes the note (C17a).
    if (!text.trim()) {
      if (item) await api.setNote(key, "", null).then(refreshNotes).catch((e) => (problem = String(e)));
    } else if (!saved) await save();
    if (problem) return;
    indexNotes();
    app.editing = null;
  }

  async function remove() {
    clearTimeout(timer);
    try {
      await api.setNote(key, "", null);
      await refreshNotes();
      app.editing = null;
    } catch (e) {
      problem = String(e);
    }
  }

  async function share() {
    if (!saved) await save();
    try {
      const md = await api.notesMarkdown(key);
      if (md) await shareFile(`${(named ? name.trim() : heading) || "Note"}.md`, "text/markdown", md);
    } catch (e) {
      problem = String(e);
    }
  }

  // ------------------------------------------------------------ the page

  onMount(() => {
    let dead = false;
    // The editor loads with the first note opened, not with the app (C9: its size is in the PR).
    import("./editor/cm").then(({ mountNote }) => {
      if (dead) return;
      nv = mountNote(
        host,
        text,
        {
          change: (t) => {
            text = t;
            can = nv?.can() ?? can;
            typed();
          },
          select: (a, b) => (sel = [a, b]),
          tick,
        },
        named ? "Write anything." : "What was discussed, what's due, what to review.",
      );
      const v = nv.view;
      const f = () => (focused = v.hasFocus);
      v.contentDOM.addEventListener("focus", f);
      v.contentDOM.addEventListener("blur", f);
      // A new note asks what to start from, unless the page says otherwise (C11a, C13).
      if (!item && !text) {
        if (entry) void entryNow();
        else if (look.start === "Ask") sheet = "templates";
        else if (look.start === "Last used" && look.last !== "blank") void template(look.last);
        else v.focus();
      } else if (entry) void entryNow();
    });
    return () => {
      dead = true;
      nv?.destroy();
      nv = null;
    };
  });

  // The + is this page's (C11).
  $effect(() => {
    assis.plus = () => (sheet = sheet === "tools" ? null : "tools");
    return () => (assis.plus = null);
  });
  $effect(() => closable(() => (sheet ? (sheet = null) : void done())));

  // Keep the screen awake while writing, if asked (C11a).
  $effect(() => {
    if (!look.awake || !("wakeLock" in navigator)) return;
    let lock: WakeLockSentinel | null = null;
    navigator.wakeLock.request("screen").then((l) => (lock = l)).catch(() => {});
    return () => void lock?.release();
  });

  function setLook(p: Partial<PageLook>) {
    look = { ...look, ...p };
    writeLook(look);
  }

  function run(e: Edit) {
    nv?.apply(e);
    nv?.view.focus();
  }
  const inline = (k: Inline) => run(wrap(text, sel[0], sel[1], k));
  const line = (k: LineKind) => run(setLines(text, sel[0], sel[1], k));

  /** A checklist tick saves at once and never opens the keyboard (C12). */
  function tick(at: number) {
    const t = toggleCheck(text, at);
    if (t === text) return;
    buzz.tick();
    text = t;
    nv?.set(t);
    void save();
  }

  async function todayHeading() {
    const today = isoDate(new Date());
    if (!key.startsWith("class:")) return entryHeading(today);
    const at = await api.entryDate(key.slice(6), today).catch(() => today);
    return entryHeading(at);
  }
  /** Add entry (C14): a dated heading, once, with the cursor under it. */
  async function entryNow() {
    run(addEntry(text, await todayHeading()));
  }
  async function template(id: Template) {
    sheet = null;
    setLook({ last: id });
    run(applyTemplate(text, id, id === "log" ? await todayHeading() : undefined));
  }

  const TOOLS: [string, string, SpriteName][] = [
    ["h", "Heading", "h"],
    ["bold", "Bold", "bold"],
    ["italic", "Italic", "italic"],
    ["mark", "Highlight", "mark"],
    ["strike", "Strike", "strike"],
    ["bullet", "Bullets", "bullet"],
    ["number", "Numbers", "number"],
    ["check", "Checklist", "check"],
    ["quote", "Quote", "quote"],
    ["code", "Code", "code"],
    ["divider", "Divider", "divider"],
    ["date", "Date entry", "date"],
    ["photo", "Photo", "photo"],
    ["tmpl", "Template", "tmpl"],
    ["cards", "Make cards", "cards"],
  ];
  function tool(c: string) {
    sheet = null;
    buzz.tick();
    if (c === "bold" || c === "italic" || c === "mark" || c === "strike") return inline(c);
    if (c === "h" || c === "bullet" || c === "number" || c === "check" || c === "quote") return line(c);
    if (c === "code" || c === "divider") return run(block(text, sel[1], c));
    if (c === "date") return void entryNow();
    if (c === "tmpl") return void (sheet = "templates");
    if (c === "cards") return startCards();
  }

  // ------------------------------------------------------------ this note

  const subjects = $derived<[string, string][]>([...new Map((app.snapshot?.sessions ?? []).map((s) => [s.subject_code, s.description] as [string, string])).entries()]);
  const subjectOf = $derived(key.startsWith("class:") ? key.slice(6) : (item?.subject ?? app.editing?.subject ?? null));

  async function pin() {
    if (!saved || !item) await save();
    await api.setNotePin(key, !item?.pinned).catch((e) => (problem = String(e)));
    await refreshNotes();
    sheet = null;
  }
  async function move(code: string | null) {
    if (!saved || !item) await save();
    await api.setNoteSubject(key, code).catch((e) => (problem = String(e)));
    await refreshNotes();
    sheet = null;
  }

  let find = $state("");
  let findMiss = $state(false);
  function findNext() {
    const q = find.trim().toLowerCase();
    if (!q || !nv) return;
    const hay = text.toLowerCase();
    let at = hay.indexOf(q, sel[1]);
    if (at < 0) at = hay.indexOf(q);
    findMiss = at < 0;
    if (at >= 0) nv.apply({ text, from: at, to: at + q.length });
  }

  // ------------------------------------------------------------ Ask LAR (020)

  let question = $state("");
  let out = $state("");
  let mode: NoteMode | null = $state(null);
  let range = $state<[number, number]>([0, 0]);
  let before: string | null = $state(null);
  let aiProblem = $state("");
  const working = $derived(assis.busy === "thinking" || assis.busy === "waking");

  async function ask(m: NoteMode) {
    if (working) return;
    const [a, b] = sel;
    const selection = b > a ? text.slice(a, b) : null;
    aiProblem = "";
    if (!text.trim()) return void (aiProblem = "There's nothing in this note to read yet.");
    if (m === "explain" && !selection) return void (aiProblem = "Select the words to explain first.");
    if (m === "ask" && !question.trim()) return void (aiProblem = "Type a question first.");
    [mode, out, before, range] = [m, "", null, selection ? [a, b] : [0, text.length]];
    try {
      out = await noteAi(m, text, selection, m === "ask" ? question : null, (w) => (out += w));
    } catch (e) {
      out = "";
      mode = null;
      aiProblem = typeof e === "string" ? e : ((e as Error)?.message ?? "Something went wrong. Try again.");
    }
  }
  function insertBelow() {
    const t = appended(text, out);
    run({ text: t, from: t.length, to: t.length });
    out = "";
    mode = null;
    before = null;
  }
  function replaceIt() {
    before = text;
    const t = replaced(text, range[0], range[1], out);
    run({ text: t, from: range[0], to: range[0] });
    out = "";
    mode = null;
  }
  function discard() {
    if (working) stop();
    out = "";
    mode = null;
  }

  // ------------------------------------------------------------ Make cards (C18–C20)

  let lines = $state<CardLine[]>([]);
  let drafts = $state<Draft[] | null>(null);
  let decks = $state<{ id: string; name: string; subject: string | null }[]>([]);
  let cardsMsg = $state("");
  const deckName = $derived((named ? name.trim() : heading) || subjectOf || "Note cards");
  const target = $derived(decks.find((d) => subjectOf && d.subject === subjectOf));

  async function startCards() {
    cardsMsg = "";
    drafts = null;
    lines = cardLines(text);
    if (!lines.length) return void (problem = "There's nothing in this note to make cards from yet.");
    sheet = "cards";
    decks = (await api.study(isoDate(new Date())).catch(() => null))?.decks ?? [];
  }
  function review() {
    drafts = lines.filter((l) => l.chosen).map((l) => ({ front: l.front, back: l.back }));
  }
  async function saveCards() {
    if (!drafts) return;
    try {
      const deck: Deck = target ? await api.deck(target.id) : { id: crypto.randomUUID(), name: deckName, subject: subjectOf, cards: [] };
      const fresh = tidy(drafts, deck.cards.map((c) => c.front));
      if (!fresh.length) return void (cardsMsg = "Those cards are already in the deck.");
      const blank = (f: string, b: string) => ({ id: "", front: f, back: b, accepted: [], memory: { due: 0, stability: 0, difficulty: 0, reps: 0, lapses: 0, last_review: null } });
      await api.saveDeck({ ...deck, cards: [...deck.cards, ...fresh.map((c) => blank(c.front, c.back))] });
      buzz.done();
      cardsMsg = `Saved ${fresh.length} ${fresh.length === 1 ? "card" : "cards"} to ${deck.name}.`;
      drafts = null;
    } catch (e) {
      cardsMsg = String(e);
    }
  }

  const count = $derived(words(text));
  const PAPER: [PageLook["paper"], string][] = [["plain", "Plain"], ["lines", "Lines"], ["dots", "Dots"], ["grid", "Grid"]];
</script>

<div class="editor" role="dialog" aria-label="Note: {heading}">
  <header>
    <button class="done" onclick={done}>Done</button>
    <span class="state">{!text.trim() ? "" : saved ? "Saved on this phone" : "Saving…"}</span>
    <div class="icons">
      <button class="ic" aria-label="Undo" disabled={!can.undo} onclick={() => nv?.undo()}><PixelIcon name="undo" size={22} /></button>
      <button class="ic" aria-label="Redo" disabled={!can.redo} onclick={() => nv?.redo()}><PixelIcon name="redo" size={22} /></button>
      <button class="ic" aria-label="Page look" aria-expanded={sheet === "page"} onclick={() => (sheet = "page")}><PixelIcon name="aa" size={22} /></button>
      <button class="ic" aria-label="This note" aria-expanded={sheet === "note"} onclick={() => (sheet = "note")}><PixelIcon name="dots" size={22} /></button>
    </div>
  </header>
  <div class="title">
    {#if named}
      <input class="name" bind:value={name} oninput={typed} placeholder="Name this note" aria-label="Note name" />
    {:else}
      <h2>{heading}</h2>
    {/if}
    {#if subjectOf}<small>{subjectOf}</small>{/if}
  </div>

  {#if focused && sel[1] > sel[0]}
    <div class="selbar" role="toolbar" aria-label="Format the selection">
      <button aria-label="Bold" onmousedown={(e) => e.preventDefault()} onclick={() => inline("bold")}><PixelIcon name="bold" size={20} /></button>
      <button aria-label="Italic" onmousedown={(e) => e.preventDefault()} onclick={() => inline("italic")}><PixelIcon name="italic" size={20} /></button>
      <button aria-label="Highlight" onmousedown={(e) => e.preventDefault()} onclick={() => inline("mark")}><PixelIcon name="mark" size={20} /></button>
      <button aria-label="Strike" onmousedown={(e) => e.preventDefault()} onclick={() => inline("strike")}><PixelIcon name="strike" size={20} /></button>
    </div>
  {/if}

  <div class="page" data-size={look.size} data-font={look.font} data-spacing={look.spacing} data-paper={look.paper} bind:this={host}></div>
  <footer>
    {#if problem}<p class="problem" role="alert">{problem}</p>{/if}
    {#if look.count}<p class="count">{count} {count === 1 ? "word" : "words"}</p>{/if}
  </footer>

  {#if sheet}
    <button class="scrim" aria-label="Close" onclick={() => (sheet = null)}></button>
    <div class="sheet card notch" role="dialog" aria-label={sheet}>
      {#if sheet === "tools"}
        <h4>Add to this note</h4>
        <div class="tools">
          {#if installed()}<button onclick={() => (sheet = "ai")}><PixelIcon name="ai" size={22} /><span>Ask LAR</span></button>{/if}
          {#each TOOLS as [c, label, icon] (c)}
            <button onclick={() => tool(c)} disabled={c === "photo"}><PixelIcon name={icon} size={22} /><span>{label}</span>{#if c === "photo"}<em>Soon</em>{/if}</button>
          {/each}
        </div>
      {:else if sheet === "templates"}
        <h4>Start from</h4>
        <div class="tgrid">
          {#each TEMPLATES as t (t.id)}
            <button onclick={() => template(t.id)}><strong>{t.name}</strong><small>{t.hint}</small></button>
          {/each}
        </div>
        {#if text.trim()}<p class="fine">It goes below what you've written, never over it.</p>{/if}
      {:else if sheet === "page"}
        <h4>Page</h4>
        <div class="seg" role="group" aria-label="Text size">{#each [["S", "Small"], ["M", "Medium"], ["L", "Large"]] as [v, l] (v)}<button aria-pressed={look.size === v} onclick={() => setLook({ size: v as PageLook["size"] })}>{l}</button>{/each}</div>
        <div class="seg" role="group" aria-label="Font">{#each [["phone", "Phone"], ["classic", "Classic"], ["mono", "Mono"]] as [v, l] (v)}<button aria-pressed={look.font === v} onclick={() => setLook({ font: v as PageLook["font"] })}>{l}</button>{/each}</div>
        <div class="seg" role="group" aria-label="Line spacing">{#each ["Tight", "Normal", "Roomy"] as v (v)}<button aria-pressed={look.spacing === v} onclick={() => setLook({ spacing: v as PageLook["spacing"] })}>{v}</button>{/each}</div>
        <div class="seg" role="group" aria-label="Paper">{#each PAPER as [v, l] (v)}<button aria-pressed={look.paper === v} onclick={() => setLook({ paper: v })}>{l}</button>{/each}</div>
        <p class="lab">A new note starts as</p>
        <div class="seg" role="group" aria-label="A new note starts as">{#each ["Ask", "Blank", "Last used"] as v (v)}<button aria-pressed={look.start === v} onclick={() => setLook({ start: v as PageLook["start"] })}>{v}</button>{/each}</div>
        <label class="sw"><span>Word count</span><input type="checkbox" checked={look.count} onchange={(e) => setLook({ count: e.currentTarget.checked })} /></label>
        <label class="sw"><span>Keep the screen awake while writing</span><input type="checkbox" checked={look.awake} onchange={(e) => setLook({ awake: e.currentTarget.checked })} /></label>
      {:else if sheet === "note"}
        <h4>This note</h4>
        <div class="menu">
          <button onclick={pin} disabled={!text.trim()}><PixelIcon name="pinn" size={18} />{item?.pinned ? "Unpin" : "Pin to the top"}</button>
          {#if named}<button onclick={() => (sheet = "move")} disabled={!text.trim()}><PixelIcon name="move" size={18} />Move to a subject<span class="val">{subjectOf ?? "General"}</span></button>{/if}
          <button onclick={() => (sheet = "find")}><PixelIcon name="find" size={18} />Find in note</button>
          <button onclick={share} disabled={!text.trim()}><PixelIcon name="share" size={18} />Share<span class="val">{count} {count === 1 ? "word" : "words"}</span></button>
          {#if item}<button class="danger" onclick={() => (confirming = true)}><PixelIcon name="trash" size={18} accent="var(--bad)" />Delete</button>{/if}
        </div>
        {#if confirming}
          <div class="confirm" role="alertdialog" aria-label="Delete this note?">
            <p>Delete this note? This can't be undone.</p>
            <button class="danger" onclick={remove}>Delete</button>
            <button onclick={() => (confirming = false)}>Cancel</button>
          </div>
        {/if}
      {:else if sheet === "move"}
        <h4>Move to a subject</h4>
        <div class="menu">
          <button onclick={() => move(null)} aria-pressed={!subjectOf}>General</button>
          {#each subjects as [code, desc] (code)}<button onclick={() => move(code)} aria-pressed={subjectOf === code}>{code}<span class="val">{desc}</span></button>{/each}
        </div>
      {:else if sheet === "find"}
        <h4>Find in note</h4>
        <form class="row" onsubmit={(e) => (e.preventDefault(), findNext())}>
          <!-- svelte-ignore a11y_autofocus -->
          <input bind:value={find} placeholder="Find…" aria-label="Find" enterkeyhint="search" autofocus />
          <button class="go" type="submit" disabled={!find.trim()}>Next</button>
        </form>
        {#if findMiss}<p class="fine">Not in this note.</p>{/if}
      {:else if sheet === "ai"}
        <h4>Ask LAR about this note</h4>
        <div class="two">
          <button onclick={() => ask("summarize")} disabled={working}>Summarize</button>
          <button onclick={() => ask("tidy")} disabled={working}>Tidy up</button>
          <button onclick={() => ask("explain")} disabled={working}>Explain</button>
          <button onclick={startCards}>Make cards</button>
        </div>
        <form class="row" onsubmit={(e) => (e.preventDefault(), ask("ask"))}>
          <input bind:value={question} placeholder="Ask about this note…" aria-label="Ask about this note" enterkeyhint="send" autocomplete="off" />
          <button class="go" type="submit" disabled={working || !question.trim()}>Ask</button>
        </form>
        {#if working && !out}<p class="fine">{assis.busy === "waking" ? "Waking up…" : "Thinking…"}</p>{/if}
        {#if out}
          <div class="result" aria-live="polite">
            <p>{out}</p>
            {#if !working}
              <div class="two">
                <button class="go" onclick={insertBelow}>Insert below</button>
                {#if mode === "tidy"}<button onclick={replaceIt}>Replace</button>{/if}
                <button onclick={discard}>Discard</button>
              </div>
            {:else}
              <button onclick={discard}>Stop</button>
            {/if}
          </div>
        {/if}
        {#if before !== null && !out}<button onclick={() => (run({ text: before!, from: 0, to: 0 }), (before = null))}>Undo replace</button>{/if}
        {#if aiProblem}<p class="problem" role="alert">{aiProblem}</p>{/if}
        <p class="fine">LAR runs on your phone. Nothing changes in your note until you tap.</p>
      {:else if sheet === "cards"}
        <h4>Make cards</h4>
        {#if !drafts}
          <p class="fine">Pick the lines to turn into cards. Lines written "term - meaning" are picked already.</p>
          <div class="lines">
            {#each lines as l, i (i)}
              <label class="pickline"><input type="checkbox" bind:checked={l.chosen} /><span>{l.text}</span></label>
            {/each}
          </div>
          <button class="go wide" onclick={review} disabled={!lines.some((l) => l.chosen)}>Review {lines.filter((l) => l.chosen).length} cards</button>
        {:else}
          <p class="fine">Into <b>{target?.name ?? deckName}</b>{target ? "" : " (a new deck)"}. Nothing is saved until Save cards.</p>
          <div class="lines">
            {#each drafts as d, i (i)}
              <div class="draft">
                <input bind:value={d.front} aria-label="Front of card {i + 1}" />
                <input bind:value={d.back} placeholder="Back" aria-label="Back of card {i + 1}" />
              </div>
            {/each}
          </div>
          <div class="two">
            <button class="go" onclick={saveCards} disabled={!drafts.some((d) => d.front.trim() && d.back.trim())}>Save cards</button>
            <button onclick={() => (drafts = null)}>Back</button>
          </div>
        {/if}
        {#if cardsMsg}<p class="fine" role="status">{cardsMsg}</p>{/if}
        {#if installed()}<p class="fine">Or let LAR write them: Ask LAR in a deck's Cards.</p>{/if}
      {/if}
    </div>
  {/if}
</div>

<style>
  .editor {
    position: fixed;
    inset: 0;
    z-index: 50;
    display: grid;
    grid-template-rows: auto auto minmax(0, 1fr) auto;
    padding: calc(var(--safe-top) + 8px) var(--gutter) calc(var(--safe-bottom) + 8px);
    background: var(--ground);
  }
  header {
    display: flex;
    align-items: center;
    gap: 8px;
    min-height: 44px;
  }
  .done {
    height: 40px;
    padding: 0 16px;
    border: 0;
    border-radius: 10px;
    background: var(--gold);
    color: var(--on-gold);
    font-family: var(--font-display);
    font-weight: 700;
  }
  .state {
    flex: 1;
    min-width: 0;
    font-size: min(0.71rem, 21px);
    color: var(--ink-3);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .icons {
    display: flex;
    gap: 2px;
  }
  .ic {
    width: 44px;
    height: 44px;
    display: grid;
    place-items: center;
    border: 0;
    border-radius: 10px;
    background: transparent;
    color: var(--ink);
  }
  .ic:active {
    background: var(--card);
  }
  .ic:disabled {
    opacity: 0.3;
  }
  .title {
    display: grid;
    gap: 2px;
    padding: 8px 0 6px;
  }
  .title small {
    font: 500 min(0.7rem, 20px) var(--font-pixel);
    letter-spacing: 0.06em;
    color: var(--ink-3);
  }
  h2,
  .name {
    margin: 0;
    font-family: var(--font-display);
    font-size: min(1.294rem, 29px);
    font-weight: 700;
    color: var(--ink);
  }
  .name {
    width: 100%;
    padding: 0;
    border: 0;
    background: none;
  }
  .selbar {
    position: absolute;
    z-index: 3;
    top: calc(var(--safe-top) + 56px);
    right: var(--gutter);
    display: flex;
    gap: 2px;
    padding: 4px;
    border-radius: 12px;
    background: var(--card);
    box-shadow: inset 0 0 0 1px var(--edge-2), 0 8px 20px rgb(0 0 0 / 0.3);
  }
  .selbar button {
    width: 40px;
    height: 40px;
    display: grid;
    place-items: center;
    border: 0;
    border-radius: 8px;
    background: transparent;
    color: var(--ink);
  }

  /* The page: CodeMirror inside, the look from Aa (C11a). Paper scrolls with the text. */
  .page {
    min-height: 0;
    overflow: hidden;
    border-radius: 12px;
    background: var(--card);
    box-shadow: inset 0 0 0 1px var(--edge);
    --fs: max(16px, min(0.941rem, 29px));
    --lh: 1.55;
  }
  .page[data-size="S"] {
    --fs: max(15px, min(0.85rem, 26px));
  }
  .page[data-size="L"] {
    --fs: max(19px, min(1.1rem, 33px));
  }
  .page[data-spacing="Tight"] {
    --lh: 1.35;
  }
  .page[data-spacing="Roomy"] {
    --lh: 1.85;
  }
  .page :global(.cm-editor) {
    height: 100%;
    color: var(--ink);
    font-size: var(--fs);
    line-height: var(--lh);
  }
  .page :global(.cm-editor.cm-focused) {
    outline: none;
  }
  .page :global(.cm-scroller) {
    padding: 12px 14px 120px;
    font-family: var(--font-body);
    line-height: var(--lh);
    background-attachment: local;
  }
  .page[data-font="classic"] :global(.cm-scroller) {
    font-family: "Iowan Old Style", "Palatino", Georgia, serif;
  }
  .page[data-font="mono"] :global(.cm-scroller) {
    font-family: ui-monospace, "SF Mono", Menlo, monospace;
  }
  .page[data-paper="lines"] :global(.cm-scroller) {
    background-image: repeating-linear-gradient(transparent 0 calc(var(--fs) * var(--lh) - 1px), var(--edge) 0 calc(var(--fs) * var(--lh)));
    background-position: 0 12px;
  }
  .page[data-paper="dots"] :global(.cm-scroller) {
    background-image: radial-gradient(var(--edge-2) 1px, transparent 1.2px);
    background-size: 14px 14px;
  }
  .page[data-paper="grid"] :global(.cm-scroller) {
    background-image: linear-gradient(var(--edge) 1px, transparent 0), linear-gradient(90deg, var(--edge) 1px, transparent 0);
    background-size: 14px 14px;
  }
  .page :global(.cm-content) {
    caret-color: var(--gold);
    padding: 0;
  }
  .page :global(.cm-line) {
    padding: 0;
  }
  .page :global(.cm-cursor) {
    border-left-color: var(--gold);
  }
  .page :global(.cm-selectionBackground),
  .page :global(.cm-focused .cm-selectionBackground) {
    background: color-mix(in srgb, var(--gold) 28%, transparent) !important;
  }
  .page :global(.cm-placeholder) {
    color: var(--ink-3);
  }
  .page :global(.cm-h) {
    font-family: var(--font-display);
    font-weight: 700;
    color: var(--ink);
  }
  .page :global(.cm-h1) {
    font-size: 1.45em;
  }
  .page :global(.cm-h2) {
    font-size: 1.25em;
  }
  .page :global(.cm-h3) {
    font-size: 1.12em;
  }
  .page :global(.cm-strong) {
    font-weight: 700;
  }
  .page :global(.cm-em) {
    font-style: italic;
  }
  .page :global(.cm-strike),
  .page :global(.cm-done) {
    text-decoration: line-through;
    text-decoration-color: var(--ink-3);
  }
  .page :global(.cm-done) {
    color: var(--ink-3);
  }
  .page :global(.cm-hl) {
    background: color-mix(in srgb, var(--gold) 30%, transparent);
    border-radius: 2px;
  }
  .page :global(.cm-icode),
  .page :global(.cm-codeblock) {
    font-family: ui-monospace, "SF Mono", Menlo, monospace;
    font-size: 0.9em;
    background: var(--sunk);
  }
  .page :global(.cm-quote) {
    padding-left: 12px;
    box-shadow: inset 2px 0 0 var(--gold);
    color: var(--ink-2);
  }
  .page :global(.cm-hr) {
    background: linear-gradient(var(--edge-2), var(--edge-2)) center / 100% 1px no-repeat;
  }
  .page :global(.cm-bullet) {
    color: var(--gold);
  }
  .page :global(.cm-box) {
    width: 1.05em;
    height: 1.05em;
    margin: 0 0.4em -0.15em 0;
    padding: 0;
    border: 0;
    border-radius: 3px;
    background: transparent;
    box-shadow: inset 0 0 0 2px var(--ink-3);
    vertical-align: baseline;
    cursor: pointer;
  }
  .page :global(.cm-box.on) {
    background: var(--gold);
    box-shadow: none;
  }

  footer {
    display: grid;
    gap: 4px;
    padding-top: 6px;
    min-height: 20px;
  }
  .count {
    margin: 0;
    font: 500 min(0.65rem, 18px) var(--font-pixel);
    letter-spacing: 0.06em;
    color: var(--ink-3);
  }
  .problem {
    margin: 0;
    font-size: min(0.765rem, 23px);
    color: var(--bad);
  }

  /* Sheets rise from the bottom, over the page. */
  .scrim {
    position: fixed;
    inset: 0;
    z-index: 51;
    border: 0;
    background: rgb(0 0 0 / 0.35);
  }
  .sheet {
    position: fixed;
    left: var(--gutter);
    right: var(--gutter);
    bottom: calc(var(--safe-bottom) + 76px);
    z-index: 52;
    display: grid;
    gap: 10px;
    max-height: 70vh;
    overflow-y: auto;
    padding: 14px;
    animation: rise 0.3s var(--ease) both;
  }
  @keyframes rise {
    from {
      opacity: 0;
      translate: 0 16px;
    }
  }
  h4 {
    margin: 0;
    font: 800 min(1.06rem, 26px) / 1.1 var(--font-display);
    color: var(--ink);
  }
  .tools {
    display: grid;
    grid-template-columns: repeat(4, 1fr);
    gap: 6px;
  }
  .tools button {
    position: relative;
    display: grid;
    justify-items: center;
    gap: 6px;
    padding: 10px 2px 8px;
    border: 0;
    border-radius: 10px;
    background: var(--sunk);
    color: var(--ink);
    font-size: min(0.68rem, 20px);
  }
  .tools button:disabled {
    opacity: 0.45;
  }
  .tools em {
    position: absolute;
    top: 4px;
    right: 4px;
    font: 500 9px var(--font-pixel);
    font-style: normal;
    color: var(--ink-3);
  }
  .tgrid {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 8px;
  }
  .tgrid button {
    display: grid;
    gap: 2px;
    min-height: 64px;
    padding: 10px 12px;
    border: 0;
    border-radius: 10px;
    background: var(--sunk);
    box-shadow: inset 0 0 0 1px var(--edge);
    color: var(--ink);
    text-align: left;
  }
  .tgrid strong {
    font-family: var(--font-display);
  }
  .tgrid small {
    font-size: min(0.72rem, 21px);
    color: var(--ink-3);
  }
  .seg {
    display: flex;
    padding: 3px;
    border-radius: 12px;
    background: var(--sunk);
  }
  .seg button {
    flex: 1;
    min-height: 40px;
    border: 0;
    border-radius: 9px;
    background: transparent;
    color: var(--ink-2);
    font-weight: 600;
  }
  .seg button[aria-pressed="true"] {
    background: var(--card);
    color: var(--ink);
    box-shadow: inset 0 0 0 1px var(--edge-2);
  }
  .lab {
    margin: 4px 0 -4px;
    font-size: min(0.72rem, 21px);
    color: var(--ink-3);
  }
  .sw {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 12px;
    min-height: 44px;
    color: var(--ink);
  }
  .sw input,
  .pickline input {
    width: 22px;
    height: 22px;
    accent-color: var(--gold);
  }
  .menu {
    display: grid;
  }
  .menu button {
    display: flex;
    align-items: center;
    gap: 12px;
    min-height: 48px;
    padding: 0 4px;
    border: 0;
    background: transparent;
    color: var(--ink);
    font-size: min(0.94rem, 28px);
    text-align: left;
  }
  .menu button + button {
    box-shadow: inset 0 1px 0 var(--edge);
  }
  .menu button[aria-pressed="true"] {
    color: var(--gold);
  }
  .menu button:disabled {
    opacity: 0.4;
  }
  .val {
    margin-left: auto;
    color: var(--ink-3);
    font-size: 0.9em;
    max-width: 50%;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .two {
    display: flex;
    flex-wrap: wrap;
    gap: 8px;
  }
  .two button,
  .row button,
  .confirm button,
  .wide {
    min-height: 44px;
    padding: 0 14px;
    border: 0;
    border-radius: 10px;
    background: var(--sunk);
    box-shadow: inset 0 0 0 1px var(--edge);
    color: var(--ink);
    font-family: var(--font-display);
    font-weight: 700;
  }
  .go {
    background: var(--gold) !important;
    box-shadow: none !important;
    color: var(--on-gold) !important;
  }
  button:disabled {
    opacity: 0.45;
  }
  .row {
    display: grid;
    grid-template-columns: 1fr auto;
    gap: 8px;
  }
  .row input,
  .draft input {
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
  .result {
    display: grid;
    gap: 8px;
    max-height: 30vh;
    overflow-y: auto;
  }
  .result p {
    margin: 0;
    white-space: pre-line;
    line-height: 1.4;
  }
  .fine {
    margin: 0;
    font-size: min(0.765rem, 23px);
    color: var(--ink-3);
  }
  .lines {
    display: grid;
    gap: 6px;
    max-height: 40vh;
    overflow-y: auto;
  }
  .pickline {
    display: flex;
    align-items: flex-start;
    gap: 10px;
    min-height: 40px;
    padding: 8px 4px;
    color: var(--ink);
  }
  .draft {
    display: grid;
    gap: 4px;
    padding-bottom: 6px;
    box-shadow: inset 0 -1px 0 var(--edge);
  }
  .confirm {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    gap: 8px;
  }
  .confirm p {
    flex: 1 1 100%;
    margin: 0;
  }
  .danger {
    color: var(--bad) !important;
  }
  @media (prefers-reduced-motion: reduce) {
    .sheet {
      animation: none;
    }
  }
</style>
