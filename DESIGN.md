---
name: IntPortal
description: An offline-first PUP SIS companion that opens onto another side, a pixel portal with LAR standing in it.
colors:
  ground: "#19191c"
  ground-2: "#202024"
  dot: "rgba(245, 178, 39, 0.07)"
  card: "#26262a"
  card-2: "#2d2d32"
  sunk: "#1f1f23"
  edge: "rgba(255, 255, 255, 0.07)"
  edge-2: "rgba(255, 255, 255, 0.13)"
  ink: "#efeff1"
  ink-2: "#a9a9b1"
  ink-3: "#7c7c85"
  gold: "#f5b227"
  gold-soft: "rgba(245, 178, 39, 0.14)"
  gold-shade: "#b87a10"
  gold-light: "#fff6dc"
  on-gold: "#1b1406"
  maroon: "#7a1128"
  maroon-2: "#9b1d36"
  good: "#58c792"
  bad: "#f07a6e"
  island: "#0e0e10"
  subject-1: "#e0697e"
  subject-2: "#e8866f"
  subject-3: "#e0b04a"
  subject-4: "#b58ad0"
  subject-5: "#5fbf9c"
  subject-6: "#7ea3e0"
  portal-night: "#0b0710"
  portal-card: "#140c16"
  portal-parchment: "#f4ecd8"
  portal-wordmark: "#fff5dc"
  lar-line-ink: "#f4e8d6"
  obsidian: "#170b1a"
  obsidian-hi: "#3a2446"
  obsidian-lo: "#060307"
  obsidian-fleck: "#4a2c58"
  obsidian-bevel: "#5a3a6c"
  swirl-0: "#170509"
  swirl-1: "#540a1c"
  swirl-2: "#941c30"
  swirl-3: "#cca128"
  swirl-4: "#faebb3"
typography:
  display:
    fontFamily: "Montserrat Variable, system-ui, sans-serif"
    fontSize: "min(1.529rem, 34px)"
    fontWeight: 700
    letterSpacing: "-0.01em"
  headline:
    fontFamily: "Montserrat Variable, system-ui, sans-serif"
    fontSize: "min(1.647rem, 36px)"
    fontWeight: 700
    letterSpacing: "-0.02em"
  numeral:
    fontFamily: "Montserrat Variable, system-ui, sans-serif"
    fontSize: "min(2.824rem, 62px)"
    fontWeight: 800
    lineHeight: 1
    letterSpacing: "-0.03em"
    fontFeature: "tnum"
  title:
    fontFamily: "Montserrat Variable, system-ui, sans-serif"
    fontSize: "min(1.294rem, 29px)"
    fontWeight: 700
  body:
    fontFamily: "Source Sans 3 Variable, system-ui, sans-serif"
    fontSize: "min(0.941rem, 29px)"
    fontWeight: 400
    lineHeight: 1.4
  body-sm:
    fontFamily: "Source Sans 3 Variable, system-ui, sans-serif"
    fontSize: "min(0.824rem, 25px)"
    fontWeight: 400
    lineHeight: 1.35
  fine:
    fontFamily: "Source Sans 3 Variable, system-ui, sans-serif"
    fontSize: "min(0.765rem, 23px)"
    fontWeight: 400
  input:
    fontFamily: "Source Sans 3 Variable, system-ui, sans-serif"
    fontSize: "max(16px, min(0.941rem, 29px))"
    fontWeight: 400
  label:
    fontFamily: "Montserrat Variable, system-ui, sans-serif"
    fontSize: "min(0.647rem, 20px)"
    fontWeight: 600
    letterSpacing: "0.08em"
  pixel:
    fontFamily: "Pixelify Sans, ui-monospace, monospace"
    fontSize: "min(0.706rem, 22px)"
    fontWeight: 500
    letterSpacing: "0.08em"
rounded:
  pixel: "0px"
  control: "10px"
  row: "12px"
spacing:
  art-pixel: "3px"
  notch-step: "3px"
  notch-step-card: "4px"
  gutter: "16px"
  card-padding: "16px"
