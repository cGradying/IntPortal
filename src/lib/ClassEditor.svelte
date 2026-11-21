<script lang="ts">
  // The class editor (spec 061 C2 to C5): a new own class, or one to change.
  // Opened from You › Classes, Today's empty state, the scan review and an
  // own class's sheet. Synced classes never open here.
  import { closable } from "./back";
  import { dismiss, scrim, sheet as rises } from "./motion";
  import { buzz } from "./haptics";
  import { adopt, app } from "./state.svelte";
  import { api, type OwnClass } from "./api";
  import { DAYS, problem as check } from "./ownClass";

  let { was, start, onsave, onclose }: { was: string | null; start: OwnClass; onsave?: (c: OwnClass) => void; onclose: () => void } = $props();
  $effect(() => closable(() => onclose()));

  // svelte-ignore state_referenced_locally
  let c = $state<OwnClass>($state.snapshot(start) as OwnClass);
  let problem = $state("");
  let busy = $state(false);

  const hhmm = (min: number) => `${String(Math.floor(min / 60)).padStart(2, "0")}:${String(min % 60).padStart(2, "0")}`;
  const minutes = (t: string) => {
    const [h, m] = t.split(":").map(Number);
    return Number.isFinite(h) && Number.isFinite(m) ? h * 60 + m : 0;
  };

  function toggle(i: number, day: (typeof DAYS)[number]["day"]) {
    const days = c.meetings[i].days;
    c.meetings[i].days = days.includes(day) ? days.filter((d) => d !== day) : [...days, day];
    problem = "";
    buzz.tick();
  }
  function another() {
    const last = c.meetings.at(-1);
    c.meetings.push({ days: [], start: last?.start ?? 480, end: last?.end ?? 570 });
  }

  async function save() {
    problem = check(c);
    if (problem) return buzz.fail();
    // The scan review keeps its found classes until "Add all": it only takes the edit back.
    if (onsave) {
      onsave($state.snapshot(c));
      return onclose();
    }
    busy = true;
    try {
      await adopt(await api.saveClass(was, $state.snapshot(c)));
      buzz.done();
      onclose();
    } catch (e) {
      problem = String((e as { message?: string })?.message ?? e);
      buzz.fail();
    } finally {
      busy = false;
    }
  }

  async function remove() {
    if (!was) return;
    try {
      await adopt(await api.deleteClass(was));
      buzz.done();
      onclose();
    } catch (e) {
      problem = String(e);
    }
  }
</script>

<div class="scrim" role="presentation" onclick={onclose} in:scrim|global out:scrim|global></div>
<div class="sheet notch" use:dismiss={onclose} in:rises|global out:rises|global role="dialog" aria-modal="true" aria-labelledby="ce-title">
  <h2 id="ce-title">{was || onsave ? "Edit class" : "New class"}</h2>
  <input class="field" bind:value={c.name} placeholder="Name" aria-label="Name" maxlength="80" autocapitalize="words" />
  <div class="two">
    <input class="field" bind:value={c.code} placeholder="Code (optional)" aria-label="Code (optional)" maxlength="20" autocapitalize="characters" spellcheck="false" />
    <input class="field" bind:value={c.room} placeholder="Room (optional)" aria-label="Room (optional)" maxlength="40" />
  </div>
  <input class="field" bind:value={c.teacher} placeholder="Teacher (optional)" aria-label="Teacher (optional)" maxlength="60" autocapitalize="words" />
  {#each c.meetings as m, i (i)}
    <div class="meeting">
      <p class="label">Days</p>
      <div class="days">
        {#each DAYS as d (d.day)}
          <button type="button" class:on={m.days.includes(d.day)} aria-pressed={m.days.includes(d.day)} aria-label={d.day} onclick={() => toggle(i, d.day)}>{d.short}</button>
        {/each}
      </div>
      <div class="times">
        <label>Starts <input type="time" value={hhmm(m.start)} onchange={(e) => (m.start = minutes(e.currentTarget.value))} /></label>
        <label>Ends <input type="time" value={hhmm(m.end)} onchange={(e) => (m.end = minutes(e.currentTarget.value))} /></label>
        {#if c.meetings.length > 1}<button type="button" class="link" aria-label="Remove this time" onclick={() => c.meetings.splice(i, 1)}>Remove</button>{/if}
      </div>
    </div>
  {/each}
  <button type="button" class="link" onclick={another}>+ Another time</button>
  {#if problem}<p class="problem" role="alert">{problem}</p>{/if}
  <button class="go" disabled={busy} onclick={save}>{busy ? "Saving…" : "Save"}</button>
  {#if was && !onsave}<button type="button" class="link quiet" onclick={remove}>Remove class</button>{/if}
</div>

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
    gap: 10px;
    padding: 18px 16px;
    max-height: calc(100dvh - var(--safe-top) - var(--safe-bottom) - 40px);
    overflow-y: auto;
    background: var(--card-2);
  }
  h2 {
    margin: 0 0 4px;
    font-family: var(--font-display);
    font-size: var(--text-headline);
  }
  .two {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 8px;
  }
  .field,
  .times input {
    min-width: 0;
    min-height: 44px;
    padding: 10px;
    border: 0;
    border-radius: var(--radius);
    background: var(--sunk);
    box-shadow: inset 0 0 0 1px var(--edge);
    color: var(--ink);
    font: inherit;
    font-size: var(--text-input);
  }
  .meeting {
    display: grid;
    gap: 8px;
    padding-top: 6px;
  }
  .label {
    margin: 0;
  }
  .days {
    display: grid;
    grid-template-columns: repeat(7, 1fr);
    gap: 4px;
  }
  .days button {
    min-height: 44px;
    border: 0;
    border-radius: var(--radius);
    background: var(--sunk);
    box-shadow: inset 0 0 0 1px var(--edge);
    color: var(--ink);
    font-weight: 700;
  }
  .days button.on {
    background: var(--gold);
    color: var(--on-gold);
    box-shadow: none;
  }
  .times {
    display: grid;
    grid-template-columns: 1fr 1fr auto;
    gap: 8px;
    align-items: end;
  }
  .times label {
    display: grid;
    gap: 4px;
    color: var(--ink-2);
    font-size: var(--text-caption);
  }
  .go {
    height: 48px;
    border: 0;
    border-radius: var(--radius);
    background: var(--gold);
    color: var(--on-gold);
    font-weight: 700;
  }
  .go:disabled {
    opacity: 0.5;
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
  .quiet {
    justify-self: center;
  }
  .problem {
    margin: 0;
    font-size: var(--text-caption);
    color: var(--bad, #e0685a);
  }
</style>
