<script lang="ts">
  // Make a theme (spec 047 C12–C19): a live preview on top with Today, Study
  // and Dive tabs, every control in the bottom half under the thumb, and the
  // section tabs at the very bottom. The page wears the theme being made, so
  // the controls and the share card show it too; the app only wears it once
  // it is saved. The look and behaviour are the picked `theme` row of the
  // round-two picks page (study-you.html#theme).
  import qrcode from "qrcode-generator";
  import { closable } from "./back";
  import { buzz } from "./haptics";
  import { contrast } from "./rooms";
  import { app, deleteTheme, saveTheme, setRoom } from "./state.svelte";
  import { NIGHT, PATTERNS, PRESETS, hsl, hueOf, isDark, larLook, look, patternCss, roles, roll, seed, type Theme } from "./theme";
  import { decodeTheme, encodeTheme, scanQr } from "./themeCode";
  import { cameraProblem } from "./camera";
  import Lar from "./lar/Lar.svelte";
  import { SIS, THEMES } from "./lar/sprite";
  import PixelIcon from "./PixelIcon.svelte";
  import PixelNum from "./PixelNum.svelte";

  const close = () => (app.themeMaker = false);
  $effect(() => closable(close));
  const reduce = typeof matchMedia === "function" && matchMedia("(prefers-reduced-motion: reduce)").matches;

  // Start from the theme the app wears, or from Night.
  const worn = app.themes.find((s) => `theme:${s.id}` === app.room);
  const first: Theme = worn ? { ...worn.theme } : { ...NIGHT, name: "My theme" };
  let t = $state<Theme>(first);
  /** The saved theme being edited; Save replaces it. */
  let editing = $state<string | null>(worn?.id ?? null);
  let hue = $state(Math.round(hueOf(first.accent)));
  let shade = $state(isDark(first) ? 14 : 80);
  let sec = $state<"Colour" | "Ground" | "Shape" | "LAR" | "Share">("Colour");
  let pv = $state<"Today" | "Study" | "Dive">("Today");
  let tune = $state(false);
  let sheet = $state<null | "share" | "add">(null);
  /** A dice roll's in-between faces. */
  let flash = $state<Theme | null>(null);
  let rolls = $state(0);
  let happy = $state(false);
  let stamp = $state(false);
  let confirmDelete = $state(false);

  const view = $derived(flash ?? t);
  const vars = $derived(look(view));
  const css = $derived(Object.entries(vars).map(([k, v]) => `${k}:${v}`).join(";"));
  const lar = $derived(view.lar != null ? larLook(view.lar) : app.mabiniConnected && !app.sisConnected ? THEMES.mabini : SIS);
  const onColour = (c: string) => (contrast("#ffffff", c) >= contrast("#111111", c) ? "#ffffff" : "#111111");
  const hues = "linear-gradient(90deg," + [0, 60, 120, 180, 240, 300, 360].map((h) => hsl(h, 0.8, 0.55)).join(",") + ")";
  const shades = $derived(`linear-gradient(90deg,${hsl(hue, 0.42, 0.04)},${hsl(hue, 0.34, 0.25)} 49%,${hsl(hue, 0.22, 0.78)} 51%,${hsl(hue, 0.3, 0.97)})`);

  function adopt(n: Theme) {
    t = { ...n };
    hue = Math.round(hueOf(n.accent));
    shade = isDark(n) ? 14 : 80;
  }

  /** The accent and night-to-day sliders re-seed the colours and keep every other choice. */
  function reseed() {
    const { hue2, lar, pattern, aura, corners, cards, titles } = t;
    t = seed(hue, shade, t.name, { hue2, lar, pattern, aura, corners, cards, titles });
  }

  function cheer() {
    happy = true;
    setTimeout(() => (happy = false), 1600);
  }

  function rollDice() {
    rolls++;
    buzz.select();
    const finish = () => {
      const f = roll();
      flash = null;
      adopt(f.t);
      hue = f.hue;
      shade = f.shade;
      editing = null;
      buzz.tick();
      cheer();
    };
    if (reduce) return finish();
    let i = 0;
    const id = setInterval(() => {
      flash = roll().t;
      if (++i >= 6) {
        clearInterval(id);
        finish();
      }
    }, 70);
  }

  type Choice = "pattern" | "aura" | "corners" | "cards" | "titles";
  function pick(k: Choice, v: string) {
    t[k] = v as never;
    buzz.select();
  }

  function showStamp() {
    stamp = true;
    setTimeout(() => (stamp = false), 1000);
  }

  /** Save keeps the theme beside the rooms and puts it on the whole app. */
  function save() {
    if (!t.name.trim()) t.name = "My theme";
    editing = saveTheme($state.snapshot(t), editing ?? undefined);
    setRoom(`theme:${editing}`);
    buzz.done();
    showStamp();
    cheer();
  }

  function remove() {
    if (editing) deleteTheme(editing);
    editing = null;
    confirmDelete = false;
    buzz.tick();
  }

  // Sharing: the code, its QR, and copying.
  const code = $derived(encodeTheme(t));
  const qr = $derived.by(() => {
    const q = qrcode(0, "M");
    q.addData(code);
    q.make();
    const n = q.getModuleCount();
    let d = "";
    for (let y = 0; y < n; y++) for (let x = 0; x < n; x++) if (q.isDark(y, x)) d += `M${x} ${y}h1v1h-1z`;
    return { n, d };
  });
  let copied = $state("Copy code");
  async function copy() {
    try {
      await navigator.clipboard.writeText(code);
      copied = "Copied";
      buzz.tick();
    } catch {
      copied = "Hold the code to copy it";
    }
  }

  // Adding a classmate's theme (C18): paste a code, see it, then Keep or Not now.
  let pasted = $state("");
  let addMsg = $state("");
  let before: Theme | null = null;
  let incoming = $state<Theme | null>(null);
  function openAdd() {
    sheet = "add";
    pasted = "";
    addMsg = "";
    incoming = null;
  }
  function tryCode(text: string) {
    const got = decodeTheme(text);
    if (!got) {
      addMsg = "That code doesn't look right, so nothing changed. Ask for it again.";
      buzz.fail();
      return;
    }
    before = $state.snapshot(t);
    incoming = got;
    adopt(got);
    buzz.select();
  }
  async function scan() {
    try {
      const text = await scanQr();
      if (text) tryCode(text);
      else if (text === "") addMsg = "No code in that photo. Fill the frame with the QR and try again, or paste the code.";
    } catch (e) {
      const why = cameraProblem(e);
      addMsg =
        why === "camera_denied"
          ? "The camera is off for IntPortal. Turn it on in the phone's Settings, or paste the code."
          : why === "no_camera"
            ? "This phone has no camera. Paste the code instead."
            : "Couldn't read that photo. Try again, or paste the code.";
    }
  }
  function notNow() {
    if (before) adopt(before);
    incoming = null;
    sheet = null;
  }
  function keep() {
    incoming = null;
    sheet = null;
    editing = null;
    save();
  }

  // The Dive tab: the tunnel in this theme's accent and pool colours, one pixel per tile.
  let cv = $state<HTMLCanvasElement>();
  $effect(() => {
    if (pv !== "Dive" || !cv) return;
    const h = hueOf(view.accent);
    const h2 = view.hue2 ?? h;
    const ramp = [0.06, 0.16, 0.32, 0.5, 0.72, 0.9].map((l, i) => hsl(i < 3 ? h2 : h, 0.75, l));
    const g = cv.getContext("2d");
    if (!g) return;
    const W = 40;
    const H = 33;
    const BAY = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5].map((v) => (v + 0.5) / 16);
    let raf = 0;
    const frame = (ts: number) => {
      const s = reduce ? 3 : ts / 1000;
      const form = Math.floor(s / 1.6) % 3;
      const k = (s / 1.6) % 1;
      for (let y = 0; y < H; y++)
        for (let x = 0; x < W; x++) {
          const dx = (x - W / 2) / H;
          const dy = (y - H / 2) / H;
          const rr = Math.hypot(dx, dy) + 0.04;
          const a = Math.atan2(dy, dx);
          const z = 0.6 / rr;
          const F = [Math.cos(a * 5 + z * 6 - s * 2), Math.cos(z * 10 - s * 3), Math.cos(a * 4) * Math.cos(z * 8 - s * 2.4)];
          const v = (F[form] * (1 - k) + F[(form + 1) % 3] * k) * 0.5 + 0.5 - rr * 0.35 + 0.12;
          g.fillStyle = ramp[Math.max(0, Math.min(5, Math.floor(v * 5 + BAY[(y & 3) * 4 + (x & 3)])))];
          g.fillRect(x, y, 1, 1);
        }
      if (!reduce) raf = requestAnimationFrame(frame);
    };
    raf = requestAnimationFrame(frame);
    return () => cancelAnimationFrame(raf);
  });

  const SECTIONS = ["Colour", "Ground", "Shape", "LAR", "Share"] as const;
  const PREVIEWS = ["Today", "Study", "Dive"] as const;
  const TUNE = [["accent", "Accent"], ["ground", "Ground"], ["card", "Cards"], ["ink", "Text"]] as const;
  const SPINES = [[1, "COMP", 4], [2, "MATH", 2], [3, "GEED", 5], [4, "IT", 1], [5, "NSTP", 3]] as const;
