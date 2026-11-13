<script lang="ts">
  // Spec 041 C10–C14, the ticket adder (picked 2026-11-09, round three B). A
  // floating window grows out of the Due card's Add. What you type is read by
  // the core as you type and shows as a ticket you can rename; one tap in the
  // three rows under it fixes the day, the subject or the kind. Add shrinks it
  // back into the Due card. With `own` it edits one, and can delete it.
  import { onMount, tick } from "svelte";
  import { api, isoDate, subjectColor, type DeadlineDraft, type DeadlineEntry } from "./api";
  import { dayLabel, dayName, guessSubject, KINDS, kindName, meets, stub, tickets, verdict, whenDays, type Fix } from "./addDue";
  import { closable } from "./back";
  import { cameraProblem, capture } from "./camera";
  import { friendly } from "./errors";
  import { buzz } from "./haptics";
  import PixelIcon from "./PixelIcon.svelte";
  import { adopt, app } from "./state.svelte";
  import { visualViewport } from "./viewport.svelte";

  let { own, onclose }: { own?: DeadlineEntry; onclose: () => void } = $props();
  $effect(() => closable(() => close()));

  const reduce = matchMedia("(prefers-reduced-motion: reduce)").matches;
  const EASE = "cubic-bezier(0.22, 1, 0.36, 1)";
  const vv = visualViewport();
  const today = isoDate(new Date());
  // svelte-ignore state_referenced_locally
  const edit = own;
  const ownId = edit?.id.replace(/^own:/, "");
  const ownDay = edit && "day" in edit.due ? edit.due.day : null;

  let text = $state(edit?.title ?? "");
  // Editing starts from what is saved; the day, subject and kind hold while the name is retyped.
  let parsed = $state<DeadlineDraft[]>(edit ? [{ title: edit.title, subject: edit.subject, kind: edit.kind, date: ownDay }] : []);
  let fixes = $state<Fix[]>(edit ? [{ subject: edit.subject, kind: edit.kind, date: ownDay }] : []);
  let dropped = $state<boolean[]>([]);
  let sel = $state(0);
  let problem = $state("");
  let leaving = $state(false);
  let saving = false;
  // Where the frame was when it started to leave, so the keyboard dropping doesn't move it.
  let pin = $state<null | { top: number; h: number }>(null);

  const ts = $derived(tickets(parsed, fixes, dropped));
  const si = $derived(Math.min(sel, ts.length - 1));
  const cur = $derived(ts[si]);
  const v = $derived(verdict(ts, !!edit));
  const sessions = $derived(app.snapshot?.sessions ?? []);
  const codes = $derived([...new Set(sessions.map((s) => s.subject_code))]);
  const colors = $derived(app.snapshot?.colors ?? {});
  const at = $derived(pin ?? vv);

  let win: HTMLElement;
  let card: HTMLElement;
  let area: HTMLTextAreaElement;
  let whenRow: HTMLElement | undefined = $state();
  let titles: HTMLInputElement[] = [];
  let keeps: HTMLInputElement[] = [];

  // ------------------------------------------------------------ reading

  let timer: ReturnType<typeof setTimeout> | undefined;
  let seq = 0;

  /** The core reads the text a quarter second after the last key. */
  function soon(now = false) {
    clearTimeout(timer);
    timer = setTimeout(read, now ? 0 : 250);
  }

  async function read() {
    const me = ++seq;
    let drafts: DeadlineDraft[] = [];
    try {
      if (text.trim()) drafts = (await api.parseOwn(text, isoDate(new Date()))).map((d) => guessSubject(d, app.snapshot?.sessions ?? []));
    } catch (e) {
      if (me === seq) problem = friendly(e);
      return;
    }
    if (me !== seq || leaving) return;
    problem = "";
    await grow(() => (parsed = drafts));
  }

  // Spec 041 C15–C18: one photo, read on the phone, not kept. A phone with no
  // camera (the simulator) picks from the library instead.
  let scanning = $state(false);
  async function scan() {
    problem = "";
    scanning = true;
    try {
      const r = await capture({ source: "camera", read: { text: true } }).catch((e) => {
        if (cameraProblem(e) === "no_camera") return capture({ source: "library", read: { text: true } });
        throw e;
      });
      if (r.cancelled) return;
      if (!r.text?.trim()) {
        problem = "Couldn't read any text. Try closer, with more light.";
        return;
      }
      text = r.text;
      await tick();
      autosize();
      soon(true);
      area.blur();
    } catch (e) {
      problem = cameraProblem(e) === "camera_denied" ? "Camera is off for IntPortal. Turn it on in Settings, or type it instead." : "Couldn't use the camera. Type it instead.";
    } finally {
      scanning = false;
    }
  }

  function autosize() {
    area.style.height = "auto";
    area.style.height = `${area.scrollHeight}px`;
  }

  async function paste() {
    try {
      const got = await navigator.clipboard.readText();
      if (!got.trim()) return area.focus();
      text = got;
      await tick();
      autosize();
      soon(true);
      // Put the keyboard away to look the tickets over.
      area.blur();
    } catch {
      // No clipboard access: the field stays as it was, ready to type.
      area.focus();
    }
  }

  // ------------------------------------------------------------ fixing

  /** Content changes ease the window's height, so nothing jumps. */
  async function grow(change: () => void) {
    const h0 = card.offsetHeight;
    change();
    await tick();
    const h1 = card.offsetHeight;
    if (h0 !== h1 && !reduce) card.animate([{ height: `${h0}px` }, { height: `${h1}px` }], { duration: 360, easing: EASE });
  }

  function fix(i: number, f: Fix) {
    fixes[i] = { ...fixes[i], ...f };
    buzz.select();
  }

  function pick(k: number) {
    if (k === si) return;
    buzz.select();
    grow(() => (sel = k));
  }

  /** A soft gold flash where the missing thing goes. */
  function flash(el: Element | null | undefined) {
    if (!el) return;
    const soft = getComputedStyle(el).getPropertyValue("--gold-soft").trim();
    const on = { backgroundColor: soft, boxShadow: `0 0 0 2px ${soft}` };
    const off = { backgroundColor: "transparent", boxShadow: "0 0 0 2px transparent" };
    el.animate([off, { ...on, offset: 0.25 }, { ...on, offset: 0.65 }, off], { duration: 900, easing: EASE });
  }

  /** A greyed Add says what's missing; tapping it goes there. */
  async function nudge() {
    buzz.tick();
    if (v.why === "text") return area.focus();
    if (v.why === "name") return titles[v.i!]?.focus();
    if (v.why === "keep") return keeps[0]?.focus();
    if (v.why === "day") {
      if (v.i !== si) await grow(() => (sel = v.i!));
      whenRow?.scrollIntoView({ block: "nearest", behavior: reduce ? "auto" : "smooth" });
      whenRow?.querySelector("button")?.focus({ preventScroll: true });
      flash(whenRow);
    }
  }

  // ------------------------------------------------------------ the window

  const toward = (r: DOMRect, t: DOMRect) => `translate(${t.left - r.left}px, ${t.top - r.top}px) scale(${t.width / r.width}, ${t.height / r.height})`;
  const addButton = () => document.querySelector("[data-due-add]");
  const ownRow = () => (edit ? document.querySelector(`[data-due-row="${CSS.escape(edit.id)}"]`) : null);

  onMount(() => {
    autosize();
    if (!edit) area.focus({ preventScroll: true });
    const from = (ownRow() ?? addButton())?.getBoundingClientRect();
    if (reduce || !from) {
      win.animate([{ opacity: 0 }, { opacity: 1 }], { duration: 200, easing: "ease-out" });
    } else {
      win.animate([{ transform: toward(win.getBoundingClientRect(), from), opacity: 0.6 }, { transform: "none", opacity: 1 }], { duration: 420, easing: EASE });
      for (const c of card.children) c.animate([{ opacity: 0 }, { opacity: 1 }], { duration: 240, delay: 140, easing: EASE, fill: "backwards" });
    }
    return () => clearTimeout(timer);
  });

  /** Into `target` (Add, the card, the row), or down off the screen after a swipe. Reduce Motion: a fade. */
  function leave(target: Element | null | undefined, dy?: number) {
    if (leaving) return;
    leaving = true;
    clearTimeout(timer);
    pin = { top: vv.top, h: vv.h };
    (document.activeElement as HTMLElement | null)?.blur?.();
    // From where it is at rest, even if it is still growing in.
    for (const a of [win, ...card.children].flatMap((el) => el.getAnimations())) a.cancel();
    const r = win.getBoundingClientRect();
    const t = target?.getBoundingClientRect();
    let a: Animation;
    if (reduce) {
      a = win.animate([{ opacity: 1 }, { opacity: 0 }], { duration: 200, easing: "ease-in", fill: "forwards" });
    } else if (dy !== undefined || !t) {
      const y = dy ?? 0;
      a = win.animate([{ transform: `translateY(${y}px)`, opacity: 1 }, { transform: `translateY(${y + 160}px)`, opacity: 0 }], { duration: 260, easing: "cubic-bezier(0.4, 0, 1, 1)", fill: "forwards" });
    } else {
      for (const c of card.children) c.animate([{ opacity: 1 }, { opacity: 0 }], { duration: 160, easing: EASE, fill: "forwards" });
      a = win.animate([{ transform: "none", opacity: 1 }, { opacity: 1, offset: 0.7 }, { transform: toward(r, t), opacity: 0 }], { duration: 440, easing: EASE, fill: "forwards" });
    }
    a.finished.then(onclose, onclose);
  }

  const close = () => leave(addButton());

  async function go() {
    if (leaving || saving) return;
    if (!v.ok) return nudge();
    saving = true;
    let snap = null;
    const saved: number[] = [];
    try {
      for (const [i, t] of ts.entries()) {
        if (!t.keep) continue;
        snap = await api.saveOwn({ id: ownId ?? "", title: t.title.trim(), subject: t.subject, kind: t.kind, date: t.date! });
        saved.push(i);
      }
      await adopt(snap!);
    } catch (e) {
      problem = friendly(e);
      buzz.fail();
      // The ones already saved are unticked, so trying again won't add them twice.
      if (!edit) for (const i of saved) dropped[i] = true;
      if (snap) await adopt(snap);
      saving = false;
      return;
    }
    buzz.done();
    leave(edit ? ownRow() : document.querySelector("[data-due-card]"));
  }

  async function remove() {
    if (!ownId || leaving || saving) return;
    saving = true;
    const row = ownRow();
    try {
      await adopt(await api.deleteOwn(ownId));
    } catch (e) {
      problem = friendly(e);
      buzz.fail();
      saving = false;
      return;
    }
    buzz.tick();
    leave(row);
  }

  // Swipe the window down to close it.
  let drag: { y: number; dy: number } | null = null;
  function down(e: PointerEvent) {
    if (leaving || (e.target as Element).closest("button, input, textarea, label, .scroll")) return;
    drag = { y: e.clientY, dy: 0 };
    card.setPointerCapture(e.pointerId);
  }
  function move(e: PointerEvent) {
    if (!drag) return;
    drag.dy = Math.max(0, e.clientY - drag.y);
    win.style.transform = `translateY(${drag.dy}px)`;
  }
  function up() {
    if (!drag) return;
    const dy = drag.dy;
    drag = null;
    if (dy > 70) return leave(null, dy);
    win.style.transform = "";
    if (dy && !reduce) win.animate([{ transform: `translateY(${dy}px)` }, { transform: "none" }], { duration: 320, easing: EASE });
  }

  // Taps on the window leave the caret where it is, so the keyboard stays up between chips.
  function keepCaret(e: MouseEvent) {
    if (!(e.target as Element).closest("textarea, input")) e.preventDefault();
  }
