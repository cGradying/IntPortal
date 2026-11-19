<script lang="ts">
  // Spec 058 C6: share an address on this site. The phone's share sheet where
  // there is one, else copy it; the link itself still works if both fail.
  import PixelIcon from "$app_lib/PixelIcon.svelte";
  let { href, title }: { href: string; title: string } = $props();
  let said = $state("");
  let timer: ReturnType<typeof setTimeout>;

  async function share(e: MouseEvent) {
    const url = new URL(href, location.href).href;
    e.preventDefault();
    if (navigator.share) {
      try {
        await navigator.share({ title, url });
      } catch {
        /* cancelled */
      }
      return;
    }
    try {
      await navigator.clipboard.writeText(url);
      said = "Link copied";
      clearTimeout(timer);
      timer = setTimeout(() => (said = ""), 2000);
    } catch {
      (e.currentTarget as HTMLElement | null)?.focus();
    }
  }
</script>

<a class="share" {href} onclick={share} aria-label="Share: {title}"><PixelIcon name="share" size={14} /><span>{said || "Share"}</span></a>
<span class="sr" aria-live="polite">{said}</span>

<style>
  .share {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    min-height: 44px;
    padding: 0 10px;
    margin-left: -10px;
    border-radius: var(--radius);
    color: var(--site-ink-3);
    font-size: 0.9rem;
    font-weight: 600;
    text-decoration: none;
    transition: color var(--t-quick) var(--ease), background var(--t-quick) var(--ease);
  }
  .share:hover {
    color: var(--gold);
    background: rgba(244, 236, 216, 0.05);
  }
  .sr {
    position: absolute;
    width: 1px;
    height: 1px;
    overflow: hidden;
    clip-path: inset(50%);
  }
</style>
