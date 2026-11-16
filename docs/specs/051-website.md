# 051 The website

**Status:** building

## What changes for the student

A student who hears about IntPortal opens one address on any phone or computer, sees what the app is in the first screen, and gets the right download for their device in one tap. Every other way to get it (other platforms, sideloading, building it, trying it in the browser) is one scroll away. They can read what happens to their data before they install anything.

## Direction and references

- The app's own world (DESIGN.md): the night ground and stars, the pixel campus at night with the jeepney, LAR, one gold for the one action, Pixelify only for short labels.
- Persuade mode, but the facts are the pitch: what it does, where the data lives, that it is unofficial. PRODUCT.md: no user counts, ratings, testimonials or press, ever.
- Real screens and GIFs from `docs/images/`; the reel from spec 054.

## Keep

- The app's fonts, colours and LAR art, imported from the app's source, not copied by hand.
- PRIVACY.md as the one privacy text; the site renders it.

## Behaviour

### Build and hosting

- **C1.** `site/` is a SvelteKit app with the static adapter. `pnpm --dir site build` writes plain files to `site/build` with Node alone: no Rust, no server, no environment variables.
- **C2.** It deploys as is to Vercel (`site/vercel.json`), Netlify, Cloudflare Pages or GitHub Pages. `site/README.md` gives each host's steps. A GitHub Actions workflow builds it on every PR that touches `site/`, and a manual run can publish it to GitHub Pages.
- **C3.** Nothing on the site calls a third party at load: fonts are self-hosted, there are no analytics, cookies, trackers or embeds. The one exception is C9's version check to the GitHub API, which sends nothing about the visitor beyond the request itself.

### Pages

- **C4.** `/`: the home page (C6 to C13).
- **C5.** `/download` (the address the app's Updates link opens), `/reel` (054), `/try` (052), `/privacy` (PRIVACY.md rendered) and a 404 page in the same world.

### Home

- **C6. The first screen.** The campus at night, live and drawn by the app's own renderer, with the jeepney passing; LAR floats in front; "IntPortal" and one sentence say what it is; one gold button gets the download for this device (C8); "Unofficial. Not made by PUP." is visible without scrolling.
- **C7. What it does.** Today, Schedule, Grades, Deadlines, Study and LAR, each with a real screen or GIF from the app and two lines of text.
- **C8. The right download first.** The page reads the device from the user agent:
  - Android: "Download for Android" fetches `IntPortal.apk` from the latest release.
  - iPhone or iPad: "Try it in your browser" (052) first, with the sideload and build options under it.
  - Mac, Windows or Linux: that desktop build when 053 has shipped one, and a QR code for the phone beside it.
  - Anything else: the full list.
- **C9. Every download, listed.** A section and `/download` list every platform with its file, size, version and requirement (Android 7, 64-bit; iOS 16; macOS 12; Windows 10; Linux x86-64). The links point at `releases/latest/download/<stable name>`, so they never go stale. The version and sizes come from the GitHub API at build time and are refreshed in the browser when the API answers; when it doesn't, the build-time values stay.
- **C10. Install help.** Android: allow installs from the browser, open the file, updates keep your data. iPhone: AltStore or SideStore with your own Apple ID (re-signs every 7 days), or build with Xcode (links docs/BUILDING.md). Mac: open it from the context menu the first time. Windows: SmartScreen's "More info, Run anyway". Each is a short numbered list.
- **C11. Your data.** Four facts from PRIVACY.md (login in the keychain, data encrypted on the phone, no IntPortal server or account, talks only to PUP), and a link to `/privacy`.
- **C12. Questions.** Is it official? Is my password safe? Does it work offline? Is it free? Why isn't it on the App Store? What about other schools? Each answer is two or three sentences.
- **C13. The footer.** The unofficial line, the licence (PolyForm Noncommercial), the source on GitHub, Report a problem, and the version.

### Every page

- **C14.** Works from 320 px wide to 2560 px, in every current browser, with no horizontal scroll. Respects Reduce Motion: the scene stands still and nothing slides.
- **C15.** Lighthouse on `/` in mobile mode: accessibility 100, performance at least 90, best practices 100, SEO 100. Each page has a title, a description and an Open Graph image.
- **C16.** Keyboard reachable, visible focus, every image labelled, contrast at least 4.5:1 for text.

## Copy

- Title: "IntPortal".
- Line: "Your PUP schedule, grades and deadlines, on your phone. Works offline. Stays on your phone."
- Unofficial: "Unofficial. Not made by or affiliated with PUP."
- Gold button labels: "Download for Android", "Try it in your browser", "Download for Mac", "Download for Windows", "Download for Linux".
- LAR's line on the first screen: "Tara, pasok!"

The rest is written with the build, in the voice of PRODUCT.md: plain, short, light Taglish, facts only.

## Data shape

- `site/src/lib/releases.ts`: `type Asset = { platform, file, url, size, version }`; `latest()` reads the GitHub API, `assets(release)` maps a release to the platform list by file name.
- `site/src/lib/device.ts`: `device(ua) -> "android" | "ios" | "mac" | "windows" | "linux" | "other"`.

## Errors

- The GitHub API is down or rate-limited at build: the build uses `site/src/lib/fallback.json` (the last known release) and says so in its log.
- A platform has no file in the latest release: its row says "Not in this release yet" and links the releases page.

## Motion and Reduce Motion

The scene runs at the app's frame rate and pauses when off screen or when the tab is hidden. Sections don't fade in. Reduce Motion shows the scene's still frame.

## Accessibility

Covered by C14 and C16. The scene is decorative and hidden from screen readers; its meaning is in the text.

## Out of scope

- A blog, accounts, a newsletter or a waitlist.
- Translations; the site is English with light Taglish like the app.

## Test map

| Criterion | Check |
|---|---|
| C1, C2 | `pnpm --dir site build` in CI |
| C3 | a test that the build output has no third-party URLs except the GitHub API and release links |
| C8 | `vitest device` |
| C9 | `vitest releases` on a recorded API answer |
| C14 to C16 | Lighthouse and screenshots at 375, 768 and 1440 px |
| the rest | screenshots |

## Open questions

None. The domain is the owner's to pick at launch; the site works on any.
