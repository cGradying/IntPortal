---
name: PUPSISPortal
description: A native student portal for PUP's SIS8 — Liquid Glass shell, six switchable theme "rooms," a pixel-dither texture, and serif+mono type doing the work chrome usually does.
colors:
  maroon: "#7A1128"
  gold: "#C9A227"
  paper-top: "#FCFBFA"
  paper-bottom: "#F2EDEC"
  grid-line: "rgba(0,0,0,0.08)"
  subject-maroon: "#7A1128"
  subject-rust: "#B13E34"
  subject-gold: "#A37314"
  subject-plum: "#5C315F"
  subject-forest: "#2E5A4F"
  subject-slate: "#3F517A"
typography:
  screenTitle:
    fontFamily: "New York, Georgia, serif"
    fontSize: "22pt"
    fontWeight: 600
  detailTitle:
    fontFamily: "New York, Georgia, serif"
    fontSize: "20pt"
    fontWeight: 600
  blockCode:
    fontFamily: "New York, Georgia, serif"
    fontSize: "15pt"
    fontWeight: 600
  body:
    fontFamily: "SF Pro Text, -apple-system, sans-serif"
    fontSize: "16pt"
    fontWeight: 400
  dayName:
    fontFamily: "SF Pro Text, -apple-system, sans-serif"
    fontSize: "12pt"
    fontWeight: 600
  gutter:
    fontFamily: "SF Mono, ui-monospace, monospace"
    fontSize: "11pt"
    fontWeight: 400
  meta:
    fontFamily: "SF Mono, ui-monospace, monospace"
    fontSize: "12pt"
    fontWeight: 400
rounded:
  xs: "4pt"
  sm: "8pt"
  md: "12pt"
  lg: "16pt"
  xl: "20pt"
spacing:
  xs: "4pt"
  sm: "8pt"
  md: "12pt"
  lg: "16pt"
  xl: "24pt"
  xxl: "32pt"
components:
  button-primary:
    backgroundColor: "{colors.maroon}"
    textColor: "#FFFFFF"
    rounded: "{rounded.md}"
    padding: "6pt 14pt"
  nav-pill:
    backgroundColor: "rgba(255,255,255,0.5)"
    rounded: "{rounded.lg}"
    padding: "6pt"
  class-block:
    backgroundColor: "{colors.subject-maroon}"
    textColor: "#FFFFFF"
    typography: "{typography.blockCode}"
    rounded: "{rounded.xs}"
    padding: "8pt 10pt"
---

# Design System: PUPSISPortal

## Overview

**Creative North Star: "The Six Rooms"**

PUPSISPortal isn't one look — it's six fully-realized rooms (PUP Maroon, Ivory, Astra Moon, Sakura, Monochrome, Matrix) a student picks between in Settings, all built on the same Liquid Glass macOS shell, the same week grid, the same retro pixel-dither texture. The personality isn't in any one palette; it's in the fact that switching rooms never touches structure, only mood — the app underneath stays exactly as legible whether it's institutional maroon-on-paper at 8am or phosphor-green terminal glow at midnight.

The voice across every room is restrained, precise, and quietly textured — not a glossy SaaS dashboard, not flat same-everywhere Material Design. Liquid Glass is spent deliberately: it's chrome (the nav island, panels) almost everywhere, and emphasis exactly once — the now-line's glass lozenge is the one place in the app tint carries meaning instead of decorating. The pixel-dither fill (an ordered Bayer 4×4 pattern, drawn as real squares, not a gradient) is the signature texture: it shows up wherever something needs to read as "finished," "empty," or "arriving" rather than just present. Serif (New York) carries course codes and titles like an editorial byline; monospace (SF Mono) carries anything that must not reflow — times, metadata, the gutter. Restraint is the actual personality here, not an absence of one.

**Key Characteristics:**
- Six named, equally-supported theme "rooms," not a light/dark toggle with one brand color
- Liquid Glass (macOS 26) for chrome, one deliberate tint exception (the now-line) for emphasis
- A hand-drawn Bayer-dither texture as the recurring "this state is different" signal, never pure decoration
- Serif for identity/titles, monospace for anything numeric or positional, sans for body
- Every animation routes through one named vocabulary (`Motion` enum) and honors Reduce Motion by returning `nil`

## Colors

