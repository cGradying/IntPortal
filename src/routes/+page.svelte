<script lang="ts">
  import "$lib/app.css";
  import { onMount } from "svelte";
  import Landing from "$lib/Landing.svelte";
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
  import { api } from "$lib/api";
  import MabiniGrades from "$lib/MabiniGrades.svelte";
  import NeedSis from "$lib/NeedSis.svelte";
  import MabiniPage from "$lib/MabiniPage.svelte";
  import { watchDynamicIsland } from "$lib/glance";
  import { watchBars } from "$lib/bars";
  import { watchBack } from "$lib/back";
  import { app, adopt, refreshLogins, setRoom, startClock } from "$lib/state.svelte";

  let ready = $state(false);
  let signedIn = $state(false);
  let inside = $state(false);
  let gallery = $state(false);
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
    if (__REVIEW__) {
      // Review builds put uncaught errors on screen; there is no console on a phone.
      const show = (m: string) => document.body.insertAdjacentHTML("beforeend", `<pre style="position:fixed;inset:auto 8px 90px;z-index:99;padding:8px;background:#300;color:#fbb;white-space:pre-wrap;font-size:11px">${m.replace(/</g, "&lt;")}</pre>`);
      addEventListener("error", (e) => show(`${e.message} @ ${e.filename}:${e.lineno}`));
      addEventListener("unhandledrejection", (e) => show(String(e.reason?.stack ?? e.reason)));
    }
    setRoom(app.room);
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
    const [, snap] = await Promise.all([refreshLogins(), api.snapshot().catch(() => null)]);
    signedIn = app.sisConnected || app.mabiniConnected;
    if (snap) await adopt(snap);
    startClock();
    ready = true;
  });

  // Each tab opens at its top, not wherever the last one was scrolled.
  $effect(() => {
    void app.tab;
    gallery = false;
    window.scrollTo(0, 0);
  });

  function enter() {
    inside = true;
  }

  // The veil lifts once Today has painted under it: mounting the app can
  // take longer than the fade, which would otherwise finish unseen.
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
    signedIn = false;
    inside = false;
  }
</script>

{#if lock.enabled && (lock.locked || lock.hidden)}<LockScreen />{/if}

{#if ready && !inside}
  <Landing {signedIn} onenter={enter} />
{/if}

{#if inside}
  <div class="shell dots" data-glance={island ? "none" : "dock"} data-lifted={lifted || undefined}>
    <div class="topfade" aria-hidden="true"></div>
    {#if !island}<Glance />{/if}
    <main>
      <PullToSync />
      {#key app.tab}
        <div class="page">
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
  <!-- The landing's void lifts off the room instead of cutting to it. -->
  <div class="veil" class:lifted aria-hidden="true"></div>
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

<style>
  .shell {
    min-height: 100vh;
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
    transition:
      opacity 0.45s var(--ease),
      visibility 0s 0.45s;
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
  .page {
    animation: in 0.3s var(--ease) backwards;
  }
  .needs {
    display: grid;
    gap: 14px;
  }
  @keyframes in {
    from { opacity: 0; transform: translateY(6px); }
  }
</style>
