---
name: IntPortal
description: A native student portal for PUP's SIS. You land in a void, step through a pixel portal, and arrive in the registrar's window — the SIS's own grammar (maroon menu field, breadcrumb header, record sheets, rubber stamps) rendered pixel-forward and calm.
colors:
  maroon: "#6D0E1F"
  maroon-deep: "#560A19"
  maroon-hover: "#7E1A2C"
  on-maroon: "#F7ECEC"
  on-maroon-2: "#DDB9BE"
  gold: "#C9A227"
  gold-ink: "#765806"
  gold-soft: "#F4E8C2"
  action: "#1B5DB8"
  action-hover: "#154C98"
  action-soft: "#E3ECF9"
  action-ink: "#1B4F99"
  ground: "#F4F2EF"
  sheet: "#FFFFFF"
  sunk: "#F7F5F2"
  line: "#E2DDD6"
  line-2: "#CBC3B9"
  ink: "#1C1517"
  ink-2: "#554C4F"
  ink-3: "#766C6F"
  good: "#1E7249"
  bad: "#B42318"
  void: "#07050A"
  obsidian: "#170B1A"
  obsidian-hi: "#34203F"
  swirl-0: "#170509"
  swirl-1: "#540A1C"
  swirl-2: "#941C30"
  swirl-3: "#CCA128"
  swirl-4: "#FAEBB3"
  subject-maroon: "#7A1128"
  subject-rust: "#B13E34"
  subject-gold: "#8F6410"
  subject-plum: "#5C315F"
  subject-forest: "#2E5A4F"
  subject-slate: "#3F517A"
typography:
  display:
    fontFamily: "Pixelify Sans, ui-monospace, monospace"
    fontWeight: 600
  body:
    fontFamily: "Source Sans 3, -apple-system, sans-serif"
    fontSize: "15pt"
    fontWeight: 400
  screenTitle:
    fontFamily: "Pixelify Sans"
    fontSize: "28pt"
    fontWeight: 700
  sheetLabel:
    fontFamily: "Pixelify Sans"
    fontSize: "14pt"
    fontWeight: 600
    letterSpacing: "0.06em"
    textTransform: uppercase
  code:
    fontFamily: "Pixelify Sans"
    fontSize: "18pt"
    fontWeight: 700
  numeric:
    fontFamily: "Pixelify Sans"
    fontSize: "16pt"
    fontWeight: 600
  stamp:
    fontFamily: "Pixelify Sans"
    fontSize: "11pt"
    fontWeight: 700
    letterSpacing: "0.12em"
    textTransform: uppercase
rounded:
  notch: "4pt stepped (2pt + 2pt)"
  window: "14pt"
spacing:
  xs: "4pt"
  sm: "8pt"
  md: "12pt"
  lg: "16pt"
  xl: "20pt"
  xxl: "28pt"
components:
  button-primary:
    backgroundColor: "{colors.action}"
    textColor: "#FFFFFF"
    typography: "{typography.display}"
    rounded: "{rounded.notch}"
    padding: "7pt 14pt"
  button-secondary:
    backgroundColor: "{colors.sheet}"
    border: "2pt {colors.line-2}"
    rounded: "{rounded.notch}"
  sheet:
    backgroundColor: "{colors.sheet}"
    border: "1pt {colors.line}"
    rounded: "{rounded.notch}"
  menu-field:
    backgroundColor: "{colors.maroon}"
    textColor: "{colors.on-maroon}"
  class-block:
    backgroundColor: "subject 13% over sheet"
    border: "2pt subject 45%"
    typography: "{typography.code}"
    rounded: "{rounded.notch}"
  stamp:
    border: "2pt currentColor"
    typography: "{typography.stamp}"
    rotation: "-3deg"
---

# Design System: IntPortal

Reference build: `docs/specs/prototypes/intportal-v2.html` (v3 adds the 3D moves once P3 lands) (open it in a browser; everything here
was measured from it). Surface specs: `docs/specs/`. This file replaces the "Six Rooms" system of
2026-08; that history is in git.

## Overview

**Creative North Star: "The Portal and the Registrar."**

