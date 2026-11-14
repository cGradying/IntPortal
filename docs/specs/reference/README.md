# Spec references

## In git

- `prototypes/portal-v8.html`: the visual reference for the tile portal. Open it in a browser. It shows forming, connecting and open states and both themes (SIS, Mabini placeholder). It is a sketch, not production code; the production renderer is Rust/WASM ([ADR 0004](../../adr/0004-landing-renders-in-rust-wasm-tiles.md)).

- `prototypes/reference-sheet.html`: the look in one sheet. It mixes the tile portal's minimalism, the calm app (`DESIGN.md`) and the IntPortal board's pixel art: rules, colour, type, the tile, a pixel art library drawn solid or as tiles, sign-in and Today mocks, and proposals for bringing more board art into the app. It embeds `static/tiles.wasm` so the portal it shows is the app's own renderer; rebuild it after changing `crates/intportal-tiles`. Shared as a private claude.ai artifact.

- `prototypes/lar-sheet.html`: LAR's sprite sheet. Every state at 2, 4 and 8 times, the fire spawn and every state in each university's colours, a loop through the state changes, LAR flying by a tile portal, and each portal's palette. Its script is the app's own `src/lib/lar/sprite.ts`, inlined by `node docs/specs/reference/prototypes/build-lar-sheet.mjs` from `lar-sheet.src.html`; rebuild it after changing the sprite.

## Mockup index

Every mockup a spec was decided from is kept in `prototypes/`. Open the `.html` file in a browser. A `.src.html` file and a folder of the same name are that page's sources; the `build-*.mjs` script beside them inlines the app's own sprite code and writes the `.html`.

| Mockup | Date | What it decided | Specs |
|---|---|---|---|
| `portal-v8.html` | 2026-10-11 | The tile portal: flat tiles with gaps, the two-way build, the stage reactions | 010, 011 |
| `reference-sheet.html` | 2026-10-15 | The look in one sheet: six rules, colour, type, the tile, the pixel art library | 010, 011, 012, 044, 045 |
| `lar-sheet.html` | 2026-10-15 | LAR's sprite: every state, the fire spawn, each school's colours | 010 C18 |
| `mockups.html` | 2026-11-05 | Look rounds one to seven: the dive, the night ground, Pixel-bridged type, Week and Day, the done run | 010 C26 on, 040, 044, 045 |
| `study-you.html` | 2026-11-05 | Study tiles, the note editor, You on one screen, the theme maker | 046, 047 |
| `lar-window.html` | 2026-11-09 | Round three: the launch hello, LAR's window, the deadline adder, Study tiles | 010 C35, 041 C10, 046 |
| `lar-chat.html` | 2026-11-10 | Round four: LAR's chat, the sky header, the step trace | 048 |

A mockup that no spec cites and a newer one replaces is deleted, not kept beside it. Drafts and previews stay out of git.

## Local only (`private/`, ignored by git)

`private/` holds things that must not be committed:

- Third-party art references. The look follows three of them; they are named here, not stored:
  - a butterfly beside its dot-matrix twin (sent by the user);
  - earbuds drawn as cross-stitch (Pinterest pin 1829656095125499);
  - a still from Nothing's Playground launch film (Pinterest pin 2111131073843923).
- Raw SIS and Mabini captures (screenshots, saved HTML) used to fill [000-sis-data-map](../000-sis-data-map.md).

Check with `git check-ignore docs/specs/reference/private/x`; it must print the path.

## Capturing a SIS or Mabini page

1. Sign in yourself, on your own account only. Nobody else types or stores your password.
2. Save the page's HTML or take a screenshot of each screen the app might read.
3. Redact before anything leaves `private/`: name, student number, birthdate, grades, photo, faculty names, and any token or cookie in the markup.
4. Describe what you saw in the data map (field label, example shape such as `2026-00000-MN-0`), never the real value.
5. Commit the description, never the capture.
