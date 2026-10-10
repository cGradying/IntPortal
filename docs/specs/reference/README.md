# Spec references

## In git

- `prototypes/portal-v8.html`: the visual reference for the tile portal. Open it in a browser. It shows forming, connecting and open states and both themes (SIS, Mabini placeholder). It is a sketch, not production code; the production renderer is Rust/WASM ([ADR 0004](../../adr/0004-landing-renders-in-rust-wasm-tiles.md)).

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
