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

The build is the `site/build` folder of plain files. Any static host works. Links like `/download` need the host to serve `download.html` for them, which all of these do.

**Vercel.** New project, import the GitHub repository, set **Root Directory** to `site`. `site/vercel.json` sets the rest. Add a domain under Settings › Domains.

**Netlify.** New site from Git, base directory `site`. `site/netlify.toml` sets the rest.

**Cloudflare Pages.** Framework preset none, root directory `site`, build command `pnpm build`, output directory `build`.

**GitHub Pages.** Settings › Pages › Source: GitHub Actions. Then Actions › Site › Run workflow with "deploy" ticked. It serves at `https://<owner>.github.io/intportal-app/` unless you add a custom domain, so set `BASE_PATH=/intportal-app` in the workflow when you have no domain.

After the site has an address, set `SITE` in `src/lib/links.ts` at the repository root, so the app's Updates link opens `/download`.

## How it stays current

The download links point at `releases/latest/download/<file>`, so a new release needs no new deploy. The version and sizes are read from GitHub when the site is built, and again in the visitor's browser when GitHub answers. When GitHub doesn't answer at build time, `src/lib/fallback.json` is used.

## The browser demo

`/try` frames the app itself, built for the browser into `static/app` by `scripts/web.sh` at the repository root (spec 052). It needs Rust, so its output is committed and the site still builds with Node alone. Run `scripts/web.sh` before a release, after the app changes.

## Media

`scripts/media.sh` turns the README's screenshots and GIFs into the WebP stills and MP4 loops in `static/media`. The outputs are committed, so hosts don't need ffmpeg.
