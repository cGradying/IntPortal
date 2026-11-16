<script lang="ts">
  import { onMount } from "svelte";
  import Lar from "$app_lib/lar/Lar.svelte";
  import { HAND_DRAWN } from "$app_lib/campus/scenes";
  import Campus from "$lib/Campus.svelte";
  import Downloads from "$lib/Downloads.svelte";
  import Phone from "$lib/Phone.svelte";
  import { device } from "$lib/device";
  import { firstFor, PLATFORMS } from "$lib/platforms";
  import { REPO_URL } from "$lib/releases";

  let { data } = $props();
  const campuses = Object.keys(HAND_DRAWN);
  let campus = $state("Sta. Mesa");
  let first = $state<string>("any");

  let larSize = $state(6);
  onMount(() => {
    first = firstFor(device(navigator.userAgent, navigator.maxTouchPoints));
    const wide = matchMedia("(min-width: 900px)");
    const fit = () => (larSize = wide.matches ? 9 : 5);
    fit();
    wide.addEventListener("change", fit);
    return () => wide.removeEventListener("change", fit);
  });

  const cta = $derived.by(() => {
    if (first === "try") return { href: "/try", text: "Try it in your browser" };
    const p = PLATFORMS.find((x) => x.id === first);
    const file = data.release?.assets.find((a) => a.platform === first);
    if (p && file) return { href: file.url, text: p.button };
    return { href: "#download", text: "Get IntPortal" };
  });

  const features = [
    { title: "Today", body: "The class in session counts down. What's due sits right under it, and the free time between classes shows as gaps you can use.", src: "/media/today.webp", alt: "Today: the campus scene, the class in session and the deadlines" },
    { title: "Deadlines", body: "SIS, eMabini and your own, in one list. Tick Done, and Undo if your thumb slipped. Scan a handout or paste a group chat message to add them.", src: "/media/done.mp4", poster: "/media/done-poster.webp", video: true, alt: "Ticking a deadline Done, then Undo" },
    { title: "Schedule", body: "Day and week. Mark a class vacant or online, move it for a week, give it a colour, keep a note on it.", src: "/media/schedule.webp", alt: "The day schedule" },
    { title: "Grades", body: "Every term, your GPA and its trend, and what you need on the rest of the term to reach the grade you want.", src: "/media/grades.webp", alt: "Grades with the GPA trend" },
    { title: "LAR", body: "A small robot from the other side of the portal shows you around and gives one nudge at a time. Turn on his assistant and he answers questions about your classes and notes, on the phone itself.", src: "/media/talk.webp", alt: "LAR asking what to call you" },
    { title: "Study and notes", body: "Notes per class or per day, with checklists and photos. Flashcard decks bring each card back just before you'd forget it.", src: "/media/tabs.mp4", poster: "/media/tabs-poster.webp", video: true, alt: "Moving between Today, Schedule, Grades, Study and You" },
  ];

  const facts = [
    ["Your login stays on your phone.", "It goes into the phone's keychain, the same place your other passwords live."],
    ["Your data is encrypted on the phone.", "Schedule, grades, notes and decks sit in a SQLCipher database. Each student who signs in gets their own."],
    ["There is no IntPortal server.", "No account, no analytics, no ads, no tracking. Nothing to sell, because nothing is collected."],
    ["It only talks to PUP.", "It signs in to SIS and eMabini with your own login, the way your browser would, then works offline."],
  ];

  const faq = [
    ["Is this official?", "No. IntPortal is an independent student project. It isn't made by PUP, isn't affiliated with PUP, and only works with your own account."],
    ["Is my password safe?", "It never leaves your phone except to sign in to PUP's own SIS or eMabini. It's kept in the phone's keychain, and the app makes at most three sign-in tries every fifteen minutes so it can never lock your SIS account."],
    ["Does it work offline?", "Yes. After one sign-in, your schedule, grades, deadlines, notes and decks are on the phone. It syncs again when you have signal."],
    ["Is it free?", "Yes, free and with no ads. The source is public under the PolyForm Noncommercial licence."],
    ["Why isn't it on the App Store?", "Publishing there needs a paid Apple developer account. Until then, iPhone users can sideload it with AltStore or SideStore, build it with Xcode, or try it in the browser."],
    ["What about other schools?", "The portal wall lists other schools' portals, but only PUP's SIS and eMabini sign in today."],
  ];
</script>

