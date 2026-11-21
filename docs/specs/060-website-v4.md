# 060 The website, fourth pass: honest install, every page finished, lighter on phones

**Status:** approved (the owner's ask, 2026-11-20: "for the website make sure you enhance it a little more, swarm on this")

## What changes for the student

A link shared in a group chat says what IntPortal is. The iPhone and Android steps tell the truth about the awkward parts before the student hits them. Every page ends with a next step. The 39 feature pages without a screen no longer look unfinished. On a phone the home page is shorter, the 3D hero waits for a good connection, and pages download less.

## Direction and references

A five-way audit on 2026-11-20 (the swarm), each lens run by its own agent on the live site:
1. Home design and hierarchy (Claude, screenshots at 390, 1440, 1920).
2. Inner pages (Claude, 11 pages at 390 and 1440).
3. Copy and the path to installing (Claude).
4. Performance and accessibility (Claude, on the production build: 4× CPU, Slow 4G).
5. What shipped app sites have that this one lacks (agy, unverified).

DESIGN.md and specs 057–059 hold. No new fonts, colours or dependencies.

## Keep

- Everything in 057, 058 and 059.
- No third party at load (051 C3): links to other sites are not loads. check-build allows the two sideloading sites as link targets only.
- The licence, all rights reserved since #335.

## Behaviour

### Copy and install (lens 3)

- **C1.** The home page's link preview says it is a free, unofficial student app, and names PUP SIS and eMabini.
- **C2. iPhone honesty.** The iPhone steps say:
  - you need a Mac or Windows computer once, to set up AltStore or SideStore;
  - a free Apple ID runs at most 3 sideloaded apps;
  - the app needs refreshing every 7 days;
  - AltStore and SideStore are linked by name.

  The iPhone button reads "Get the iPhone file (.ipa)".
- **C3. Android.** The steps include Play Protect's "unknown app" warning and how to get past it.
- **C4. The data facts on the home page.**
  - "Your login only goes to your school." replaces "Your login stays on your phone.", which contradicted Help.
  - "an encrypted database" replaces "SQLCipher".
  - A fact is added: "Anyone can read the code", linking GitHub.
- **C5. A next step at every page end.** Feature pages, Privacy, What's new, Roadmap and About end with the same band: "Get IntPortal" for the visitor's device, and "Try it in your browser". The spec link on feature pages becomes a footnote.
- **C6.** Old "comes with 0.4" lines become "Coming in a later release."

### Home (lens 1)

- **C7.** On phones, story text no longer reserves 500 px: no dead space after each story.
- **C8.** From 900 px, "On the other side" and its lede sit at the top of the story column, so the pinned phone shows from the first screen.
- **C9.** "Stays on your phone" gets a pixel icon in an obsidian tile beside each fact.
- **C10.** The campus scene scales by whole numbers (4×, 5×, 6×), so its pixels stay square.
- **C11.**
  - The directory becomes a grid of the groups: 3 across from 1280 px.
  - Each feature link is at least 44 px tall.
  - On phones, the directory shows the group names only, each linking to its group on /features.
- **C12.** The roadmap band and "Questions?" share one row from 900 px. "Questions?" lists three real questions linking to their answers (`#q-is-this-official`, `#q-is-my-password-safe`, `#q-why-isnt-it-on-the-app-store`).
- **C13.** The hero's line grows with wide screens, up to 1.6rem. The unofficial line is 0.95rem.

### Inner pages (lens 2)

- **C14.** One shared page head:
  - the same h1 and lede sizes;
  - a band of the dot ground behind it, fading down;
  - on every inner page.

  Privacy's column aligns with the others.
- **C15.** A feature page without media shows a phone-shaped obsidian tile with stepped corners, the dot ground and the group's pixel icon, captioned "Lives in <group>". On phones the title comes before the phone.
- **C16.** What's new:
  - a row of version chips under the lede;
  - the three newest releases open, older ones folded into `<details>`;
  - a version's address opens its release.
- **C17.** Roadmap's Shipped list shows the five newest releases, then "All N releases on What's new".
- **C18.** /features:
  - an empty filter result shows LAR, Clear, and "Search everything", which opens the site search with the query;
  - the group rail marks the group you're in.
- **C19.** The 404 page offers search and chips to Features, Help and What's new.

### Lighter on phones (lens 4)

- **C20.** The 3D hero also waits for a 4G-class connection (`effectiveType`, where the browser reports it; the raw downlink figure is ignored, because Chrome understates it on a fresh profile). It loads during idle time, after the first paint.
- **C21.** The service worker saves nothing on install under Save-Data or on 2G/3G. Pages are still saved when opened.
- **C22.**
  - The two Latin body fonts are preloaded.
  - The Pixelify CSS imports only the Latin subset (no inlined Cyrillic).
  - Small stylesheets are inlined.
- **C23. Accessibility.**
  - /download has an h2 before its device rows.
  - Changelog version links and the footer mark are 44 px targets.
  - The "since" badges are 14 px at 0.7.

## Out of scope (named by the swarm, needs the owner)

- A pricing / "free forever vs Cloud" page.
- A comparison with the official SIS.
- A press kit.
- A status page.
- RSS.

All of these depend on commercial decisions, or on a hosted address the site doesn't have yet.

## Test map

| Criterion | Check |
|---|---|
| C1–C6 | vitest on platforms and help content; a rendered read of each page |
| C7–C19 | screenshots at 390, 1440 and 1920 |
| C20, C21 | vitest on `canRun` with the connection; playwright with Save-Data |
| C22 | check-build: no Cyrillic font in the main CSS |
| C23 | playwright: heading order and target sizes |
