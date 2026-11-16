#!/usr/bin/env bash
# Makes the site's screens and loops from docs/images: WebP stills and H.264
# loops (a GIF is 5 to 10 times the bytes). The outputs are committed, so the
# site builds with Node alone (spec 051 C1). Run it after docs/images change.
set -euo pipefail
cd "$(dirname "$0")/.."
src=../docs/images
out=static/media
for f in today schedule grades talk; do
  cwebp -quiet -q 82 "$src/$f.png" -o "$out/$f.webp"
done
for f in dive done tabs; do
  ffmpeg -v error -y -i "$src/$f.gif" -movflags +faststart -pix_fmt yuv420p -vf "scale=trunc(iw/2)*2:trunc(ih/2)*2" -c:v libx264 -crf 24 -preset slow -an "$out/$f.mp4"
  ffmpeg -v error -y -i "$src/$f.gif" -frames:v 1 "$out/$f-poster.png"
  cwebp -quiet -q 82 "$out/$f-poster.png" -o "$out/$f-poster.webp"
  mv "$out/$f-poster.png" "${TMPDIR:-/tmp}/"
done
ls -lh "$out" | awk '{print $5, $9}'
