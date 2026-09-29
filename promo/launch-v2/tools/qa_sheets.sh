#!/usr/bin/env bash
# Contact sheets of a render, one tile per beat (0.4 s), 20 tiles per sheet.  usage: tools/qa_sheets.sh render.mp4 outdir
set -euo pipefail
in="${1:?render.mp4}"; out="${2:-qa}"; mkdir -p "$out"
ffmpeg -y -loglevel error -i "$in" -vf "fps=1/0.4,scale=384:216,drawtext=text='%{pts\:hms}':x=6:y=6:fontcolor=white:fontsize=18:box=1:boxcolor=black@0.6,tile=5x4" -frames:v 4 "$out/sheet_%d.jpg"
echo "wrote $out/sheet_1..4.jpg"
