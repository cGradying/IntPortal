<script lang="ts">
  import "$lib/app.css";
  import { onMount } from "svelte";
  import Landing from "$lib/Landing.svelte";
  import Dive from "$lib/Dive.svelte";
  import { DIVE_WAIT_MS, type DiveStart } from "$lib/dive";
  import { FALLBACK_SIS } from "$lib/portals";
  import Glance from "$lib/Glance.svelte";
  import TabBar from "$lib/TabBar.svelte";
  import Today from "$lib/screens/Today.svelte";
  import Schedule from "$lib/screens/Schedule.svelte";
  import Grades from "$lib/screens/Grades.svelte";
  import Study from "$lib/screens/Study.svelte";
  import You from "$lib/screens/You.svelte";
  import Gallery from "$lib/Gallery.svelte";
  import NoteEditor from "$lib/NoteEditor.svelte";
  import SubjectPage from "$lib/SubjectPage.svelte";
  import FirstRun from "$lib/FirstRun.svelte";
  import AssisOrb from "$lib/assis/AssisOrb.svelte";
  import AssisSheet from "$lib/assis/AssisSheet.svelte";
  import { assis, watchAssis } from "$lib/assis/assis.svelte";
  import PullToSync from "$lib/PullToSync.svelte";
  import LockScreen from "$lib/LockScreen.svelte";
  import { lock, watchLock } from "$lib/lock.svelte";
  import { api, isoDate } from "$lib/api";
  import MabiniGrades from "$lib/MabiniGrades.svelte";
  import NeedSis from "$lib/NeedSis.svelte";
  import MabiniPage from "$lib/MabiniPage.svelte";
  import { watchDynamicIsland } from "$lib/glance";
  import { watchBars } from "$lib/bars";
  import { watchBack } from "$lib/back";
  import { app, adopt, listenForTaps, refreshLogins, setRoom, setTextStyle, startClock, syncNow } from "$lib/state.svelte";

  let ready = $state(false);
  let signedIn = $state(false);
  let inside = $state(false);
  let gallery = $state(false);
  // The dive, while it runs. A first sign-in holds the landing under it until it is hidden.
  let dive = $state<DiveStart | null>(null);
  let holdLanding = $state(false);
  // A dive hands over to Today itself, so the veil stays out of it.
  let dived = $state(false);
  let welcomed = $state(remembered("welcomed") === "1");

  function remembered(key: string): string | null {
    try {
      return localStorage.getItem(key);
    } catch {
      return null;
    }
  }

  function welcomeDone() {
    welcomed = true;
    try {
      localStorage.setItem("welcomed", "1");
    } catch {
      // Shown again next launch; harmless.
    }
  }
  // Dynamic Island phones show the next class in the Live Activity outside
  // the app; inside, the dock would only crowd the screen.
  let island = $state(false);

  onMount(async () => {
    listenForTaps();
    if (__REVIEW__) {
      // Review builds put uncaught errors on screen; there is no console on a phone.
      const show = (m: string) => document.body.insertAdjacentHTML("beforeend", `<pre style="position:fixed;inset:auto 8px 90px;z-index:99;padding:8px;background:#300;color:#fbb;white-space:pre-wrap;font-size:11px">${m.replace(/</g, "&lt;")}</pre>`);
      addEventListener("error", (e) => show(`${e.message} @ ${e.filename}:${e.lineno}`));
      addEventListener("unhandledrejection", (e) => show(String(e.reason?.stack ?? e.reason)));
    }
    setRoom(app.room);
    setTextStyle(app.textStyle);
    watchLock();
    // The keyboard covers the bottom; the tab bar and dock step aside while
    // a text field has focus, so they don't ride up on top of it.
    const typing = (e: Event) => (e.target as HTMLElement).matches?.("input:not([type=checkbox]):not([type=radio]), textarea, select");
    addEventListener("focusin", (e) => typing(e) && (document.documentElement.dataset.keyboard = "open"));
    addEventListener("focusout", () => setTimeout(() => {
      if (!document.activeElement?.matches("input, textarea, select")) delete document.documentElement.dataset.keyboard;
    }, 50));
    watchDynamicIsland((has) => (island = has));
    watchBars();
    watchAssis();
    watchBack(() => app.tab !== "today" && ((app.tab = "today"), true));
    // Review builds keep demo mode across launches, so a signed-in launch can be seen without a real login.
    const keepDemo = __REVIEW__ && remembered("demo") === "1";
    const snapshot = (keepDemo ? api.demo(isoDate(new Date())) : api.snapshot()).catch(() => null);
    if (keepDemo) await snapshot;
    await refreshLogins();
    signedIn = app.sisConnected || app.mabiniConnected;
    const reduce = matchMedia("(prefers-reduced-motion: reduce)").matches;
    // Signed in: the dive is the loading screen, and the snapshot loads while it runs (spec 010 C26).
    if (signedIn && !reduce) {
      dived = true;
      dive = { first: false, portal: await ownPortal() };
    }
    const waited = new Promise<undefined>((done) => setTimeout(() => done(undefined), DIVE_WAIT_MS));
    const snap = await (signedIn ? Promise.race([snapshot, waited]) : snapshot);
    if (snap) await adopt(snap);
    startClock();
    ready = true;
    if (signedIn && snap !== null) {
      // Past the wait, Today opens with what is cached and the snapshot follows when it can.
      if (snap === undefined) snapshot.then((s) => s && adopt(s));
      syncNow();
      inside = true;
    } else {
      // A login that won't adopt lands on the landing (C34).
      dive = null;
      dived = false;
    }
  });

  async function ownPortal() {
    const list = await api.portals().catch(() => []);
    const id = app.sisConnected ? "sis" : "mabini";
    return list.find((p) => p.id === id) ?? FALLBACK_SIS;
  }

  // Step through, on a first sign-in (C27). Today mounts now, under the landing,
  // so the work is done at the tap and not in the middle of the dive.
  function diveIn(start: DiveStart) {
    dived = true;
    holdLanding = true;
    dive = start;
    if (signedIn) syncNow();
    inside = true;
  }

  // No dive after all: on to Today with the veil (spec 010 Errors).
  function noDive() {
    dive = null;
    dived = false;
    holdLanding = false;
  }

  // Each tab opens at its top, not wherever the last one was scrolled.
  $effect(() => {
    if (app.tab !== firstTab) tabbed = true;
    // The page slides toward the tab you chose (spec 045 C22).
    slide = TAB_ORDER.indexOf(app.tab) >= TAB_ORDER.indexOf(lastTab) ? 12 : -12;
    lastTab = app.tab;
    gallery = false;
    window.scrollTo(0, 0);
  });

  // The page only slides in when the student changes tab: Today is simply
  // there when they arrive (spec 010 C30).
  const firstTab = app.tab;
  let tabbed = $state(false);
  const TAB_ORDER = ["today", "schedule", "grades", "study", "you"];
  let lastTab = app.tab;
  let slide = $state(12);

  function enter() {
    inside = true;
  }

  // The veil lifts once Today has painted under it: mounting the app can
  // take longer than the fade, which would otherwise finish unseen. Today
  // itself doesn't move (spec 010 C30).
  let lifted = $state(false);
  $effect(() => {
    if (!inside) return void (lifted = false);
    requestAnimationFrame(() => requestAnimationFrame(() => (lifted = true)));
  });

  // One portal signed out: stay inside while the other still has a login.
  async function signedOut() {
    await refreshLogins();
    if (app.sisConnected || app.mabiniConnected) {
      const snap = await api.snapshot().catch(() => null);
      if (snap) await adopt(snap);
      return;
    }
    app.snapshot = null;
    app.mabini = null;
    app.mabiniPage = false;
    app.today = null;
    app.notes = [];
    app.editing = null;
    app.subject = null;
    app.tab = "today";
    try {
      localStorage.removeItem("demo");
    } catch {
      // Review builds only; harmless.
    }
    signedIn = false;
    inside = false;
    dived = false;
  }
