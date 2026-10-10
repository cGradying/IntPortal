# The landing renders in Rust/WASM tiles

The landing is a minimal grid of flat square tiles, drawn by a Rust crate compiled to WebAssembly into a canvas in software. It replaces the three.js scene (`src/lib/portal3d.ts`) and the pentomino frame (`src/lib/pentomino.ts`). LAR stays.

The scene is a pure function of time and state, so `cargo test` can check a frame (for example the tile colours at a given `t`) without a screen. The same crate can draw the sign-in morph into Today. The spec is [010-landing](../specs/010-landing.md).

Reasons: a flat tile grid needs no 3D engine, so three.js and its half-float render target go; the look is exactly specified, so it should be exactly testable; and it keeps the art logic in Rust beside the rest of the core, away from the Svelte layer.

Costs: a WASM build step in `pnpm build`, and a size and frame-rate budget measured on the iPhone 17e. If WASM fails to load, the landing falls back to a still image of the open portal and sign-in still works.
