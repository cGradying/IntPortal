#!/bin/sh
# Full film render (video only; audio is muxed afterwards). Logs to out/render.log.
cd "$(dirname "$0")/.."
exec npx remotion render src/index.ts Main out/v4-video.mp4 --log=info > out/render.log 2>&1