</script>

{#if lock.enabled && (lock.locked || lock.hidden)}<LockScreen />{/if}

{#if ready && (!inside || holdLanding)}
  <Landing {signedIn} onenter={enter} ondive={diveIn} />
{/if}

{#if inside}
  <div class="shell dots" data-glance={island ? "none" : "dock"}>
    <div class="topfade" aria-hidden="true"></div>
    {#if !island}<Glance />{/if}
    <main>
      <PullToSync />
      {#key app.tab}
        <div class="page" class:slides={tabbed} style:--slide="{slide}px">
          {#if app.tab === "today"}<Today />
          {:else if app.tab === "schedule"}{#if app.sisConnected}<Schedule />{:else}<div class="needs"><NeedSis what="your schedule" /></div>{/if}
          {:else if app.tab === "grades"}{#if app.sisConnected}<Grades />{:else}<div class="needs"><NeedSis what="your grades" /><MabiniGrades /></div>{/if}
          {:else if app.tab === "study"}<Study />
          {:else if gallery}<Gallery onclose={() => (gallery = false)} />
          {:else}<You onsignout={signedOut} ongallery={() => ((gallery = true), window.scrollTo(0, 0))} />{/if}
        </div>
      {/key}
    </main>
    <TabBar />
    <AssisOrb />
  </div>
  <!-- Without a dive, the void lifts off the room instead of cutting to it. -->
  {#if !dived}<div class="veil" class:lifted aria-hidden="true"></div>{/if}
  {#if !welcomed}<FirstRun ondone={welcomeDone} />{/if}
  {#if app.subject}
    {#key app.subject.code}<SubjectPage {...app.subject} />{/key}
  {/if}
  {#if app.editing}
    {#key app.editing.key}<NoteEditor {...app.editing} />{/key}
  {/if}
  {#if app.mabiniPage}<MabiniPage />{/if}
  {#if assis.open}<AssisSheet onclose={() => (assis.open = false)} />{/if}
{/if}

{#if dive}
  <Dive start={dive} ready={lifted} oncovered={() => (holdLanding = false)} ondone={() => (dive = null)} onfail={noDive} />
{/if}

<style>
  .shell {
    min-height: 100vh;
    /* Its own stacking context, so the dot grid's ripple can sit under the cards. */
    isolation: isolate;
  }
  /* No fill mode: a lingering filter or transform would turn these into the
     containing block for the fixed dock, tab bar and sheets. */
  .topfade {
    position: fixed;
    top: 0;
    left: 0;
    right: 0;
    z-index: 25;
    height: calc(var(--safe-top) + 12px);
    background: linear-gradient(var(--ground) 55%, transparent);
    pointer-events: none;
  }
  .veil {
    position: fixed;
    inset: 0;
    z-index: 70;
    background: var(--void);
    pointer-events: none;
    /* Today's first frame reaches the screen a few hundred ms after it
       mounts on a phone, so the lift waits for it. */
    transition:
      opacity 0.4s var(--ease) 0.25s,
      visibility 0s 0.65s;
  }
  .veil.lifted {
    opacity: 0;
    visibility: hidden;
  }
  main {
    padding: calc(var(--safe-top) + 12px) var(--gutter) calc(var(--safe-bottom) + 92px);
  }
  [data-glance="dock"] main {
    padding-bottom: calc(var(--safe-bottom) + 150px);
  }
  .page.slides {
    animation: in 0.22s var(--ease) backwards;
  }
  .needs {
    display: grid;
    gap: 14px;
  }
  @keyframes in {
    from { opacity: 0; translate: var(--slide) 0; }
  }
</style>
