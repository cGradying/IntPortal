<script lang="ts">
  // 057 C15: Features, Roadmap, Help, Try it and the gold Get it; on a phone they
  // fold into a sheet that holds focus and closes on Escape.
  import { page } from "$app/state";
  import { tick } from "svelte";
  import PixelIcon from "$app_lib/PixelIcon.svelte";
  import PixelPortal from "./PixelPortal.svelte";
  import Search from "./Search.svelte";
  import { REPO_URL } from "./releases";

  const links = [
    ["/features", "Features"],
    ["/roadmap", "Roadmap"],
    ["/help", "Help"],
    ["/try", "Try it"],
  ] as const;
  const more = [
    ["/changelog", "What's new"],
    ["/reel", "Reel"],
    ["/about", "About"],
  ] as const;

  let scrolled = $state(false);
  let open = $state(false);
  let sheet = $state<HTMLElement>();
  let toggle = $state<HTMLButtonElement>();
  let finder = $state<ReturnType<typeof Search>>();

  const here = (href: string) => page.url.pathname === href || page.url.pathname.startsWith(href + "/");

  async function show(v: boolean) {
    open = v;
    await tick();
    if (v) sheet?.querySelector<HTMLElement>("a")?.focus();
    else toggle?.focus();
  }
  function keys(e: KeyboardEvent) {
    if (!open) return;
    if (e.key === "Escape") return void show(false);
    if (e.key !== "Tab" || !sheet || !toggle) return;
    // The toggle and the sheet's links are the only stops while it is open.
    const f = [toggle, ...sheet.querySelectorAll<HTMLElement>("a")];
    const at = f.indexOf(document.activeElement as HTMLElement);
    e.preventDefault();
    f[(at + (e.shiftKey ? -1 : 1) + f.length) % f.length].focus();
  }
  $effect(() => {
    void page.url.pathname;
    open = false;
  });
</script>

<svelte:window onscroll={() => (scrolled = scrollY > 8)} onkeydown={keys} />

<header class="site" class:scrolled class:open>
  <nav class="wrap" aria-label="Main">
    <a class="mark" href="/" aria-label="IntPortal home"><PixelPortal size={3} /><span>IntPortal</span></a>
    <ul class="wide">
      {#each links as [href, text] (href)}
        <li><a {href} aria-current={here(href) ? "page" : undefined}>{text}</a></li>
      {/each}
      <li><a href={REPO_URL} rel="noopener">GitHub</a></li>
    </ul>
    <div class="end">
      <button class="find" aria-label="Search" aria-keyshortcuts="/ Control+K Meta+K" onclick={() => finder?.open()}><PixelIcon name="search" size={18} /></button>
      <a class="get" href="/download">Get it</a>
      <button class="menu" bind:this={toggle} aria-expanded={open} aria-controls="menu" aria-label={open ? "Close the menu" : "Open the menu"} onclick={() => show(!open)}>
        <PixelIcon name={open ? "close" : "dots"} size={20} />
      </button>
    </div>
  </nav>
  {#if open}
    <div class="sheet" id="menu" bind:this={sheet} role="dialog" aria-modal="true" aria-label="Menu">
      <ul>
        {#each [...links, ["/download", "Download"], ...more] as [href, text] (href)}
          <li><a {href} aria-current={here(href) ? "page" : undefined} onclick={() => (open = false)}>{text}<PixelIcon name="chev" size={12} /></a></li>
        {/each}
        <li><a href={REPO_URL} rel="noopener">GitHub<PixelIcon name="chev" size={12} /></a></li>
      </ul>
    </div>
  {/if}
</header>
<Search bind:this={finder} />

<style>
  header {
    position: sticky;
    top: 0;
    z-index: 10;
    background: color-mix(in srgb, var(--void) 88%, transparent);
    backdrop-filter: blur(14px);
    -webkit-backdrop-filter: blur(14px);
    box-shadow: 0 1px 0 transparent;
    transition: box-shadow var(--t-move) var(--ease);
  }
  header.scrolled,
  header.open {
    box-shadow: 0 1px 0 var(--site-line);
  }
  nav {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 16px;
    min-height: 64px;
  }
  .mark {
    display: inline-flex;
    align-items: center;
    gap: 10px;
    min-height: 44px;
    font-family: var(--site-display);
    font-weight: 800;
    font-size: 1.12rem;
    letter-spacing: -0.02em;
    text-decoration: none;
  }
  ul {
    margin: 0;
    padding: 0;
    list-style: none;
  }
  .wide {
    display: flex;
    gap: 2px;
    margin-left: auto;
  }
  .wide a {
    display: inline-flex;
    align-items: center;
    min-height: 44px;
    padding: 0 12px;
    border-radius: var(--radius);
    color: var(--site-ink-2);
    font-weight: 600;
    text-decoration: none;
    transition: color var(--t-quick) var(--ease), background var(--t-quick) var(--ease);
  }
  .wide a:hover {
    color: var(--site-ink);
    background: rgba(244, 236, 216, 0.06);
  }
  a[aria-current="page"] {
    color: var(--gold) !important;
  }
  .end {
    display: flex;
    align-items: center;
    gap: 6px;
  }
  .get {
    display: inline-flex;
    align-items: center;
    min-height: 44px;
    padding: 0 16px;
    border-radius: var(--radius);
    background: var(--gold);
    color: #1b1406;
    font-family: var(--site-display);
    font-weight: 700;
    text-decoration: none;
    box-shadow: inset 0 -3px 0 #b87a10;
    transition: transform var(--t-quick) var(--ease);
  }
  .get:active {
    transform: translateY(1px);
    box-shadow: inset 0 -1px 0 #b87a10;
  }
  .find {
    display: grid;
    width: 44px;
    height: 44px;
    place-items: center;
    border: 0;
    border-radius: var(--radius);
    background: transparent;
    color: var(--site-ink-2);
    cursor: pointer;
    transition: color var(--t-quick) var(--ease), background var(--t-quick) var(--ease);
  }
  .find:hover {
    color: var(--site-ink);
    background: rgba(244, 236, 216, 0.06);
  }
  .menu {
    display: none;
    width: 44px;
    height: 44px;
    place-items: center;
    border: 0;
    border-radius: var(--radius);
    background: transparent;
    color: var(--site-ink);
    cursor: pointer;
  }
  .menu:hover {
    background: rgba(244, 236, 216, 0.06);
  }
  .sheet {
    display: none;
  }
  @media (max-width: 860px) {
    .wide {
      display: none;
    }
    .menu {
      display: grid;
    }
    .sheet {
      display: block;
      position: absolute;
      left: 0;
      right: 0;
      top: 100%;
      max-height: calc(100svh - 64px);
      overflow-y: auto;
      padding: 8px var(--site-gutter) 24px;
      background: var(--void);
      box-shadow: 0 1px 0 var(--site-line), 0 30px 60px -20px rgba(0, 0, 0, 0.8);
      animation: drop var(--t-move) var(--ease);
    }
    .sheet a {
      display: flex;
      align-items: center;
      justify-content: space-between;
      min-height: 56px;
      color: var(--site-ink);
      font-family: var(--site-display);
      font-weight: 600;
      font-size: 1.2rem;
      text-decoration: none;
      box-shadow: inset 0 -1px 0 var(--site-line);
    }
    .sheet a :global(svg) {
      color: var(--site-ink-3);
    }
  }
  @keyframes drop {
    from {
      opacity: 0;
      transform: translateY(-8px);
    }
  }
  @media (max-width: 380px) {
    .mark span {
      display: none;
    }
  }
</style>
