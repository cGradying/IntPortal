<script lang="ts">
  import { onMount } from "svelte";
  import PixelIcon, { type SpriteName } from "$app_lib/PixelIcon.svelte";
  import { HAND_DRAWN } from "$app_lib/campus/scenes";
  import Campus from "$lib/Campus.svelte";
  import Downloads from "$lib/Downloads.svelte";
  import Phone from "$lib/Phone.svelte";
  import Hero from "$lib/hero/Hero.svelte";
  import { FEATURES, GROUPS } from "$lib/content/features";
  import { GROUP_ICON } from "$lib/groupIcon";
  import { device } from "$lib/device";
  import { firstFor, PLATFORMS } from "$lib/platforms";
  import { REPO_URL } from "$lib/releases";

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

  const inGroup = (g: string) => FEATURES.filter((f) => f.group === g);
  const slug = (t: string) => "s-" + t.toLowerCase();

  // 058 C10: on a wide screen one phone stays in view and shows the story at the
  // middle of the viewport.
  let story = $state(0);
  let stories = $state<HTMLElement>();
  onMount(() => {
    if (!stories) return;
    const io = new IntersectionObserver(
      (es) => es.forEach((e) => e.isIntersecting && (story = Number((e.target as HTMLElement).dataset.i))),
      { rootMargin: "-50% 0px -50% 0px" },
    );
    stories.querySelectorAll<HTMLElement>("article").forEach((a) => io.observe(a));
    return () => io.disconnect();
  });

  // 058 C13: the dot ground lights up round a fine pointer.
  let lit = $state<HTMLElement>();
  let frame = 0;
  function glow(e: PointerEvent) {
    if (e.pointerType !== "mouse" || !lit || frame) return;
    const { clientX, clientY } = e;
    frame = requestAnimationFrame(() => {
      frame = 0;
      if (!lit) return;
      // The ground spans the viewport's width from its left edge, so x is the
      // pointer's own; y is measured from the section's top.
      lit.style.setProperty("--gx", `${clientX}px`);
      lit.style.setProperty("--gy", `${clientY - lit.getBoundingClientRect().top}px`);
    });
  }

  const features: { group: string; title: string; body: string; src: string; alt: string; video?: boolean; poster?: string }[] = [
    { group: "today", title: "Today", body: "The class in session counts down. What's due sits right under it, and the free time between classes shows as gaps you can use.", src: "/media/today.webp", alt: "Today: the campus scene, the class in session and the deadlines" },
    { group: "today", title: "Deadlines", body: "SIS, eMabini and your own, in one list. Tick Done, and Undo if your thumb slipped. Scan a handout or paste a group chat message to add them.", src: "/media/due.webp", alt: "The Due card on Today with three deadlines and Add, on sample data" },
    { group: "schedule", title: "Schedule", body: "Day and week. Mark a class vacant or online, move it for a week, give it a colour, keep a note on it.", src: "/media/schedule.webp", alt: "The day schedule" },
    { group: "grades", title: "Grades", body: "Every term, your GPA and its trend, and what you need on the rest of the term to reach the grade you want.", src: "/media/grades.webp", alt: "Grades with the GPA trend" },
    { group: "lar", title: "LAR", body: "A small robot from the other side of the portal shows you around and gives one nudge at a time. Turn on his assistant and he answers questions about your classes and notes, on the phone itself.", src: "/media/talk.webp", alt: "LAR asking what to call you" },
    { group: "study", title: "Study", body: "Notes per class or per day, with checklists and photos. Decks bring each card back just before you'd forget it, and a session plays like a card game: a streak multiplies your points.", src: "/media/game.webp", alt: "A round of the study game on sample cards" },
  ];

  const facts: { icon: SpriteName; lead: string; more: string; href?: string; link?: string }[] = [
    { icon: "lock", lead: "Your login only goes to your school.", more: "It's kept in the phone's keychain and used only to sign in to your school's own portal." },
    { icon: "disk", lead: "Your data is encrypted on the phone.", more: "Schedule, grades, notes and decks sit in an encrypted database. Each student who signs in gets their own." },
    { icon: "you", lead: "There is no IntPortal server.", more: "No account, no analytics, no ads, no tracking. Nothing to sell, because nothing is collected." },
    { icon: "sync", lead: "It only talks to your school.", more: "It signs in to your school's portal with your own login, the way your browser would, then works offline. If you add LAR's AI, it also downloads the model files from Hugging Face, sending nothing about you beyond the download itself." },
    { icon: "find", lead: "Anyone can read the code.", more: "It's published on GitHub, so anyone can check what the app does.", href: REPO_URL, link: "The code on GitHub" },
  ];
  const questions = [
    ["q-is-this-official", "Is this official?"],
    ["q-is-my-password-safe", "Is my password safe?"],
    ["q-why-isnt-it-on-the-app-store", "Why isn't it on the App Store?"],
  ];

  const shipped = $derived(
    data.release?.date ? new Date(data.release.date).toLocaleDateString("en-PH", { month: "long", day: "numeric", year: "numeric", timeZone: "Asia/Manila" }) : null,
  );
