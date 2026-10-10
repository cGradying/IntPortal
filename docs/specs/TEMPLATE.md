# NNN Title

**Status:** draft | approved | building | shipped

## What changes for the student

One or two plain sentences. Who notices, and what is different on their phone.

## Direction and references

The look or behaviour being aimed at, with sources. Link files in `reference/`; third-party images are named, not committed.

## Keep

What exists today and must survive this change, one line each.

## Behaviour

Numbered criteria. Each is one observable fact that a test or a screenshot can confirm.

- **C1.** …
- **C2.** …

## Copy

Every string the student reads, exactly as written. Follow `PRODUCT.md` and `DESIGN.md`.

## Data shape

The types and fields this touches, with the file they live in.

## Errors

Each failure the student can hit, what they see, and what they can do next.

## Motion and Reduce Motion

Durations, frame rates and haptics. What Reduce Motion shows instead.

## Accessibility

Labels, focus order, touch sizes, contrast, Dynamic Type.

## Out of scope

What this spec deliberately does not decide.

## Test map

| Criterion | Check |
|---|---|
| C1 | `cargo test …` / `vitest …` / screenshot on the role's simulator |

## Open questions

Anything the user still has to answer. A spec with open questions cannot move to `approved`.
