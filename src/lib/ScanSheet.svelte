<script lang="ts">
  // A schedule from a photo or pasted text (spec 060 C10 to C14): the phone reads
  // it, the core finds the classes, IntAssis tries when the rules find none, and
  // the student checks every class before anything is saved.
  import { closable } from "./back";
  import { dismiss, scrim, sheet as rises } from "./motion";
  import { buzz } from "./haptics";
  import { adopt, editClass } from "./state.svelte";
  import { api, type FoundClass, type OwnClass } from "./api";
  import { cameraProblem, capture, noScanner, scannerDownloading } from "./camera";
  import { timeLine } from "./ownClass";
  import { timetableByAi } from "./assis/assis.svelte";
  import ClassEditor from "./ClassEditor.svelte";

  let { onclose }: { onclose: () => void } = $props();
  $effect(() => closable(() => (editing !== null ? (editing = null) : onclose())));

  let step = $state<"pick" | "paste" | "reading" | "review" | "none">("pick");
  let reading = $state("Reading your schedule…");
  let found = $state<FoundClass[]>([]);
  let pasted = $state("");
  let problem = $state("");
  let editing = $state<number | null>(null);
  let busy = $state(false);

  async function take(source: "camera" | "library") {
    problem = "";
    try {
      const r = await capture({ source, read: { text: true } }, () => (reading = scannerDownloading));
      if (r.cancelled) return;
      await read(r.lines ?? [], r.text ?? "");
    } catch (e) {
      const why = cameraProblem(e);
      step = "pick";
      problem = why === "camera_denied" ? "Camera is off for IntPortal. Turn it on in Settings, or paste instead." : why === "no_scanner" ? noScanner : "Couldn't use the camera. Paste instead.";
    }
  }

  async function read(lines: { text: string; x: number; y: number; w: number; h: number }[], text: string) {
    step = "reading";
    reading = "Reading your schedule…";
    let got = await api.readTimetable(lines, text).catch(() => [] as FoundClass[]);
    if (!got.length && text.trim()) {
      reading = "IntAssis is reading it…";
      got = (await timetableByAi(text)) ?? [];
    }
    found = got;
    step = got.length ? "review" : "none";
    if (got.length) buzz.done();
    else buzz.fail();
  }

  function replace(i: number, c: OwnClass) {
    found[i] = { class: c, unsure: false };
  }

  /** Saves every class in turn; one already on the week is skipped and counted, not fatal. */
  async function addAll() {
    busy = true;
    let skipped = 0;
    for (const f of $state.snapshot(found)) {
      try {
        await adopt(await api.saveClass(null, f.class));
      } catch {
        skipped++;
      }
    }
    busy = false;
    if (skipped === found.length) {
      problem = "Those classes are already on your week.";
      return buzz.fail();
    }
    buzz.done();
    onclose();
  }

  const many = (n: number) => (n === 1 ? "1 class" : `${n} classes`);
</script>