</script>

{#snippet seg(k: Choice, opts: readonly (readonly [string, string])[], label: string)}
  <div class="field">
    <p class="label">{label}</p>
    <div class="seg" role="group" aria-label={label}>
      {#each opts as [v, n] (v)}<button aria-pressed={t[k] === v} onclick={() => pick(k, v)}>{n}</button>{/each}
    </div>
  </div>
{/snippet}

<div class="tm" role="dialog" aria-label="Make a theme" style={css} data-corners={view.corners} data-cards={view.cards}>
  <div class="prev" class:still={view.aura === "off"}>
    {#if pv === "Dive"}<canvas class="dive" bind:this={cv} width="40" height="33" aria-label="The dive in this theme"></canvas>{/if}
    <div class="top">
      <button class="back" onclick={close}>Back</button>
      <div class="pvtabs" role="group" aria-label="Preview">
        {#each PREVIEWS as n (n)}<button aria-pressed={pv === n} onclick={() => ((pv = n), buzz.select())}>{n}</button>{/each}
      </div>
    </div>
    {#if pv === "Today"}
      <div class="card notch hero"><b>COMP 20083</b><span class="t"><PixelNum text="10:30" size={3} /></span><span>In 25 min</span></div>
      <div class="card notch list">
        <div class="r"><i class="chk"></i><em>Tonight</em><span class="x">Lab 4: Interfaces</span></div>
        <div class="r"><i class="chk on"></i><em>Done</em><span class="x done">Reading 6</span></div>
      </div>
      <span class="primary sample">Primary</span>
      <div class="lar"><Lar size={3} theme={lar} state={happy ? "happy" : "idle"} label="LAR in this theme" /></div>
    {:else if pv === "Study"}
      <div class="minis">
        {#each SPINES as [s, n, k] (n)}
          {@const c = vars[`--s${s}`]}
          <span class="spine notch" style:background={c} style:color={onColour(c)} style:height="{64 + k * 5}px"><b>{n}</b><span class="pips">{#each { length: k }, i (i)}<u></u>{/each}</span></span>
        {/each}
      </div>
      <div class="card notch note"><b>Inheritance vs composition</b><p>Today · Prefer composition…</p></div>
    {/if}
    <button class="dice" onclick={rollDice} aria-label="Surprise me: roll a theme">{#key rolls}<span class:spin={rolls > 0}><PixelIcon name="dice" size={24} /></span>{/key}</button>
  </div>

  <div class="ctrls">
    {#if sec === "Colour"}
      <div class="presets">
        {#each PRESETS as p (p.name)}
          <button onclick={() => (adopt(p), (editing = null), buzz.select())}><i style:background={roles(p)["--gold"]}></i>{p.name}</button>
        {/each}
        {#each app.themes as s (s.id)}
          <button class="mine" aria-pressed={editing === s.id} onclick={() => (adopt(s.theme), (editing = s.id), buzz.select())}><i style:background={roles(s.theme)["--gold"]}></i>{s.theme.name}</button>
        {/each}
      </div>
      <div class="field">
        <p class="label">Accent</p>
        <input type="range" min="0" max="359" value={hue} style:--trk={hues} aria-label="Accent colour" oninput={(e) => ((hue = +e.currentTarget.value), reseed())} />
      </div>
      <div class="field">
        <p class="label">Night to day</p>
        <input type="range" min="0" max="100" value={shade} style:--trk={shades} aria-label="Night to day" oninput={(e) => ((shade = +e.currentTarget.value), reseed())} />
      </div>
      <button class="ghost sm" onclick={() => (tune = !tune)}>{tune ? "Hide fine tuning" : "Fine tune each colour"}</button>
      {#if tune}
        <div class="tune">
          {#each TUNE as [k, n] (k)}<label>{n}<input type="color" value={t[k]} oninput={(e) => (t[k] = e.currentTarget.value)} /></label>{/each}
        </div>
        <p class="fine">Whatever you pick, text stays readable: it is pushed until it reads on the cards.</p>
      {/if}
    {:else if sec === "Ground"}
      <div class="field">
        <p class="label">Pattern</p>
        <div class="patterns">
          {#each PATTERNS as p (p)}
            {@const g = patternCss(p, vars["--ink-2"])}
            <button aria-pressed={t.pattern === p} aria-label={p} onclick={() => pick("pattern", p)} style:background-image={g.image} style:background-size={g.size}>{p === "none" ? "None" : ""}</button>
          {/each}
        </div>
      </div>
      <div class="field">
        <p class="label">Pool colour</p>
        <input type="range" min="0" max="359" value={t.hue2 ?? hue} style:--trk={hues} aria-label="Pool colour" oninput={(e) => (t.hue2 = +e.currentTarget.value)} />
      </div>
      {@render seg("aura", [["full", "Full"], ["soft", "Soft"], ["off", "Still"]], "Moving pools")}
    {:else if sec === "Shape"}
      {@render seg("corners", [["step", "Stepped"], ["deep", "Deep"], ["round", "Round"], ["sharp", "Sharp"]], "Corners")}
      {@render seg("cards", [["fill", "Filled"], ["outline", "Outline"], ["tint", "Tinted"]], "Cards")}
      {@render seg("titles", [["phone", "Phone"], ["classic", "Classic"], ["pixel", "Pixel"]], "Titles")}
      <p class="fine">Pixel titles look great and read slower. Times, rooms and due dates stay in reading type whatever you pick.</p>
    {:else if sec === "LAR"}
      <div class="field">
        <p class="label">LAR's colour</p>
        <input type="range" min="0" max="359" value={t.lar ?? 40} style:--trk={hues} aria-label="LAR's colour" oninput={(e) => (t.lar = +e.currentTarget.value)} />
      </div>
      <button class="ghost sm" onclick={() => ((t.lar = null), cheer())}>Back to your school's colours</button>
      <p class="fine">It changes his glow, studs, cube and belly swirl. He's still obsidian underneath, and his eyes stay gold. The Dive tab shows your tunnel, built from your accent and pool colours.</p>
    {:else}
      <div class="field">
        <p class="label">Name</p>
        <input class="nm" bind:value={t.name} maxlength="24" aria-label="Theme name" />
      </div>
      <button class="primary big" onclick={() => ((sheet = "share"), (copied = "Copy code"))}><PixelIcon name="share" size={16} accent="currentColor" />Share as a card and QR</button>
      <div class="two">
        <button class="ghost big" onclick={save}>Save</button>
        <button class="ghost big" onclick={openAdd}>Add a code</button>
      </div>
      {#if editing}
        {#if confirmDelete}
          <p class="fine">Delete “{t.name}”? If you're wearing it, the app goes back to Night.</p>
          <div class="two">
            <button class="ghost" onclick={() => (confirmDelete = false)}>Keep it</button>
            <button class="danger" onclick={remove}>Delete</button>
          </div>
        {:else}
          <button class="ghost sm" onclick={() => (confirmDelete = true)}>Delete this theme</button>
        {/if}
      {/if}
      <p class="fine">Save puts it on the whole app and beside the rooms in You. Rename it here and save again.</p>
    {/if}
  </div>

  <div class="sections" role="group" aria-label="Sections">
    {#each SECTIONS as n (n)}<button aria-pressed={sec === n} onclick={() => ((sec = n), buzz.select())}>{n}</button>{/each}
  </div>

  {#if sheet}
    <button class="scrim" aria-label="Close" onclick={() => (incoming ? notNow() : (sheet = null))}></button>
    {#if sheet === "share"}
      <div class="sheet notch" role="dialog" aria-label="Share this theme">
        <div class="tcard notch">
          <h5>{t.name || "My theme"}</h5>
          <div class="qrbox">
            <svg role="img" aria-label="QR code of this theme" viewBox="-4 -4 {qr.n + 8} {qr.n + 8}" width={(qr.n + 8) * 4} height={(qr.n + 8) * 4} shape-rendering="crispEdges"><rect x="-4" y="-4" width={qr.n + 8} height={qr.n + 8} fill="#ffffff" /><path d={qr.d} fill="#120a06" /></svg>
          </div>
        </div>
        <p class="fine center">Your classmate adds it in Make a theme, under Share: Add a code.</p>
        <div class="code">{code}</div>
        <div class="two">
          <button class="ghost" onclick={() => (sheet = null)}>Close</button>
          <button class="primary" onclick={copy}>{copied}</button>
        </div>
      </div>
    {:else}
      <div class="sheet notch" role="dialog" aria-label="Add a theme">
        {#if incoming}
          <h4>{incoming.name}</h4>
          <p class="fine">This is how it looks. A code holds only colours, choices and a name.</p>
          <div class="two">
            <button class="ghost" onclick={notNow}>Not now</button>
            <button class="primary" onclick={keep}>Keep</button>
          </div>
        {:else}
          <h4>Add a classmate's theme</h4>
          <textarea bind:value={pasted} aria-label="Theme code" spellcheck="false" placeholder="IPT1.…"></textarea>
          <p class="fine" role="status">{addMsg}</p>
          <div class="two">
            <button class="ghost" onclick={() => (sheet = null)}>Close</button>
            <button class="primary" onclick={() => tryCode(pasted)}>Add</button>
          </div>
          <button class="ghost" onclick={scan}>Take a photo of a QR</button>
        {/if}
      </div>
    {/if}
  {/if}

  {#if stamp}<div class="bigstamp" aria-hidden="true">SAVED</div>{/if}
  <p class="sr" role="status">{stamp ? "Saved" : ""}</p>
</div>

<style>
  .tm {
    position: fixed;
    inset: 0;
    z-index: 60;
    display: flex;
    flex-direction: column;
    background: var(--ground);
    color: var(--ink);
  }
  /* The preview: the theme's ground, its pools, and a slice of each screen. */
  .prev {
    flex: none;
    height: calc(var(--safe-top) + min(300px, 40vh));
    position: relative;
    overflow: hidden;
    isolation: isolate;
    padding: calc(var(--safe-top) + 8px) 12px 8px;
    display: grid;
    gap: 7px;
    align-content: start;
    background-color: var(--ground);
    background-image: var(--pattern, radial-gradient(var(--dot) 1px, transparent 1.2px));
    background-size: var(--pattern-size, 14px 14px);
    box-shadow: 0 1px 0 var(--edge-2);
  }
  .prev::before,
  .prev::after {
    content: "";
    position: absolute;
    inset: -45%;
    z-index: -1;
    pointer-events: none;
    opacity: var(--aura-o, 1);
    will-change: transform;
  }
  .prev::before {
    background: radial-gradient(32% 24% at 32% 30%, var(--aura-a), transparent 72%), radial-gradient(30% 22% at 70% 68%, var(--aura-b), transparent 72%);
    animation: aura1 13s ease-in-out infinite alternate;
  }
  .prev::after {
    background: radial-gradient(26% 24% at 66% 28%, var(--aura-c), transparent 72%), radial-gradient(30% 20% at 26% 72%, var(--aura-b), transparent 72%);
    animation: aura2 17s ease-in-out infinite alternate;
  }
  .prev.still::before,
  .prev.still::after {
    animation: none;
  }
  .top {
    position: relative;
    z-index: 2;
    display: flex;
    align-items: center;
    gap: 6px;
  }
  .back {
    min-height: 40px;
    padding: 0 12px;
    border: 0;
    border-radius: 10px;
    background: color-mix(in srgb, var(--card) 85%, transparent);
    box-shadow: inset 0 0 0 1px var(--edge);
    font-family: var(--font-display);
    font-weight: 700;
    font-size: min(0.824rem, 25px);
    color: var(--ink);
  }
  .pvtabs {
    flex: 1;
    display: flex;
    gap: 4px;
    justify-content: center;
    margin-right: 60px;
  }
  .pvtabs button,
  .sections button,
  .seg button,
  .presets button {
    -webkit-tap-highlight-color: transparent;
  }
  .pvtabs button {
    min-height: 40px;
    padding: 0 10px;
    border: 0;
    background: color-mix(in srgb, var(--card) 80%, transparent);
    box-shadow: inset 0 0 0 1px var(--edge);
    font: 500 min(0.706rem, 20px) var(--font-label);
    letter-spacing: var(--label-track);
    color: var(--ink-2);
    clip-path: polygon(0 3px, 3px 3px, 3px 0, calc(100% - 3px) 0, calc(100% - 3px) 3px, 100% 3px, 100% calc(100% - 3px), calc(100% - 3px) calc(100% - 3px), calc(100% - 3px) 100%, 3px 100%, 3px calc(100% - 3px), 0 calc(100% - 3px));
  }
  .pvtabs button[aria-pressed="true"] {
    background: var(--gold);
    color: var(--on-gold);
  }
  .card {
    position: relative;
    z-index: 1;
  }
  .hero {
    padding: 9px 12px;
    display: grid;
    grid-template-columns: 1fr auto;
    gap: 2px 8px;
    align-items: end;
  }
  .hero b {
    font: var(--title-weight) min(0.941rem, 21px) / 1.1 var(--font-display);
    letter-spacing: var(--title-track);
    color: var(--gold);
  }
  .hero span {
    font-size: min(0.765rem, 20px);
    color: var(--ink-2);
  }
  .hero .t {
    grid-row: 1 / 3;
    grid-column: 2;
    color: var(--ink);
  }
  .list {
    padding: 8px 12px;
    display: grid;
    gap: 6px;
  }
  .r {
    display: flex;
    align-items: center;
    gap: 8px;
    font-size: min(0.765rem, 20px);
  }
  .r em {
    font-style: normal;
    font-weight: 700;
    color: var(--gold);
    width: 50px;
    flex: none;
  }
  .r .x {
    flex: 1;
    min-width: 0;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .r .done {
    color: var(--ink-3);
    text-decoration: line-through;
  }
  .chk {
    width: 14px;
    height: 14px;
    flex: none;
    background: var(--sunk);
    box-shadow: inset 0 0 0 2px var(--ink-3);
  }
  .chk.on {
    background: var(--gold);
    box-shadow: none;
  }
  .sample {
    position: relative;
    z-index: 1;
    width: 130px;
    display: grid;
    place-items: center;
    min-height: 36px;
  }
  .lar {
    position: absolute;
    right: 64px;
    bottom: -10px;
    z-index: 3;
    pointer-events: none;
  }
  .minis {
    position: relative;
    z-index: 1;
    display: flex;
    gap: 4px;
    align-items: flex-end;
    height: 92px;
  }
  .spine {
    width: 48px;
    padding: 5px 4px;
    display: grid;
    align-content: space-between;
    justify-items: center;
  }
  .spine b {
    font-size: 12px;
  }
  .pips {
    display: flex;
    flex-wrap: wrap;
    gap: 2px;
    justify-content: center;
  }
  .pips u {
    width: 5px;
    height: 5px;
    background: currentColor;
  }
  .note {
    padding: 7px 12px;
  }
  .note b {
    font: var(--title-weight) min(0.824rem, 21px) / 1.2 var(--font-display);
    letter-spacing: var(--title-track);
  }
  .note p {
    margin: 0;
    font-size: min(0.706rem, 20px);
    color: var(--ink-2);
  }
  canvas.dive {
    position: absolute;
    inset: 0;
    width: 100%;
    height: 100%;
    z-index: 0;
    image-rendering: pixelated;
  }
  .dice {
    position: absolute;
    right: 10px;
    bottom: 10px;
    z-index: 4;
    width: 48px;
    height: 48px;
    display: grid;
    place-items: center;
    border: 0;
    padding: 0;
    color: var(--ink);
    background: linear-gradient(var(--card-2), var(--card));
    box-shadow: inset 0 0 0 1px var(--edge-2);
    clip-path: polygon(0 3px, 3px 3px, 3px 0, calc(100% - 3px) 0, calc(100% - 3px) 3px, 100% 3px, 100% calc(100% - 3px), calc(100% - 3px) calc(100% - 3px), calc(100% - 3px) 100%, 3px 100%, 3px calc(100% - 3px), 0 calc(100% - 3px));
  }
  .dice span {
    display: grid;
  }
  .dice .spin {
    animation: rolld 0.5s var(--ease);
  }
  @keyframes rolld {
    to {
      rotate: 360deg;
    }
  }

  /* The controls: the bottom half, under the thumb. */
  .ctrls {
    flex: 1;
    min-height: 0;
    overflow-y: auto;
    padding: 12px var(--gutter);
    display: grid;
    grid-template-columns: minmax(0, 1fr);
    gap: 12px;
    align-content: start;
    scrollbar-width: none;
  }
  .ctrls::-webkit-scrollbar {
    display: none;
  }
  .field {
    display: grid;
    gap: 6px;
  }
  .field .label {
    margin: 0;
  }
  .presets {
    display: flex;
    gap: 6px;
    overflow-x: auto;
    scrollbar-width: none;
    margin-inline: calc(var(--gutter) * -1);
    padding-inline: var(--gutter);
  }
  .presets::-webkit-scrollbar {
    display: none;
  }
  .presets button {
    flex: none;
    min-height: 44px;
    padding: 0 12px;
    border: 0;
    display: inline-flex;
    align-items: center;
    gap: 6px;
    font-size: min(0.765rem, 22px);
    font-weight: 600;
    background: var(--sunk);
    box-shadow: inset 0 0 0 1px var(--edge);
    clip-path: polygon(0 3px, 3px 3px, 3px 0, calc(100% - 3px) 0, calc(100% - 3px) 3px, 100% 3px, 100% calc(100% - 3px), calc(100% - 3px) calc(100% - 3px), calc(100% - 3px) 100%, 3px 100%, 3px calc(100% - 3px), 0 calc(100% - 3px));
  }
  .presets button.mine {
    box-shadow: inset 0 0 0 1px var(--edge-2);
  }
  .presets button[aria-pressed="true"] {
    box-shadow: inset 0 0 0 2px var(--gold);
  }
  .presets i {
    width: 10px;
    height: 10px;
  }
  input[type="range"] {
    -webkit-appearance: none;
    appearance: none;
    width: 100%;
    height: 44px;
    background: none;
    margin: 0;
  }
  input[type="range"]::-webkit-slider-runnable-track {
    height: 16px;
    background: var(--trk, var(--sunk));
    box-shadow: inset 0 0 0 1px var(--edge-2);
  }
  input[type="range"]::-moz-range-track {
    height: 16px;
    background: var(--trk, var(--sunk));
    box-shadow: inset 0 0 0 1px var(--edge-2);
  }
  input[type="range"]::-webkit-slider-thumb {
    -webkit-appearance: none;
    width: 28px;
    height: 36px;
    margin-top: -10px;
    background: var(--ink);
    box-shadow: inset 0 -3px 0 rgb(0 0 0 / 0.3);
    border: 0;
    border-radius: 0;
  }
  input[type="range"]::-moz-range-thumb {
    width: 28px;
    height: 36px;
    background: var(--ink);
    border: 0;
    border-radius: 0;
  }
  .seg {
    display: grid;
    grid-auto-flow: column;
    grid-auto-columns: 1fr;
    gap: 2px;
    padding: 3px;
    background: var(--sunk);
    box-shadow: inset 0 0 0 1px var(--edge);
    border-radius: 12px;
  }
  .seg button {
    min-height: 42px;
    border: 0;
    background: none;
    border-radius: 9px;
    font-size: min(0.765rem, 22px);
    font-weight: 600;
    color: var(--ink-2);
    padding: 0 4px;
  }
  .seg button[aria-pressed="true"] {
    background: var(--gold);
    color: var(--on-gold);
  }
  .patterns {
    display: grid;
    grid-template-columns: repeat(5, 1fr);
    gap: 5px;
  }
  .patterns button {
    aspect-ratio: 1;
    padding: 0;
    border: 0;
    background-color: var(--sunk);
    box-shadow: inset 0 0 0 1px var(--edge);
    font-size: min(0.647rem, 18px);
    font-weight: 600;
    color: var(--ink-3);
    clip-path: polygon(0 3px, 3px 3px, 3px 0, calc(100% - 3px) 0, calc(100% - 3px) 3px, 100% 3px, 100% calc(100% - 3px), calc(100% - 3px) calc(100% - 3px), calc(100% - 3px) 100%, 3px 100%, 3px calc(100% - 3px), 0 calc(100% - 3px));
  }
  .patterns button[aria-pressed="true"] {
    box-shadow: inset 0 0 0 2px var(--gold);
  }
  .tune {
    display: grid;
    grid-template-columns: repeat(4, 1fr);
    gap: 6px;
  }
  .tune label {
    display: grid;
    gap: 4px;
    justify-items: center;
    font-size: min(0.706rem, 20px);
    color: var(--ink-2);
  }
  .tune input {
    width: 100%;
    height: 44px;
    padding: 0;
    border: 0;
    background: none;
  }
  .nm,
  textarea {
    width: 100%;
    padding: 0 12px;
    border: 0;
    border-radius: 10px;
    background: var(--sunk);
    box-shadow: inset 0 0 0 1px var(--edge);
    color: var(--ink);
    font: 16px var(--font-body);
    outline: 0;
  }
  .nm {
    height: 44px;
  }
  textarea {
    min-height: 88px;
    padding: 10px 12px;
    font: 14px/1.4 ui-monospace, monospace;
    resize: none;
  }
  .nm:focus-visible,
  textarea:focus-visible {
    box-shadow: inset 0 0 0 2px var(--gold);
  }
  .primary,
  .ghost,
  .danger {
    min-height: 44px;
    padding: 0 14px;
    border: 0;
    border-radius: 10px;
    display: inline-flex;
    align-items: center;
    justify-content: center;
    gap: 8px;
    font-family: var(--font-display);
    font-weight: 700;
    font-size: min(0.824rem, 25px);
  }
  .primary {
    background: var(--gold);
    color: var(--on-gold);
  }
  .ghost {
    background: var(--sunk);
    box-shadow: inset 0 0 0 1px var(--edge);
    color: var(--ink);
  }
  .danger {
    background: var(--bad);
    color: var(--white);
  }
  .sm {
    justify-self: start;
    min-height: 40px;
    font-size: min(0.765rem, 22px);
  }
  .big {
    min-height: 50px;
  }
  .two {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 8px;
  }
  .fine {
    margin: 0;
    font-size: min(0.765rem, 22px);
    color: var(--ink-2);
  }
  .center {
    text-align: center;
  }
  .sections {
    flex: none;
    display: grid;
    grid-auto-flow: column;
    grid-auto-columns: 1fr;
    padding-bottom: var(--safe-bottom);
    box-shadow: inset 0 1px 0 var(--edge);
  }
  .sections button {
    min-height: 56px;
    border: 0;
    background: none;
    font-size: min(0.765rem, 22px);
    font-weight: 600;
    color: var(--ink-3);
  }
  .sections button[aria-pressed="true"] {
    color: var(--ink);
    box-shadow: inset 0 3px 0 var(--gold);
  }

  /* Sheets over the maker: the share card, and adding a code. */
  .scrim {
    position: absolute;
    inset: 0;
    z-index: 9;
    border: 0;
    background: rgb(0 0 0 / 0.45);
    animation: fadein 0.2s both;
  }
  .sheet {
    --s: 4px;
    position: absolute;
    left: var(--gutter);
    right: var(--gutter);
    bottom: calc(var(--safe-bottom) + 12px);
    z-index: 10;
    max-height: 86%;
    overflow-y: auto;
    padding: 18px 16px;
    display: grid;
    gap: 10px;
    background: var(--card);
    box-shadow: inset 0 0 0 1px var(--edge-2);
    animation: sheetin 0.35s var(--ease) both;
  }
  .sheet h4 {
    margin: 0;
    font: var(--title-weight) min(1.059rem, 24px) / 1.1 var(--font-display);
    letter-spacing: var(--title-track);
    overflow-wrap: anywhere;
  }
  .tcard {
    --s: 4px;
    padding: 14px;
    display: grid;
    gap: 10px;
    justify-items: center;
    background-color: var(--ground);
    background-image: var(--pattern, radial-gradient(var(--dot) 1px, transparent 1.2px));
    background-size: var(--pattern-size, 14px 14px);
    box-shadow: inset 0 0 0 2px var(--gold);
  }
  .tcard h5 {
    margin: 0;
    font: var(--title-weight) min(1.059rem, 24px) / 1.1 var(--font-display);
    letter-spacing: var(--title-track);
    text-align: center;
    overflow-wrap: anywhere;
  }
  .qrbox {
    line-height: 0;
  }
  .qrbox svg {
    max-width: 100%;
    height: auto;
  }
  .code {
    padding: 8px;
    background: var(--sunk);
    box-shadow: inset 0 0 0 1px var(--edge);
    font: 12px/1.35 ui-monospace, monospace;
    word-break: break-all;
    user-select: text;
    -webkit-user-select: text;
  }
  .bigstamp {
    position: absolute;
    left: 50%;
    top: 30%;
    z-index: 20;
    translate: -50% -50%;
    padding: 8px 14px;
    font: 700 24px var(--font-pixel);
    letter-spacing: 0.06em;
    color: var(--gold);
    box-shadow: inset 0 0 0 3px currentColor;
    background: var(--card);
    rotate: -7deg;
    animation: thunk 0.36s var(--ease) both;
    pointer-events: none;
  }
  .sr {
    position: absolute;
    width: 1px;
    height: 1px;
    overflow: hidden;
    clip-path: inset(50%);
  }
  @keyframes thunk {
    from {
      scale: 1.9;
      opacity: 0;
    }
    60% {
      scale: 0.97;
      opacity: 1;
    }
  }
  @keyframes sheetin {
    from {
      translate: 0 36px;
    }
  }
  @keyframes fadein {
    from {
      opacity: 0;
    }
  }
</style>
