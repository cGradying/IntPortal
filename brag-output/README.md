# IntPortal launch video

`brag.mp4` (1920x1080, 25s, with music) is the render (also copied to `docs/media/launch.mp4`); `brag.jpg` is the poster (also baked in as frame 0).
Made with the [`/brag`](https://github.com/latent-spaces/brag) skill on Hyperframes. All names, grades and notes on screen are the design prototype's fictional sample data.

Rebuild: `cd composition && npx hyperframes@0.8.91 render --quality high --output ../brag.mp4`. The git-ignored `assets/` need restoring first:
- `assets/fonts/PixelifySans.ttf`, `SourceSans3.ttf`: copy from `Sources/PUPSISPortalApp/Resources/Fonts/`
- `assets/vendor/gsap.min.js`: `npm pack gsap@3.14.2`
- `assets/music/bed.mp3` and `assets/sfx/*`: from the brag skill's `assets/` (music is "Happy Beats / Business Moves vol. 11" by ende.app; check its license before redistributing)