</script>

<svelte:window onkeydown={(e) => e.key === "Escape" && close()} />

<div class="scrim" class:leaving role="presentation" onclick={close}></div>
<!-- A frame that is exactly the visual viewport, so the keyboard lifts the window above it. -->
<div class="frame" class:typing={vv.keyboard} style:top="{at.top}px" style:height="{at.h}px">
  <div class="win" bind:this={win} role="dialog" aria-modal="true" aria-label={edit ? "Edit due" : "Add a due"}>
    <!-- svelte-ignore a11y_no_static_element_interactions -->
    <div class="card notch" bind:this={card} onpointerdown={down} onpointermove={move} onpointerup={up} onpointercancel={up} onmousedown={keepCaret}>
      <div class="head" aria-hidden="true"></div>
      <div class="top">
        <div class="field">
          <textarea
            bind:this={area}
            bind:value={text}
            oninput={() => (autosize(), soon())}
            rows="1"
            enterkeyhint="enter"
            placeholder="quiz COMP fri"
            aria-label="What's due?"
          ></textarea>
          {#if !text}
            <button class="chip paste" onclick={paste}><span class="face">Paste</span></button>
            <button class="chip paste" onclick={scan} disabled={scanning} aria-label="Scan a photo"><span class="face">{scanning ? "Reading…" : "Scan"}</span></button>
          {/if}
        </div>
        <button class="x" onclick={close} aria-label="Close"><PixelIcon name="close" size={14} /></button>
      </div>

      {#if cur}
        <div class="body">
          <div class="tks">
            {#each ts as t, k (k)}
              {@const s = t.date ? stub(t.date) : null}
              <!-- The stub is the keyboard's way to choose a ticket; a tap anywhere on it works too. -->
              <!-- svelte-ignore a11y_click_events_have_key_events, a11y_no_static_element_interactions -->
              <div class="tk" class:on={ts.length > 1 && k === si} class:off={!t.keep} onclick={() => pick(k)}>
                <button class="stub" class:miss={!s} aria-label={t.date ? dayName(t.date) : "No day yet"} aria-current={ts.length > 1 && k === si}>
                  {#if s}<span>{s.dow}</span><b>{s.day}</b><span>{s.mon}</span>{:else}<span>DAY</span><b>?</b><span>&nbsp;</span>{/if}
                </button>
                <div class="tb">
                  <input
                    class="tt"
                    bind:this={titles[k]}
                    value={t.title}
                    oninput={(e) => (fixes[k] = { ...fixes[k], title: e.currentTarget.value })}
                    placeholder="Name it"
                    aria-label="Name"
                    enterkeyhint="done"
                  />
                  <small>
                    {#if t.subject}<span class="tile" style:--c={subjectColor(t.subject, colors)}></span>{/if}
                    {t.subject ?? "No subject"} · {kindName(t.kind)}
                  </small>
                </div>
                {#if ts.length > 1}
                  <label class="keep"><input type="checkbox" bind:this={keeps[k]} checked={t.keep} onchange={() => ((dropped[k] = !dropped[k]), buzz.tick())} aria-label="Add this one" /></label>
                {/if}
              </div>
            {/each}
          </div>

          <div class="fix">
            <div class="crow" role="group" aria-label="When" bind:this={whenRow}>
              <span class="lab" aria-hidden="true">When</span>
              <div class="scroll">
                {#each whenDays(sessions, cur.subject, cur.date, today) as d (d)}
                  {@const cls = meets(sessions, cur.subject, d)}
                  <button class="chip" aria-pressed={cur.date === d} aria-label="{dayName(d)}{cls ? `, ${cur.subject} meets` : ''}" onclick={() => fix(si, { date: d })}>
                    <span class="face">{#if cls}<span class="tile" style:--c={subjectColor(cur.subject!, colors)}></span>{/if}{dayLabel(d, today)}</span>
                  </button>
                {/each}
                <label class="chip q">
                  <span class="face"><PixelIcon name="schedule" size={12} accent="currentColor" />Pick…</span>
                  <input
                    type="date"
                    min={today}
                    value={cur.date ?? ""}
                    aria-label="Pick a day"
                    onclick={(e) => {
                      try {
                        e.currentTarget.showPicker();
                      } catch {
                        // The phone opens its own picker on the tap.
                      }
                    }}
                    onchange={(e) => e.currentTarget.value && fix(si, { date: e.currentTarget.value })}
                  />
                </label>
              </div>
            </div>
            <div class="crow" role="group" aria-label="Subject">
              <span class="lab" aria-hidden="true">Subject</span>
              <div class="scroll">
                {#each codes as c (c)}
                  <button class="chip" aria-pressed={cur.subject === c} onclick={() => fix(si, { subject: c })}>
                    <span class="face"><span class="tile" style:--c={subjectColor(c, colors)}></span>{c}</span>
                  </button>
                {/each}
                <button class="chip" aria-pressed={!cur.subject} onclick={() => fix(si, { subject: null })}><span class="face">No subject</span></button>
              </div>
            </div>
            <div class="crow" role="group" aria-label="Kind">
              <span class="lab" aria-hidden="true">Kind</span>
              <div class="seg">
                {#each KINDS as [k, name] (k)}
                  <button aria-pressed={cur.kind === k} onclick={() => fix(si, { kind: k })}>{name}</button>
                {/each}
              </div>
            </div>
          </div>
        </div>
      {/if}

      {#if problem}<p class="problem" role="alert">{problem}</p>{/if}

      <div class="bar">
        {#if edit}<button class="del" onclick={remove}>Delete</button>{/if}
        <button class="go" aria-disabled={!v.ok} onclick={go}>{v.label}</button>
      </div>
    </div>
  </div>
</div>

<style>
  .scrim {
    position: fixed;
    inset: 0;
    z-index: 60;
    background: rgb(5 2 8 / 0.5);
    animation: dim 0.3s var(--ease) backwards;
    transition: opacity 0.3s var(--ease);
  }
  .scrim.leaving {
    opacity: 0;
    pointer-events: none;
  }
  @keyframes dim {
    from { opacity: 0; }
  }
  :global(:root[data-room="day"]) .scrim {
    background: rgb(28 21 23 / 0.24);
  }

  .frame {
    position: fixed;
    left: 8px;
    right: 8px;
    z-index: 61;
    display: flex;
    align-items: flex-end;
    padding: calc(var(--safe-top) + 8px) 0 calc(var(--safe-bottom) + 12px);
    pointer-events: none;
    transition: top var(--t-flow) var(--ease), height var(--t-flow) var(--ease), padding var(--t-flow) var(--ease);
  }
  .frame.typing {
    padding-bottom: 8px;
  }
  /* The shadow sits on the unclipped parent; the card is cut. */
  .win {
    pointer-events: auto;
    display: flex;
    width: 100%;
    max-height: 100%;
    transform-origin: 0 0;
    filter: drop-shadow(0 12px 22px rgb(0 0 0 / 0.45));
  }
  .card {
    --step: 4px;
    display: flex;
    flex-direction: column;
    width: 100%;
    max-height: 100%;
    overflow: hidden;
    background: linear-gradient(var(--card-2), var(--card));
    box-shadow: inset 0 0 0 1px color-mix(in srgb, var(--gold) 30%, transparent);
    touch-action: none;
  }
  .head {
    position: relative;
    flex: none;
    height: 12px;
  }
  .head::before {
    content: "";
    position: absolute;
    left: 50%;
    top: 5px;
    width: 32px;
    height: 4px;
    translate: -50% 0;
    background: var(--edge-2);
  }
  .top {
    flex: none;
    display: flex;
    align-items: flex-start;
    gap: 2px;
    padding: 0 4px 0 10px;
  }
  .x {
    flex: none;
    width: 44px;
    height: 44px;
    display: grid;
    place-items: center;
    border: 0;
    padding: 0;
    background: none;
    color: var(--ink-2);
  }
  .field {
    flex: 1;
    min-width: 0;
    display: flex;
    align-items: flex-start;
    gap: 6px;
    padding: 4px 4px 4px 12px;
    background: var(--sunk);
    box-shadow: inset 0 0 0 1px var(--edge);
    border-radius: 10px;
    transition: box-shadow 0.2s var(--ease);
  }
  .field:focus-within {
    box-shadow: inset 0 0 0 1.5px var(--gold);
  }
  textarea {
    flex: 1;
    min-width: 0;
    max-height: 5.2em;
    padding: 7px 0;
    border: 0;
    outline: 0;
    resize: none;
    background: none;
    font: max(16px, var(--text-body)) / 1.375 var(--font-ui);
    color: var(--ink);
    caret-color: var(--gold);
    scrollbar-width: none;
  }
  textarea::placeholder {
    color: var(--ink-2);
  }
  textarea::selection,
  .tt::selection {
    background: var(--gold);
    color: var(--on-gold);
  }

  /* A chip: a 44 pt button around a smaller stepped face. */
  .chip {
    position: relative;
    flex: none;
    display: flex;
    align-items: center;
    min-height: 44px;
    padding: 4px 0;
    border: 0;
    background: none;
    color: var(--ink);
  }
  .face {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    min-height: 36px;
    padding: 0 11px;
    white-space: nowrap;
    font: 600 var(--text-caption) var(--font-ui);
    background: var(--sunk);
    box-shadow: inset 0 0 0 1px var(--edge-2);
    clip-path: polygon(0 6px, 3px 6px, 3px 3px, 6px 3px, 6px 0, calc(100% - 6px) 0, calc(100% - 6px) 3px, calc(100% - 3px) 3px, calc(100% - 3px) 6px, 100% 6px, 100% calc(100% - 6px), calc(100% - 3px) calc(100% - 6px), calc(100% - 3px) calc(100% - 3px), calc(100% - 6px) calc(100% - 3px), calc(100% - 6px) 100%, 6px 100%, 6px calc(100% - 3px), 3px calc(100% - 3px), 3px calc(100% - 6px), 0 calc(100% - 6px));
    transition: background 0.2s var(--ease), color 0.2s var(--ease), box-shadow 0.2s var(--ease);
  }
  .chip[aria-pressed="true"] .face {
    background: var(--gold);
    color: var(--on-gold);
    box-shadow: inset 0 -2px 0 rgb(0 0 0 / 0.22);
  }
  .chip[aria-pressed="true"] .tile {
    --c: var(--on-gold) !important;
  }
  .paste {
    margin: -4px 0;
    color: var(--ink-2);
  }
  .paste .face {
    min-height: 30px;
    padding: 0 10px;
  }
  .q {
    color: var(--ink-2);
  }
  /* The native date control sits invisibly over Pick…, so a tap opens the phone's picker. */
  .q input {
    position: absolute;
    inset: 0;
    width: 100%;
    height: 100%;
    opacity: 0;
    border: 0;
    padding: 0;
  }
  .tile {
    flex: none;
    width: 8px;
    height: 8px;
    background: var(--c, var(--gold));
    clip-path: polygon(0 2px, 2px 2px, 2px 0, calc(100% - 2px) 0, calc(100% - 2px) 2px, 100% 2px, 100% calc(100% - 2px), calc(100% - 2px) calc(100% - 2px), calc(100% - 2px) 100%, 2px 100%, 2px calc(100% - 2px), 0 calc(100% - 2px));
  }

  .body {
    flex: 1 1 auto;
    min-height: 0;
    overflow-y: auto;
    scrollbar-width: none;
    display: flex;
    flex-direction: column;
    gap: 10px;
    padding: 10px 10px 0;
  }
  .body > * {
    flex: none;
  }

  /* The ticket: a date stub, a perforation, and the name you can retype. */
  .tks {
    display: grid;
    gap: 6px;
  }
  .tk {
    --stub: min(3.41rem, 86px);
    --a: calc(var(--stub) - 3px);
    --b: calc(var(--stub) + 3px);
    position: relative;
    display: flex;
    min-height: 64px;
    background: color-mix(in srgb, var(--gold) 6%, var(--sunk));
    box-shadow: inset 0 0 0 1px var(--edge-2);
    transition: box-shadow 0.2s var(--ease), opacity 0.2s var(--ease);
    clip-path: polygon(0 3px, 3px 3px, 3px 0, var(--a) 0, var(--a) 4px, var(--b) 4px, var(--b) 0, calc(100% - 3px) 0, calc(100% - 3px) 3px, 100% 3px, 100% calc(100% - 3px), calc(100% - 3px) calc(100% - 3px), calc(100% - 3px) 100%, var(--b) 100%, var(--b) calc(100% - 4px), var(--a) calc(100% - 4px), var(--a) 100%, 3px 100%, 3px calc(100% - 3px), 0 calc(100% - 3px));
  }
  .tk.on {
    box-shadow: inset 0 0 0 1.5px var(--gold);
  }
  .tk.off > :not(.keep) {
    opacity: 0.45;
  }
  .stub {
    flex: none;
    width: var(--stub);
    border: 0;
    padding: 6px 0;
    display: grid;
    justify-items: center;
    align-content: center;
    gap: 1px;
    color: var(--ink);
    background: linear-gradient(var(--edge-2) 50%, transparent 0) right top / 2px 6px repeat-y, var(--gold-soft);
  }
  .stub span {
    font: 500 var(--text-label) var(--font-pixel);
    letter-spacing: 0.06em;
    color: var(--gold);
  }
  .stub span + b + span {
    color: var(--ink-2);
  }
  .stub b {
    font: 800 min(1.412rem, 34px) / 1 var(--font-ui);
    letter-spacing: -0.03em;
    font-variant-numeric: tabular-nums;
  }
  .stub.miss b,
  .stub.miss span {
    color: var(--ink-3);
  }
  .tb {
    flex: 1;
    min-width: 0;
    display: grid;
    align-content: center;
    gap: 3px;
    padding: 8px 12px;
  }
  .tk:has(.keep) .tb {
    padding-right: 44px;
  }
  .tt {
    width: 100%;
    min-height: 44px;
    padding: 0;
    border: 0;
    border-radius: 0;
    outline: 0;
    background: none;
    font: 700 max(16px, min(1rem, 30px)) / 1.2 var(--font-ui);
    color: var(--ink);
    caret-color: var(--gold);
  }
  .tt:focus {
    box-shadow: 0 1.5px 0 var(--gold);
  }
  .tt::placeholder {
    color: var(--ink-3);
  }
  .tb small {
    display: flex;
    align-items: center;
    gap: 6px;
    font-size: var(--text-caption);
    color: var(--ink-2);
    white-space: nowrap;
    overflow: hidden;
  }
  .keep {
    position: absolute;
    right: 4px;
    top: 4px;
    width: 44px;
    height: 44px;
    display: grid;
    place-items: center;
  }

  /* Three rows to fix the selected ticket: when, subject, kind. */
  .fix {
    display: grid;
  }
  .crow {
    display: flex;
    align-items: center;
    gap: 8px;
    min-width: 0;
    border-radius: 4px;
  }
  .lab {
    flex: none;
    width: max(52px, 4.7em);
    font: 500 var(--text-label) var(--font-pixel);
    letter-spacing: 0.06em;
    text-transform: uppercase;
    color: var(--ink-2);
  }
  .scroll {
    flex: 1;
    min-width: 0;
    display: flex;
    gap: 6px;
    overflow-x: auto;
    scrollbar-width: none;
    margin-right: -10px;
    padding-right: 10px;
    -webkit-mask: linear-gradient(90deg, #000 calc(100% - 22px), transparent);
    mask: linear-gradient(90deg, #000 calc(100% - 22px), transparent);
  }
  .scroll::-webkit-scrollbar,
  .body::-webkit-scrollbar {
    display: none;
  }
  .seg {
    flex: 1;
    display: grid;
    grid-auto-flow: column;
    grid-auto-columns: 1fr;
    gap: 2px;
    margin: 4px 0;
    padding: 2px;
    background: var(--sunk);
    box-shadow: inset 0 0 0 1px var(--edge);
    border-radius: 10px;
  }
  .seg button {
    min-height: 44px;
    padding: 0 4px;
    border: 0;
    border-radius: 8px;
    background: none;
    font: 600 var(--text-caption) var(--font-ui);
    color: var(--ink-2);
    transition: background 0.2s var(--ease), color 0.2s var(--ease);
  }
  .seg button[aria-pressed="true"] {
    background: var(--gold);
    color: var(--on-gold);
  }

  .problem {
    flex: none;
    margin: 8px 10px 0;
    font-size: min(0.824rem, 25px);
    color: var(--bad);
  }
  .bar {
    flex: none;
    display: flex;
    align-items: flex-end;
    gap: 8px;
    padding: 8px 10px;
  }
  .go,
  .del {
    min-height: 46px;
    border: 0;
    border-radius: 10px;
    font-family: var(--font-ui);
    font-weight: 700;
  }
  .go {
    flex: 1;
    font-size: min(0.882rem, 27px);
    background: var(--gold);
    color: var(--on-gold);
    box-shadow: inset 0 -3px 0 rgb(0 0 0 / 0.22);
    transition: background 0.24s var(--ease), color 0.24s var(--ease), box-shadow 0.24s var(--ease), scale var(--t-quick) var(--ease-spring);
  }
  .go[aria-disabled="true"] {
    background: var(--sunk);
    color: var(--ink-2);
    box-shadow: inset 0 0 0 1px var(--edge-2);
  }
  .del {
    flex: none;
    padding: 0 14px;
    font-size: min(0.824rem, 25px);
    background: none;
    box-shadow: inset 0 0 0 1px var(--edge-2);
    color: var(--bad);
  }
</style>
