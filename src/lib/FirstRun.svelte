<script lang="ts">
  // Three short screens the first time someone gets in: what IntPortal does,
  // where their data lives, and reminders (the only place that asks the
  // phone for notification permission unprompted).
  import { buzz } from "./haptics";
  import Isko from "./Isko.svelte";
  import Lar from "./lar/Lar.svelte";
  import { chatModel, embedModel, install, mb } from "./assis/assis.svelte";
  import { app, scheduleReminders } from "./state.svelte";

  let { ondone }: { ondone: () => void } = $props();
  let step = $state(0);

  const size = $derived(mb((chatModel()?.bytes ?? 0) + (embedModel()?.bytes ?? 0)));
  // The AI choice only shows on builds that have it.
  const steps = $derived([
    { title: "Meet IskoLAR.", body: "You're Isko. I'm LAR, the Lakbay-Aral Robot, here to study with you. Your schedule, grades, notes and study cards are in one place, and I'll count down to your next class." },
    { title: "Everything stays on this phone.", body: "Your login sits in the phone's keychain. IntPortal only talks to PUP SIS, and your notes and decks never leave the device." },
    ...(chatModel()
      ? [{ title: "Light, or with AI?", ai: true, body: `Light is the app with no AI and nothing extra to download. With AI, LAR answers questions about your classes and notes and can summarize a note, all on this phone. It is a one-time ${size} download (use Wi-Fi), works offline, and you can remove it any time on You.` }]
      : []),
    { title: "Want a heads-up before class?", body: "A nudge 10 minutes before each class, and the evening before quizzes and exams. You can change or turn these off on You." },
  ] as { title: string; body: string; ai?: boolean }[]);

  async function allow() {
    await scheduleReminders(true);
    ondone();
  }

  function skipReminders() {
    app.reminderLead = 0;
    try {
      localStorage.setItem("reminderLead", "0");
    } catch {
      // Asked again next time.
    }
    ondone();
  }
</script>

<div class="first" role="dialog" aria-label="Welcome">
  <div class="art"><Isko size={120} /><Lar size={4} gesture="wave" /></div>
  <div class="card notch text">
    <p class="label">{step + 1} of {steps.length}</p>
    <h1>{steps[step].title}</h1>
    <p>{steps[step].body}</p>
  </div>
  <div class="dots" aria-hidden="true">{#each steps as _, i (i)}<i class:on={i === step}></i>{/each}</div>
  {#if steps[step].ai}
    <button class="primary" onclick={() => { buzz.tick(); install(); step++; }}>With AI · {size}</button>
    <button class="link" onclick={() => { buzz.select(); step++; }}>Light, no AI</button>
  {:else if step < steps.length - 1}
    <button class="primary" onclick={() => { buzz.select(); step++; }}>Next</button>
    <button class="link" onclick={ondone}>Skip</button>
  {:else}
    <button class="primary" onclick={allow}>Turn on reminders</button>
    <button class="link" onclick={skipReminders}>Not now</button>
  {/if}
</div>

<style>
  .first {
    position: fixed;
    inset: 0;
    z-index: 60;
    display: grid;
    align-content: end;
    gap: 14px;
    padding: calc(var(--safe-top) + 24px) var(--gutter) calc(var(--safe-bottom) + 24px);
    background: var(--ground);
  }
  .art {
    display: flex;
    align-items: end;
    justify-content: center;
    gap: 18px;
    padding-bottom: 8px;
  }
  .text {
    --step: 4px;
    padding: 20px;
  }
  h1 {
    margin: 4px 0 8px;
    font-family: var(--font-display);
    font-size: min(1.412rem, 31px);
  }
  .text p:last-child {
    margin: 0;
    font-size: min(0.941rem, 29px);
    line-height: 1.5;
    color: var(--ink-2);
  }
  .dots {
    display: flex;
    justify-content: center;
    gap: 6px;
  }
  .dots i {
    width: 6px;
    height: 6px;
    background: var(--edge-2);
  }
  .dots i.on {
    width: 18px;
    background: var(--gold);
  }
  button {
    height: 52px;
    border: 0;
    border-radius: 12px;
    font-family: var(--font-display);
    font-weight: 700;
    font-size: min(0.941rem, 29px);
  }
  .primary {
    background: var(--gold);
    color: var(--on-gold);
  }
  .link {
    height: 36px;
    background: none;
    color: var(--ink-2);
  }
</style>
