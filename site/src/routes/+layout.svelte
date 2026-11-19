<script lang="ts">
  import "$app_lib/app.css";
  import "../site.css";
  import Nav from "$lib/Nav.svelte";
  import Footer from "$lib/Footer.svelte";
  import { afterNavigate, beforeNavigate, onNavigate } from "$app/navigation";
  let { children } = $props();

  // 058 C7: offline, a link loads the whole page, so the service worker can
  // answer it from what it saved; an in-app move would need code it may not have.
  beforeNavigate((nav) => {
    if (navigator.onLine || nav.type !== "link" || !nav.to || nav.to.url.origin !== location.origin) return;
    nav.cancel();
    location.href = nav.to.url.href;
  });
  // An in-app move fetches only code, so ask for the page itself too and the
  // worker saves it. Skipped on Save-Data.
  afterNavigate((nav) => {
    const saveData = (navigator as { connection?: { saveData?: boolean } }).connection?.saveData;
    if (nav.type === "enter" || !nav.to || saveData || !navigator.serviceWorker?.controller) return;
    fetch(nav.to.url.pathname).catch(() => {});
  });

  // 058 C9: cross-fade between pages where the browser can, never under Reduce
  // Motion, and not when it already animated a swipe-back itself.
  onNavigate((nav) => {
    const nv = (window as { navigation?: { hasUAVisualTransition?: boolean } }).navigation;
    if (!document.startViewTransition || nav.from?.url.pathname === nav.to?.url.pathname) return;
    if (nv?.hasUAVisualTransition || matchMedia("(prefers-reduced-motion: reduce)").matches) return;
    return new Promise((resolve) => {
      document.startViewTransition(async () => {
        resolve();
        await nav.complete;
      });
    });
  });
</script>

<a class="skip" href="#main">Skip to content</a>
<Nav />
<main id="main">{@render children()}</main>
<Footer />

<style>
  .skip {
    position: absolute;
    left: 12px;
    top: -60px;
    z-index: 20;
    padding: 10px 14px;
    border-radius: var(--radius);
    background: var(--gold);
    color: #1b1406;
    font-weight: 700;
  }
  .skip:focus {
    top: 12px;
  }
</style>