Six palettes, each a complete `Palette` (accent, secondary, canvas gradient, grid line, online-class strip, six subject colors) — switching rooms swaps the whole struct, never individual tokens. **PUP Maroon** is canonical here (PUP's own institutional maroon+gold, and the light-mode default under "Match System"); the other five are fully-supported alternates a student is as likely to be living in.

### Primary
- **Maroon** (#7A1128): the accent — PUP's own maroon. Carries the now-line, primary buttons, the default subject-1 color. Used once per screen as emphasis, never as a flood.

### Secondary
- **Gold** (#C9A227): PUP's paired institutional color. Carries the online-class strip and secondary accents where maroon would be too heavy.

### Neutral
- **Warm Paper** (#FCFBFA → #F2EDEC): the canvas wash, a slow top-to-bottom gradient so Liquid Glass has something with texture to bend, not a flat fill that reads as a grey box.
- **Ink Grid** (rgba(0,0,0,0.08)): the week grid's hairlines — deliberately faint, a hierarchy signal, not a border.

### Subject Palette
Six deterministically-assigned colors per class, seeded from the subject code's character sum (never `Hashable` — that reseeds every process launch and would repaint every class a different color each run):
- **Maroon** (#7A1128) · **Rust** (#B13E34) · **Gold** (#A37314) · **Plum** (#5C315F) · **Forest** (#2E5A4F) · **Slate** (#3F517A)

### Named Rules
**The One Tint Rule.** The accent color has exactly one job across the whole app: marking the present moment on the now-line. Buttons, chrome, and panels lean on Liquid Glass's own material, not a flood of brand color — a tint that showed up everywhere would stop meaning "now."

### The Other Five Rooms
- **Ivory** — ink navy (#343C51) on warm cream paper (#FDFBF6 → #F6F2EA), gold-brown secondary (#9E8D66). An editorial light room, quieter than Maroon: earthy jewel-tone subjects instead of maroon-and-gold.
- **Astra Moon** — emerald (#10B981) on deep navy (#0E1525 → #060C18), the dark-mode default under "Match System." The room most associated with late-night notes/quiz study.
- **Sakura** — hot pink (#E0417E) on warm blush paper (#FFF7FA → #FCE9F0), dusty rose secondary (#C98FA6).
- **Monochrome** — near-black (#111111) on white (#FFFFFF → #F2F2F2), mid-gray secondary (#808080). No hue at all; subjects read apart by lightness alone.
- **Matrix** — phosphor green (#00FF41) on near-black (#0D0F0D → #000000), dim-green secondary (#008F11). A terminal room.

## Typography

**Display/Title Font:** New York (`.serif` design), with Georgia/system-serif fallback
**Body Font:** SF Pro (system default)
**Label/Mono Font:** SF Mono (`.monospaced` design)

**Character:** Serif carries identity — a course code set in New York reads as the anchor of a schedule block, not another bolded caption. Monospace is functional, not decorative: it's reserved for anything whose width must not reshuffle (`9AM` next to `12PM` in the same column) or that's genuinely metadata.

### Hierarchy
- **Screen Title** (semibold, 22pt/title2, serif): top-level screen headers.
- **Detail Title** (semibold, 20pt/title3, serif): panel and popover headers.
- **Block Code** (semibold, 15pt/subheadline, serif): the subject code on a class block — the anchor of the whole card.
- **Day Name** (semibold, 12pt/caption, sans): weekday headers, the nav island's segment labels.
- **Body** (regular, 16pt/callout, sans): detail body copy.
- **Gutter/Meta** (regular, 11–12pt/caption2, mono): the time gutter, block times, metadata rows — anything positional or numeric.
- **Now Clock** (semibold, 11pt/caption2, mono): the live clock in the now-line's glass lozenge.

### Named Rules
**The No-Reflow Rule.** Anything showing a time or a number that updates live (the gutter, block times, the now-line clock) is monospace, full stop — a proportional face reflowing `9AM` against `12PM` reads as jitter, not information.

## Layout

The week grid is the spatial anchor: a fixed gutter column (time labels, monospace) plus seven day columns, blocks positioned by real minute-offset math, not a CSS-grid-style even split. A floating nav island — never a sidebar or tab bar — is the only persistent chrome; it lives centered at launch (a home launcher) and glides to the top when a destination opens, expanding on hover to reveal per-screen controls (Schedule's week nav, Notebook's Vault/Quizzes toggle) rather than each screen drawing its own toolbar. Overlapping blocks get side-by-side lanes computed from real interval overlap, never stacked or clipped.

## Elevation & Depth

Liquid Glass (macOS 26; `.regularMaterial` fallback below it) is the material system, not shadows — there is no drop-shadow vocabulary in this app. Depth reads through translucency and blur (the nav island, panels, popovers), and through the dither texture's density (a "this is finished/empty" veil reads as eroded, not just dimmed). One surface breaks the "chrome only" rule on purpose: the now-line's lozenge is tinted glass, because it's the one place emphasis is the whole point.

### Named Rules
**The Chrome-Not-Decoration Rule.** Glass renders UI structure (the island, panels, popovers) — it is never applied to content itself for a "glossy" look. If a surface isn't chrome, it doesn't get glass.

## Shapes

Rounded rectangles throughout, on a tight radius scale: `4pt` for small marks (a block's colored strip corner), `8pt` for the most common case (rows, list items, small controls — the single most-used radius in the codebase), `12pt` for cards and popovers, `16pt` for the nav island and glass panels, `20pt` reserved for the most prominent surfaces. No sharp corners anywhere in the shipped UI; no radius above 20pt (nothing pretends to be a pill-shaped hero element except the nav island's segments and glass capsules, which use true `Capsule()` shapes, not a large radius approximation).

## Components

### Buttons
- **Shape:** rounded rectangle, `{rounded.md}` (12pt), or `Capsule()` for glass/pill buttons.
- **Primary:** `.glassProminentButton()` on macOS 26 (native `.glassProminent` style), `.borderedProminent` fallback below — never a custom-colored fill competing with the system's own glass.
- **Secondary/Plain:** `.glassButton()` / `.bordered`, or `.buttonStyle(.plain)` for inline/borderless actions (tab close buttons, row actions).
- **Hover/Focus:** native system feedback via the glass button styles; no custom hover-color overrides.

### Cards / Containers
- **Corner Style:** `{rounded.lg}` (16pt) for glass panels and popovers; `{rounded.md}`–`{rounded.xs}` (12pt–4pt) for smaller content cards and blocks, scaling down with the surface's own size.
- **Background:** `glassPanel(in:)` (Liquid Glass / `.regularMaterial`) for chrome; `.quaternary.opacity(0.4)` for plain content cards (list rows, quiz cards) that don't need to read as floating chrome.
- **Shadow Strategy:** none — see Elevation & Depth.
- **Internal Padding:** `{spacing.lg}`–`{spacing.xxl}` (16–32pt) for full cards; `{spacing.sm}`–`{spacing.md}` (8–12pt) for compact rows.

### Navigation — the Nav Island
- **Style:** one floating glass capsule/pill, not a sidebar or tab bar. Three states: **home** (centered launcher, date + next-class glance + destination segments), **compact pill** (top, idle — icon + label + glance), **expanded bar** (top, hovered — full segment row + the active screen's own controls).
- **Selection:** a `matchedGeometryEffect`-driven capsule highlight slides between segments rather than each segment redrawing its own background.
- **Motion:** the home→top flight and collapsed↔expanded morph both use `Motion.island` (`.spring(response: 0.42, dampingFraction: 0.82)`), so the whole nav element reads as one continuous move, never a snap-cut.

### The Now-Line (Signature Component)
A hairline in the accent color drawn straight across the week grid at the current minute, with a tinted-glass lozenge in the gutter carrying a live monospace clock. The one place per app that spends the accent as a tint and Liquid Glass as emphasis rather than chrome — every other surface stays quiet specifically so this one reads as "now."

### The Pixel-Dither Fill (Signature Component)
An ordered Bayer 4×4 dither, drawn as individual squares (never a gradient or bitmap image) via a custom `Shape`. Three ramps: `topDown` (a fading chrome-band edge), `flat(density)` (a uniform veil over finished/empty content), and `wave` (two drifting sine gradients, for a "light on water" ambient effect). Always has a job — a fade, a veil, an ambient signal — never sprinkled as pure decoration.

### Quiz Feedback (Signature Component)
Small procedural pixel-art badges (`PixelBadge`), drawn square-by-square on a `Canvas` from a hand-authored bitmap grid — no image assets. Correct/incorrect/streak states fill in over ~150ms, a deliberately blocky, retro-game-adjacent counterpoint to the glass shell everywhere else. Card transitions between quiz questions use a settle-in ease (blur → sharp, slight drop, opacity in, matching the note editor's own AI-text-reveal timing curve) plus one accent-tinted sweep beam crossing once — never a spinning or repeating effect, and it disappears entirely under Reduce Motion.

## Do's and Don'ts

### Do:
- **Do** treat all six theme rooms as equally real — a new component's spec should read correctly in Matrix (near-black, phosphor green) as much as in PUP Maroon.
- **Do** route every animation through the `Motion` enum and make sure it returns `nil`/degrades under Reduce Motion — this is checked in every animated view already shipped, not optional per-component.
- **Do** reserve monospace for anything numeric/positional that must not reflow.
- **Do** give the dither texture a job (fade, veil, ambient signal) before using it — it's not a background pattern.

### Don't:
- **Don't** add a drop-shadow vocabulary. Depth is glass + dither, not shadows.
- **Don't** spend the accent tint on more than the now-line without a comparably strong reason — its rarity is what makes it read as "now."
- **Don't** hardcode a hex color into a new component. Every color comes from `Environment(\.palette)` so it's correct across all six rooms automatically.
- **Don't** seed a deterministic color (subject colors, any future per-item color) with `Hashable` — it reseeds per process launch and repaints on every relaunch. Use the character-sum seed pattern `Theme.swift` already establishes.
