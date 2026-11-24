# 058 The website, third pass: find, share, offline, and a home that moves

**Status:** approved (the owner's ask, 2026-11-20: "improve the website more, on visuals and functionality … do specs for developing this one, you can QA it yourself")

## What changes for the student

Anything on the site is one search away: press / or ⌘K, or tap the magnifier, and type. Every help answer, release and feature has a link you can share into the group chat. Pages you've opened still load with no signal. On a computer the home page keeps one phone in view and changes its screen as you read; LAR answers when you tap him; and the home directory lists every feature, not nine boxes.

## Direction and references

- Spec 057 and DESIGN.md hold: the void and the gold dot ground, one gold, obsidian tiles, Montserrat, Source Sans 3, Pixelify for short labels, stepped corners on pixel surfaces. No new fonts, colours or dependencies.
- Researched on 2026-11-20 in two web research passes, both unverified, used for ideas only:
  - Raycast and Linear: a command palette, opened by keyboard.
  - Linear: a dot field that answers the pointer.
  - Scroll-told product pages: one device that stays in view while the story moves.
  - Function, ranked for students on weak data:
    - an offline service worker;
    - a small client-side index instead of Pagefind's WASM;
    - Web Share with a copy fallback;
    - a print sheet for Help;
    - View Transitions, skipped under Reduce Motion and when the browser already animated a swipe-back.
- Rejected:
  - A "what's new since your last visit" badge: there is no place for it in the header.
  - RSS, sitemap, JSON-LD and per-page OG images: these need an absolute site address, and the host isn't picked (057).
  - Translations (057, out of scope).
  - Draggable windows, sound, and a light/dark slider: off-world.

## Keep

- Everything in 057 and 051: the hero, the dive, the gates, no third party at load, the static build, the addresses, and the menu sheet's focus rules.
- `three` stays only in the hero's chunk (check-build).
- The directory's filter and group rail on `/features`.

## Behaviour

### Find (every page)

- **C1.** The header gets a search button: the pixel magnifier, labelled "Search". On a phone it sits beside Get it.
  - It opens a search dialog (native `<dialog>`, modal). Pressing `/` opens it too, except while typing in a field; ⌘K/Ctrl+K opens it anywhere.
- **C2.** The dialog searches:
  - every feature (name, line, group, body);
  - every help question and fix;
  - every release in CHANGELOG.md;
  - the site's pages.
  
  Results come in groups (Pages, Features, Help, Releases), at most 6 per group, best first. The group holding the best hit comes first; ties keep that order.
  - A match is every typed word appearing as the start of a word in the item.
  - Name hits rank above body hits.
- **C3.** ↑ and ↓ move through the results, Enter opens one, and Escape or the close button shuts the dialog. Focus returns to whatever opened it. With nothing typed, it lists the pages.
- **C4.** The index is built from the same content modules the pages use. It ships as one JSON asset of at most 48 KB (gzip at most 16 KB), fetched the first time the dialog opens. check-build asserts its size.

### Share and deep links

- **C5.** Every help question and fix has an id (`/help#q-is-it-free`). Opening the address with that hash opens its `<details>` and scrolls to it. A search result for a question goes there.
- **C6.** Each help answer, each release on `/changelog` and each feature page has a Share link.
  - It uses `navigator.share` where it exists, and otherwise copies the address and says "Link copied" for 2 s (`aria-live`).
  - If both fail, the link still points at the address.

### Offline

- **C7.** A service worker (SvelteKit `src/service-worker.ts`) saves `/`, `/help`, `/features`, `/download` and the search index when it installs. Prerendered pages read without their scripts.
  - Code, fonts and every other page are saved the first time they load. Nobody downloads the 3D hero just because the worker installed.
  - Pages are network-first with the saved copy as fallback; hashed build files are cache-first.
  - `/app/`, `/reel`, videos and release downloads are never saved.
  - Old caches are deleted on activate.
  - Offline, a link loads the whole page instead of moving in-app, so the worker can answer it. After an in-app move the page itself is fetched once in the background so the worker saves it (not on Save-Data).
- **C8.** Offline, a page that wasn't saved opens the site's error page: "You're offline." over "This page wasn't saved yet. Pages you've opened before still work." and a gold Open Help.

### Moving between pages

- **C9.** Where the browser has View Transitions, page changes cross-fade the main column in 180 ms while the header stays still.
  - A feature's name in the directory grows into its page's heading.
  - Skipped under Reduce Motion, and when `navigation.hasUAVisualTransition` says the browser already animated it.

### Home

- **C10. One phone, six screens.**
  - At 900 px and wider, "On the other side" keeps one phone pinned beside the six stories. The phone shows the screen for the story at the middle of the viewport.
  - The screen changes with a stepped dissolve: 4 opacity steps over 240 ms, the pixel world's way of changing.
  - A rail of the six names (Pixelify) shows where you are, and each name scrolls to its story.
  - Below 900 px the current stacked layout stays. Reduce Motion swaps the screen with no dissolve.
- **C11. The directory lists everything.** The nine equal group boxes become an index: each group's icon, name and count, then every feature in it as a link to its page, in two columns from 900 px.
- **C12. LAR talks back.**
  - Tapping LAR (or his line) on the hero says the next line from the app's own `LINES`: first `tap`, then `tip`, never repeating the last three.
  - LAR is a button labelled "LAR, say something", and his line is a polite live region.
  - The first line stays "Tara, pasok!".
- **C13. The dot ground answers the pointer.**
  - On devices with a fine pointer and Reduce Motion off, dots of the ground under "On the other side" within about 140 px of the pointer brighten to full gold, then fade at the edge.
  - It is a CSS mask driven by two custom properties, with no canvas, and costs nothing when the pointer is away.

### Browser surfaces

- **C14.** Scrollbars, the caret, form accents, number columns (the changelog's dates and the download sizes as tabular figures) and the print sheet carry the palette.
  - The print sheet applies to `/help`: details open, dark backgrounds dropped, links printed with their address.

## Copy

- Search button label "Search"; field placeholder "Search features, help and releases"; group names "Pages", "Features", "Help", "Releases"; empty "Nothing called that yet. Help might know." with a link to Help; hint row "↑↓ to move · Enter to open · Esc to close" (hidden on touch).
- Share "Share"; after copying "Link copied".
- Offline error as in C8.
- LAR's button label "LAR, say something".
- Story rail: Today, Deadlines, Schedule, Grades, LAR, Study (the existing titles).

## Data shape

- `site/src/lib/content/help.ts`: `FAQ` and `FIXES` as `{ id: string; q: string; a: string }[]`, moved out of the help page.
- `site/src/lib/search.ts`:
  - `type Hit = { kind: "page" | "feature" | "help" | "release"; title: string; line: string; href: string; text: string }`;
  - `buildIndex(...)`, which returns `Hit[]`;
  - `search(index, query): Map<kind, Hit[]>`.
- `site/src/routes/search.json/+server.ts` prerenders the index.

## Errors

- The index fails to load: the dialog says "Search didn't load. Check your connection." and keeps the page links.
- Share is cancelled: nothing happens.
- Clipboard is denied too: the link goes to its address, so the student can copy it from the address bar.

## Motion and Reduce Motion

- The dialog opens with a 120 ms fade and a 6 px rise.
- C9 is 180 ms, C10 240 ms stepped, C13 follows the pointer.
- Reduce Motion: no dialog motion, no page transition, no dissolve, and no pointer glow.

## Accessibility

- The dialog has a label and its field is a `combobox` with `aria-activedescendant` on the active result. The result count is announced.
- The rail's links are real anchors.
- LAR's button and Share are 44 px targets.
- 057 C16 still holds.

## Out of scope

- A "new since last visit" badge.
- RSS, sitemap, JSON-LD and per-page OG images, until the site has a host.
- Translations.
- Sound.

## Test map

| Criterion | Check |
|---|---|
| C2, C4 | vitest on `search` (prefix match, ranking, groups, caps); check-build on the index size |
| C1, C3 | playwright: `/`, ⌘K and the button open it; arrows, Enter, Escape; focus returns |
| C5, C6 | playwright: `/help#q-is-it-free` opens it; Share copies in a browser without `navigator.share` |
| C7, C8 | playwright: load, go offline, reload a visited page and an unvisited one |
| C9 | playwright with and without Reduce Motion: `document.startViewTransition` called or not |
| C10–C13 | screenshots at 1440 and 390; a recording of the story scroll; LAR tap cycles lines |
| C14 | screenshot of the print preview of `/help` |
