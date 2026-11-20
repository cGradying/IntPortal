# 057 The website, second edition

**Status:** approved (the owner's ask, 2026-11-18: "a fully fledged website… directory, downloads, roadmap… introduce the staff… especially Three.js"; answers: the staff is the owner alone, the directory is every feature plus help, the look is the app's own)

## What changes for the student

The site stops being one download page. The first screen is the portal itself, in 3D: LAR stands in front of the obsidian frame, the swirl turns inside, and scrolling dives through it into the app. Every feature has its own page, help and the changelog are a tap away, a roadmap says what is shipped, being built and next, and an About page says who made it.

## Direction and references

- The app's own world, unchanged (DESIGN.md): the void and the dot grid, one gold, obsidian tiles, the SIS swirl ramp, Montserrat and Source Sans 3, Pixelify for short labels only, stepped corners on pixel surfaces.
- The hero is the tile portal of spec 010 and the dive of 010 C26–C30, rebuilt in Three.js for the web: tiles as real blocks with depth, the swirl as a dithered shader, rendered at a third of the screen and scaled up with nearest-neighbour so it reads as pixels, not as glossy 3D.
- Shipped app sites as references for what a full site carries, not for their look: a feature directory with a page per feature, a changelog, a public roadmap, install help, an about page. PRODUCT.md still forbids counts, ratings, testimonials and press.

## Keep

- Everything in 051: the right download first, every download listed, install help, privacy, questions, the footer, the static build with Node alone, no third party at load (051 C3), Lighthouse targets (051 C15).
- `/download`, `/try`, `/reel`, `/privacy` and their addresses.
- The campus scene and the campus chips; they move below the hero.

## Behaviour

### Stack

- **C1.** Still SvelteKit with the static adapter. Three.js is one pinned dependency of `site/` (exact version), imported only inside the hero with a dynamic `import()`, so no other page loads it and the first paint never waits for it.
- **C2.** The hero runs Three.js only when WebGL 2 is available, Reduce Motion is off, Save-Data is off and the device reports at least 4 cores. Otherwise it shows the still: the open portal and LAR as a static image drawn from the same art. The page never shows an empty box.

### The hero (`/`)

