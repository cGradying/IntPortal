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

<div class="list">
  <div class="row try" class:mine={first === "try"}>
    <div class="what">
      <h3>Any browser</h3>
      <p class="needs">No install. The whole app on sample data, gone when you leave.</p>
    </div>
    <a class={first === "try" ? "gold" : "ghost"} href="/try">Try it in your browser</a>
  </div>
  {#each rows as p (p.id)}
    <div class="row" class:mine={p.id === first}>
      <div class="what">
        <h3>{p.name}</h3>
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
      </div>
      <div class="get">
        {#each p.files as f (f.file)}
          <a class={p.id === first ? "gold" : "ghost"} href={f.url} rel="noopener">{p.files.length > 1 ? (f.file.endsWith(".deb") ? ".deb" : "AppImage") : p.button}</a>
        {/each}
        {#if p.id === "android" && android && (here === "mac" || here === "windows" || here === "linux")}
          <span class="qr"><Qr text={android.url} label="Scan with your Android phone to download" /></span>
        {/if}
      </div>
    </div>
  {/each}
</div>
<p class="fine all">Every file and its checksum is on the <a href={RELEASES_URL} rel="noopener">releases page</a>. The APK is signed with the same key since the first beta, so updates install over the old version.</p>

<style>
  .list {
    display: grid;
    gap: 0;
    position: relative;
  }
  .row {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 16px 24px;
    padding: 20px 4px;
    box-shadow: inset 0 -1px 0 var(--site-line);
  }
  .row.mine {
    order: -1;
  }
  .try.mine {
    order: -2;
  }
  h3 {
    font-size: 1.25rem;
    margin-bottom: 4px;
  }
  .needs {
    color: var(--site-ink-2);
  }
  .meta {
    margin-top: 4px;
    font-size: 0.88rem;
    color: var(--site-ink-3);
    font-variant-numeric: tabular-nums;
  }
  .get {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    gap: 8px 16px;
    flex: none;
  }
  .all {
    margin-top: 20px;
    max-width: 70ch;
  }
  @media (max-width: 640px) {
    .row {
      flex-direction: column;
      align-items: stretch;
    }
    .get a {
      flex: 1;
    }
  }
  /* A narrow window gets the button alone; the QR is for a computer beside a phone. */
  @media (max-width: 640px) {
    .qr {
      display: none;
    }
  }
</style>
