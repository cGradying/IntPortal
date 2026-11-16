<script lang="ts">
  import { page } from "$app/state";
  import PixelPortal from "./PixelPortal.svelte";
  import { REPO_URL } from "./releases";
  const links = [
    ["/#features", "Features"],
    ["/download", "Download"],
    ["/reel", "Reel"],
    ["/try", "Try it"],
  ] as const;
  let scrolled = $state(false);
</script>

<svelte:window onscroll={() => (scrolled = scrollY > 8)} />

<header class:scrolled>
  <nav class="wrap" aria-label="Main">
    <a class="mark" href="/" aria-label="IntPortal home"><PixelPortal size={3} /><span>IntPortal</span></a>
    <ul>
      {#each links as [href, text] (href)}
        <li><a {href} aria-current={page.url.pathname === href ? "page" : undefined}>{text}</a></li>
      {/each}
      <li class="gh"><a href={REPO_URL} rel="noopener">GitHub</a></li>
    </ul>
  </nav>
</header>

<style>
  header {
    position: sticky;
    top: 0;
    z-index: 10;
    background: var(--void);
    box-shadow: 0 1px 0 transparent;
    transition: box-shadow var(--t-move) var(--ease);
  }
  header.scrolled {
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
    display: flex;
    gap: 4px;
    margin: 0;
    padding: 0;
    list-style: none;
  }
  ul a {
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
  ul a:hover {
    color: var(--site-ink);
    background: rgba(244, 236, 216, 0.06);
  }
  ul a[aria-current="page"] {
    color: var(--gold);
  }
  @media (max-width: 640px) {
    .gh,
    ul li:first-child {
      display: none;
    }
    ul a {
      padding: 0 9px;
    }
  }
  @media (max-width: 380px) {
    .mark span {
      display: none;
    }
  }
</style>
