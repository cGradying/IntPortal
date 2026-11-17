<script lang="ts">
  import { onMount } from "svelte";
  import PixelIcon from "$app_lib/PixelIcon.svelte";
  import { HAND_DRAWN } from "$app_lib/campus/scenes";
  import Campus from "$lib/Campus.svelte";
  import Downloads from "$lib/Downloads.svelte";
  import Phone from "$lib/Phone.svelte";
  import Hero from "$lib/hero/Hero.svelte";
  import { FEATURES, GROUPS } from "$lib/content/features";
  import { GROUP_ICON } from "$lib/groupIcon";
  import { device } from "$lib/device";
  import { firstFor, PLATFORMS } from "$lib/platforms";

  let { data } = $props();
  const campuses = Object.keys(HAND_DRAWN);
  let campus = $state("Sta. Mesa");
  let first = $state<string>("any");

  onMount(() => {
    first = firstFor(device(navigator.userAgent, navigator.maxTouchPoints));
  });

  const cta = $derived.by(() => {
    if (first === "try") return { href: "/try", text: "Try it in your browser" };
    const p = PLATFORMS.find((x) => x.id === first);
    const file = data.release?.assets.find((a) => a.platform === first);
    if (p && file) return { href: file.url, text: p.button };
    return { href: "#download", text: "Get IntPortal" };
  });

  const count = (g: string) => FEATURES.filter((f) => f.group === g).length;

  const features = [
    { group: "today", title: "Today", body: "The class in session counts down. What's due sits right under it, and the free time between classes shows as gaps you can use.", src: "/media/today.webp", alt: "Today: the campus scene, the class in session and the deadlines" },
    { group: "today", title: "Deadlines", body: "SIS, eMabini and your own, in one list. Tick Done, and Undo if your thumb slipped. Scan a handout or paste a group chat message to add them.", src: "/media/done.mp4", poster: "/media/done-poster.webp", video: true, alt: "Ticking a deadline Done, then Undo" },
    { group: "schedule", title: "Schedule", body: "Day and week. Mark a class vacant or online, move it for a week, give it a colour, keep a note on it.", src: "/media/schedule.webp", alt: "The day schedule" },
    { group: "grades", title: "Grades", body: "Every term, your GPA and its trend, and what you need on the rest of the term to reach the grade you want.", src: "/media/grades.webp", alt: "Grades with the GPA trend" },
    { group: "lar", title: "LAR", body: "A small robot from the other side of the portal shows you around and gives one nudge at a time. Turn on his assistant and he answers questions about your classes and notes, on the phone itself.", src: "/media/talk.webp", alt: "LAR asking what to call you" },
    { group: "study", title: "Study", body: "Notes per class or per day, with checklists and photos. Decks bring each card back just before you'd forget it, and a session plays like a card game: a streak multiplies your points.", src: "/media/tabs.mp4", poster: "/media/tabs-poster.webp", video: true, alt: "Moving between Today, Schedule, Grades, Study and You" },
  ];

  const facts = [
    ["Your login stays on your phone.", "It goes into the phone's keychain, the same place your other passwords live."],
    ["Your data is encrypted on the phone.", "Schedule, grades, notes and decks sit in a SQLCipher database. Each student who signs in gets their own."],
    ["There is no IntPortal server.", "No account, no analytics, no ads, no tracking. Nothing to sell, because nothing is collected."],
    ["It only talks to your school.", "It signs in to your school's portal with your own login, the way your browser would, then works offline. If you choose With AI, it also downloads the model file once from Hugging Face, sending nothing about you."],
  ];

  const shipped = $derived(
    data.release?.date ? new Date(data.release.date).toLocaleDateString("en-PH", { month: "long", day: "numeric", year: "numeric", timeZone: "Asia/Manila" }) : null,
  );
</script>

<svelte:head>
  <title>IntPortal: your schedule, grades and deadlines, on your phone</title>
  <meta name="description" content="An unofficial student app. Your schedule, grades and deadlines from your school's portal, on your phone. PUP's SIS and eMabini today, more schools coming. Works offline. Stays on your phone. Free for Android, iPhone, computers and the browser." />
  <meta property="og:title" content="IntPortal" />
  <meta property="og:description" content="Your schedule, grades and deadlines, on your phone. Works offline. Stays on your phone." />
  <meta property="og:image" content="/og.png" />
  <meta name="twitter:card" content="summary_large_image" />
</svelte:head>

