<script lang="ts">
  // Every platform with its file, size, version and requirement (051 C9),
  // the visitor's own first (C8).
  import { onMount } from "svelte";
  import { device, type Device } from "./device";
  import { firstFor, PLATFORMS } from "./platforms";
  import Qr from "./Qr.svelte";
  import { fetchRelease, megabytes, RELEASES_URL, type Release } from "./releases";

  let { release: initial }: { release: Release | null } = $props();
  let fresh = $state<Release | null>(null);
  const release = $derived(fresh ?? initial);
  let here = $state<Device>("other");

  onMount(async () => {
    here = device(navigator.userAgent, navigator.maxTouchPoints);
    fresh = await fetchRelease();
  });

  const first = $derived(firstFor(here));
  const rows = $derived(
    [...PLATFORMS]
      .sort((a, b) => Number(b.id === first) - Number(a.id === first))
      .map((p) => ({ ...p, files: release?.assets.filter((a) => a.platform === p.id) ?? [] })),
  );
  const android = $derived(release?.assets.find((a) => a.platform === "android"));
</script>

<div class="grid">
  {#each rows as p (p.id)}
    <article class="card" class:mine={p.id === first} aria-labelledby="dl-{p.id}">
      <div class="what">
        {#if p.id === first}<p class="yours pixel">For this device</p>{/if}
        <h3 id="dl-{p.id}">{p.name}</h3>
        <p class="needs">{p.needs}</p>
        {#if p.links}
          <p class="meta">Set up with {#each p.links as l, i (l.href)}{#if i}{" or "}{/if}<a href={l.href} rel="noopener">{l.name}</a>{/each}.</p>
        {/if}
        {#if p.files.length}
          <p class="meta">
            {#each p.files as f, i (f.file)}{#if i}<span aria-hidden="true">{" · "}</span>{/if}{f.file.replace(/-[\d.]+(?=[-.])/, "")}, {megabytes(f.size)}{/each}
            <span aria-hidden="true">{" · "}</span>{release?.prerelease ? "pre-release" : "version"} {release?.version}
          </p>
        {:else}
          <p class="meta">{p.later ?? "Not in this release yet."} <a href={RELEASES_URL} rel="noopener">All releases</a></p>
        {/if}
        {#if p.id === "android" && android && (here === "mac" || here === "windows" || here === "linux")}
          <span class="qr"><Qr text={android.url} label="Scan with your Android phone to download" /></span>
        {/if}
      </div>
      <div class="get">
        {#each p.files as f (f.file)}
          <a class={p.id === first ? "gold" : "ghost"} href={f.url} rel="noopener">{p.files.length > 1 ? (f.file.endsWith(".deb") ? ".deb" : "AppImage") : p.id === first ? p.button : `Download .${f.file.split(".").pop()}`}</a>
        {/each}
      </div>
    </article>
  {/each}
</div>
<p class="fine all">Every file and its checksum is on the <a href={RELEASES_URL} rel="noopener">releases page</a>. The APK is signed with the same key since the first beta, so updates install over the old version.</p>

<style>
  /* Your own device leads as one wide card; the rest sit side by side, their
     buttons lined up along the bottom. */
  .grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(min(100%, 236px), 1fr));
    gap: 12px;
  }
  .card {
    position: relative;
    display: grid;
    grid-template-rows: 1fr auto;
    gap: 20px;
    padding: 22px;
    border-radius: var(--radius);
    background: rgba(244, 236, 216, 0.03);
    box-shadow: inset 0 0 0 1px var(--site-line);
  }
  .card.mine {
    order: -1;
    grid-column: 1 / -1;
    grid-template-columns: 1fr auto;
    grid-template-rows: auto;
    align-items: center;
    gap: 16px 32px;
    padding: clamp(24px, 4vw, 40px);
    background: linear-gradient(120deg, rgba(245, 178, 39, 0.1), rgba(245, 178, 39, 0.02) 60%);
    box-shadow: inset 0 0 0 1px rgba(245, 178, 39, 0.35);
  }
  .yours {
    margin-bottom: 8px;
    font-size: 0.72rem;
    letter-spacing: 0.08em;
    text-transform: uppercase;
    color: var(--gold);
  }
  h3 {
    font-size: 1.2rem;
    margin-bottom: 6px;
  }
  .mine h3 {
    font-size: clamp(1.6rem, 3vw, 2.2rem);
  }
  .needs {
    color: var(--site-ink-2);
  }
  .meta {
    margin-top: 6px;
    font-size: 0.88rem;
    color: var(--site-ink-3);
    font-variant-numeric: tabular-nums;
  }
  .get {
    display: flex;
    flex-wrap: wrap;
    gap: 8px;
    align-self: end;
  }
  .card:not(.mine) .get a {
    flex: 1 1 auto;
  }
  .mine .get {
    align-self: center;
  }
  /* Under the text, so every card's button still lines up along the bottom. */
  .qr {
    display: block;
    margin-top: 14px;
  }
  .qr :global(figure) {
    grid-template-columns: 88px auto;
    align-items: center;
    justify-items: start;
  }
  .qr :global(svg) {
    width: 88px;
    height: 88px;
  }
  .qr :global(figcaption) {
    text-align: left;
  }
  .all {
    margin-top: 20px;
    max-width: 70ch;
  }
  @media (max-width: 640px) {
    .card.mine {
      grid-template-columns: 1fr;
    }
    .get a {
      flex: 1 1 auto;
    }
    /* A phone gets the button alone; the QR is for a computer beside a phone. */
    .qr {
      display: none;
    }
  }
</style>
