<script lang="ts">
  // 051 C13 and 057 C15: the unofficial line, the licence, and every page.
  import { page } from "$app/state";
  import PixelPortal from "./PixelPortal.svelte";
  import { REPO_URL } from "./releases";
  const release = $derived(page.data.release as { version: string } | null);
  const cols = [
    ["The app", [["/features", "Features"], ["/download", "Download"], ["/try", "Try it in your browser"], ["/reel", "The reel"]]],
    ["Help", [["/help", "Help and questions"], ["/help#install", "Installing it"], ["/privacy", "Privacy"], [`${REPO_URL}/issues`, "Report a problem"]]],
    ["Project", [["/roadmap", "Roadmap"], ["/changelog", "What's new"], ["/about", "About"], [REPO_URL, "Source on GitHub"]]],
  ] as const;
</script>

<footer>
  <div class="wrap grid">
    <div class="brand">
      <a class="mark" href="/"><PixelPortal size={3} /><span>IntPortal</span></a>
      <p class="un">Unofficial. Not made by or affiliated with any school.</p>
      <p class="fine">
        An independent student project, free under the
        <a href="{REPO_URL}/blob/main/LICENSE" rel="noopener">PolyForm Noncommercial</a> licence.{#if release}{" "}Version {release.version}.{/if}
      </p>
    </div>
    {#each cols as [title, items] (title)}
      <nav aria-label={title}>
        <p class="label pixel">{title}</p>
        <ul>
          {#each items as [href, text] (href)}
            <li><a {href} rel={href.startsWith("http") ? "noopener" : undefined}>{text}</a></li>
          {/each}
        </ul>
      </nav>
    {/each}
  </div>
</footer>

<style>
  footer {
    margin-top: 120px;
    padding: 56px 0 calc(56px + env(safe-area-inset-bottom));
    box-shadow: inset 0 1px 0 var(--site-line);
  }
  .grid {
    display: grid;
    grid-template-columns: 1.6fr repeat(3, 1fr);
    gap: 40px 32px;
  }
  .mark {
    display: inline-flex;
    align-items: center;
    gap: 10px;
    font-family: var(--site-display);
    font-weight: 800;
    font-size: 1.12rem;
    text-decoration: none;
  }
  .un {
    margin-top: 18px;
    font-family: var(--site-display);
    font-weight: 600;
  }
  .brand .fine {
    margin-top: 8px;
    max-width: 40ch;
    line-height: 1.6;
  }
  .label {
    font-size: 0.82rem;
    color: var(--site-ink-3);
    margin-bottom: 10px;
  }
  ul {
    margin: 0;
    padding: 0;
    list-style: none;
  }
  li a {
    display: inline-flex;
    align-items: center;
    min-height: 44px;
    color: var(--site-ink-2);
    text-decoration: none;
  }
  li a:hover {
    color: var(--site-ink);
    text-decoration: underline;
  }
  @media (max-width: 760px) {
    .grid {
      grid-template-columns: 1fr 1fr;
    }
    .brand {
      grid-column: 1 / -1;
    }
  }
</style>