<Hero>
  <h1 id="hero-h">IntPortal</h1>
  <p class="line">Your school schedule, grades and deadlines, on your phone. Works offline. Stays on your phone.</p>
  <div class="actions">
    <a class="gold" href={cta.href}>{cta.text}</a>
    {#if first !== "try"}<a class="ghost" href="/try">Try it in your browser</a>{:else}<a class="ghost" href="#download">Every download</a>{/if}
  </div>
  <p class="un">Unofficial. Not made by or affiliated with any school.</p>
</Hero>

<section id="features" class="wrap features" aria-labelledby="f-h">
  <h2 id="f-h">On the other side</h2>
  <p class="lede">Everything SIS has, kept on your phone, and the parts SIS never had.</p>
  {#each features as f, i (f.title)}
    <article class="feature" class:flip={i % 2 === 1}>
      <Phone src={f.src} alt={f.alt} video={f.video} poster={f.poster} />
      <div class="text">
        <h3>{f.title}</h3>
        <p>{f.body}</p>
        <a class="more" href="/features#{f.group}">More in {GROUPS.find((g) => g.id === f.group)?.name}<PixelIcon name="chev" size={12} /></a>
      </div>
    </article>
  {/each}
</section>

<section class="wrap directory" aria-labelledby="dir-h">
  <div class="head">
    <h2 id="dir-h">Everything in IntPortal</h2>
    <a class="ghost" href="/features">The whole directory</a>
  </div>
  <ul class="groups">
    {#each GROUPS as g (g.id)}
      <li>
        <a href="/features#{g.id}">
          <span class="icon"><PixelIcon name={GROUP_ICON[g.id]} size={24} /></span>
          <span class="name">{g.name}</span>
          <span class="gline">{g.line}</span>
          <span class="count pixel">{count(g.id)} {count(g.id) === 1 ? "feature" : "features"}</span>
        </a>
      </li>
    {/each}
  </ul>
</section>

<section class="campus" aria-labelledby="c-h">
  <div class="wrap">
    <h2 id="c-h">Your campus, at this hour</h2>
    <p class="lede">Today opens on your campus, drawn in pixels and lit for the time of day. A jeepney passes now and then.</p>
  </div>
  <Campus {campus} />
  <div class="wrap pick" role="group" aria-label="Campus">
    <span class="pixel">Campus</span>
    <div class="chips">
      {#each campuses as c (c)}
        <button class:on={c === campus} aria-pressed={c === campus} onclick={() => (campus = c)}>{c}</button>
      {/each}
    </div>
  </div>
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
  <p class="fine after">Installing it for the first time? <a href="/help#install">Install help for every device</a>.</p>
</section>

<section class="wrap next" aria-labelledby="n-h">
  <div class="band">
    <div>
      <h2 id="n-h">Where it's going</h2>
      <p>
        {#if data.release}Version {data.release.version} shipped{#if shipped} on {shipped}{/if}.{/if}
        The roadmap shows what's being built now and what comes after, straight from the specs and issues it's built from.
      </p>
    </div>
    <div class="links">
      <a class="ghost" href="/roadmap">The roadmap</a>
      <a class="ghost" href="/changelog">What changed</a>
    </div>
  </div>
</section>

<section class="wrap ask" aria-labelledby="q-h">
  <h2 id="q-h">Questions?</h2>
  <p>Is it official? Is my password safe? Why isn't it on the App Store? The answers, and fixes for when something's wrong, are in <a href="/help">Help</a>.</p>
</section>

<style>
  h1 {
    font-size: clamp(3.4rem, 9vw, 6rem);
    font-weight: 800;
    letter-spacing: -0.04em;
    line-height: 0.95;
  }
  .line {
    margin-top: 18px;
    max-width: 30ch;
    font-size: clamp(1.12rem, 2.1vw, 1.42rem);
    line-height: 1.4;
    color: var(--site-ink-2);
  }
  .actions {
    display: flex;
    flex-wrap: wrap;
    gap: 12px;
    margin-top: 28px;
  }
  .un {
    margin-top: 18px;
    font-size: 0.9rem;
    color: var(--site-ink-3);
  }
  section h2 {
    font-size: clamp(2rem, 5vw, 3.2rem);
  }
  .lede {
    margin-top: 16px;
    max-width: 52ch;
    font-size: 1.15rem;
    line-height: 1.55;
    color: var(--site-ink-2);
  }
  .features,
  .directory,
  .campus,
  .data,
  .dl,
  .next,
  .ask {
    margin-top: clamp(96px, 14vh, 160px);
  }
  .features {
    position: relative;
    margin-top: clamp(48px, 8vh, 96px);
  }
  /* The dive ends in the dot grid; it carries on behind the first section and fades out. */
  .features::before {
    content: "";
    position: absolute;
    z-index: -1;
    left: 50%;
    top: calc(-1 * clamp(48px, 8vh, 96px));
    width: 100vw;
    height: 110vh;
    translate: -50% 0;
    background: radial-gradient(rgba(245, 178, 39, 0.07) 1px, transparent 1.5px) 0 0 / 15px 15px;
    mask-image: linear-gradient(#000, transparent);
    -webkit-mask-image: linear-gradient(#000, transparent);
    pointer-events: none;
  }
  .features .lede {
    margin-bottom: 32px;
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
  .feature p {
    font-size: 1.12rem;
    line-height: 1.6;
    color: var(--site-ink-2);
  }
  .more {
    display: inline-flex;
    align-items: center;
    gap: 8px;
    min-height: 44px;
    margin-top: 12px;
    color: var(--gold);
    font-family: var(--site-display);
    font-weight: 600;
    text-decoration: none;
  }
  .more:hover {
    text-decoration: underline;
  }

  .head {
    display: flex;
    flex-wrap: wrap;
    align-items: end;
    justify-content: space-between;
    gap: 16px 24px;
    margin-bottom: 36px;
  }
  .groups {
    list-style: none;
    margin: 0;
    padding: 0;
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(min(100%, 260px), 1fr));
    box-shadow: inset 1px 1px 0 var(--site-line);
  }
  .groups li {
    box-shadow: inset -1px -1px 0 var(--site-line);
  }
  .groups a {
    display: grid;
    grid-template-columns: 24px 1fr;
    grid-template-rows: auto auto 1fr;
    column-gap: 14px;
    row-gap: 6px;
    height: 100%;
    padding: 22px 20px 20px;
    background: var(--void);
    text-decoration: none;
    transition: background var(--t-quick) var(--ease);
  }
  .groups a:hover {
    background: color-mix(in srgb, var(--void) 88%, var(--gold));
  }
  .icon {
    grid-row: 1 / 3;
    color: var(--site-ink-2);
    padding-top: 2px;
  }
  .groups a:hover .icon {
    color: var(--parch);
  }
  .name {
    font-family: var(--site-display);
    font-weight: 700;
    font-size: 1.15rem;
  }
  .gline {
    color: var(--site-ink-2);
    line-height: 1.45;
  }
  .count {
    grid-column: 2;
    align-self: end;
    margin-top: 10px;
    font-size: 0.78rem;
    color: var(--site-ink-3);
  }

  .campus .lede {
    margin-bottom: 8px;
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
    font: inherit;
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

  .data h2,
  .dl h2 {
    margin-bottom: 40px;
  }
  dl {
    display: grid;
    grid-template-columns: repeat(2, 1fr);
    gap: 40px 56px;
    margin: 0;
  }
  dt {
    font-family: var(--site-display);
    font-weight: 700;
    font-size: 1.25rem;
    margin-bottom: 8px;
  }
  dd {
    margin: 0;
    color: var(--site-ink-2);
    line-height: 1.6;
    max-width: 46ch;
  }
  .data .fine,
  .after {
    margin-top: 32px;
  }

  .band {
    display: flex;
    flex-wrap: wrap;
    align-items: end;
    justify-content: space-between;
    gap: 24px 48px;
    padding: clamp(28px, 5vw, 56px);
    background: var(--void-2, #0e0a12);
    box-shadow: inset 0 0 0 1px var(--site-line);
    clip-path: polygon(0 4px, 4px 4px, 4px 0, calc(100% - 4px) 0, calc(100% - 4px) 4px, 100% 4px, 100% calc(100% - 4px), calc(100% - 4px) calc(100% - 4px), calc(100% - 4px) 100%, 4px 100%, 4px calc(100% - 4px), 0 calc(100% - 4px));
  }
  .band p {
    margin-top: 14px;
    max-width: 56ch;
    color: var(--site-ink-2);
    line-height: 1.6;
  }
  .links {
    display: flex;
    flex-wrap: wrap;
    gap: 10px;
  }
  .ask p {
    margin-top: 14px;
    max-width: 60ch;
    font-size: 1.12rem;
    line-height: 1.6;
    color: var(--site-ink-2);
  }
  @media (max-width: 899px) {
    h1 {
      font-size: clamp(2.9rem, 13vw, 4rem);
    }
    .line {
      margin-top: 12px;
      font-size: 1.06rem;
    }
    .actions {
      margin-top: 20px;
      gap: 10px;
    }
    .un {
      margin-top: 14px;
    }
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
  }
</style>
