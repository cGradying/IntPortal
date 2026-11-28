# 059 The portal, alive: sculptures from the other side

**Status:** shipped (#334, 2026-11-20; approved from the owner's ask, 2026-11-20: "for the portal make it dynamic too: instead of a normal 3D, add an effect for it, like the same concept of the chatbox where it becomes a sculpture … innovate in a way that fits the app and makes this production ready")

## What changes for the student

The portal on the website's first screen is alive. It breathes, it notices your pointer, and gold motes drift into it. When LAR speaks, the portal sends out a small voxel sculpture of what he's talking about: a padlock for the login in the keychain, a notebook for notes, a bell for reminders. When he moves on to his next line, the sculpture goes back in. He talks on his own every few seconds until you tap him.

## Direction and references

- **The app's own idea.** In LAR's chat, the crystal is 27 voxels of glass that take shapes while he thinks: a neuron, roots, a helix (spec 046 C1b3, `src/lib/assis/crystal.ts`). The website does the same in its own medium: obsidian and ramp-toned voxels, rendered at a third of the screen and scaled up nearest-neighbour (057 C1), so they read as pixel art with depth.
- **Research, 2026-11-20.** Five web research passes, unverified, used for ideas only:
  1. Shipped WebGL heroes: Bruno Simon, Lusion, Active Theory.
  2. Voxel morphing:
     - instanced voxels with staggered springs suit ≤ 600 voxels;
     - GPGPU and WebGPU are overkill and too heavy for mid-range Android.
  3. Dither styles. Screen-space Bayer swims under camera motion. Here that is intended, because the dive ends in a dither break (057 C6).
  4. Portals that feel alive, ranked by impact for cost:
     - a breathing vortex that surges near the pointer (Rick and Morty, Hyper Light Drifter);
     - motes pulled in (Minecraft's nether portal, Celeste);
     - a burst on opening (Stargate's kawoosh);
     - a parallax glimpse of the other side (Portal, Outer Wilds), kept for later.
  5. Production on low-end phones:
     - stay on WebGL2;
     - gate on device memory as well;
     - cap phones at 30 fps;
     - keep the still as the first paint;
     - fall back on context loss or sustained slow frames.
- Kept from 057: the frame of 96 obsidian tiles, the SIS ramp, the 4×4 Bayer dither, the dive and its dot-ground ending.

## Keep

- 057 C1–C8 and C16, and 058 C12 (LAR's lines, in order, on tap).
- `three` only in the hero's chunk (check-build); no new dependency.
- The still (`Still.svelte`) stays the first paint and the fallback.

## Behaviour

- **C1. Sculptures.**
  - Each of LAR's lines names a form, or none. "Tara, pasok!" names none, because the portal itself is the invitation.
  - The forms: crystal, heart, phone, lock, book, cards, bell, calendar, hourglass. Each is at most 72 voxels in the ramp's five tones (`site/src/lib/hero/forms.ts`), with front faces at tone 2 or lighter. Voxels touch, and one obsidian outline runs round the silhouette. While a sculpture is out, the swirl dims in a pool behind it, so it reads against the fire.
  - On a new line, the current sculpture goes back into the mouth, last voxel first, in 0.35 s. Then the new one comes out: each voxel leaves the mouth's centre in order, bottom first, and springs into place with a little overshoot, all within 0.9 s.
  - It floats in front of the mouth's upper half, turns slowly (±25°) and bobs.
- **C2. LAR talks on his own.**
  - While the 3D scene runs and the hero is on screen and not diving, LAR says his next line every 7 s, four lines in all; then he rests, so motion doesn't keep pulling at the eye while the visitor reads.
  - Tapping him moves to the next line at once and stops the timer for good: from then on, the student leads.
- **C3. The vortex breathes.**
  - The swirl's brightness rises and falls on a 5 s cycle.
  - As the pointer nears the mouth, the swirl turns up to 1.8 times faster and brighter, eased.
- **C4. Motes.** About 40 gold and pale pixels spiral into the mouth on slow inward paths and are reborn at the rim. They are drawn in the vertex shader, with no work on the CPU.
- **C5. Kawoosh.** Once the mouth has opened after the frame builds (057 C3), a bright ring runs out from the centre to the frame in 0.6 s, then the swirl settles.
- **C6. Tiles lean in.** With a fine pointer over the portal, the frame tiles within about 2.5 tiles of it lift toward the viewer by up to half a tile and light one tone, eased back when it leaves.
- **C7. The dive.** Scrolling into the dive shrinks the sculpture into the mouth with the camera's approach, so nothing floats in front of the tunnel. Scrolling back brings it out again.

### Production

- **C8.** On top of 057 C2, the 3D also needs `navigator.deviceMemory` ≥ 4 wherever the browser reports it.
- **C9.** With a coarse pointer, the scene draws at most 30 frames a second. The slow-frame fallback (057 C8) is unchanged, measured on drawn frames.
- **C10.**
  - `webglcontextlost` calls `preventDefault`, stops and shows the still (as 057).
  - Every new geometry and material is disposed on stop.
  - The CPU allocates nothing per frame in the voxel loops.

## Copy

None new. LAR's lines are 058 C12's.

## Data shape

- `site/src/lib/hero/forms.ts`:
  - `type Voxel = { x; y; z; tone }`;
  - `FORMS: Record<string, { id; voxels: Voxel[] }>`;
  - `MAX = 72`.
- `site/src/lib/hero/talk.ts`: `talk: { text: string; form: string | null }[]`.
- `Hero` (from `scene.ts`) gains `form(id: string | null)`.

## Errors

As 057: WebGL missing, lost or slow means the still and LAR's lines, with no sculptures.

## Motion and Reduce Motion

- C1 timings as above.
- Reduce Motion runs no 3D at all (057 C2), so none of this. LAR's line still changes on tap, without the timer.

## Accessibility

- Everything here is decorative and inside the `aria-hidden` canvas.
- LAR's line is a polite live region only for lines the visitor asked for by tapping. Lines he says on his own are not announced, so a screen reader isn't interrupted every 7 s.

## Out of scope

- The parallax glimpse of an app screen through the mouth: a later spec.
- Sound.
- Sculptures in the phone app.

## Test map

| Criterion | Check |
|---|---|
| C1 | vitest: every form ≤ 72 voxels, centred, ramp tones, no duplicates; every talk line's form exists |
| C1–C7 | frames captured from Chrome at 1440 and 390: at rest, sculpture out, tiles lifted, mid-dive |
| C2 | playwright: the line changes after 7 s untouched; after a tap it stops changing on its own |
| C8 | vitest on `canRun` with `memory: 2` |
| C9 | playwright with `hasTouch`: rAF callbacks that draw ≤ 31 per second |
| C10 | check-build; a context-loss test shows the still |
