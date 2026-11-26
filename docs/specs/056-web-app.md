# 056 The web app

**Status:** draft (future plan, not scheduled)

## What changes for the student

IntPortal opens in any browser and is the same app as on the phone: the same screens, the same Rust core and the same look. A student signs in with their own school account and their data stays in that browser. It can be installed to the home screen or the dock like any other app.

## Direction and references

- One app, every platform. The browser is one more target of the Svelte UI and the Rust core, like iOS, Android, Mac, Windows and Linux. It is not a separate website with its own UI.
- The start is already shipped: the browser demo (spec 052) runs the real app on sample data. Its files are still in `site/static/app`, but since #362 (2026-11-21) the site no longer links to it.
- The old hosted port, kept in [reference/intportal-web](reference/intportal-web/README.md), is the anti-reference. It was a second app on a server that held logins.

## Keep

- No IntPortal account, and no server that stores logins or data (`PRODUCT.md`).
- The same UI as the native apps. A web-only screen is a bug.
- The demo keeps working with no sign-in, if it is linked again.

## Behaviour

To be written when this is scheduled. Open questions first:

- **Sign-in.** A browser can't call SIS directly. The options are a relay that only passes requests through and stores nothing (for example a Cloudflare Worker), or a sign-in that stays app-only. Whatever runs on a server reads [THREAT-MODEL.md](reference/intportal-web/THREAT-MODEL.md) first.
- **Storage.** The SQLCipher store becomes browser storage (OPFS or IndexedDB). How is it encrypted with no keychain?
- **Install.** A web app manifest and a service worker, so it works offline after the first visit.
- **What stays app-only.** Reminders, the camera and the on-device assistant need native APIs.

## Copy

To be written.

## Data shape

`crates/intportal-web` (spec 052) already answers app commands in wasm. A real web app adds a storage backend behind the `store` feature, and a network backend behind `net` that goes through the relay.