Two worlds, one crossing. Outside is the **void**: near-black, drifting pixel motes, an obsidian
frame that assembles block by block where the student stands, and a maroon-to-gold dithered swirl.
Inside is the **registrar's window**: the PUP SIS portal's own grammar (a maroon menu field on the
left, a breadcrumb header, white record sheets, COR-style tables, rubber-stamp statuses) rendered
native, pixel-forward and calm. The crossing is the warp: the camera dives into the swirl, the
pixels grow, a gold-white flash, and the student is in.

The voice is **institutional, but yours**. It reads like the SIS because students already know how
to read the SIS; it feels like a game because studying should reward you. Pixel type carries
identity (titles, course codes, numbers, buttons). A clean humanist sans carries everything you
actually read (notes, descriptions, AI replies).

**Key characteristics**
- One maroon field (the sidebar) owns the left edge. Content lives on white sheets over a warm
  neutral ground.
- Pixel display type for identity, Source Sans 3 for reading. Never pixel type for paragraphs.
- Stepped 4pt pixel notches instead of rounded corners, everywhere except the window itself.
- One action color (SIS blue). Gold marks the present moment and stamps. Nothing else is tinted.
- Dither and 3D only where they carry information: free time, emptiness, sync state, due load,
  exam proximity, mastery.
- Every animation routes through `Motion` and disappears under Reduce Motion.

## Colors

Restrained strategy inside the app: neutrals plus one committed field (the maroon menu), one action
hue, one "now" hue. The void is its own single dark world.

### Registrar (light, default)
- **Maroon** `#6D0E1F`: the menu field. `maroon-deep` `#560A19` marks the active item,
  `maroon-hover` `#7E1A2C` the hover. Text on it is `on-maroon` / `on-maroon-2`.
- **Action blue** `#1B5DB8`: primary buttons, links, focus rings, selected rows. Borrowed straight
  from the SIS "Sign in" button. The only interactive hue.
- **Gold** `#C9A227`: the now-line, the today-column wash, stamps' vacant ink, the active menu icon,
  the swirl's bright band. `gold-ink` `#765806` when gold must be read as text.
- **Ground / sheet / sunk**: `#F4F2EF` window ground, `#FFFFFF` sheets, `#F7F5F2` sunken strips
  (table heads, free-time rows).
- **Lines**: `#E2DDD6` hairlines, `#CBC3B9` control borders.
- **Ink**: `#1C1517` / `#554C4F` / `#766C6F`. `ink-3` is the floor for readable text (≥ 4.5:1 on
  sheet).
- **Semantic**: good `#1E7249`, bad `#B42318`, with soft fills. Separate from the accent.

### Registrar Night (dark)
Same roles, retuned (never inverted): ground `#141112`, sheet `#1C1819`, maroon field `#35060F`,
action `#5B93F0`, gold `#DDB64E`, subjects lifted (`#D66A7E` `#E07D70` `#D5A544` `#B083B3` `#62AE94`
`#8398CD`). Values are in the prototype's dark blocks.

### The void (landing only)
`void #07050A → #12070E` gradient, obsidian `#170B1A` blocks with `#34203F` highlights and `#060307`
shadows, swirl ramp `#170509 → #540A1C → #941C30 → #CCA128 → #FAEBB3`, 5 steps, Bayer-dithered.

### Subject palette
Six deterministic subject colors, seeded from the code's character sum (never `Hashable`):
Maroon, Rust, Gold, Plum, Forest, Slate. Class blocks use the subject at 13% over the sheet with a
45% border; the course code is set in the full subject color.

### Theme rooms
`ThemeChoice.auto` maps to Registrar / Registrar Night. The other palettes in `Core/Theme.swift`
stay selectable, but each must now fill the new role set (menu field, action, gold, sheet, sunk,
ink ×3). A room that can't fill a role is removed, not approximated. See `07-settings.md`.

### Named rules
**The One Action Rule.** Blue means "you can do this." It never decorates.
**The Now Rule.** Gold marks the present (now-line, today column, "This week" line) and stamps.
It never marks importance or selection.
**No hex in views.** Every color comes from `\.palette`.

## Typography

- **Display:** Pixelify Sans (OFL, variable 400–700). Titles, course codes, numbers, buttons, sheet
  labels, stamps, the gutter, menu section heads.
