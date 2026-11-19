<script lang="ts">
  let { data } = $props();
</script>

<svelte:head>
  <title>Privacy · IntPortal</title>
  <meta name="description" content="What IntPortal does with your data: it stays on your phone. No account, no server, no analytics." />
</svelte:head>

<article class="wrap prose">
  <!-- eslint-disable-next-line svelte/no-at-html-tags: our own PRIVACY.md, escaped by markdown() -->
  {@html data.html}
</article>

<style>
  .prose {
    padding-top: clamp(32px, 7vh, 80px);
    max-width: 72ch;
    line-height: 1.65;
    color: var(--site-ink-2);
  }
  .prose :global(h1) {
    font-size: clamp(2.6rem, 7vw, 4rem);
    color: var(--site-ink);
    margin-bottom: 20px;
  }
  .prose :global(h2) {
    font-size: 1.6rem;
    color: var(--site-ink);
    margin: 48px 0 14px;
  }
  .prose :global(p),
  .prose :global(ul) {
    margin: 0 0 14px;
  }
  .prose :global(strong) {
    color: var(--site-ink);
  }
  .prose :global(code) {
    font-size: 0.9em;
    color: var(--site-ink);
  }
  .prose :global(a) {
    overflow-wrap: anywhere;
  }
  .prose :global(.table) {
    overflow-x: auto;
    margin: 20px 0;
  }
  .prose :global(table) {
    border-collapse: collapse;
    min-width: 560px;
  }
  .prose :global(th),
  .prose :global(td) {
    text-align: left;
    vertical-align: top;
    padding: 10px 14px 10px 0;
    box-shadow: inset 0 -1px 0 var(--site-line);
  }
  .prose :global(th) {
    color: var(--site-ink);
  }
</style>
