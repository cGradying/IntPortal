# The IntPortal website

The download site: the right file for each device, install help, privacy, the reel and the browser demo. Spec: [051-website](../docs/specs/051-website.md).

It is a static SvelteKit build. It needs Node and nothing else: no server, no Rust, no environment variables. It borrows the app's fonts, colours, campus scenes and LAR from `../src/lib`.

## Run it

From the repository root, once: `pnpm install`. Then, in `site/`:

```bash
pnpm dev
```
```bash
pnpm build && node scripts/check-build.mjs && pnpm preview
```

`pnpm test` runs the site's own tests and `pnpm check` its types.

## Put it online

The build is the `site/build` folder of plain files. Any static host works. Links like `/download` need the host to serve `download.html` for them, which all of these do. The site must sit at the root of its domain, because the browser demo is built for `/app`.

**Cloudflare Pages (recommended).** It is free, with no bandwidth cap, and allows commercial use. You get `<name>.pages.dev`. Workers & Pages › Create › Pages › Connect to Git, pick the repository, then:

| Setting | Value |
|---|---|
| Framework preset | None |
| Root directory | `site` |
| Build command | `pnpm install --frozen-lockfile && pnpm build && node scripts/check-build.mjs` |
| Build output directory | `build` |
| Environment variables | `SKIP_DEPENDENCY_INSTALL=1`, `PNPM_VERSION=11.7.0` |

`static/_headers` sets the security and cache headers. Every push to `main` redeploys. Each file must stay under 25 MiB, and the largest today is the 8.3 MB reel.

**Vercel.** The free Hobby plan is for non-commercial use only. New project, import the GitHub repository, set **Root Directory** to `site`. `site/vercel.json` sets the rest.

**Netlify.** New site from Git, base directory `site`. `site/netlify.toml` sets the rest, and `static/_headers` sets the headers.

**GitHub Pages.** It needs a custom domain, because without one the site lives under `/IntPortal/` and the demo breaks. Settings › Pages › Source: GitHub Actions, add the domain, then Actions › Site › Run workflow with "deploy" ticked.

After the site has an address, set `SITE` in `src/lib/links.ts` at the repository root, so the app's Updates link opens `/download`.

## How it stays current

The download links point at `releases/latest/download/<file>`, so a new release needs no new deploy. The version and sizes are read from GitHub when the site is built, and again in the visitor's browser when GitHub answers. When GitHub doesn't answer at build time, `src/lib/fallback.json` is used.

## The browser demo

`/try` frames the app itself, built for the browser into `static/app` by `scripts/web.sh` at the repository root (spec 052). It needs Rust, so its output is committed and the site still builds with Node alone. Run `scripts/web.sh` before a release, after the app changes.

## Media

`scripts/media.sh` turns the README's screenshots and GIFs into the WebP stills and MP4 loops in `static/media`. The outputs are committed, so hosts don't need ffmpeg.
