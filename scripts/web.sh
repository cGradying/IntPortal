#!/usr/bin/env bash
# Builds Look around for any browser (spec 052) into the website at site/static/app:
# the tile portal and the core as WebAssembly, then the app's screens with a
# browser shell. The output is committed, so the website still builds with Node
# alone. Run it before a release, after the app changes.
set -euo pipefail
cd "$(dirname "$0")/.."
scripts/tiles.sh
# Build paths in panic messages would print the builder's home folder on the public site.
RUSTFLAGS="${RUSTFLAGS:-} --remap-path-prefix=$HOME=~" cargo build -q -p intportal-web --target wasm32-unknown-unknown --release
cp "${CARGO_TARGET_DIR:-target}/wasm32-unknown-unknown/release/intportal_web.wasm" static/intportal_web.wasm
# adapter-static empties site/static/app before it writes.
INTPORTAL_WEB=1 pnpm exec vite build >/tmp/intportal-web-build.log 2>&1 || { tail -30 /tmp/intportal-web-build.log; exit 1; }
du -sh site/static/app
