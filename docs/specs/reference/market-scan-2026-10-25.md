# Market scan: what shipping apps do (2026-10-25)

Step 1 of [PLAN-dive-environment](../PLAN-dive-environment.md). This was gathered by a background research agent from the web, and every claim carries the link it came from. Anything without a primary source is marked **unverified**. Some page text came through a summarising fetcher, so treat details as second-hand.

## Balatro (mobile)
- **Award.** Apple Design Award 2025, Delight and Fun ([Apple Newsroom](https://www.apple.com/newsroom/2025/06/apple-unveils-winners-and-finalists-of-the-2025-apple-design-awards/)).
- **Look and stack.** Built on LÖVE/Lua. The feel is described as "a wobbling, liquid background, CRT curvature, card tilt, screen shake, and pitch-bending chip ticks" ([DEV Community](https://dev.to/wlz/why-balatro-bet-on-love-and-lua-the-niche-stack-behind-a-5-million-copy-poker-roguelike-4ck7)).
- **Scoring sequence.** Numbers tick up with escalating sound, each card "steps forward in turn", and the multiplier catches fire and burns hotter as it grows. The score preview is hidden on purpose ([GMTK](https://gmtk.substack.com/p/balatros-cursed-design-problem)).
- **Blog numbers, not game data.** One writer's CSS reconstruction gives:
  - hover lift of 12px at scale 1.05;
  - a digit roll of 0.4s with a 50ms stagger;
  - shake tiers of ±2–4, ±4 and ±8px.
  It is not the game's code ([guide](https://blakecrosley.com/guides/design/balatro)). The pitch scale and the idle-sway values are unverified.
- **Compulsion versus feel.** This split is our own inference, not from a source.
  - **Pure feel:** count-up, rising pitch, flame, shake, hover lift and the living background.
  - **Compulsion-adjacent:** the hidden preview, slot suspense and "one more run".
  - PEGI first rated the game 18+ for gambling imagery, then lowered it to 12+ ([Wikipedia](https://en.wikipedia.org/wiki/Balatro)).

## Duolingo
- **Type.** Feather Bold for headlines (custom, by Fontsmith) and DIN Next Rounded for UI ([Fonts In Use](https://fontsinuse.com/uses/59497/duolingo-app)).
- **Streak milestones.** These were treated "like power-ups". Several rough animation passes were made for rhythm, and concepts that did not scale across cultures were dropped ([Duolingo blog](https://blog.duolingo.com/streak-milestone-design-animation)). The feedback stacks sound, haptics and animation (unverified). This is a retention-driven system, so a caution applies.

## Gentler Streak
- **Award.** Apple Design Award 2024, Social Impact.
- **Approach.** "Northern star is simplicity". Soft transitions, supportive copy, familiar iOS conventions, and "cute surprises" kept to icons and widgets. Stats are turned into plain-language status ([Sketch](https://sketch.com/blog/gentler-streak)).

## Things 3
- **Layout and colour.** Bold type and an open layout. Colour comes in "thoughtful splashes", and events take their calendar's colour ([MacStories](https://www.macstories.net/reviews/things-3-beauty-and-delight-in-a-task-manager/)).
- **Today.** Past events turn grey, and a separate This Evening section sits below.
- **Feedback.** Tapping a task pops it into a card, and long-press lifts it. Haptics fire only on pick-up, Magic Plus and pull-to-search (MacStories).

## Fantastical
- **Facts.** Views: DayTicker, day, week, month, quarter and year. Weather in every view, Calendar Sets and Focus Filters ([Flexibits](https://flexibits.com/fantastical)).
- **iOS 26.** Controls moved to the bottom with glass toolbars ([Flexibits blog](https://flexibits.com/blog/2025/09/apple-os-26-updates-starring-fantastical-4-1-and-cardhop-2-4/)).
- **Unverified.** Typeface, block shape, now-line and cancelled items.

## Structured
- **Facts.** A vertical timeline that shows free time between tasks, colour coding, icons and a black theme ([App Store](https://apps.apple.com/app/structured-daily-planner/id1499198946)).
- **Accessibility.** The listing claims support for Reduced Motion and Differentiate Without Color, plus a dyslexia font option.
- **Onboarding.** An 11-step flow that builds the first day ([ScreensDesign](https://screensdesign.com/showcase/structured-daily-planner)).

## Notion Calendar, Arc Search, Opal, Finch, Apple Invites
- **Notion Calendar:** command menu, database items overlaid on events, drag to edit ([Notion](https://www.notion.com/product/calendar)). Its visual details are unverified.
- **The other four:** no primary design sources were found.

## Takeaways for IntPortal
Ranked by fit with the rule "playful wraps the data; times, rooms and due dates stay calm and exact".
1. **Two-layer type.** A distinctive display face for headings and LAR's voice, and a neutral face with tabular numerals for times, rooms and dates. This is the Duolingo split.
2. **Colour is signal.** Use it only per course or for urgency, never as decoration. This follows Things' "splashes".
3. **Grey out finished classes.** The now-line then becomes a state change.
4. **Cute surprises in the margins.** LAR goes in empty states, onboarding and "all clear", never inside a class block.
5. **Pixel craft in the chrome, clean faces for times and rooms.** Balatro's CRT look works because it wraps a clear readout.
6. **Feedback scaled by weight.** Only the student's own actions get stacked cues: a deadline marked done gets a tick, a pop and one haptic. Ordinary taps get only a press state.
7. **Haptics with intent.** Only on direct manipulation and on completion.
8. **One celebration per milestone, not per tap.**
9. **Reduce Motion skips every wobble, shake and count-up.** Motion is never the only signal.
10. **Calendar.** Flat fills, pixel notches, a fixed now-line colour, and moved or cancelled shown by a label plus a pattern.
11. **Sound off by default.** Soft ticks only after the student opts in.
12. **A living environment.** A slow, low-contrast backdrop behind the data that stops under Reduce Motion.

**Anti-patterns:**
1. Streak guilt, hidden suspense and run loops.
2. Play on the data itself: no wobble, shake or glow on times, rooms or due dates.
3. Celebrating routine taps.