<svelte:head>
  <title>IntPortal: your PUP schedule, grades and deadlines, on your phone</title>
  <meta name="description" content="An unofficial student app for PUP. Your schedule, grades and deadlines from SIS and eMabini, on your phone. Works offline. Stays on your phone. Free for Android, iPhone and the browser." />
  <meta property="og:title" content="IntPortal" />
  <meta property="og:description" content="Your PUP schedule, grades and deadlines, on your phone. Works offline. Stays on your phone." />
  <meta property="og:image" content="/og.png" />
  <meta name="twitter:card" content="summary_large_image" />
</svelte:head>

<section class="hero">
  <div class="lar">
    <p class="slab"><span class="pixel who">LAR</span> Tara, pasok!</p>
    <Lar size={larSize} gesture="wave" label="LAR, the Lakbay-Aral Robot, waving" />
  </div>
  <div class="wrap copy">
    <h1>IntPortal</h1>
    <p class="line">Your PUP schedule, grades and deadlines, on your phone. Works offline. Stays on your phone.</p>
    <div class="actions">
      <a class="gold" href={cta.href}>{cta.text}</a>
      {#if first !== "try"}<a class="ghost" href="/try">Try it in your browser</a>{:else}<a class="ghost" href="#download">Every download</a>{/if}
    </div>
    <p class="un">Unofficial. Not made by or affiliated with PUP.</p>
  </div>
  <div class="stage">
    <Campus {campus} />
  </div>
  <div class="wrap pick" role="group" aria-label="Campus">
    <span class="pixel">Campus</span>
    <div class="chips">
      {#each campuses as c (c)}
        <button class:on={c === campus} aria-pressed={c === campus} onclick={() => (campus = c)}>{c}</button>
      {/each}
    </div>
  </div>
</section>

<section id="features" class="wrap features" aria-labelledby="f-h">
  <h2 id="f-h">What's in it</h2>
  {#each features as f, i (f.title)}
    <article class="feature" class:flip={i % 2 === 1}>
      <Phone src={f.src} alt={f.alt} video={f.video} poster={f.poster} />
      <div class="text">
        <h3>{f.title}</h3>
        <p>{f.body}</p>
      </div>
    </article>
  {/each}
  <p class="outside">And outside the app: reminders before class and before things are due, a countdown on the Lock Screen and in the Dynamic Island (a status-bar chip on Android), and a home-screen widget.</p>
</section>

<section class="wrap data" aria-labelledby="d-h">
  <h2 id="d-h">Stays on your phone</h2>
  <dl>
    {#each facts as [lead, more] (lead)}
      <div><dt>{lead}</dt><dd>{more}</dd></div>
    {/each}
  </dl>
  <p class="fine">The whole of it is in the <a href="/privacy">privacy policy</a>.</p>
</section>

<section id="download" class="wrap dl" aria-labelledby="dl-h">
  <h2 id="dl-h">Get it</h2>
  <Downloads release={data.release} />
</section>

<section id="help" class="wrap help" aria-labelledby="h-h">
  <h2 id="h-h">Installing it</h2>
  {#each PLATFORMS as p (p.id)}
    <details>
      <summary>{p.name}</summary>
      <ol>{#each p.steps as s (s)}<li>{s}</li>{/each}</ol>
      {#if p.id === "ios"}<p class="fine"><a href="{REPO_URL}/blob/main/docs/BUILDING.md" rel="noopener">Building it with Xcode</a></p>{/if}
    </details>
  {/each}
</section>

<section class="wrap faq" aria-labelledby="q-h">
  <h2 id="q-h">Questions</h2>
  {#each faq as [q, a] (q)}
    <details>
      <summary>{q}</summary>
      <p>{a}</p>
    </details>
  {/each}
</section>

<style>
  .hero {
    position: relative;
    display: flex;
    flex-direction: column;
    padding-top: clamp(32px, 7vh, 88px);
  }
  h1 {
    font-size: clamp(3.4rem, 10vw, 6rem);
    font-weight: 800;
    letter-spacing: -0.04em;
    line-height: 0.95;
  }
  .line {
    margin-top: 20px;
    max-width: 30ch;
    font-size: clamp(1.15rem, 2.2vw, 1.45rem);
    line-height: 1.4;
    color: var(--site-ink-2);
  }
  .actions {
    display: flex;
    flex-wrap: wrap;
    gap: 12px;
    margin-top: 32px;
  }
  .un {
    margin-top: 20px;
    font-size: 0.9rem;
    color: var(--site-ink-3);
  }
  .stage {
    position: relative;
    margin-top: clamp(8px, 3vh, 40px);
  }
  /* On a wide screen LAR floats in the night beside the name; on a phone he
     stands on the roofline. */
  .lar {
    position: absolute;
    right: max(var(--site-gutter), (100% - var(--site-max)) / 2 + 40px);
    top: clamp(96px, 16vh, 170px);
    z-index: 1;
    display: grid;
    justify-items: center;
    gap: 6px;
  }
  .slab {
    padding: 8px 14px;
    background: var(--void-3);
    box-shadow: inset 0 0 0 3px var(--slab-edge);
    clip-path: polygon(0 3px, 3px 3px, 3px 0, calc(100% - 3px) 0, calc(100% - 3px) 3px, 100% 3px, 100% calc(100% - 3px), calc(100% - 3px) calc(100% - 3px), calc(100% - 3px) 100%, 3px 100%, 3px calc(100% - 3px), 0 calc(100% - 3px));
    color: var(--parch);
    font-weight: 600;
    white-space: nowrap;
  }
  .who {
    color: var(--gold);
    margin-right: 6px;
  }
  .pick {
    display: flex;
    align-items: center;
    gap: 14px;
    padding-top: 14px;
  }
  .pick > .pixel {
    color: var(--site-ink-3);
    font-size: 0.85rem;
    flex: none;
  }
  .chips {
    display: flex;
    gap: 6px;
    overflow-x: auto;
    scrollbar-width: none;
    padding: 4px 2px;
  }
  .chips button {
    flex: none;
    min-height: 44px;
    padding: 0 14px;
    border: 0;
    border-radius: var(--radius);
    background: rgba(244, 236, 216, 0.05);
    color: var(--site-ink-2);
    font-weight: 600;
    cursor: pointer;
    transition: background var(--t-quick) var(--ease), color var(--t-quick) var(--ease);
  }
  .chips button:hover {
    color: var(--site-ink);
  }
  .chips button.on {
    background: var(--gold-soft);
    color: var(--gold);
  }
  section h2 {
    font-size: clamp(2rem, 5vw, 3.2rem);
    margin-bottom: 40px;
  }
  .features,
  .data,
  .dl,
  .help,
  .faq {
    margin-top: clamp(96px, 14vh, 160px);
  }
  .feature {
    display: flex;
    align-items: center;
    gap: clamp(28px, 6vw, 96px);
    padding-block: 28px;
  }
  .feature.flip {
    flex-direction: row-reverse;
  }
  .feature .text {
    max-width: 44ch;
  }
  .feature h3 {
    font-size: clamp(1.6rem, 3.4vw, 2.3rem);
    margin-bottom: 14px;
  }
  .feature p,
  .outside {
    font-size: 1.12rem;
    line-height: 1.6;
    color: var(--site-ink-2);
  }
  .outside {
    margin-top: 40px;
    max-width: 60ch;
  }
  dl {
    display: grid;
    grid-template-columns: repeat(2, minmax(0, 1fr));
    gap: 36px 56px;
    margin: 0 0 32px;
  }
  dt {
    font-family: var(--site-display);
    font-weight: 700;
    font-size: 1.3rem;
    margin-bottom: 8px;
  }
  dd {
    margin: 0;
    color: var(--site-ink-2);
    line-height: 1.6;
    max-width: 44ch;
  }
  details {
    box-shadow: inset 0 -1px 0 var(--site-line);
  }
  summary {
    display: flex;
    align-items: center;
    justify-content: space-between;
    min-height: 60px;
    font-family: var(--site-display);
    font-weight: 600;
    font-size: 1.15rem;
    cursor: pointer;
    list-style: none;
  }
  summary::-webkit-details-marker {
    display: none;
  }
  summary::after {
    content: "";
    width: 12px;
    height: 12px;
    flex: none;
    background: linear-gradient(var(--gold), var(--gold)) center / 12px 2px no-repeat, linear-gradient(var(--gold), var(--gold)) center / 2px 12px no-repeat;
    transition: transform var(--t-move) var(--ease);
  }
  details[open] summary::after {
    transform: rotate(45deg);
  }
  details p,
  details ol {
    max-width: 65ch;
    margin: 0 0 20px;
    color: var(--site-ink-2);
    line-height: 1.6;
  }
  details ol {
    padding-left: 1.3em;
  }
  details li + li {
    margin-top: 6px;
  }
  .copy {
    order: -1;
  }
  @media (max-width: 760px) {
    .feature,
    .feature.flip {
      flex-direction: column;
      align-items: flex-start;
    }
    dl {
      grid-template-columns: 1fr;
    }
    .lar {
      position: static;
      justify-items: end;
      margin: 24px var(--site-gutter) -36px 0;
    }
  }
</style>
