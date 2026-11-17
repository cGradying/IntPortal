<script lang="ts">
  import { page } from "$app/state";
  import { REPO_URL } from "./releases";
  const release = $derived(page.data.release as { version: string } | null);
</script>

<footer>
  <div class="wrap">
    <p class="un">Unofficial. Not made by or affiliated with any school.</p>
    <p class="fine">
      IntPortal is an independent student project, free under the
      <a href="{REPO_URL}/blob/main/LICENSE" rel="noopener">PolyForm Noncommercial</a> licence.
      <a href={REPO_URL} rel="noopener">Source on GitHub</a> ·
      <a href="{REPO_URL}/issues" rel="noopener">Report a problem</a> ·
      <a href="/privacy">Privacy</a>{#if release} · Version {release.version}{/if}
    </p>
  </div>
</footer>

<style>
  footer {
    margin-top: 96px;
    padding: 40px 0 calc(48px + env(safe-area-inset-bottom));
    box-shadow: inset 0 1px 0 var(--site-line);
  }
  .un {
    font-family: var(--site-display);
    font-weight: 600;
    margin-bottom: 8px;
  }
  .fine {
    max-width: 70ch;
    line-height: 1.7;
  }
</style>