</script>

<svelte:head>
  <title>IntPortal: your schedule, grades and deadlines, on your phone</title>
  <meta name="description" content="An unofficial student app. Your schedule, grades and deadlines from your school's portal, on your phone. PUP's SIS and eMabini today, more schools coming. Works offline. Stays on your phone. Free for Android, iPhone, computers and the browser." />
  <meta property="og:title" content="IntPortal: your school portal, on your phone" />
  <meta property="og:description" content="Free, unofficial student app. Your schedule, grades and deadlines from PUP SIS and eMabini, on your phone. Works offline." />
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

<svelte:window onpointermove={glow} />

<section id="features" class="wrap features" aria-labelledby="f-h" bind:this={lit}>
  <div class="story">
    <div class="steps" bind:this={stories}>
      <h2 id="f-h">On the other side</h2>
      <p class="lede">Everything SIS has, kept on your phone, and the parts SIS never had.</p>
      {#each features as f, i (f.title)}
        <article id={slug(f.title)} class="feature" class:flip={i % 2 === 1} class:on={i === story} data-i={i}>
          <div class="own"><Phone src={f.src} alt={f.alt} video={f.video} poster={f.poster} /></div>
          <span class="vh">{f.alt}</span>
          <div class="text">
            <h3>{f.title}</h3>
            <p>{f.body}</p>
            <a class="more" href="/features#{f.group}">More in {GROUPS.find((g) => g.id === f.group)?.name}<PixelIcon name="chev" size={12} /></a>
          </div>
        </article>
      {/each}
    </div>
    <div class="stage" aria-hidden="true">
      <div class="phone">
        {#each features as f, i (f.title)}
          <img src={f.video ? f.poster : f.src} alt="" class:on={i === story} loading="lazy" decoding="async" width="450" height="1000" />
        {/each}
      </div>
      <ol class="rail">
        {#each features as f, i (f.title)}
          <li><a href="#{slug(f.title)}" class="pixel" class:on={i === story} tabindex="-1">{f.title}</a></li>
        {/each}
      </ol>
    </div>
  </div>
</section>

<section class="wrap directory" aria-labelledby="dir-h">
  <div class="head">
    <h2 id="dir-h">Everything in IntPortal</h2>
    <a class="ghost" href="/features">The whole directory</a>
  </div>
  <div class="index">
    {#each GROUPS as g (g.id)}
      {@const fs = inGroup(g.id)}
      <section class="group" aria-labelledby="g-{g.id}">
        <h3 id="g-{g.id}"><a href="/features#{g.id}"><span class="icon"><PixelIcon name={GROUP_ICON[g.id]} size={20} /></span>{g.name}<span class="count pixel">{fs.length}</span></a></h3>
        <p class="gline">{g.line}</p>
        <ul>
          {#each fs as f (f.slug)}<li><a href="/features/{f.slug}">{f.name}</a></li>{/each}
        </ul>
      </section>
    {/each}
  </div>
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
    {#each facts as f (f.lead)}
      <div>
        <span class="tile" aria-hidden="true"><PixelIcon name={f.icon} size={20} /></span>
        <dt>{f.lead}</dt>
        <dd>{f.more}{#if f.href}{" "}<a href={f.href} rel="noopener">{f.link}</a>{/if}</dd>
      </div>
    {/each}
  </dl>
  <p class="fine">The whole of it is in the <a href="/privacy">privacy policy</a>.</p>
</section>

<section id="download" class="wrap dl" aria-labelledby="dl-h">
  <h2 id="dl-h">Get it</h2>
  <Downloads release={data.release} />
  <p class="fine after">Installing it for the first time? <a href="/help#install">Install help for every device</a>.</p>
</section>

<div class="wrap after-dl">
<section class="next" aria-labelledby="n-h">
  <div class="band">
    <div>
      <h2 id="n-h">Where it's going</h2>
      <p>
        {#if data.release}Version {data.release.version} shipped{#if shipped}{" "}on {shipped}{/if}.{/if}
        The roadmap shows what's being built now and what comes after, straight from the specs and issues it's built from.
      </p>
    </div>
    <div class="links">
      <a class="ghost" href="/roadmap">The roadmap</a>
      <a class="ghost" href="/changelog">What changed</a>
    </div>
  </div>
</section>

<section class="ask" aria-labelledby="q-h">
  <h2 id="q-h">Questions?</h2>
  <ul>
    {#each questions as [id, q] (id)}<li><a href="/help#{id}">{q}<PixelIcon name="chev" size={12} /></a></li>{/each}
  </ul>
  <a class="all" href="/help#questions">All questions</a>
</section>
</div>

<style>
  h1 {
    font-size: clamp(3.4rem, 9vw, 6rem);
    font-weight: 800;
    letter-spacing: -0.04em;
    line-height: 0.95;
  }
  .line {
    margin-top: 18px;
    max-width: 34ch;
    font-size: clamp(1.12rem, 1.5vw, 1.6rem);
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
    font-size: 0.95rem;
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
  .after-dl {
    margin-top: clamp(96px, 14vh, 160px);
  }
  .features {
    position: relative;
    isolation: isolate;
    margin-top: 0;
    padding-top: 32px;
  }
  /* The dive ends in the dot grid; it carries on behind the first section and fades out. */
  .features::before {
    content: "";
    position: absolute;
    z-index: -1;
    left: 50%;
    top: 0;
    width: 100vw;
    height: 110vh;
    translate: -50% 0;
    /* The same 3 px dot on a 15 px pitch the dive ends on, lit, then fading out. */
    background: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='15' height='15'%3E%3Crect width='3' height='3' fill='%23f5b227' fill-opacity='.26'/%3E%3C/svg%3E") 0 12px / 15px 15px;
    mask-image: linear-gradient(#000 20%, transparent);
    -webkit-mask-image: linear-gradient(#000 20%, transparent);
    pointer-events: none;
  }
  /* 058 C13: a brighter copy of the same dots, shown only round the pointer. */
  .features::after {
    content: "";
    position: absolute;
    z-index: -1;
    left: 50%;
    top: 0;
    width: 100vw;
    height: 100%;
    translate: -50% 0;
    background: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='15' height='15'%3E%3Crect width='3' height='3' fill='%23f5b227' fill-opacity='.75'/%3E%3C/svg%3E") 0 12px / 15px 15px;
    mask-image: radial-gradient(circle 140px at var(--gx, -999px) var(--gy, -999px), #000, transparent);
    -webkit-mask-image: radial-gradient(circle 140px at var(--gx, -999px) var(--gy, -999px), #000, transparent);
    opacity: 0;
    transition: opacity 240ms var(--ease);
    pointer-events: none;
  }
  @media (hover: hover) and (pointer: fine) and (prefers-reduced-motion: no-preference) {
    .features:hover::after {
      opacity: 1;
    }
  }
  .features .lede {
    margin-bottom: 32px;
  }
  /* Phone and text sit together in the middle, alternating sides, so no row
     leaves a dead half beside its text. */
  .feature {
    display: flex;
    align-items: center;
    justify-content: center;
    gap: clamp(28px, 6vw, 88px);
    padding-block: 28px;
  }
  .feature.flip {
    flex-direction: row-reverse;
  }
  .feature .text {
    flex: 0 1 500px;
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
  .stage {
    display: none;
  }
  /* 058 C10: on a wide screen the stories scroll past one phone that stays put. */
  @media (min-width: 900px) {
    .story {
      display: grid;
      grid-template-columns: repeat(2, minmax(0, 1fr));
      gap: clamp(40px, 6vw, 96px);
    }
    .own {
      display: none;
    }
    .feature,
    .feature.flip {
      flex-direction: row;
      justify-content: flex-start;
      min-height: 72svh;
      padding-block: 0;
    }
    .feature .text {
      flex: 0 1 520px;
    }
    .feature h3,
    .feature p {
      transition: color 240ms var(--ease);
    }
    .feature:not(.on):not(:focus-within) h3 {
      color: var(--site-ink-2);
    }
    .feature:not(.on):not(:focus-within) p {
      color: var(--site-ink-3);
    }
    .steps {
      padding-bottom: 22svh;
    }
    .steps > article:first-of-type {
      min-height: auto;
      padding-block: 8px 18svh;
    }
    .stage {
      --w: min(17.65rem, calc((100svh - 190px) * 0.45));
      position: sticky;
      top: calc(50svh - var(--w) * 10 / 9 - 27px);
      align-self: start;
      display: grid;
      justify-items: center;
      gap: 22px;
    }
    .phone {
      position: relative;
      width: var(--w);
      aspect-ratio: 9 / 20;
      padding: 8px;
      border-radius: 36px;
      background: #050307;
      box-shadow: inset 0 0 0 1px rgba(244, 236, 216, 0.12), 0 40px 80px -30px rgba(0, 0, 0, 0.9), 0 0 0 1px #000;
    }
    .phone img {
      position: absolute;
      inset: 8px;
      width: calc(100% - 16px);
      height: calc(100% - 16px);
      object-fit: cover;
      border-radius: 28px;
      background: var(--void-2);
      opacity: 0;
      transition: opacity 240ms steps(4, jump-none);
    }
    .phone img.on {
      opacity: 1;
    }
    .rail {
      display: flex;
      flex-wrap: wrap;
      justify-content: center;
      gap: 0 4px;
      margin: 0;
      padding: 0;
      list-style: none;
    }
    .rail a {
      display: inline-flex;
      align-items: center;
      gap: 6px;
      min-height: 32px;
      padding: 0 6px;
      color: var(--site-ink-3);
      font-size: 0.7rem;
      text-decoration: none;
      transition: color 240ms var(--ease);
    }
    .rail a::before {
      content: "";
      width: 4px;
      height: 4px;
      background: currentColor;
      opacity: 0.5;
    }
    .rail a:hover {
      color: var(--site-ink);
    }
    .rail a.on {
      color: var(--gold);
    }
    .rail a.on::before {
      opacity: 1;
    }
  }
  @media (min-width: 900px) and (prefers-reduced-motion: reduce) {
    .phone img,
    .feature h3,
    .feature p {
      transition: none;
    }
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
  /* 058 C11: every feature, by group, as plain links. */
  .index {
    display: grid;
    gap: 0 clamp(32px, 4vw, 56px);
  }
  @media (min-width: 900px) {
    .index {
      grid-template-columns: repeat(2, minmax(0, 1fr));
    }
  }
  @media (min-width: 1280px) {
    .index {
      grid-template-columns: repeat(3, minmax(0, 1fr));
    }
  }
  .group {
    padding: 22px 0 28px;
    box-shadow: inset 0 1px 0 var(--site-line);
  }
  .group h3 a {
    display: flex;
    align-items: center;
    gap: 12px;
    min-height: 44px;
    font-size: 1.3rem;
    text-decoration: none;
  }
  .group h3 a:hover {
    color: var(--gold);
  }
  .icon {
    display: inline-grid;
    color: var(--site-ink-2);
  }
  .count {
    margin-left: 2px;
    color: var(--site-ink-3);
    font-size: 0.875rem;
    font-weight: 400;
  }
  .gline {
    margin: 2px 0 14px 32px;
    color: var(--site-ink-2);
    line-height: 1.45;
  }
  .group ul {
    display: flex;
    flex-wrap: wrap;
    gap: 2px 4px;
    margin: 0 0 0 22px;
    padding: 0;
    list-style: none;
  }
  .group li a {
    display: inline-flex;
    align-items: center;
    min-height: 44px;
    gap: 8px;
    padding: 0 10px;
    border-radius: var(--radius);
    color: var(--site-ink);
    font-weight: 600;
    text-decoration: none;
    transition: color var(--t-quick) var(--ease), background var(--t-quick) var(--ease);
  }
  .group li a::before {
    content: "";
    width: 4px;
    height: 4px;
    flex: none;
    background: var(--gold);
    opacity: 0.5;
  }
  .group li a:hover::before {
    opacity: 1;
  }
  .group li a:hover {
    color: var(--gold);
    background: rgba(244, 236, 216, 0.05);
  }

  .vh {
    display: none;
  }
  @media (min-width: 900px) {
    .vh {
      display: block;
      position: absolute;
      width: 1px;
      height: 1px;
      overflow: hidden;
      clip-path: inset(50%);
      white-space: nowrap;
    }
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
  dl > div {
    display: grid;
    grid-template-columns: 36px minmax(0, 1fr);
    align-content: start;
    gap: 0 18px;
  }
  dl dt,
  dl dd {
    grid-column: 2;
  }
  .tile {
    grid-row: 1 / span 2;
    display: grid;
    place-items: center;
    width: 36px;
    height: 36px;
    background: var(--obsidian);
    color: var(--site-ink);
    /* The band's stepped corner, one 3 px art pixel deep. */
    clip-path: polygon(0 3px, 3px 3px, 3px 0, calc(100% - 3px) 0, calc(100% - 3px) 3px, 100% 3px, 100% calc(100% - 3px), calc(100% - 3px) calc(100% - 3px), calc(100% - 3px) 100%, 3px 100%, 3px calc(100% - 3px), 0 calc(100% - 3px));
  }
  dt {
    padding-top: 4px;
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
  /* 060 C12: the roadmap band and Questions share one row on a wide screen. */
  .after-dl {
    display: grid;
    gap: clamp(64px, 10vh, 96px) clamp(40px, 5vw, 72px);
  }
  @media (min-width: 900px) {
    .after-dl {
      grid-template-columns: minmax(0, 3fr) minmax(0, 2fr);
      align-items: start;
    }
    /* Questions' heading lines up with the one inside the band. */
    .ask {
      padding-top: clamp(28px, 5vw, 56px);
    }
    .next h2,
    .ask h2 {
      font-size: clamp(2rem, 3.2vw, 2.6rem);
    }
  }
  .ask ul {
    margin: 18px 0 0;
    padding: 0;
    list-style: none;
  }
  .ask li a {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 12px;
    min-height: 52px;
    box-shadow: inset 0 -1px 0 var(--site-line);
    color: var(--site-ink);
    font-size: 1.08rem;
    font-weight: 600;
    text-decoration: none;
    transition: color var(--t-quick) var(--ease);
  }
  .ask li a:hover {
    color: var(--gold);
  }
  .ask li :global(svg) {
    flex: none;
    color: var(--gold);
  }
  .all {
    display: inline-flex;
    align-items: center;
    min-height: 44px;
    margin-top: 10px;
    color: var(--gold);
    font-family: var(--site-display);
    font-weight: 600;
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
      gap: 20px;
      padding-block: 20px;
    }
    .feature .text {
      flex: none;
    }
    dl {
      grid-template-columns: 1fr;
    }
    /* 060 C11: on a phone the directory is the groups; each opens on /features. */
    .gline,
    .group ul {
      display: none;
    }
    .group {
      padding: 6px 0;
    }
  }
</style>
