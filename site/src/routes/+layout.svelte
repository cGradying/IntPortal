<script lang="ts">
  import "$app_lib/app.css";
  import "../site.css";
  import Nav from "$lib/Nav.svelte";
  import Footer from "$lib/Footer.svelte";
  let { children } = $props();
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
