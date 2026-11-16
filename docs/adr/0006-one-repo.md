# 0006 One repo for the app, the website and the reel

**Status:** accepted, 2026-11-17

## Context

The work sat in four places:

- `intportal-app`, public: the app.
- `intportal-films`, local only: the October launch film and its render rig. 98 MB of history, mostly media, including screenshots of the macOS app.
- `intportal-web`, private: a hosted, multi-user port with a FastAPI server and a Postgres database, from September.
- No website at all.

The owner asked for a download website and a reel page, in one repo if that is better.

## Decision

`intportal-app` holds all of it:

- `site/`: the website, a static SvelteKit build. It reuses the app's fonts, tokens and art from `src/lib` and `static/`.
- `reel/`: the new reel's source and render scripts. The rendered films are published with the site, not committed twice.

`intportal-films` is not imported. Its history is large media, it shows the retired Isko mascot, and it includes Mac app screenshots that were never reviewed for publishing. The new reel copies only the small render engine files it needs (`motion.js`, `render.mjs`, `sfx.mjs`), which are the owner's own code.

`intportal-web` is not merged. A server that holds students' SIS logins contradicts [ADR 0002](0002-device-only-data.md). It should be archived on GitHub; that is the owner's call.

## Consequences

- One CI, one version, one changelog. A change to the app's look reaches the site in the same PR.
- The site's build must not need Rust, so any host can build it. Whatever needs Rust (the browser demo's WebAssembly) is built by CI and published as a release asset or a prebuilt folder.
- The public repo gains the reel's source. Anything in it must be fit to publish: demo data only, no real student data, no third-party art.