- **C3. Spawn.** On load the frame builds from the bottom centre up both sides and meets at the top in about 0.6 s, each block popping light core, accent, then its tone, as in 010. The swirl then opens inside.
- **C4. At rest.** The swirl turns in the SIS ramp (`#3b1220`, `#7a1c2c`, `#b5412a`, `#e08a35`, `#f3cf6a`) through a 4×4 Bayer dither. A few blocks flip tone now and then. Stars drift behind in three layers. LAR floats in front, bobbing, his art drawn by the app's own `drawLar`, nearest-neighbour.
- **C5. Pointer.** The portal turns up to 8° toward the pointer (or the phone's tilt when allowed), eased; LAR turns less, so the two separate in depth.
- **C6. The dive.** Scrolling through the hero's first 100 vh flies the camera into the portal's mouth: the swirl becomes a tunnel, the frame passes the edges of the screen, and at the end the field breaks into the page's dot grid as the next section arrives. Scrolling back reverses it. It is a pure function of scroll position.
- **C7.** Copy over the scene: "IntPortal", the one line, the one gold button for this device (051 C8), "Try it in your browser", and the unofficial line, all readable at 4.5:1 over every frame of the scene.
- **C8.** The scene renders at most 60 fps while it moves, stops when the hero is off screen or the tab is hidden, and drops to a still frame if the frame time stays over 40 ms for a second.

### Pages

- **C9. Feature directory, `/features`.** Every feature in groups (Sign-in, Today, Schedule, Grades, Study, LAR, You, Outside the app, Everywhere), each a card with a pixel icon, its name and one line, linking to its page. A filter field narrows the list as you type.
- **C10. Feature page, `/features/<slug>`.** Its name, the tab it lives in, a real screen or loop when one exists, what it does in a few short paragraphs, how to use it as numbered steps, the version it arrived in, and Previous and Next within its group. Each page is prerendered with its own title and description.
- **C11. Help, `/help`.** Install help for every platform (051 C10), the questions (051 C12), "Something's wrong" fixes (signing in, sync, reminders, the 7-day iPhone re-sign), and links to privacy and reporting a problem.
- **C12. Changelog, `/changelog`.** CHANGELOG.md rendered, newest first, each version with its date, its items and its known gaps, and an anchor per version.
- **C13. Roadmap, `/roadmap`.** Four lanes: Shipped (each release with its real date), Building (approved specs not yet shipped), Next (open P0 and P1 issues) and Later (draft specs and P2 issues). Each item says what it is in a student's words and links its spec or issue. No dates that don't exist.
- **C14. About, `/about`.** The owner alone: the GitHub handle cGradying, a PUP student, their public bio, what IntPortal is built with, and a link to their GitHub. Nothing that isn't on their public profile.
- **C15. Navigation.** The header has Features, Roadmap, Help, Try it, GitHub and a gold Get it, which is Download (one link to it, in gold, rather than two). On phones it folds into a menu sheet, which also lists Download, What's new, Reel and About. The footer lists every page.

### Every page

- **C16.** 051 C14–C16 hold for every new page: 320 to 2560 px, no horizontal scroll, Reduce Motion, keyboard, labels, contrast.

## Copy

- Hero line: "Your school schedule, grades and deadlines, on your phone. Works offline. Stays on your phone."
- LAR on the hero: "Tara, pasok!"
- Scroll hint under the hero copy: "Scroll to step through".
- Directory: heading "Everything in IntPortal", filter placeholder "Find a feature", empty "Nothing called that yet."
- Roadmap lanes: "Shipped", "Building", "Next", "Later"; intro "What's done, what's being built, and what comes after. No dates until they're real."
- About heading "Made by one student".
- Everything else is written with the build in PRODUCT.md's voice.

## Data shape

`site/src/lib/content/types.ts`:

```ts
export type Group = "signin" | "today" | "schedule" | "grades" | "study" | "lar" | "you" | "outside" | "everywhere";
export type Media = { src: string; alt: string; poster?: string; video?: boolean };
export type Feature = { slug: string; name: string; group: Group; line: string; body: string[]; steps: string[]; media?: Media; since?: string; spec?: string };
export type Release = { version: string; date: string; intro: string; items: string[]; gaps: string[] };
export type Lane = "shipped" | "building" | "next" | "later";
export type RoadItem = { title: string; line: string; lane: Lane; href: string; kind: "spec" | "issue" | "release"; date?: string };
```

- `site/src/lib/content/features.ts` exports `FEATURES: Feature[]` and `GROUPS: { id: Group; name: string; line: string }[]`, written from docs/FEATURES.md and the shipped specs.
- `site/src/lib/content/changelog.ts` exports `parseChangelog(md: string): Release[]`; the route reads `../CHANGELOG.md` at build time.
- `site/src/lib/content/roadmap.ts` exports `roadmap(specIndexMd: string, issues: GhIssue[], releases: Release[]): RoadItem[]`; issues come from the GitHub API at build time with `roadmap-fallback.json` when it doesn't answer, like 051's releases.
- `site/src/lib/hero/` holds the Three.js scene: `scene.ts` (pure: `frame(t, scroll, pointer)`), `Hero.svelte` (mount, gates, fallback).

## Errors

- WebGL fails or the context is lost: the still replaces the canvas without a jump.
- GitHub doesn't answer at build: the roadmap uses its fallback and the build log says so.

## Motion and Reduce Motion

Spawn and dive as C3 and C6, with the app's ease. Reduce Motion: the still portal, no dive, no tilt; sections never fade in.

## Accessibility

The scene is decorative (`aria-hidden`); its meaning is in the hero text. The menu sheet traps focus and closes on Escape. The directory filter has a label and announces the count.

## Out of scope

A blog, accounts, newsletters, comments, translations, analytics. Other team members on About.

## Test map

| Criterion | Check |
|---|---|
| C1 | check-build: `three` only in the hero's chunk; no third-party hosts |
| C2, C8 | vitest on the gate function; screenshot with Reduce Motion |
| C3–C7 | screenshots and a recording at 375, 768, 1440 |
| C9, C10 | vitest: every feature has a slug, group, line, body; every slug prerenders |
| C12 | vitest `parseChangelog` on CHANGELOG.md |
| C13 | vitest `roadmap` on the spec index and a recorded issue list |
| C11, C14–C16 | screenshots, Lighthouse |