- **Body:** Source Sans 3 (OFL, variable). Everything read in sentences.
- Both ship in `Resources/Fonts/` and register through `FontLibrary`. The user's font choice
  (Settings ▸ Appearance ▸ Font) now overrides **body only**; display stays Pixelify Sans because it
  is the identity.

| Role | Face | Size | Weight | Notes |
|---|---|---|---|---|
| screenTitle | Pixelify | 28 | 700 | balanced wrap |
| sheetLabel | Pixelify | 14 | 600 | uppercase, +0.06em |
| code | Pixelify | 18 (block 15) | 700 | subject color |
| numeric | Pixelify | 16 | 600 | times, counts, grades, GPA |
| gutter / meta | Pixelify | 11.5–13 | 500 | time gutter, dates |
| body | Source Sans 3 | 15 | 400 | notes, descriptions |
| secondary | Source Sans 3 | 13–14 | 400 | ink-2 / ink-3 |
| stamp | Pixelify | 11 (10 on blocks) | 700 | uppercase, +0.12em |
| GPA hero | Pixelify | 56 | 700 | Grades only |

**The No-Reflow Rule** still holds: anything live and numeric uses tabular figures.

## Layout

- **Window:** 236pt maroon sidebar + main column. Main = header (title, one-line context,
  breadcrumb "Student Module › Screen") + scrolling body with 28pt side padding.
- **Sidebar:** portal glyph + wordmark (click = back to the hub), menu in three groups (Main:
  Today, Schedule, Grades · Study: Notebook, Quizzes, Syllabus · System: Settings), footer with the
  student, campus chip and sync host. Replaces the nav island entirely.
- **Sheets:** content lives in sheets with a header strip (uppercase label left, meta right).
  Two-column screens split ~1.6 : 1 (main sheet : rail). Collapse to one column under 1080pt.
- **Spacing:** 4-point scale; 16–18pt between sheets, 12–16pt inside, more space above a heading
  than below it.

## Elevation & depth

Flat. Sheets separate by border and ground contrast, not shadow. Only floating things (IntAssis
chat, dialogs, popovers) take a soft shadow (`0 18 40 -16`). **Liquid Glass is retired from the
Registrar world**: no glass panels, no glass buttons. `GlassCompat` remains only if a system control
needs it. Depth that means something is drawn in 3D instead (see Signature components).

## Shapes

`PixelNotch`: a rectangle with 4pt stepped corners (2pt + 2pt), used for sheets, buttons, chips,
stamps, class blocks, the orb, inputs. No `RoundedRectangle` anywhere in the app content. The
window keeps its 14pt system corner. Borders are 2pt on controls, 1pt on sheets.

## Components

- **Buttons:** primary = action fill; secondary = sheet fill + 2pt `line-2` border; small = 4×10
  padding. Label in display face. Focus = inset 2pt action ring (outlines are clipped by the notch).
- **Segmented control:** sunken track, pressed segment = sheet fill + 1pt inset line.
- **Inputs / selects:** 2pt `line-2` border, notch, sheet fill; pixel chevron on selects.
- **Stamp:** display face, uppercase, 2pt border in `currentColor`, rotated −3°, ink-noise mask.
  In person = subject maroon, Online = action ink, Vacant = gold ink. Setting a status plays the
  **thunk** (scale 1.9 → 0.92 → 1, blur 2 → 0, 420ms).
- **Class block:** subject tint, notch, code + time + title (if ≥ 90pt tall), stamp bottom-right
  when not in person; vacant = 45° hatch.
- **Date tile:** maroon month strip + big day number, notch. Used in Due soon and Syllabus.
- **Pixel icons:** 12×12 bitmaps (`PixelIcon`), rendered at 12pt (inline) or 24pt (menu, orb) —
  integer scales only.
- **Empty state:** dithered blob + display title + one sentence + one action.
- **Job bar:** action-soft strip with a pixel progress bar, used for background AI jobs.

## Signature components

- **The portal** (`09-landing-portal.md`): obsidian frame, Metal swirl shader, platform, figure,
  motes, the warp.
- **Portal glyph** (sidebar): a 13×18 animated swirl; its speed shows sync activity, its presence is
  the way back to the hub.
