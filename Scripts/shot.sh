#!/bin/sh
# Screenshots one PUPSISPortal window (no shadow) for live checks.
# Usage: Scripts/shot.sh out.png PID
# PID is required so a check never captures another running copy of the app.
# Needs Screen Recording permission for the terminal running it.
set -e
OUT="${1:?usage: Scripts/shot.sh out.png PID}"
PID="${2:?usage: Scripts/shot.sh out.png PID}"
ID="$(PID="$PID" osascript -l JavaScript -e '
ObjC.import("CoreGraphics"); ObjC.import("stdlib");
const pid = Number($.getenv("PID"));
const list = ObjC.deepUnwrap(ObjC.castRefToObject($.CGWindowListCopyWindowInfo($.kCGWindowListOptionOnScreenOnly, 0)));
const w = list.find(w => w.kCGWindowOwnerPID === pid && w.kCGWindowLayer === 0);
w ? String(w.kCGWindowNumber) : "";
')"
[ -n "$ID" ] || { echo "no on-screen window for pid $PID" >&2; exit 1; }
screencapture -x -o -l "$ID" "$OUT"
echo "$OUT"