<div class="scrim" role="presentation" onclick={onclose} in:scrim|global out:scrim|global></div>
<div class="sheet notch" use:dismiss={onclose} in:rises|global out:rises|global role="dialog" aria-modal="true" aria-labelledby="scan-title">
  {#if step === "pick" || step === "paste"}
    <h2 id="scan-title">Scan a schedule</h2>
    <p class="fine">A photo of your registration form or class list. It's read on this phone and not kept.</p>
    {#if step === "pick"}
      <div class="two">
        <button class="go" onclick={() => take("camera")}>Camera</button>
        <button class="plain" onclick={() => take("library")}>Photos</button>
      </div>
      <button class="link" onclick={() => (step = "paste")}>Paste instead</button>
    {:else}
      <textarea rows="6" bind:value={pasted} placeholder={"COMP 101  Intro to Computing  MWF 7:30-9:00 AM\nPE 2  Dance  TTh 1:00-3:00 PM"} aria-label="Your schedule as text"></textarea>
      <button class="go" disabled={!pasted.trim()} onclick={() => read([], pasted)}>Read it</button>
    {/if}
  {:else if step === "reading"}
    <h2 id="scan-title">Scan a schedule</h2>
    <p class="fine" aria-live="polite">{reading}</p>
  {:else if step === "none"}
    <h2 id="scan-title">Couldn't find classes in that photo.</h2>
    <div class="two">
      <button class="go" onclick={() => (onclose(), editClass())}>Add by hand</button>
      <button class="plain" onclick={() => (step = "pick")}>Try another photo</button>
    </div>
  {:else}
    <h2 id="scan-title">Found {many(found.length)}</h2>
    <ul class="found">
      {#each found as f, i (i)}
        <li>
          <div class="what">
            <strong>{f.class.name}</strong>
            <small>{f.class.code || "No code"}{f.class.room ? ` · ${f.class.room}` : ""}</small>
            {#each f.class.meetings as m, k (k)}<small>{timeLine(m)}</small>{/each}
            {#if f.unsure}<em>Check this</em>{/if}
          </div>
          <div class="acts">
            <button class="plain" onclick={() => (editing = i)}>Edit</button>
            <button class="link" onclick={() => found.splice(i, 1)}>Remove</button>
          </div>
        </li>
      {/each}
    </ul>
    {#if found.length}<button class="go" disabled={busy} onclick={addAll}>{busy ? "Adding…" : `Add ${many(found.length)}`}</button>{/if}
  {/if}
  {#if problem}<p class="problem" role="alert">{problem}</p>{/if}
</div>
{#if editing !== null && found[editing]}
  {@const i = editing}
  <ClassEditor was={null} start={found[i].class} onsave={(c) => replace(i, c)} onclose={() => (editing = null)} />
{/if}

<style>
  .scrim {
    position: fixed;
    inset: 0;
    z-index: 60;
    background: rgba(0, 0, 0, 0.45);
  }
  .sheet {
    --step: 4px;
    position: fixed;
    left: var(--gutter);
    right: var(--gutter);
    bottom: calc(var(--safe-bottom) + 12px);
    z-index: 61;
    display: grid;
    gap: 12px;
    padding: 18px 16px;
    max-height: calc(100dvh - var(--safe-top) - var(--safe-bottom) - 40px);
    overflow-y: auto;
    background: var(--card-2);
  }
  h2 {
    margin: 0;
    font-family: var(--font-display);
    font-size: var(--text-headline);
  }
  .fine {
    margin: 0;
    color: var(--ink-2);
    font-size: var(--text-caption);
  }
  .two {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 8px;
  }
  .go,
  .plain {
    min-height: 48px;
    padding: 0 14px;
    border: 0;
    border-radius: var(--radius);
    font-weight: 700;
  }
  .go {
    background: var(--gold);
    color: var(--on-gold);
  }
  .go:disabled {
    opacity: 0.5;
  }
  .plain {
    background: var(--sunk);
    box-shadow: inset 0 0 0 1px var(--edge);
    color: var(--ink);
  }
  .link {
    justify-self: start;
    min-height: 44px;
    padding: 0;
    border: 0;
    background: none;
    color: var(--ink-2);
    text-decoration: underline;
  }
  textarea {
    min-width: 0;
    padding: 10px;
    border: 0;
    border-radius: var(--radius);
    background: var(--sunk);
    box-shadow: inset 0 0 0 1px var(--edge);
    color: var(--ink);
    font: inherit;
    font-size: var(--text-input);
    resize: none;
  }
  .found {
    display: grid;
    gap: 8px;
    margin: 0;
    padding: 0;
    list-style: none;
  }
  .found li {
    display: flex;
    gap: 10px;
    align-items: center;
    justify-content: space-between;
    padding: 10px 12px;
    border-radius: var(--radius);
    background: var(--sunk);
    box-shadow: inset 0 0 0 1px var(--edge);
  }
  .what {
    display: grid;
    gap: 2px;
    min-width: 0;
  }
  .what small {
    color: var(--ink-2);
    font-size: var(--text-caption);
  }
  .what em {
    color: var(--gold);
    font-style: normal;
    font-size: var(--text-caption);
    font-weight: 700;
  }
  .acts {
    display: grid;
    gap: 2px;
    justify-items: end;
  }
  .acts .plain {
    min-height: 44px;
    font-weight: 600;
  }
  .problem {
    margin: 0;
    font-size: var(--text-caption);
    color: var(--bad, #e0685a);
  }
</style>
