<script lang="ts">
  import NextStep from "$lib/NextStep.svelte";
  let { data } = $props();
  // 060 C14: PRIVACY.md's title and first paragraph become the shared page head.
  const cut = $derived(data.html.indexOf("</p>") + 4);
  const head = $derived(data.html.slice(0, cut).replace("<p>", '<p class="lede">'));
  const body = $derived(data.html.slice(cut));
</script>

<svelte:head>
  <title>Privacy · IntPortal</title>
  <meta name="description" content="What IntPortal does with your data: it stays on your phone, and your login only goes to your school. No account, no server, no analytics." />
</svelte:head>

<article class="wrap">
  <!-- eslint-disable svelte/no-at-html-tags: our own PRIVACY.md, escaped by markdown() -->
  <header class="page-head">{@html head}</header>
  <div class="prose">{@html body}</div>
  <!-- eslint-enable svelte/no-at-html-tags -->
  <NextStep />
</article>

<style>
  .prose {
    max-width: 72ch;
    line-height: 1.65;
    color: var(--site-ink-2);
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