components:
  button-portal:
    backgroundColor: "{colors.gold}"
    textColor: "{colors.on-gold}"
    rounded: "{rounded.pixel}"
    height: "50px"
  button-primary:
    backgroundColor: "{colors.gold}"
    textColor: "{colors.on-gold}"
    rounded: "{rounded.control}"
    height: "44px"
  button-ghost:
    backgroundColor: "{colors.sunk}"
    textColor: "{colors.ink}"
    rounded: "{rounded.control}"
    height: "44px"
  input-portal:
    backgroundColor: "{colors.portal-night}"
    textColor: "#ffffff"
    typography: "{typography.input}"
    rounded: "{rounded.pixel}"
    height: "46px"
    padding: "0 12px"
  card:
    backgroundColor: "{colors.card}"
    textColor: "{colors.ink}"
    padding: "{spacing.card-padding}"
  sign-in-card:
    backgroundColor: "{colors.portal-card}"
    textColor: "{colors.portal-parchment}"
    padding: "16px 16px 12px"
  lar-line:
    backgroundColor: "{colors.obsidian}"
    textColor: "{colors.lar-line-ink}"
    typography: "{typography.body-sm}"
    padding: "10px 12px"
  stone:
    backgroundColor: "{colors.obsidian}"
    textColor: "{colors.lar-line-ink}"
    padding: "8px 9px 6px"
  tab-bar:
    textColor: "{colors.ink-3}"
    padding: "8px 8px 6px"
---

# Design System: IntPortal

## Overview

**Creative North Star: "The Other Side of the Portal"**

IntPortal has two registers that share one gold. Inside the app is the legacy calm: a charcoal ground under a faint gold dot grid, quiet gradient cards with hairline edges, Montserrat for anything that carries weight and Source Sans 3 for everything read. On top of that calm sit pixel accents that are drawn, not decorated: stepped card corners, 12 by 12 pixel icons, stepped animations, Isko the pixel student. The landing is the other register, the world the calm app opens onto: a night ground, an obsidian portal built from falling pentominoes, a maroon-to-gold dithered swirl, and LAR, a small obsidian robot who comes through it.

The pixel world exists to serve a glance. Students open the app between classes, on weak data, in jeepneys; clear first, charming second. Every pixel element on screen does a job (a tab, a stone that names a section, a mascot that speaks), and nothing on screen only decorates. The landing deliberately refuses the logo-over-a-form login screen: the portal and LAR own the top half, LAR's line and the sign-in card own the bottom half, and the one gold button is Sign in.

**Key Characteristics:**
- Dark-first, charcoal ground with a 14 px gold dot grid; Day and Maroon rooms restyle the same roles.
- One gold for action and selection, on every room and on the landing.
- A 3 CSS px art pixel for the portal and LAR; crisp edges and nearest-neighbour scaling everywhere art appears.
- Stepped (clip-path) corners on cards and pixel slabs, never a border radius on a pixel surface.
- Type scales with the iPhone text size from a 17 px root, with hard caps per role.
- Motion is stepped for pixel things and eased for interface things; the landing runs on one pure clock.

## Colors

A neutral charcoal system with one warm gold voice, and a separate night palette (obsidian purples, a maroon-to-gold swirl) reserved for the portal world.

### Primary
- **Portal Gold** (gold): every primary action (Sign in, Step through, the primary app button), the active tab's label and icon accent, the caret, focus rings on the landing, the LAR speaker tag, campus confirmation, and the drifting motes. Its pressed shadow is **Gold Shade** (gold-shade), drawn as a 3 px inner bottom edge; its focus ring on a gold button is **Gold Light** (gold-light). Text on gold is **Burnt Ink** (on-gold).
- **Gold Wash** (gold-soft): tinted fills behind selected or highlighted rows.

### Secondary
- **PUP Maroon** (maroon, maroon-2): the brand's second colour, carried by the swirl, LAR's mouth, and the Day room's first subject colour. Maroon and gold are allowed; the PUP seal and wordmark are not.

