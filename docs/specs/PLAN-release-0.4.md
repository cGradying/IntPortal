# Plan: release 0.4.0, the website and the reel

**Asked (2026-11-17):** finish the app first; then a website that can launch later (Vercel or anything static) with every download link; a page for the motion reel; one repo instead of two if that is better; every app and web app works on any platform.

## Decisions

- **One repo.** The website and the reel move into this repo as `site/` and `reel/`. See [ADR 0006](../adr/0006-one-repo.md). `intportal-films` stays a local archive; `intportal-web` (the old hosted port) is not merged.
- **The website is static.** It builds with Node alone and deploys to Vercel, Netlify, Cloudflare Pages or GitHub Pages without a server. Download links point at GitHub Releases, so a new release needs no site deploy.
- **"Any platform", made concrete.**
  - Android: the signed APK, as today.
  - iPhone: no App Store without a paid developer account. An unsigned IPA ships for sideloading (AltStore, SideStore), next to the build-it-yourself guide, and the browser demo works on any iPhone.
  - Mac, Windows and Linux: desktop builds of the same app (spec 053).
  - Any browser: Look around runs in the browser on demo data (spec 052).
- **The reel is new.** The October film shows the retired Isko mascot and the old look. The new one is made from the app as it is today.

## Specs

| Spec | What | Gate |
|---|---|---|
| [050-release-0.4](050-release-0.4.md) | Finish the app: guard hardening, study mastery and forecast, this week in a syllabus, eMabini fixes, honest specs, stable release asset names | Ships as 0.4.0 |
| [051-website](051-website.md) | The download site: hero, downloads per platform, features, privacy, install help, FAQ | Builds and passes its checks; launching it is the owner's step |
| [052-try-in-browser](052-try-in-browser.md) | Look around in any browser: the real screens on demo data, the Rust core compiled to WebAssembly | Runs at `/try` on the site |
| [053-desktop](053-desktop.md) | Mac, Windows and Linux builds from the same code | CI builds all three |
| [054-reel](054-reel.md) | A new launch reel made from the app, and its page on the site | Rendered, critiqued to 8+, on `/reel` |

## Order

1. This plan and the specs (docs PR).
2. 050, the app. Each part is its own PR, merged on green CI.
3. 051, the site, with the download links and the reel's slot.
4. 052, the browser demo. A spike first: if the core can't reach WebAssembly in a day, the demo falls back to replaying recorded answers, and the spec says so.
5. 054, the reel, recorded from the app in demo mode.
6. 053, desktop. macOS is checked on this Mac; Windows and Linux in CI.
7. 0.4.0: version, CHANGELOG, the signed Android build, a draft release. It goes public only when the owner says "publish".

## What stays the owner's

- Publishing a release, and pointing a domain at the site.
- Creating the Vercel (or other) project. `site/README.md` has the steps.
- Archiving `intportal-web` on GitHub.
- Feeling the app on a real phone.
