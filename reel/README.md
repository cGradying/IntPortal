# The reel

IntPortal in 46 seconds (spec [054](../docs/specs/054-reel.md)), in two cuts: 9:16 and 16:9. The website shows it at `/reel`.

The footage is the real app, recorded from the browser demo on demo data. LAR and the campus are drawn by the app's own renderers. The film is a pure function of time: `seek(t)` in `film.ts` paints frame t.

## Make it again

The site must be built and served first: `cd site && pnpm build && pnpm preview`. Every step needs `PLAYWRIGHT` (the path to `playwright-core/index.mjs`) and `CHROME` (a Chrome with GPU). Run each one from the repository root.

1. Record the footage:
   ```bash
   SITE=http://localhost:4173 node reel/capture.mjs
   ```
2. Cut the footage into frames:
   ```bash
   for c in dive today schedule grades study; do mkdir -p reel/footage/$c; ffmpeg -i reel/footage/$c.mp4 -vf fps=30,scale=780:-2 -q:v 3 reel/footage/$c/%04d.jpg; done
   ```
3. Make the score and mix it:
   ```bash
   node reel/score.mjs && ffmpeg -i reel/out/score.wav -af loudnorm=I=-14:TP=-1.5 reel/out/mix.wav
   ```
4. Render both cuts:
   ```bash
   node reel/render.mjs --w 1080 --h 1920 && node reel/render.mjs --w 1920 --h 1080
   ```
5. Put them on the site:
   ```bash
   node reel/publish.mjs
   ```

To check a few moments without a full render, use `node reel/render.mjs --w 1080 --h 1920 --sheet 3,9,14,30,44`.

The scores and the fixes are in [REVIEW.md](REVIEW.md). Footage and renders are not committed. The published files live in `site/static/reel`.