### Tertiary: the portal world
- **Night** (portal-night): the landing ground, the 3D scene background and fog, and the landing's inputs. Nothing else in the app sits on it.
- **Obsidian** (obsidian, obsidian-hi, obsidian-lo, obsidian-fleck, obsidian-bevel): the portal blocks, the stones, and LAR's speech slab. Each slab is lit on top (obsidian-hi or obsidian-bevel) and shaded at the bottom (obsidian-lo), with purple flecks.
- **The Swirl** (swirl-0 to swirl-4): the brand's core image, a five-tone ordered-dither ramp from near-black maroon to pale gold. Used only inside the portal opening and the flat fallback drawing. LAR's belly window runs its own warmer five-tone ramp (#2a0a14, #7a1128, #c2403a, #f5b227, #fff1c4).
- **Parchment** (portal-parchment, portal-wordmark, lar-line-ink): warm off-whites for text on the night ground. Secondary landing text uses Parchment at 0.5 to 0.6 alpha.

### Neutral
- **Charcoal Ground** (ground, ground-2): the app background, under the gold dot grid (dot) on a 14 px pitch.
- **Card Charcoal** (card, card-2): cards are a top-to-bottom gradient from card-2 to card. **Sunk** (sunk) is for wells, ghost buttons and skeletons. **Island** (island) is the darkest surface, for the floating glance dock.
- **Ink** (ink, ink-2, ink-3): primary text, secondary text, and labels or idle icons.
- **Edges** (edge, edge-2): 1 px inset hairlines on cards and controls; edge-2 for emphasised outlines.
- **Status** (good, bad): positive and negative grades, errors, the danger button.
- **Subject colours** (subject-1 to subject-6): one per class, for schedule blocks and grade rows. The student can recolour.

### Rooms
A room is one block of roles on `:root[data-room]`; components read roles, never room hex. **Night** is the default (the tokens above). **Day** is light: ground #f4f2ef, card #ffffff, ink #1c1517, gold darkens to #b8860b with on-gold #ffffff, maroon #6d0e1f, dot grid in maroon. **Maroon** is dark and warm: ground #1a0a0e, card #2a1016, ink #f7ecec, gold #f2c14e. Further rooms are derived from the legacy palettes in `rooms.ts`, with contrast clamps.

### Named Rules
**The One Gold Rule.** Gold means "do this" or "you are here": the primary action, the selected option, the active tab. Secondary actions are ghost buttons or underlined text, never a second hue.

**The Swirl Stays in the Portal Rule.** The swirl ramp lives inside an opening (the portal, LAR's belly window). It is never a background gradient, a card fill, or a text colour.

**The Roles Not Hex Rule.** App screens read colour roles (`var(--gold)`, `var(--card)`), so every room works. The landing is the one surface that names its own night palette, because it does not change with the room.

## Typography

**Display Font:** Montserrat Variable (with system-ui, sans-serif)
**Body Font:** Source Sans 3 Variable (with system-ui, sans-serif)
**Pixel Font:** Pixelify Sans 500 and 700 (with ui-monospace, monospace)

**Character:** Montserrat is the confident geometric voice for the wordmark, headings, numbers and buttons; Source Sans 3 is the patient reading voice for sentences, notes and fields. Pixelify Sans is the other side's voice: LAR's name tag, the stone labels, and system hints like "PUP SIS · via sis8".

### The scale
The root is the iPhone's body text size (`font: -apple-system-body`, 17 px at the default; Android keeps 17 px). Every size is written `min(<rem>, <px cap>)`, where the rem is the design size divided by 17 and the cap stops growth at about 1.3 times for headings and about 1.8 times for body and labels.

- **Numeral** (800, 48 px at default, cap 62 px, line-height 1, -0.03em, tabular): the GPA figure on Grades.
- **Display** (700, 26 px, cap 34 px, -0.01em): the landing wordmark, "Student" in gold and "IntPortal" in Parchment.
- **Headline** (700, 28 px, cap 36 px, -0.02em): each tab's screen title.
- **Title** (700, 22 px, cap 29 px): page and sheet headings (subject page, note editor); 24 px (cap 31 px) for first-run and study cards; 18 px (cap 32 px) for sheet headings.
- **Body** (400, 16 px, cap 29 px, line-height 1.4): the default body size.
- **Body small** (400, 14 px, cap 25 px): LAR's line, errors, descriptions. 15 px (cap 27 px) for list rows and buttons.
- **Fine** (400, 13 px, cap 23 px): the most used secondary size: meta lines, privacy notes, small buttons.
- **Label** (Montserrat 600, 11 px, cap 20 px, 0.08em, uppercase, ink-3): field names and metadata. The landing's field labels run 12 px (cap 22 px) at 0.06em.
- **Pixel** (Pixelify 500, 12 px, cap 22 px, 0.04em to 0.08em): LAR's tag, stone labels, hints.
- **Input** (16 px floor, then the body size): every text field, so iOS never zooms on focus.

### Named Rules
**The Capped Growth Rule.** Every font size is `min(rem, px)`. A new size divides the design px by 17 for the rem and sets the cap near 1.3 times (headings) or 1.8 times (body, labels). The tab bar is the one tighter cap (13 px), because five labels share the width.

**The Pixel Voice Rule.** Pixelify Sans speaks for the other side (LAR, the stones, system hints) and never sets a heading, a button, or a sentence the student has to read twice.

## Layout

A single phone column. Content sits in a 16 px gutter on both sides, under the safe-area insets (`env(safe-area-inset-top/bottom)`), with a fixed five-tab bar at the bottom. Cards stack with 8 to 16 px gaps and carry 16 px of padding. Bottom sheets float inside the gutter, 12 px above the safe area. While the keyboard is open, the tab bar and the glance dock hide.

The landing is a fixed full-screen stage. The portal fills the top half; the dock (LAR's line plus the sign-in card) is pinned to the bottom, 12 px above the safe area. When the card is up, the camera pulls back and lifts the portal (lift 0.2 of the height, 16.5 world units across); once signed in it moves in and comes down to meet Step through (lift 0.08, 12.5 units), easing 8% of the way each frame. A 64 px band under the status bar fades to Night so motes never cross the clock or the wordmark.

### The art pixel grid
One art pixel is 3 CSS px, for the portal and for LAR alike. The 3D portal renders into a target one third of the screen's size and scales up with nearest-neighbour filtering (half-float, so the deepest purples do not round to grey); the no-WebGL fallback draws the same frame flat at the same pixel. Motes are one art pixel each. Pixel icons are 12 by 12 grids drawn as SVG rects with crisp edges, at 18, 22 or 24 px.

## Elevation & Depth

The app is flat and tonal. Depth comes from the card gradient (card-2 to card) and a 1 px inset hairline (`inset 0 0 0 1px` edge), which is on 33 surfaces. A soft floating shadow (`0 10px 30px`, black at 0.35 on Night) is reserved for things that float over content. The tab bar is the only glass: 86% ground with a 16 px backdrop blur and a 1 px top edge.

Pixel surfaces use bevels instead of shadows: a lit top edge and a dark bottom edge drawn as inset box-shadows, 2 to 3 px deep. The gold button has a 3 px Gold Shade lip at the bottom that flips to the top when pressed, with a 1 px drop.

### Shadow Vocabulary
- **Hairline** (`box-shadow: inset 0 0 0 1px var(--edge)`): every card and quiet control.
- **Float** (`box-shadow: var(--shadow)`; `0 10px 30px rgba(0,0,0,0.35)` on Night): surfaces that hover over content.
- **Dock lift** (`filter: drop-shadow(0 -10px 30px rgb(0 0 0 / 0.5))`): the landing dock, cast upward onto the portal.
- **Stone drop** (`filter: drop-shadow(0 6px 8px rgb(0 0 0 / 0.5))`): the floating stones.
- **Obsidian bevel** (`inset 0 3px 0 #5a3a6c, inset 0 -3px 0 #060307`): stones; LAR's slab uses 2 px with #3a2446 on top.
- **Gold lip** (`inset 0 -3px 0 #b87a10`, pressed `inset 0 3px 0 #b87a10`): gold pixel buttons.

### Named Rules
**The Shadow on the Parent Rule.** A clip-path cuts its own box-shadow off. Stepped shapes get their shadow as a `drop-shadow` filter on an unclipped wrapper.

## Shapes

Two corner languages, by register. Pixel surfaces (cards, sheets, the problem card, the landing's slabs, fields and buttons) have stepped corners cut with clip-path, two steps deep: 3 px steps by default and 4 px on cards and sheets, so they read clean at arm's length and pixel up close. Landing fields have square corners. Inside the app, controls (buttons, inputs, selects, list rows, skeleton bars) use soft radii: 10 px for controls and 12 px for rows and segmented controls. Round shapes appear only for LAR's ground shadow and status dots.

The portal's own geometry is the brand's: an 8 by 11 block frame, two blocks thick, built from pentominoes, with a 4 by 7 opening. LAR's ears are the frame's stepped corner blocks.

## Components

### Buttons
- **Portal button** (Sign in, Step through): solid gold, Burnt Ink text, Montserrat 700 at body size, 50 px tall, 4 px stepped corners, the gold lip. Step through is at least 220 px wide with 28 px side padding. Focus draws a 3 px Gold Light inner ring; pressed flips the lip and drops 1 px; disabled is 0.7 opacity.
- **Primary (app):** gold on on-gold, Montserrat 700, 44 px tall (36 px in compact cards), 10 px radius.
- **Ghost (app):** Sunk fill with the hairline, Ink text, same shape.
- **Danger:** bad fill with white text.
- **Text link:** the landing's demo link, gold at 0.85, underlined 3 px below.

### Cards / Containers
- **Corner Style:** stepped, 4 px steps.
- **Background:** card-2 to card gradient; the sign-in card is Portal Card with a gold hairline at 0.16 alpha.
- **Shadow Strategy:** hairline only; Float for overlays.
- **Internal Padding:** 16 px (18 by 16 px for sheets).

### Inputs / Fields
- **Landing:** 46 px tall, square, Night fill, a 1 px white hairline at 0.1, white text, placeholders at 0.58 alpha, gold caret. Focus is a 2 px gold inner ring. An empty date field shows a "mm / dd / yyyy" hint.
- **App:** sunk or card fill with the hairline, 10 px radius, 16 px minimum text.

### Navigation
- **Tab bar:** five equal columns (Today, Schedule, Grades, Study, You), each a 22 px pixel icon over a Montserrat 600 label. Idle is ink-3. Active turns the label and the icon's accent pixels gold, and the icon hops 3 px in three steps (0.35 s). Selecting a tab buzzes `select`.

### The pentomino portal (signature)
Twelve pentominoes in ten shapes (P and Y twice) fill the 60-cell ring, landing bottom-up: V, P, T, Z, N, L, Y, I, Y, F, P, U. Each piece is its own shade of obsidian (tinted 0, 22, 10, 30, 5 or 16% toward obsidian-hi) with a bevel only on the edges that do not touch its own blocks, so each piece reads as one joined shape, plus four seeded purple flecks per block that flare as it locks. The blocks are glossy (roughness 0.32, clearcoat 0.7). The opening holds two stencil-masked swirl layers, front and back, for depth; the swirl has three arms winding into the core, a rim falling into shadow, and the shipped five-tone Bayer dither. The frame stands on a 5 by 3 platform of brown slabs (#3a2c27, #33261f, #41302a, #2e231e, centre #5a3f2c). Light: violet ambient (#3a2440), a violet rim (#8663a8), a warm key (#f4e8d6), a lilac front (#b8a8ff), and a gold point light (#cca128) from the swirl. 56 gold motes drift upward. Dragging sways the camera up to 10 degrees, which eases back on release; at rest it orbits 6 degrees on a slow sine.

### Stones
Three obsidian slabs that LAR pulls out of the swirl: Schedule, Grades, Study. Each is a 18 px pixel icon with a gold accent over a Pixelify label, with 3 px stepped corners, the obsidian bevel, flecks, and maroon light on the side that faces the portal, in three bands (0.34, 0.22, 0.12 alpha). They bob gently unless the student is typing.

### LAR
The Lakbay-Aral Robot, 26 by 23 art pixels: an obsidian pebble lit from the top left in four tones with ordered dither, stepped block ears, a dark visor with gold eyes, a belly window with a live 6 by 5 swirl, a gold spark antenna, two floating mitts, a small orbiting portal cube, and a magenta rim light on his right edge so he reads on dark scenes. He is drawn as separate canvases so the parts move smoothly between whole pixels.

- **Palette:** outline #1a0f20; body #2c1c3a, #43295a, #5f3f7e, #8663a8, #b996d8; visor #140b1b with rim #2d1d3c; gold #f5b227 and #b87a10; highlight #fff6dc; blush #ff7a9c; mouth #7a1128; belly frame #24162e; #5d3f78; rim light #e27bd0; cube core #c2403a.
- **Moods:** open (blinks for about a tenth of a second every 2.9 to 3.7 s), blink, happy, wow, wink, focus. On the landing: open at rest, focus while typing or signing in, wow on an error, happy once signed in.
- **Gestures:** idle, wave, point, reach, thumbs. Reach while the stones come out, wave on arrival and at the hub.
- **Speech:** LAR talks through a 3 px stepped obsidian slab, his name in gold Pixelify, his line in light Taglish ("Hi, I'm LAR...", "Ayos! Your schedule and grades are in.", "Welcome back, iskolar. Tara?").

### Isko
The 14 by 20 pixel student, drawn as SVG rects, waving on a slow stepped loop and standing still under Reduce Motion. He fronts error cards and empty states. He belongs to the user's own redesign.

### Motion
Interface motion uses one ease, `cubic-bezier(0.22, 1, 0.36, 1)`: the landing dock rises 40 px over 0.7 s, sheets rise over 0.35 s, the wordmark fades in over 0.6 s, and leaving drops dock and wordmark 16 px over 0.25 s ease-in. Pixel motion uses `steps()`: the tab hop, skeleton shimmer (1.4 s, 8 steps), Isko's wave, the campus strip.

The landing is a pure function of time (`landingAt(t)` in `landing.ts`). A first visit runs:
1. **Dark**, 0.4 s.
2. **Assembling**, 2.66 s: a piece starts falling every 0.19 s and takes 0.42 s to lock (a stiff spring, dropping 9 blocks with a tumble), then a 0.15 s settle. The camera starts wide and low and settles in.
3. **Igniting**, 0.7 s: the swirl lights from the core outward, with a gold-white flash near the end.
4. **Arrival**, 1.0 s: LAR rises out of the opening, spinning 540 degrees and growing from 0.15 to full size.
5. **Glimpse**, 0.7 s: the three stones come out, staggered 0.12 s.
6. **Rest**, from 5.46 s: the wordmark and the dock appear.
7. **Stepping**, 1.1 s from Step through: the camera dives into the swirl (eased in, field of view 35 to 80 degrees), the art pixel grows from 3 to 24 px, the swirl spins up to nine times faster and flashes, then the app lands on Today.

A returning student skips the build: dark 0.2 s, igniting 0.5 s, arrival 0.8 s, glimpse 0.5 s, resting at 2.0 s.

**Reduce Motion.** A global rule clamps every CSS animation and transition to 0.01 ms. The landing timeline has no segments, so it opens at rest with the frame standing and the swirl lit. LAR holds still and stops blinking, Isko stands, the skeleton stops shimmering, confetti is skipped, and the campus strip redraws one still frame a minute.

### Haptics
Eight verbs, all silent when haptics are off in You or there is no engine, and two buzzes within 35 ms collapse into one:
- **select** (selection): moving between tabs, days, views or options.
- **tick** (rigid impact): a crisp change; on the landing, each pentomino locking.
- **press** (medium impact): a long press opening its actions.
- **pull** (soft impact): pull-to-sync crossing its line.
- **release** (light impact): letting go of a pull; pressing Step through.
- **done** (success): something landed; the swirl igniting, a sign-in.
- **warn** (warning): a stalled sync, offline.
- **fail** (error): a failed sync or sign-in, a wrong answer.

## Do's and Don'ts

### Do:
- **Do** read colour roles (`var(--gold)`, `var(--card)`, `var(--ink-3)`) on every app screen so all rooms work.
- **Do** size every art element on the 3 px art pixel, with `image-rendering: pixelated` or `shape-rendering: crispEdges`.
- **Do** write every font size as `min(<px / 17>rem, <cap>px)`, capping headings near 1.3 times and body near 1.8 times.
- **Do** cut pixel surfaces with stepped corners (3 px, or 4 px on cards and sheets) and put their shadow on an unclipped parent.
- **Do** use `steps()` for pixel motion and the shared ease for interface motion, and give every animation a Reduce Motion resting state.
- **Do** pair each meaningful change with its haptic verb from `haptics.ts`.
- **Do** say plainly where login happens that the login stays on the phone and the app only talks to PUP SIS.

### Don't:
- **Don't** use the PUP seal or wordmark, or anything that implies the app is official. Maroon, gold and the plain name "PUP SIS" are fine.
- **Don't** put a logo over a form for sign-in; the portal and LAR open the app.
- **Don't** let the pixel world slow a glance: no art in front of the next class, a grade or a due date.
- **Don't** add generic effects (glows, gradients, particles) that only decorate; the motes and the swirl exist because the portal is the brand.
- **Don't** use the swirl ramp outside a portal opening.
- **Don't** set headings, buttons or long sentences in Pixelify Sans.
- **Don't** redesign Isko unasked.
- **Don't** invent user counts, ratings, testimonials or press.
- **Don't** introduce a second accent hue for actions; gold is the only one.
