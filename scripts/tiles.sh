#!/usr/bin/env bash
# Build the landing's tile portal (crates/intportal-tiles) to WebAssembly and
# put it where the web build serves it: static/tiles.wasm.
# One-time setup: rustup target add wasm32-unknown-unknown
set -euo pipefail
cd "$(dirname "$0")/.."
cargo build -q -p intportal-tiles --target wasm32-unknown-unknown --release
cp "${CARGO_TARGET_DIR:-target}/wasm32-unknown-unknown/release/intportal_tiles.wasm" static/tiles.wasm
