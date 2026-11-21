<script lang="ts">
  import "$lib/app.css";
  import { onMount } from "svelte";
  import Landing from "$lib/Landing.svelte";
  import Dive from "$lib/Dive.svelte";
  import Greeting from "$lib/Greeting.svelte";
  import { DIVE_WAIT_MS, type DiveStart } from "$lib/dive";
  import { FALLBACK_SIS } from "$lib/portals";
  import { setSchool, watchVisible } from "$lib/rooms";
  import { watchKeyboard } from "$lib/viewport.svelte";
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
  import AssisWindow from "$lib/assis/AssisWindow.svelte";
  import InstallView from "$lib/assis/InstallView.svelte";
  import { assis, chatModel, watchAssis } from "$lib/assis/assis.svelte";
  import { showFirstRun } from "$lib/welcome/intro";
  import { setCovered } from "$lib/quiet";
  import PullToSync from "$lib/PullToSync.svelte";
  import { shared, tabDir, type Dir } from "$lib/motion";
  import { watchPress } from "$lib/press";
  import LockScreen from "$lib/LockScreen.svelte";
  import { lock, watchLock } from "$lib/lock.svelte";
  import { api, isoDate } from "$lib/api";
  import MabiniGrades from "$lib/MabiniGrades.svelte";
  import NeedSis from "$lib/NeedSis.svelte";
  import MabiniPage from "$lib/MabiniPage.svelte";
  import ClassEditor from "$lib/ClassEditor.svelte";
  import ThemeMaker from "$lib/ThemeMaker.svelte";
  import { watchDynamicIsland } from "$lib/glance";
  import { watchBars } from "$lib/bars";
  import { watchBack } from "$lib/back";
  import { app, adopt, applyLook, forgetStudent, hasClasses, listenForTaps, refreshLogins, setRoom, setTextStyle, startClock, syncNow, watchGlance } from "$lib/state.svelte";

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
  // The hello after the dive, on every way in (spec 010 C35).
  let greet = $state(false);

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

  // WKWebView ignores user-scalable=no for pinch; its gesture events can be cancelled.
  onMount(() => {
    const stop = (e: Event) => e.preventDefault();
    for (const t of ["gesturestart", "gesturechange"]) document.addEventListener(t, stop, { passive: false });
    return () => {
      for (const t of ["gesturestart", "gesturechange"]) document.removeEventListener(t, stop);
    };
  });
  onMount(watchPress);

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
    watchVisible();
    applyLook();
    watchLock();
    watchGlance();
    watchKeyboard();
    watchDynamicIsland((has) => (island = has));
    watchBars();
    watchAssis();
    watchBack(() => app.tab !== "today" && ((app.tab = "today"), true));
    // Review builds keep demo mode across launches, so a signed-in launch can be seen without a real login.
    // The browser demo (spec 052) is always the demo account.
    const keepDemo = __WEB__ || (__REVIEW__ && remembered("demo") === "1");
    const snapshot = (keepDemo ? api.demo(isoDate(new Date())) : api.snapshot()).catch(() => null);
    if (keepDemo) await snapshot;
    await refreshLogins();
    signedIn = app.sisConnected || app.mabiniConnected || app.ownSchedule !== null;
    if (signedIn) void ownPortal();
    const reduce = matchMedia("(prefers-reduced-motion: reduce)").matches;
    // Signed in: the dive is the loading screen, and the snapshot loads while it runs (spec 010 C26).
    greet = signedIn;
    // The dive can be turned off in You (spec 047 C8); Today then shows its skeleton while data loads.
    if (signedIn && !reduce && app.dive !== "off") {
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
      greet = false;
      dive = null;
      dived = false;
    }
  });

  async function ownPortal() {
    const list = await api.portals().catch(() => []);
    const id = app.sisConnected ? "sis" : app.ownSchedule !== null ? "own" : "mabini";
    const found = list.find((p) => p.id === id);
    if (found) setSchool(found.theme); // only a real match changes the school
    return found ?? FALLBACK_SIS;
  }

  // Step through, on a first sign-in (C27). Today mounts now, under the landing,
  // so the work is done at the tap and not in the middle of the dive.
  function diveIn(start: DiveStart) {
    setSchool(start.portal.theme); // a first sign-in sets the school (spec 045 C4), dive or not
    if (app.dive === "off") {
      greet = true;
      if (signedIn) syncNow();
      inside = true;
      return;
    }
    dived = true;
    holdLanding = true;
    greet = true;
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

  // Each tab comes back to where it was left. The save runs before the page swaps, while the old
  // tab's scroll is still its own; the new page then slides in toward the tab you chose (spec 045 C22).
  let from = app.tab;
  const scrolls: Record<string, number> = {};
  $effect.pre(() => {
    if (app.tab !== from) scrolls[from] = scrollY;
  });
  $effect(() => {
    if (app.tab === from) return;
    from = app.tab;
    gallery = false;
    const y = scrolls[app.tab] ?? 0;
    scrollTo(0, y);
    // A page that is still loading is short; try again once it has its height.
    if (y) requestAnimationFrame(() => requestAnimationFrame(() => scrollTo(0, y)));
  });
  // Transitions on a keyed block play on a change, not on arrival: Today is simply there (spec 010 C30).
  const page = (enter: boolean) => ({ dir: tabDir(from, app.tab) as Dir, enter });

  function enter() {
    inside = true;
  }

  // The hello's rise on Today plays on the first entry after a sign-in, never on later launches
  // (nothing re-rises). app.css only lets it through while html[data-first] is set.
  $effect(() => {
    if (!inside) return;
    try {
      if (localStorage.getItem("entered") !== "1") {
        localStorage.setItem("entered", "1");
        document.documentElement.dataset.first = "";
      }
    } catch {
      // Storage off: no rise, which is the quiet choice.
    }
  });

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
    if (app.sisConnected || app.mabiniConnected || app.ownSchedule !== null) {
      const snap = await api.snapshot().catch(() => null);
      if (snap) await adopt(snap);
      void ownPortal(); // the school that is left
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
    assis.chat = [];
    void forgetStudent();
    try {
      localStorage.removeItem("entered");
      delete document.documentElement.dataset.first;
      localStorage.removeItem("demo");
    } catch {
      // Review builds only; harmless.
    }
    signedIn = false;
    inside = false;
    dived = false;
    setSchool(FALLBACK_SIS.theme);
  }
  // LAR's window covers the screen: what is behind it holds still (#189). It waits out the
  // opening dither, which starts from the chip in the shell.
  $effect(() => {
    if (!assis.open) return;
    const t = setTimeout(() => setCovered(true), 600);
    return () => (clearTimeout(t), setCovered(false));
  });
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
        <div class="page" in:shared={page(true)} out:shared={page(false)}>
          {#if app.tab === "today"}<Today />
          {:else if app.tab === "schedule"}{#if hasClasses()}<Schedule />{:else}<div class="needs"><NeedSis what="your schedule" /></div>{/if}
          {:else if app.tab === "grades"}{#if app.sisConnected}<Grades />{:else}<div class="needs"><NeedSis what="your grades" /><MabiniGrades /></div>{/if}
          {:else if app.tab === "study"}<Study />
          {:else if gallery}<Gallery onclose={() => (gallery = false)} />
          {:else}<You onsignout={signedOut} ongallery={() => ((gallery = true), window.scrollTo(0, 0))} />{/if}
        </div>
      {/key}
    </main>
    <TabBar />
    <!-- In the shell's stacking context, so the crystal can sit above it as its + (046 C11). -->
    {#if app.editing}
      {#key app.editing.key}<NoteEditor {...app.editing} />{/key}
    {/if}
    <AssisOrb settled={!dive} />
  </div>
  <!-- Without a dive, the void lifts off the room instead of cutting to it. -->
  {#if !dived}<div class="veil" class:lifted aria-hidden="true"></div>{/if}
  {#if showFirstRun(welcomed, chatModel())}<FirstRun ondone={welcomeDone} />{/if}
  {#if app.subject}
    {#key app.subject.code}<SubjectPage {...app.subject} />{/key}
  {/if}
  {#if app.mabiniPage}<MabiniPage />{/if}
  {#if app.classEditor}
    {#key app.classEditor}<ClassEditor was={app.classEditor.was} start={app.classEditor.cls} onclose={() => (app.classEditor = null)} />{/key}
  {/if}
  {#if app.themeMaker}<ThemeMaker />{/if}
  {#if assis.open}<AssisWindow onclose={() => (assis.open = false)} />{/if}
  {#if assis.install.open}<InstallView />{/if}
{/if}

{#if greet && inside}
  <Greeting start={!dive} ready={lifted && (app.today !== null || !hasClasses())} ondone={() => (greet = false)} />
{/if}

{#if dive}
  <Dive start={dive} speed={app.dive === "short" ? 2 : 1} ready={lifted} oncovered={() => (holdLanding = false)} ondone={() => (dive = null)} onfail={noDive} />
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
    padding: calc(var(--safe-top) + 12px) var(--gutter) calc(var(--safe-bottom) + 140px);
  }
  [data-glance="dock"] main {
    padding-bottom: calc(var(--safe-bottom) + 198px);
  }
  .needs {
    display: grid;
    gap: 14px;
  }
</style>