- **Study map** (`11-study-upgrades.md`): isometric pixel tiles — subject regions, topic tiles lit by
  mastery, towers rising as an exam approaches, gold pips on mastered tiles.
- **Card stacks:** decks drawn as a 3D stack whose height is the due count; lifts on hover.
- **Flashcard flip:** real 3D Y-rotation, question → answer.
- **Dither with a job:** free-time rows, empty states, due-forecast bars. Never wallpaper.
- **Hub carousel** (`09`): portal frames on a ring you orbit with the arrow keys. The lit frame is
  PUP SIS labelled with your campus; dark frames are "Not connected yet". Encodes: where you can go.
- **Week turn** (`03`): paging Schedule turns the grid in 3D, left into the past, right into the
  future. Encodes: direction in time. Variant (cube or slab) is picked from prototype v3.
- **Depth push** (`01`): changing screens moves along the sidebar's order in Z, forward when you go
  down the menu, back when you go up. Encodes: where the screen sits in the menu. Variant (push or
  dive) is picked from prototype v3.
- **Sync ripple** (`01`): a refresh sends one pixel ring out from the portal glyph across the
  sheets, green on success, a red stutter on failure. Encodes: the sync result.
- **Deck fan-out** (`11`): opening a deck fans its due cards in 3D, then deals the first to center.
  Encodes: fan width = cards due.
- **Thinking cube** (`06`): the IntAssis orb turns into a spinning voxel cube while the model works.
  Encodes: waiting on the model.

## Motion

| Token | Use | Spec |
|---|---|---|
| `arrival` | screen enter | 320ms, ease-out-expo, 6pt rise |
| `thunk` | stamp set | 420ms, (.2,.9,.25,1) |
| `portalForm` | frame assembly | 24 blocks over 1.2s, each drops 1.6 blocks |
| `ignite` | swirl fade-in | 500ms |
| `warp` | dive | 950ms, zoom 1→12 (ease-in ^2.6), swirl speed ×9, pixel cell ×4, flash at 82% |
| `flip` | flashcard | 550ms (.3,.7,.2,1) |
| `pop` | matching pair | 350ms scale 1.12 |
| `sweep` | AI text reveal | 1.2s gold band |
| `orbit` | hub carousel step | spring, response 0.34, damping 0.86 |
| `turn` | Schedule week change | spring, response 0.42, damping 0.9 |
| `depthPush` | screen change | spring, response 0.3, damping 0.92, 24pt Z travel |
| `ripple` | sync result | 700ms linear ring, ease-out fade |
| `fan` | deck fan-out | spring, response 0.4, damping 0.8, 18ms per card |
| `think` | IntAssis waiting | 1.6s per voxel turn, linear, loops |

Reduce Motion: no zoom, no drops, static swirl frame, flash becomes a 200ms crossfade, stamps and
cards appear without motion.

### macOS 27 motion and depth

IntPortal takes macOS 27's feel without its glass.
- **Fast, interruptible springs.** Every transition is a spring that a new input can redirect
  mid-flight. Nothing waits for an animation to finish before accepting the next key.
- **Depth on floating layers only.** IntAssis, popovers, the hub and dialogs get a darkened 1pt
  outer edge and a 1pt bright top highlight over the soft shadow. Inline sheets stay flat.
- **One toolbar row per screen**, the same height and order on every screen.
- **Active window shadow.** The key window casts the system's stronger shadow; nothing custom.
- **Force reduced motion.** The in-app setting and the system setting both turn every token off.

## Do's and Don'ts

**Do**
- Read every screen as an SIS page first: title, breadcrumb, sheets, tables.
- Put identity in pixel type and reading in Source Sans.
- Give every 3D or dithered element a number it encodes.
- Keep the exact product copy (IntAssis, "Runs locally and can be wrong…", GPA, "Login now").

**Don't**
- Don't use pixel type for paragraphs, notes, or AI replies.
- Don't add glass, gradients-as-decoration, drop shadows on sheets, or rounded rectangles.
- Don't tint for emphasis: blue = action, gold = now/stamp, subject colors = subjects.
- Don't show PUP's seal or official marks; the app is unofficial and says so on the landing.
- Don't invent AI capabilities in UI copy; the tool list is in `06-assistant.md`.
